import SwiftData
import SwiftUI
import UIKit
import os

struct TodayView: View {
    let profile: Profile?
    var onOpenBaseline: () -> Void
    /// Switches the root tab to Plan — the meds tile is a shortcut to the full routine.
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(DeepLinkRouter.self) private var deepLinks
    @Environment(NotificationService.self) private var notifications
    @AppStorage("eveningCheckInEnabled") private var eveningCheckInEnabled = false
    @AppStorage(ReminderNudge.shownKey) private var reminderNudgeShown = false
    /// True once "Turn on" led to a denied system prompt — the nudge card stays up, but its body
    /// switches to the honest "notifications are off, here's how to fix it" state. View state
    /// only: it is not persisted, so the card never returns in a later session once the shown
    /// flag above has retired it.
    @State private var nudgeNeedsSettings = false
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query private var missedDoses: [MissedDoseRecord]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]
    @Query(sort: \ProgressCheckIn.date) private var progressCheckIns: [ProgressCheckIn]
    @Query(sort: \SideEffectLog.date) private var sideEffectLogs: [SideEffectLog]

    @State private var showLog = false
    @State private var showBackfill = false
    /// Reward handed back by LogSheet.save; held until the log sheet finishes dismissing.
    @State private var pendingReward: CheckInReward?
    /// Drives the celebration sheet — set only from the log sheets' onDismiss (see below).
    @State private var celebrationReward: CheckInReward?
    @State private var insight: DailyInsight?
    @State private var showDeepAnalysis = false
    @State private var showLearn = false
    @State private var showChat = false
    @State private var chatDetent: PresentationDetent = .large
    @State private var chatContext = ""
    @State private var skipCandidate: PlanAdherence.Occurrence?
    @State private var pauseCandidate: PlanAdherence.Occurrence?
    @State private var detailTreatment: Treatment?

    private var calendar: Calendar { .current }
    private var todayEntry: DailyEntry? {
        entries.first { calendar.isDateInToday($0.date) }
    }
    /// Today's plan, the week strip and the week-so-far count, all from one engine.
    private var todayPlan: PlanAdherence.TodayPlan {
        PlanAdherence.today(treatments: treatments, doses: doses, missed: missedDoses, now: .now, calendar: calendar)
    }
    private var weekStates: [PlanAdherence.DayState] {
        PlanAdherence.week(treatments: treatments, doses: doses, missed: missedDoses, now: .now, calendar: calendar)
    }
    private var weekSummary: PlanAdherence.Consistency? {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return nil }
        return PlanAdherence.consistency(treatments: treatments, doses: doses, missed: missedDoses,
                                         from: start, through: today, now: .now, calendar: calendar)
    }
    private var medsDone: Int { todayPlan.completedCount }
    private var medsTotal: Int { todayPlan.occurrences.count }
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
            medsTotal: medsTotal,
            hasPhotoThisWeek: hasPhotoThisWeek
        )
    }

    /// True only on the very first day the app has any data at all — the sole entry in history
    /// is today's, seeded by onboarding rather than tapped by the user. Feeds the rings card's
    /// day-one welcome line only; never affects the score itself.
    private var isDayOneSeed: Bool {
        entries.count == 1 && todayEntry != nil
    }

    /// Whether the reminder nudge card is on screen: the model's own rule, plus the settings
    /// follow-up state that keeps the card up (in its other body) after a denied system prompt.
    private var showsReminderNudge: Bool {
        ReminderNudge.shouldShow(hasLoggedToday: todayEntry != nil, isDayOneSeed: isDayOneSeed,
                                 eveningReminderOn: eveningCheckInEnabled, alreadyShown: reminderNudgeShown)
            || nudgeNeedsSettings
    }

    /// Most recent trigger still inside the ~16-week telogen-effluvium watch period.
    private var watchTriggerWeeks: Int? {
        triggers.lazy.map { $0.weeksElapsed() }.first { (0...16).contains($0) }
    }

    var body: some View {
        // Computed once per render and fed to both `canOffer` and the tap closure below, rather
        // than looking yesterday's entry up twice (here and again inside `copyYesterday`).
        let yesterday = YesterdayCopy.yesterdayEntry(in: entries)
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
                    onCopyYesterday: YesterdayCopy.canOffer(
                        todayLogged: todayEntry != nil,
                        yesterday: yesterday
                    ) ? { copyYesterday(yesterday: yesterday) } : nil,
                    xp: xpTotal,
                    levelProgress: GamificationLevel.progressToNext(xp: xpTotal).fraction,
                    onShedSet: { level in
                        // Quiet by design — a drag-set upserts today's entry directly, with no
                        // celebration sheet. Streak/XP queries refresh naturally from the write.
                        if let entry = todayEntry {
                            entry.shed = level
                        } else {
                            try? DailyEntryRepository(context: context).upsert(day: .now) {
                                $0.shed = level
                            }
                        }
                    }
                )
                .staggeredEntrance(index: 0)
                if showsReminderNudge {
                    reminderNudgeCard
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
                VStack(alignment: .leading, spacing: 16) {
                    // Entrance sequence: hero 0, plan section 1, compass rings 2 (shares its 50ms
                    // step with the grid's own tile 1 below — a harmless timing overlap, not a
                    // functional dependency), tiles 1…6 (inside the grid, indices owned by
                    // TodayTileGrid), cards continue at 8…11.
                    TodayPlanSection(
                        plan: todayPlan,
                        week: weekStates,
                        weekSummary: weekSummary,
                        onComplete: { occurrence in
                            _ = try? DoseRepository(context: context).log(treatment: occurrence.treatment, slot: occurrence.slot)
                        },
                        onUndo: { occurrence in
                            switch occurrence.state {
                            case .completed:
                                _ = try? DoseRepository(context: context).delete(treatment: occurrence.treatment, slot: occurrence.slot)
                            case .skipped:
                                _ = try? MissedDoseRepository(context: context).delete(treatment: occurrence.treatment, slot: occurrence.slot)
                            default:
                                break
                            }
                        },
                        onSkip: { skipCandidate = $0 },
                        onPause: { pauseCandidate = $0 },
                        onOpenDetail: { detailTreatment = $0.treatment },
                        onOpenPlan: onOpenPlan
                    )
                    .staggeredEntrance(index: 1)
                    CompassRingsCard(
                        score: compassScore,
                        medsDone: medsDone,
                        medsTotal: medsTotal,
                        isDayOneSeed: isDayOneSeed,
                        onLog: { showLog = true }
                    )
                    .staggeredEntrance(index: 2)
                    TodayTileGrid(
                        entry: todayEntry,
                        sleepHours: todaySleepHours,
                        triggerWeeks: watchTriggerWeeks,
                        onLogTap: { showLog = true },
                        onBackfill: { showBackfill = true }
                    )
                    insightCard.staggeredEntrance(index: 9)
                    StrandDivider()
                    learnFootnote.staggeredEntrance(index: 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Ground flourish: the botanical garland grows out of the bottom of the page —
                // full-bleed, unboxed; its transparent upper canvas is the breathing room. The
                // 110pt clearance below keeps it above the floating tab bar.
                PageCloser()

                // A colophon, not a card: the one honest "is this current" line closes the page
                // like the last line of a journal entry, under the garland rather than boxed
                // above it — "System status" restated nothing the ledger above didn't already say.
                statusCaption
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .staggeredEntrance(index: 11)
            }
            .padding(.bottom, 24)
            // Round: the reminder-nudge card's own insertion/removal (e.g. the page settling
            // once the first log lands) used to be unanimated and made the page jump. One
            // animation on the container it lives in covers every path that flips
            // `showsReminderNudge` — a button tap inside the card, or an external data change
            // like saving today's first entry.
            .animation(.easeOut(duration: 0.25), value: showsReminderNudge)
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
        .onChange(of: [deepLinks.openLogRequested, deepLinks.canConsumeRoutes]) { _, _ in
            if deepLinks.consumeLogRequest() { showLog = true }
        }
        .onAppear {
            // Covers the cold-start case where the widget's URL arrives before this view exists.
            if deepLinks.consumeLogRequest() { showLog = true }
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
            DeepAnalysisSheet()
        }
        .sheet(isPresented: $showChat) {
            HairChatSheet(
                contextJSON: chatContext, focus: chatFocus,
                eyebrow: "Ask about your record",
                starterKind: .fullRecord
            )
            .presentationDetents([.medium, .large], selection: $chatDetent)
        }
        .sheet(isPresented: $showLearn) {
            NavigationStack {
                LearnView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showLearn = false } } }
            }
        }
        .sheet(item: $detailTreatment) { TreatmentDetailSheet(treatment: $0) }
        .confirmationDialog(TodayPlanCopy.skipTitle, isPresented: Binding(
            get: { skipCandidate != nil }, set: { if !$0 { skipCandidate = nil } }
        ), titleVisibility: .visible) {
            // A clinician-directed pause is a plan-level state (Pause on the row's long-press
            // menu, or the Plan tab's own reason list) — this dialog only records a one-day skip.
            ForEach(MissedDoseReason.allCases.filter { $0 != .clinicianDirectedPause }) { reason in
                Button(reason.title) { recordSkip(reason) }
            }
            Button("Cancel", role: .cancel) { skipCandidate = nil }
        } message: {
            Text(TodayPlanCopy.skipMessage)
        }
        .confirmationDialog(TodayPlanCopy.pauseTitle(pauseCandidate?.treatment.name ?? ""), isPresented: Binding(
            get: { pauseCandidate != nil }, set: { if !$0 { pauseCandidate = nil } }
        ), titleVisibility: .visible) {
            Button(TodayPlanCopy.pauseAction) { pauseTreatment() }
            Button("Cancel", role: .cancel) { pauseCandidate = nil }
        } message: {
            Text(TodayPlanCopy.pauseMessage)
        }
    }

    /// Promotes a saved reward to the presented celebration once the log sheet has fully
    /// dismissed — presenting from onDismiss avoids racing two sheet presentations.
    private func presentPendingReward() {
        guard let reward = pendingReward else { return }
        pendingReward = nil
        celebrationReward = reward
    }

    /// One tap, one full entry: today becomes a copy of yesterday's ratings. The hero flips to
    /// "Edit log" the moment the write lands, so a wrong tap is a one-tap fix.
    private func copyYesterday(yesterday: DailyEntry?) {
        guard let yesterday else { return }
        do {
            try DailyEntryRepository(context: context).upsert(day: .now, updateExisting: false) { today in
                YesterdayCopy.apply(from: yesterday, to: today)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // The next tap on "Log today" reaches the same store through the sheet.
            Logger(subsystem: "hair-compass", category: "today")
                .error("copyYesterday failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Learn (one rotating ink line, replacing the flash-card carousel)

    /// One quiet, daily-changing invitation instead of a six-card horizontal carousel — the most
    /// conventional dashboard idiom left on the page. The pick is deterministic (the day of year
    /// modulo the library size), so it's the same all day and different tomorrow: the page feels
    /// subtly alive across days without any decoration pretending to be new data. Tapping it opens
    /// the full `LearnView` sheet — the whole library is still one tap away, nothing is lost.
    private var learnFootnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Learn")
            Button { showLearn = true } label: {
                HStack(alignment: .top, spacing: 6) {
                    Text(dailyLearnCard.question)
                        .font(Clinical.body(14, weight: .medium))
                        .foregroundStyle(Clinical.accent)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(Clinical.body(11, weight: .semibold))
                        .foregroundStyle(Clinical.accent.opacity(0.6))
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.clinicalPressable)
            .accessibilityLabel("Today's learn card: \(dailyLearnCard.question)")
            .accessibilityHint("Opens the full library")
        }
    }

    /// Deterministic day-of-year pick — same card all day, a different one tomorrow. The library
    /// is never empty (it's a large static literal), so the index is always in range.
    private var dailyLearnCard: FlashCard {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        return LearnLibrary.cards[day % LearnLibrary.cards.count]
    }

    // MARK: - Insight (hybrid: on-device AI, deterministic fallback)

    private var insightFingerprint: String {
        // Include the latest entry's *content*, not just the count/date — editing today's check-in
        // in place (the hero drag or the Log sheet's Edit path) mutates the existing DailyEntry
        // without changing the count, so a count-only key would leave the insight describing a shed
        // level the user just changed.
        let latest = entries.first.map {
            "\($0.shedRaw)-\($0.flaking)-\($0.erythema)-\($0.itch)-\($0.date.timeIntervalSince1970)"
        } ?? "none"
        return "\(entries.count)-\(latest)-\(snapshots.count)-\(treatments.count)-\(labs.count)-\(progressCheckIns.count)-\(sideEffectLogs.count)"
    }

    @MainActor
    private func buildContext() -> InsightContext {
        InsightContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers, labs: labs, profile: profile,
            progressCheckIns: progressCheckIns, sideEffects: sideEffectLogs
        )
    }

    private func refreshInsight() async {
        let ctx = buildContext()
        insight = await InsightEngine.dailyInsight(for: ctx)
    }

    /// An unboxed margin note — the last ClinicalCard on the page's tail became this: an eyebrow,
    /// the insight sentence directly on canvas, a hairline, then one footnote line that says the
    /// source, the honesty caption, and the deep-analysis affordance together instead of stacking
    /// three separate lines inside a card.
    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Today's insight")
            Text(insight?.text ?? "Reading your recent entries…")
                .font(Clinical.caption(15))
                .foregroundStyle(insight == nil ? Clinical.tertiary : Clinical.ink)
            Divider().overlay(Clinical.hairline)
            insightFootnote
        }
    }

    /// Source label + "record-keeping, not diagnosis" + the flagship AI affordances, said once
    /// on one line instead of stacking separate statements down a card. "Ask Wren" is the
    /// first-class entry point into the on-device hair chat — previously reachable only three
    /// levels deep inside Compare; "Deep analysis" opens the one-tap written summary.
    private var insightFootnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(insightFootnoteText)
                .font(Clinical.caption(11))
                .foregroundStyle(Clinical.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                Button {
                    // The sheet itself handles the Pro gate, the cloud-AI consent card, and the
                    // engine availability check — nothing is sent before consent.
                    openChat()
                } label: {
                    HStack(spacing: 4) {
                        CompanionView(moment: .resting, variant: .avatar, size: 16)
                        Text("Ask \(Companion.name)")
                        Image(systemName: "chevron.right").font(Clinical.body(8, weight: .semibold))
                    }
                    .font(Clinical.body(11, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.clinicalPressable)
                .accessibilityLabel("Ask \(Companion.name) about your tracking record")

                Button {
                    showDeepAnalysis = true
                } label: {
                    HStack(spacing: 2) {
                        Text("AI record summary")
                        Image(systemName: "chevron.right").font(Clinical.body(8, weight: .semibold))
                    }
                    .font(Clinical.body(11, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.clinicalPressable)
            }
        }
    }

    /// One line telling the chat what's on screen — the whole record, not a specific chart,
    /// since Today has no single comparison in view.
    private var chatFocus: String {
        "User is asking from the Today screen about their overall record."
    }

    /// Snapshot the canonical AIContext at open time — same pattern as `CompareView.openChat()`
    /// and `DeepAnalysisSheet`, just grounded on the whole record instead of one chart.
    private func openChat() {
        chatContext = AIContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers,
            labs: labs, sideEffects: sideEffectLogs, photos: photos,
            profile: profile, progressCheckIns: progressCheckIns, now: .now
        ).jsonString()
        showChat = true
    }

    private var insightFootnoteText: String {
        let base = "For record-keeping, not diagnosis."
        guard let source = insight?.source else { return base }
        return "\(source.label) · \(base)"
    }

    private var greeting: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let hour = calendar.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// A quiet colophon confirming the app is current — not decorative copy, an honest
    /// reflection of when data last changed, so silence never reads as staleness. Demoted from
    /// its own "System status" card to a single centered caption under the meadow, the way a
    /// book's last page carries one small printer's line instead of another heading.
    private var statusCaption: some View {
        let lastActivity = [entries.first?.date, doses.map(\.loggedAt).max()].compactMap { $0 }.max()
        return Text(lastActivity.map { "Up to date · last entry \($0.formatted(.relative(presentation: .named)))" }
                    ?? "Ready for your first entry")
            .font(Clinical.caption(11))
            .foregroundStyle(Clinical.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Asked once, after the first real log, while reminders are off. Both buttons retire it —
    /// unless "Turn on" hits a denied system prompt, in which case the card stays up in its other
    /// body (`nudgeNeedsSettings`) instead of silently doing nothing.
    private var reminderNudgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if nudgeNeedsSettings {
                Text("Notifications are off for Hair Compass")
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                Text("Turn them on in Settings › Notifications › Hair Compass, then switch on the evening check-in from the Plan tab.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityIdentifier("reminderNudgeSettings")
                    Button("Got it") { nudgeNeedsSettings = false }
                        .font(Clinical.body(13, weight: .medium))
                        .foregroundStyle(Clinical.tertiary)
                        .buttonStyle(.plain)
                        .minimumHitTarget()
                        .accessibilityIdentifier("reminderNudgeGotIt")
                    Spacer(minLength: 0)
                }
            } else {
                Text("Want a nudge tomorrow evening?")
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                Text("One quiet reminder at the evening check-in time. You can change or switch it off on the Plan tab.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        // Set before the request: an interrupted prompt must still retire the
                        // card, and the follow-up (nudgeNeedsSettings) is view state that keeps
                        // showing it regardless.
                        reminderNudgeShown = true
                        Task {
                            let granted = await notifications.requestAuthorizationIfNeeded()
                            eveningCheckInEnabled = granted
                            if !granted && notifications.authorization == .denied {
                                nudgeNeedsSettings = true
                            }
                        }
                    } label: {
                        Text("Turn on")
                            .font(Clinical.body(12, weight: .medium))
                            .foregroundStyle(Clinical.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .background(Clinical.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.clinicalPressable)
                    .accessibilityIdentifier("reminderNudgeOn")
                    Button("Not now") { reminderNudgeShown = true }
                        .font(Clinical.body(13, weight: .medium))
                        .foregroundStyle(Clinical.tertiary)
                        .buttonStyle(.plain)
                        .minimumHitTarget()
                        .accessibilityIdentifier("reminderNudgeNotNow")
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(Clinical.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(Clinical.hairline) }
        .accessibilityIdentifier("reminderNudge")
    }

    // MARK: - Plan actions

    private func recordSkip(_ reason: MissedDoseReason) {
        guard let candidate = skipCandidate else { return }
        _ = try? MissedDoseRepository(context: context).record(
            treatment: candidate.treatment, slot: candidate.slot, reason: reason
        )
        skipCandidate = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Records the person's own decision and its date — never advises it. Resuming lives on the
    /// Plan tab's treatment card ("Reactivate"), which clears the end date again.
    private func pauseTreatment() {
        guard let candidate = pauseCandidate else { return }
        candidate.treatment.isActive = false
        candidate.treatment.endDate = .now
        pauseCandidate = nil
    }
}
