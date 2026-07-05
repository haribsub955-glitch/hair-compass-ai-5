import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    let profile: Profile?
    var onOpenBaseline: () -> Void
    /// Switches the root tab to Plan — the meds tile is a shortcut to the full routine.
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]

    @State private var showLog = false
    @State private var showBackfill = false
    /// Reward handed back by LogSheet.save; held until the log sheet finishes dismissing.
    @State private var pendingReward: CheckInReward?
    /// Drives the celebration sheet — set only from the log sheets' onDismiss (see below).
    @State private var celebrationReward: CheckInReward?
    @State private var insight: DailyInsight?
    @State private var showDeepAnalysis = false
    @State private var showAIConsent = false
    @State private var aiConsentJustGranted = false
    @State private var showLearn = false

    private var calendar: Calendar { .current }
    private var todayEntry: DailyEntry? {
        entries.first { calendar.isDateInToday($0.date) }
    }
    private var activeDaily: [Treatment] {
        treatments.filter { $0.isActive && !$0.slots.isEmpty }
    }
    private var streak: Int {
        HairAnalytics.loggingStreak(entryDates: entries.map(\.date))
    }

    /// Effort-only gamification level ("Sapling") shown beside the streak in the hero.
    private var levelName: String {
        GamificationLevel.level(for: XP.total(
            entries: entries, doses: doses, photos: photos, labs: labs, triggers: triggers
        )).name
    }

    /// Today's HealthKit sleep hours, if the sync service has cached a snapshot for today.
    private var todaySleepHours: Double? {
        snapshots.first { calendar.isDateInToday($0.date) }?.sleepHours
    }

    /// Every daily (treatment, slot) step — the same universe treatmentRows renders.
    private var dailySlots: [(Treatment, String)] {
        activeDaily.flatMap { t in t.slots.map { (t, $0) } }
    }
    private var medsDone: Int {
        dailySlots.filter { isLogged($0.0, slot: $0.1) }.count
    }

    /// Most recent trigger still inside the ~16-week telogen-effluvium watch period.
    private var watchTriggerWeeks: Int? {
        triggers.lazy.map { $0.weeksElapsed() }.first { (0...16).contains($0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ConditionsHero(
                    shed: todayEntry?.shed,
                    scalpTotal: todayEntry?.scalpTotal,
                    scalpBand: todayEntry?.scalpBand,
                    greeting: greeting,
                    streak: streak,
                    levelName: levelName,
                    onOpenBaseline: onOpenBaseline,
                    onLog: { showLog = true }
                )
                .staggeredEntrance(index: 0)
                VStack(alignment: .leading, spacing: 16) {
                    // Entrance sequence: hero 0, tiles 1…6 (inside the grid), cards continue.
                    TodayTileGrid(
                        entry: todayEntry,
                        sleepHours: todaySleepHours,
                        medsDone: medsDone,
                        medsTotal: dailySlots.count,
                        triggerWeeks: watchTriggerWeeks,
                        onLogTap: { showLog = true },
                        onOpenPlan: onOpenPlan
                    )
                    logCard.staggeredEntrance(index: 7)
                    insightCard.staggeredEntrance(index: 8)
                    StrandDivider()
                    learnStrip.staggeredEntrance(index: 9)
                    statusCard.staggeredEntrance(index: 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Ground flourish: the botanical garland grows out of the bottom of the page —
                // full-bleed, unboxed; its transparent upper canvas is the breathing room. The
                // 110pt clearance below keeps it above the floating tab bar.
                Image(BrandArt.meadow)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 110)
        }
        .clinicalScreen()
        .task(id: insightFingerprint) { await refreshInsight() }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_LEARN") { showLearn = true }
            if ProcessInfo.processInfo.arguments.contains("HC_LOG") { showLog = true }
            if ProcessInfo.processInfo.arguments.contains("HC_BACKFILL") { showBackfill = true }
            if ProcessInfo.processInfo.arguments.contains("HC_CELEBRATE") {
                // Representative fixture for screenshots: +22 XP, 6-day streak, no level-up.
                celebrationReward = CheckInReward(
                    xpGained: 22,
                    totalXP: 240,
                    level: GamificationLevel.level(for: 240),
                    progressToNext: GamificationLevel.progressToNext(xp: 240),
                    leveledUp: false,
                    streak: 6,
                    newBadges: []
                )
            }
            #endif
        }
        // Celebration presentation uses the same onDismiss chain as the AI-consent →
        // deep-analysis pair: the log sheet stores the reward, and only its onDismiss
        // promotes it to the presented sheet — never two sheet presentations racing.
        .sheet(isPresented: $showLog, onDismiss: presentPendingReward) {
            LogSheet(existing: todayEntry, condition: profile?.condition ?? .unsure,
                     onSaved: { pendingReward = $0 })
        }
        .sheet(isPresented: $showBackfill, onDismiss: presentPendingReward) {
            // existing: nil shows the day strip, so any of the last 60 days can be backfilled.
            LogSheet(existing: nil, condition: profile?.condition ?? .unsure,
                     onSaved: { pendingReward = $0 })
        }
        .sheet(item: $celebrationReward) { reward in
            CheckInCelebration(reward: reward)
        }
        .sheet(isPresented: $showDeepAnalysis) {
            DeepAnalysisSheet(context: buildContext(), images: analysisImages())
        }
        // One-time consent before the first deep analysis (photos leave the device). Presenting the
        // analysis sheet from onDismiss avoids racing two sheet presentations.
        .sheet(isPresented: $showAIConsent, onDismiss: {
            if aiConsentJustGranted {
                aiConsentJustGranted = false
                showDeepAnalysis = true
            }
        }) {
            AIConsentSheet(
                onAllow: {
                    aiConsentJustGranted = true
                    showAIConsent = false
                },
                onNotNow: { showAIConsent = false }
            )
        }
        .sheet(isPresented: $showLearn) {
            NavigationStack {
                LearnView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showLearn = false } } }
            }
        }
    }

    /// Promotes a saved reward to the presented celebration once the log sheet has fully
    /// dismissed — presenting from onDismiss avoids racing two sheet presentations.
    private func presentPendingReward() {
        guard let reward = pendingReward else { return }
        pendingReward = nil
        celebrationReward = reward
    }

    // MARK: - Learn strip (flash cards)

    private var learnStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Learn")
                Spacer()
                Button("See all") { showLearn = true }
                    .font(Clinical.eyebrow(11)).foregroundStyle(Clinical.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(learnPreview) { card in
                        FlashCardView(card: card).frame(width: 250)
                    }
                }
            }
        }
    }

    private var learnPreview: [FlashCard] {
        Array(LearnLibrary.cards.prefix(6))
    }

    // MARK: - Insight (hybrid: on-device AI, deterministic fallback)

    private var insightFingerprint: String {
        "\(entries.count)-\(entries.first?.date.timeIntervalSince1970 ?? 0)-\(snapshots.count)-\(treatments.count)"
    }

    @MainActor
    private func buildContext() -> InsightContext {
        InsightContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers, profile: profile
        )
    }

    private func refreshInsight() async {
        let ctx = buildContext()
        insight = await InsightEngine.dailyInsight(for: ctx)
    }

    /// The latest photo per region, loaded for the cloud call (capped downstream).
    private func analysisImages() -> [UIImage] {
        var seen = Set<PhotoRegion>()
        var images: [UIImage] = []
        for record in photos where !seen.contains(record.region) {
            if let image = PhotoStore.shared.load(record.imagePath) {
                images.append(image)
                seen.insert(record.region)
            }
        }
        return images
    }

    private var insightCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Today's insight")
                    Spacer()
                    if let source = insight?.source {
                        Label(source.label, systemImage: source == .onDevice ? "cpu" : "checkmark.seal")
                            .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
                    }
                }
                Text(insight?.text ?? "Reading your recent entries…")
                    .font(.system(size: 15))
                    .foregroundStyle(insight == nil ? Clinical.tertiary : Clinical.ink)
                Text("For record-keeping, not diagnosis.")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                Button("Deep analysis with photos") {
                    // Consent gate: the deep analysis sends scalp photos off-device, so the first
                    // tap asks in plain language. Once granted (revocable in Privacy), straight in.
                    if AIConsent.isGranted() {
                        showDeepAnalysis = true
                    } else {
                        showAIConsent = true
                    }
                }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                    .padding(.top, 2)
            }
        }
    }

    private var greeting: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let hour = calendar.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// Redesign v3: the numbers moved up into the glance tiles, so this card slims down to the
    /// action (edit/log) plus today's routine.
    private var logCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Daily log")
                if todayEntry != nil {
                    Button("Edit today's log") { showLog = true }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                } else {
                    Text("Log shedding, scalp signs, sleep and stress. It takes about 20 seconds.")
                        .font(.system(size: 14))
                        .foregroundStyle(Clinical.secondary)
                    Button("Log today") { showLog = true }
                        .buttonStyle(ClinicalButtonStyle())
                }
                Button("Log a past day") { showBackfill = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Clinical.accent)

                if !activeDaily.isEmpty {
                    Divider().overlay(Clinical.hairline).padding(.vertical, 2)
                    Eyebrow(text: "Today's routine")
                    ForEach(activeDaily) { treatment in
                        ForEach(treatment.slots, id: \.self) { slot in
                            treatmentRow(treatment, slot: slot)
                            if !(treatment.id == activeDaily.last?.id && slot == treatment.slots.last) {
                                Divider().overlay(Clinical.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func treatmentRow(_ treatment: Treatment, slot: String) -> some View {
        let done = isLogged(treatment, slot: slot)
        return Button {
            toggle(treatment, slot: slot, currentlyDone: done)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Clinical.accent : Clinical.hairline, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Clinical.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(treatment.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Clinical.ink)
                        .strikethrough(done, color: Clinical.tertiary)
                    Text("\(slot) · \(treatment.treatmentClass.title)")
                        .font(.system(size: 12))
                        .foregroundStyle(Clinical.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A quiet footer confirming the app is current — not decorative copy, an honest
    /// reflection of when data last changed, so silence never reads as staleness.
    private var statusCard: some View {
        let lastActivity = [entries.first?.date, doses.map(\.loggedAt).max()].compactMap { $0 }.max()
        return ClinicalCard(padding: 14) {
            VStack(alignment: .center, spacing: 4) {
                Eyebrow(text: "System status")
                Text(lastActivity.map { "Up to date · last entry \($0.formatted(.relative(presentation: .named)))" }
                     ?? "Ready for your first entry")
                    .font(.system(size: 12))
                    .foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Dose logging

    private func isLogged(_ treatment: Treatment, slot: String) -> Bool {
        doses.contains {
            $0.treatment?.persistentModelID == treatment.persistentModelID
                && $0.slot == slot
                && calendar.isDateInToday($0.loggedAt)
        }
    }

    private func toggle(_ treatment: Treatment, slot: String, currentlyDone: Bool) {
        if currentlyDone {
            if let existing = doses.first(where: {
                $0.treatment?.persistentModelID == treatment.persistentModelID
                    && $0.slot == slot
                    && calendar.isDateInToday($0.loggedAt)
            }) {
                context.delete(existing)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            context.insert(TreatmentDose(treatment: treatment, loggedAt: .now, slot: slot))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
