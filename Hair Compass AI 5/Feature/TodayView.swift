import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    let profile: Profile?
    var onOpenBaseline: () -> Void
    /// Switches the root tab to Plan — the meds tile is a shortcut to the full routine.
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(DeepLinkRouter.self) private var deepLinks
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
    /// Displayed streak with Duolingo-style shields — see `HairAnalytics.shieldedStreak`. Only
    /// what's shown changes; XP/badge math (`CheckInReward`) still runs off the plain,
    /// unshielded streak, so shields never mint extra reward.
    private var shieldedInfo: (streak: Int, shieldsHeld: Int) {
        HairAnalytics.shieldedStreak(entryDates: entries.map(\.date))
    }

    /// Total XP — a pure fold over the tracking data, hoisted so the hero's level name and its
    /// XP chip (with progress-to-next ring) share one computation.
    private var xpTotal: Int {
        XP.total(entries: entries, doses: doses, photos: photos, labs: labs, triggers: triggers)
    }

    /// Effort-only gamification level ("Sapling") shown in the hero's XP chip.
    private var levelName: String {
        GamificationLevel.level(for: xpTotal).name
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

    /// True when a progress photo exists in the current calendar week — the Lens ring input.
    private var hasPhotoThisWeek: Bool {
        photos.contains { calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .weekOfYear) }
    }

    /// Today's effort score behind the Compass Rings — built only from controllable inputs.
    /// Shedding/scalp severity never touch it.
    private var compassScore: CompassScore {
        CompassScore(
            hasLoggedToday: todayEntry != nil,
            medsDone: medsDone,
            medsTotal: dailySlots.count,
            hasPhotoThisWeek: hasPhotoThisWeek
        )
    }

    /// True only on the very first day the app has any data at all — the sole entry in history
    /// is today's, seeded by onboarding rather than tapped by the user. Feeds the rings card's
    /// day-one welcome line only; never affects the score itself.
    private var isDayOneSeed: Bool {
        entries.count == 1 && todayEntry != nil
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
                    hasLoggedToday: todayEntry != nil,
                    greeting: greeting,
                    streak: shieldedInfo.streak,
                    shields: shieldedInfo.shieldsHeld,
                    levelName: levelName,
                    onOpenBaseline: onOpenBaseline,
                    onLog: { showLog = true },
                    xp: xpTotal,
                    levelProgress: GamificationLevel.progressToNext(xp: xpTotal).fraction,
                    onShedSet: { level in
                        // Quiet by design — a drag-set upserts today's entry directly, with no
                        // celebration sheet. Streak/XP queries refresh naturally from the write.
                        if let entry = todayEntry {
                            entry.shed = level
                        } else {
                            context.insert(DailyEntry(date: .now, shed: level))
                        }
                    }
                )
                .staggeredEntrance(index: 0)
                VStack(alignment: .leading, spacing: 16) {
                    // Entrance sequence: hero 0, compass rings 1 (shares its 50ms step with the
                    // grid's own tile 1 below — a harmless timing overlap, not a functional
                    // dependency), tiles 1…6 (inside the grid, indices owned by TodayTileGrid),
                    // cards continue at 8…11.
                    CompassRingsCard(
                        score: compassScore,
                        medsDone: medsDone,
                        medsTotal: dailySlots.count,
                        isDayOneSeed: isDayOneSeed,
                        onLog: { showLog = true }
                    )
                    .staggeredEntrance(index: 1)
                    TodayTileGrid(
                        entry: todayEntry,
                        sleepHours: todaySleepHours,
                        medsDone: medsDone,
                        medsTotal: dailySlots.count,
                        triggerWeeks: watchTriggerWeeks,
                        onLogTap: { showLog = true },
                        onOpenPlan: onOpenPlan
                    )
                    logCard.staggeredEntrance(index: 8)
                    insightCard.staggeredEntrance(index: 9)
                    StrandDivider()
                    learnStrip.staggeredEntrance(index: 10)
                    statusCard.staggeredEntrance(index: 11)
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
            .padding(.bottom, 24)
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
        .onChange(of: deepLinks.openLogRequested) { _, requested in
            if requested { showLog = true; deepLinks.openLogRequested = false }
        }
        .onAppear {
            // Covers the cold-start case where the widget's URL arrives before this view exists.
            if deepLinks.openLogRequested { showLog = true; deepLinks.openLogRequested = false }
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
        "\(entries.count)-\(entries.first?.date.timeIntervalSince1970 ?? 0)-\(snapshots.count)-\(treatments.count)-\(labs.count)"
    }

    @MainActor
    private func buildContext() -> InsightContext {
        InsightContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers, labs: labs, profile: profile
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
            if let image = PhotoStore.shared.loadThumbnail(record.imagePath, maxPixel: 1024) {
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

    /// A compact checklist: check-in and routine steps share one scannable surface. The primary
    /// log action also lives in the hero, so this row confirms state without another full CTA.
    private var logCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow(text: "Today's checklist")
                    Spacer()
                    Button("Past day") { showBackfill = true }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Clinical.accent)
                }

                Button { showLog = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: todayEntry == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(todayEntry == nil ? Clinical.tertiary : Clinical.positive)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily check-in")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Clinical.ink)
                            Text(todayEntry == nil ? "About 20 seconds" : "Completed today")
                                .font(.system(size: 12))
                                .foregroundStyle(Clinical.secondary)
                        }
                        Spacer()
                        Text(todayEntry == nil ? "Log" : "Edit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Clinical.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Clinical.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(todayEntry == nil ? "Opens today's check-in" : "Edits today's check-in")

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
