import SwiftData
import SwiftUI

/// The Plan tab: what to do today (routine), how you're doing (coach + milestones), reminders to
/// keep you on track, and the treatment regimen with its 24-week judging gate. Guidance is
/// non-prescriptive — it helps you follow treatments you added, it doesn't tell you what to start.
struct CareView: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationService.self) private var notifications
    @Environment(DeepLinkRouter.self) private var deepLinks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var sideEffectLogs: [SideEffectLog]
    @Query private var labs: [LabResult]
    @Query private var triggerEvents: [TriggerEvent]
    @Query(sort: \ProcedureAppointment.date) private var procedureAppointments: [ProcedureAppointment]
    @Query(sort: \ProgressCheckIn.date, order: .reverse) private var checkIns: [ProgressCheckIn]
    @Query(sort: \PhotoRecord.createdAt) private var photoRecords: [PhotoRecord]

    @State private var showAdd = false
    @State private var showRecommender = false
    @State private var remindersOn = false
    @State private var expandedSteps: Set<String> = []
    @State private var detailTreatment: Treatment?
    @State private var showReport = false
    /// Which active daily treatment the progress report is scoped to. nil defers to
    /// `ProgressReport.build`'s default (the earliest one) — set explicitly by the in-card
    /// picker (when there's more than one) or by a milestone notification's deep link so a
    /// second treatment's milestone opens THAT treatment's report.
    @State private var reportFocusTreatment: Treatment?
    @State private var showProcedures = false
    @State private var showProgressCheckIn = false
    @State private var showAddTrigger = false
    /// 0…1 fraction driving the header's scroll-condense (see `ScreenHeader.condensed`) — set
    /// directly from the ScrollView's own content offset.
    @State private var headerCondense: CGFloat = 0

    /// Evening check-in reminder — independent of the routine "Reminders" toggle above, off
    /// until the user turns it on. Time is stored as minutes-since-midnight (default 20:30).
    @AppStorage("eveningCheckInEnabled") private var eveningCheckInEnabled = false
    @AppStorage("eveningCheckInMinutes") private var eveningCheckInMinutes = 20 * 60 + 30

    private var profile: Profile? { profiles.first }

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Your plan",
                    title: "Plan",
                    trailing: AnyView(
                        HeaderActionButton(systemName: "plus", accessibilityLabel: "Add treatment") {
                            showAdd = true
                        }
                    ),
                    condensed: headerCondense
                ).padding(.top, 8)
                    .staggeredEntrance(index: 0)

                // One entrance sequence down the card stack; indices are fixed positions, so a
                // missing conditional card just leaves an invisible 50ms gap. The coach card is
                // gone — its one fact ("N steps left today") now lives as a living subtitle
                // right under the header, above a hairline that fills as steps complete, so the
                // actual ritual (the routine list) is the first thing the page shows instead of
                // a card that just restated what's below it.
                routineProgressHeader.staggeredEntrance(index: 1)
                if hasRecentSevereSideEffect { severeSideEffectBanner.staggeredEntrance(index: 2) }
                if !routine.isEmpty { routineSection.staggeredEntrance(index: 3) }
                guidanceCard.staggeredEntrance(index: 4)
                remindersCard.staggeredEntrance(index: 5)
                gateExplainer.staggeredEntrance(index: 6)
                if let report = progressReport { progressReportCard(report).staggeredEntrance(index: 7) }

                if treatments.isEmpty {
                    empty.staggeredEntrance(index: 8)
                } else {
                    ForEach(Array(treatments.enumerated()), id: \.element.id) { i, t in
                        // Capped: everything past here is below the fold at load anyway.
                        treatmentCard(t).staggeredEntrance(index: min(8 + i, 12))
                    }
                }

                // Same cap as the last treatment card above — lands in the same beat, no
                // renumbering of the fixed indices elsewhere in this stack required.
                proceduresCard.staggeredEntrance(index: 12)

                // New card, new trailing index — appended past the capped treatment/procedures
                // beat rather than renumbering any index above.
                progressCheckInCard.staggeredEntrance(index: 13)

                // Same trailing pattern one index later — a life event (illness, crash diet,
                // childbirth, a new medication…) is the only entry point to `TriggerEvent`
                // outside onboarding, so every downstream surface that reads dated triggers
                // (journey markers, insights, the clinician export) stays usable for the whole
                // life of the record, not just its first day.
                lifeEventCard.staggeredEntrance(index: 14)

                // No entrance on the science section — HC_SCROLL_PRODUCTS screenshots jump
                // straight to it and must never catch a mid-fade frame.
                ScienceProductsSection().id("science")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Condenses the header's serif title as the page scrolls — direct 1:1 offset tracking.
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, newY in
            headerCondense = Clinical.headerCondenseFraction(newY)
        }
        .clinicalScreen()
        .sheet(isPresented: $showAdd) { AddTreatmentSheet() }
        .sheet(item: $detailTreatment) { TreatmentDetailSheet(treatment: $0) }
        .sheet(isPresented: $showProcedures) { ProceduresView() }
        .sheet(isPresented: $showAddTrigger) { AddTriggerSheet() }
        .sheet(isPresented: $showProgressCheckIn) {
            ProgressCheckInSheet(treatmentContext: progressCheckInTreatmentContext)
        }
        .sheet(isPresented: $showReport) {
            if let report = progressReport { ProgressReportSheet(report: report, photos: photoRecords) }
        }
        .sheet(isPresented: $showRecommender) {
            NavigationStack {
                RecommenderView(condition: profile?.condition ?? .unsure, sex: profile?.sex ?? .male)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showRecommender = false } } }
            }
        }
        .task {
            await notifications.refreshAuthorization()
            remindersOn = notifications.isEnabled
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_SCROLL_PRODUCTS") {
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { proxy.scrollTo("science", anchor: .top) }
            }
            if ProcessInfo.processInfo.arguments.contains("HC_TREATMENT_DETAIL") {
                try? await Task.sleep(for: .milliseconds(250))
                detailTreatment = treatments.first
            }
            if ProcessInfo.processInfo.arguments.contains("HC_REPORT") {
                try? await Task.sleep(for: .milliseconds(250))
                if progressReport != nil { showReport = true }
            }
            if ProcessInfo.processInfo.arguments.contains("HC_ADDTREATMENT") {
                try? await Task.sleep(for: .milliseconds(250))
                showAdd = true
            }
            if ProcessInfo.processInfo.arguments.contains("HC_PROCEDURES") {
                try? await Task.sleep(for: .milliseconds(250))
                showProcedures = true
            }
            if ProcessInfo.processInfo.arguments.contains("HC_PROGRESSCHECKIN") {
                try? await Task.sleep(for: .milliseconds(250))
                showProgressCheckIn = true
            }
            #endif
        }
        // Combined fingerprint: an appointment change alone (fingerprint unaffected by
        // treatments), or a new progress check-in alone (fingerprint unaffected by both), still
        // needs to re-plan its own reminder, so all three fingerprints key the same task.
        // `reschedule()` runs first — it's the only one of the four calls below that does a
        // `removeAllPendingNotificationRequests()`, so it must land before the
        // procedure/progress-check-in/evening calls or it would wipe the reminders they just
        // scheduled.
        .task(id: "\(treatmentFingerprint)||\(procedureFingerprint)||\(checkIns.first?.date.timeIntervalSince1970 ?? 0)") {
            await notifications.reschedule(treatments: notifTreatments, refills: notifRefills)
            await notifications.planProcedureReminders(notifProcedures)
            await notifications.planProgressCheckInReminder(lastCheckIn: checkIns.first?.date)
            await notifications.planMilestoneReminders(notifMilestoneTreatments)
            await replanEveningCheckIn()
        }
        // Tapping a milestone reminder lands here already on Plan (RootView switches tabs) —
        // just open the report it pointed to, focused on the treatment the milestone was about
        // (round-5 fix: a second treatment's week-12 milestone used to always open the earliest
        // treatment's report instead of its own).
        .onChange(of: deepLinks.openProgressReportRequested) { _, requested in
            guard requested else { return }
            deepLinks.openProgressReportRequested = false
            if let focusID = deepLinks.progressReportFocusTreatmentID,
               let matched = dailyActiveTreatments.first(where: { String($0.persistentModelID.hashValue) == focusID }) {
                reportFocusTreatment = matched
            }
            deepLinks.progressReportFocusTreatmentID = nil
            if progressReport != nil { showReport = true }
        }
        // A refill or treatment-schedule reminder tap lands here already on Plan (RootView
        // switches tabs) — the tab switch itself is the fix (round 4: these used to dead-end at
        // the app icon), so this just consumes the flag per the router's consume-once idiom.
        .onChange(of: deepLinks.openCareRequested) { _, requested in
            guard requested else { return }
            deepLinks.openCareRequested = false
        }
        // Re-plans whenever today's logged state flips — the "cancel when logged" honesty rule:
        // once today is logged, today's pending reminder id is dropped from the schedule.
        .task(id: hasLoggedToday) {
            await replanEveningCheckIn()
        }
        .onChange(of: eveningCheckInEnabled) { _, on in
            Task {
                if on {
                    let granted = await notifications.requestAuthorizationIfNeeded()
                    guard granted else { eveningCheckInEnabled = false; return }
                }
                await replanEveningCheckIn()
            }
        }
        .onChange(of: eveningCheckInMinutes) { _, _ in
            guard eveningCheckInEnabled else { return }
            Task { await replanEveningCheckIn() }
        }
        }
    }

    // MARK: Derived state

    private var activeTreatments: [Treatment] { treatments.filter(\.isActive) }
    private var treatmentWeeks: [(name: String, weeks: Int)] {
        activeTreatments.map { (($0.name.isEmpty ? $0.treatmentClass.title : $0.name), HairAnalytics.weeksElapsed(since: $0.startDate)) }
    }
    private var notifTreatments: [(name: String, slots: [String])] {
        activeTreatments.filter { !$0.slots.isEmpty }.map { ($0.name.isEmpty ? $0.treatmentClass.title : $0.name, $0.slots) }
    }
    private var notifRefills: [(name: String, refillBy: Date)] {
        activeTreatments.compactMap { t in
            t.refillBy.map { (t.name.isEmpty ? t.treatmentClass.title : t.name, $0) }
        }
    }
    /// Every active treatment, unfiltered by schedule — the 24-week judging gate applies to any
    /// treatment (see `gateExplainer`/`treatmentCard`), not just the daily-slot ones the routine
    /// reminders target.
    private var notifMilestoneTreatments: [(id: String, name: String, startDate: Date)] {
        activeTreatments.map {
            (String($0.persistentModelID.hashValue), $0.name.isEmpty ? $0.treatmentClass.title : $0.name, $0.startDate)
        }
    }
    private var treatmentFingerprint: String {
        activeTreatments.map { "\($0.name)\($0.scheduleTimes)\($0.isActive)\($0.refillBy?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
    }
    private var upcomingProcedures: [ProcedureAppointment] { procedureAppointments.filter(\.isUpcoming) }
    private var notifProcedures: [(id: String, title: String, date: Date)] {
        upcomingProcedures.map { (String($0.persistentModelID.hashValue), $0.type.title, $0.date) }
    }
    private var procedureFingerprint: String {
        procedureAppointments.map { "\($0.persistentModelID.hashValue)|\($0.date.timeIntervalSince1970)|\($0.isCompleted)" }.joined(separator: "|")
    }
    private var streak: Int { HairAnalytics.loggingStreak(entryDates: entries.map(\.date)) }
    private var hasRecentSevereSideEffect: Bool {
        HairAnalytics.hasRecentSevereSideEffect(logs: sideEffectLogs.map { ($0.severity, $0.date) })
    }

    // MARK: Evening check-in reminder

    /// The shielded (displayed) streak, not the raw coach/milestone one above — the evening
    /// reminder's copy should match whatever number the Today hero is actually showing.
    private var shieldedStreak: Int {
        HairAnalytics.shieldedStreak(entryDates: entries.map(\.date)).streak
    }
    private var hasLoggedToday: Bool { entries.contains { calendar.isDateInToday($0.date) } }
    private var eveningCheckInComponents: DateComponents {
        var comps = DateComponents()
        comps.hour = eveningCheckInMinutes / 60
        comps.minute = eveningCheckInMinutes % 60
        return comps
    }
    /// Binding into the AppStorage minutes-since-midnight Int, for the DatePicker below.
    private var eveningCheckInTime: Binding<Date> {
        Binding(
            get: {
                var comps = calendar.dateComponents([.year, .month, .day], from: .now)
                comps.hour = eveningCheckInMinutes / 60
                comps.minute = eveningCheckInMinutes % 60
                return calendar.date(from: comps) ?? .now
            },
            set: { newValue in
                let comps = calendar.dateComponents([.hour, .minute], from: newValue)
                eveningCheckInMinutes = (comps.hour ?? 20) * 60 + (comps.minute ?? 30)
            }
        )
    }
    private func replanEveningCheckIn() async {
        await notifications.planEveningCheckIn(
            enabled: eveningCheckInEnabled,
            time: eveningCheckInComponents,
            hasLoggedToday: hasLoggedToday,
            streak: shieldedStreak
        )
    }

    /// The periodic synthesis — nil until there's an active daily treatment or ≥ 8 weeks of logs.
    /// Scoped to `reportFocusTreatment` when set (picker choice or a milestone notification's
    /// deep link); otherwise `ProgressReport.build` falls back to the earliest active daily
    /// treatment, same as before.
    private var progressReport: ProgressReport? {
        ProgressReport.build(
            entries: entries, treatments: treatments, doses: doses,
            labs: labs, sideEffects: sideEffectLogs, triggers: triggerEvents,
            focus: reportFocusTreatment
        )
    }

    /// Every active treatment with its own daily schedule — the report-focus picker only earns
    /// its place once there's more than one to choose between.
    private var dailyActiveTreatments: [Treatment] {
        activeTreatments.filter { !$0.slots.isEmpty }
    }

    /// Today's routine grouped into blocks, carrying the Treatment so a tap can log the dose.
    private var routine: [(block: RoutineBlock, steps: [(treatment: Treatment, slot: String)])] {
        var map: [RoutineBlock: [(Treatment, String)]] = [:]
        for t in activeTreatments {
            // Day-scheduled care products (a shampoo set to Mon/Thu) only join today's routine on
            // their days; medications and un-scheduled items have an empty schedule → always due.
            guard t.isDueToday() else { continue }
            if t.slots.isEmpty {
                map[.periodic, default: []].append((t, ""))
            } else {
                for slot in t.slots { map[RoutineBlock.block(for: slot), default: []].append((t, slot)) }
            }
        }
        return RoutineBlock.allCases.compactMap { b in map[b].map { (b, $0) } }
    }
    private var dailySteps: [(Treatment, String)] { routine.filter { $0.block != .periodic }.flatMap { $0.steps } }
    private var doneToday: Int { dailySteps.filter { isLogged($0.0, slot: $0.1) }.count }

    // MARK: Routine progress (the coach card's one surviving fact)

    /// Replaces the old coach card — its illustration, flame streak and motivational copy used
    /// to merely restate the list sitting right under it. What's left is the one fact worth
    /// saying up top ("N steps left today") as a living subtitle beneath the header, and a
    /// single copper hairline that fills left-to-right as steps complete instead of a separate
    /// ring widget.
    private var routineProgressHeader: some View {
        let remaining = max(0, dailySteps.count - doneToday)
        let isComplete = !dailySteps.isEmpty && remaining == 0
        let fraction = dailySteps.isEmpty ? 0 : Double(doneToday) / Double(dailySteps.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(routineStatusText(remaining: remaining, isComplete: isComplete))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                    .contentTransition(.opacity)
                if streak > 0 {
                    Text("\(streak)d streak")
                        .font(Clinical.eyebrow(10))
                        .foregroundStyle(Clinical.accent)
                }
            }
            if !dailySteps.isEmpty {
                RoutineHairlineProgress(fraction: fraction)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isComplete)
    }

    private func routineStatusText(remaining: Int, isComplete: Bool) -> String {
        if dailySteps.isEmpty { return "No routine steps today" }
        if isComplete { return "Today's routine is done · \(dailySteps.count) of \(dailySteps.count)" }
        return "\(remaining) step\(remaining == 1 ? "" : "s") left today"
    }

    /// Fraction toward the milestone's own next marker, derived from the same data
    /// (`treatmentWeeks`/`streak`) the milestone was built from — `Milestone` itself carries no
    /// numeric progress, only an id whose prefix identifies which kind it is.
    private func milestoneProgress(_ m: Milestone) -> Double? {
        if m.id.hasPrefix("ready-") { return 1 }
        if m.id.hasPrefix("half-") {
            let name = String(m.id.dropFirst("half-".count))
            guard let weeks = treatmentWeeks.first(where: { $0.name == name })?.weeks else { return nil }
            return min(1, Double(weeks) / 24)
        }
        if m.id.hasPrefix("streak-") {
            guard let next = Milestones.streakThresholds.first(where: { $0 > streak }) else { return 1 }
            let prevTier = Milestones.streakThresholds.last(where: { $0 <= streak }) ?? 0
            let span = Double(next - prevTier)
            return span > 0 ? min(1, Double(streak - prevTier) / span) : 1
        }
        return nil
    }

    // MARK: Routine — the ritual is the page, so it sits directly on the canvas

    /// No enclosing card — MORNING/EVENING/PERIODIC blocks sit on the ivory under hairline
    /// section rules, and the gold milestone (formerly its own separate card in the stack) closes
    /// the list as a one-line footnote instead of a fourth competing widget.
    private var routineSection: some View {
        let milestone = Milestones.achieved(streak: streak, treatments: treatmentWeeks).first
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Today's routine").padding(.bottom, 12)
            ForEach(Array(routine.enumerated()), id: \.element.block.id) { index, entry in
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: entry.block.title)
                    ForEach(Array(entry.steps.enumerated()), id: \.offset) { _, step in
                        routineRow(step.treatment, slot: step.slot, periodic: entry.block == .periodic)
                    }
                }
                .padding(.bottom, 14)
                if index != routine.count - 1 {
                    Divider().overlay(Clinical.hairline).padding(.bottom, 14)
                }
            }
            if let milestone {
                Divider().overlay(Clinical.hairline).padding(.bottom, 10)
                milestoneFootnote(milestone)
            }
        }
    }

    /// The gold milestone bar, demoted from its own card to the one-line annotation that closes
    /// the routine list — its full body text still reaches VoiceOver via the accessibility label.
    private func milestoneFootnote(_ m: Milestone) -> some View {
        HStack(spacing: 6) {
            Image(systemName: m.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Clinical.gold)
            Text(m.title)
                .font(Clinical.eyebrow(10))
                .foregroundStyle(Clinical.secondary)
                .lineLimit(1)
            if let progress = milestoneProgress(m), progress < 1 {
                // Just the number — some milestone titles ("halfway there") already end in
                // "there"; appending "% there" a second time read as "halfway there · 83% there".
                Text("· \(Int((progress * 100).rounded()))%")
                    .font(Clinical.eyebrow(10))
                    .foregroundStyle(Clinical.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.title). \(m.body)")
    }

    /// A single hairline-ruled footnote row — decongested from an icon-tile card with its own
    /// subtitle. "Education, not a prescription" now lives inside the sheet this opens (see
    /// `TreatmentRecommender.disclaimer` in `RecommenderView`) instead of being said twice.
    private var guidanceCard: some View {
        Button { showRecommender = true } label: {
            VStack(spacing: 0) {
                Divider().overlay(Clinical.hairline)
                HStack(spacing: 10) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Clinical.accent)
                        .frame(width: 20, alignment: .leading)
                    Text("What the evidence supports for you")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Clinical.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Clinical.tertiary)
                }
                .padding(.vertical, 13)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel("What the evidence supports for you")
        .accessibilityHint("Opens ranked treatment options for your pattern — education, not a prescription")
    }

    /// One calm, non-blocking nudge when a severity-3 side effect was logged in the last 14 days.
    /// A prompt to have a conversation — never advice to stop or change anything.
    private var severeSideEffectBanner: some View {
        ClinicalCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 16)).foregroundStyle(Clinical.critical)
                Text("You logged a severe side effect — worth discussing with your prescriber.")
                    .font(.system(size: 13)).foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Routine rows

    private func routineRow(_ t: Treatment, slot: String, periodic: Bool) -> some View {
        let key = "\(t.persistentModelID.hashValue)|\(slot)"
        return RoutineStepRow(
            treatment: t,
            slot: slot,
            periodic: periodic,
            done: isLogged(t, slot: slot),
            expanded: expandedSteps.contains(key),
            onToggle: { toggle(t, slot: slot, currentlyDone: isLogged(t, slot: slot)) },
            onInfo: {
                if expandedSteps.contains(key) { expandedSteps.remove(key) } else { expandedSteps.insert(key) }
            }
        )
    }

    // MARK: Reminders

    /// Un-boxed: two hairline-separated toggle rows in the ritual list's own geometry, bounded by
    /// its own leading/trailing rules — the last piece of card chrome the page used to end on.
    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline).padding(.bottom, 12)
            Eyebrow(text: "Reminders").padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $remindersOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Routine reminders").font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                        Text("Nudge me at my routine times.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                }
                .tint(Clinical.accent)
                .onChange(of: remindersOn) { _, on in
                    Task {
                        if on {
                            let granted = await notifications.enable(treatments: notifTreatments, refills: notifRefills)
                            if !granted { remindersOn = false }
                        } else {
                            notifications.disable()
                        }
                    }
                }
                if remindersOn && notifTreatments.isEmpty {
                    Text("Add a daily treatment with times to get routine reminders.")
                        .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                }
            }
            .padding(.bottom, 12)

            Divider().overlay(Clinical.hairline).padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $eveningCheckInEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evening check-in").font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                        Text("One invite at a time you pick — off until you turn it on.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                }
                .tint(Clinical.accent)
                if eveningCheckInEnabled {
                    DatePicker("Reminder time", selection: eveningCheckInTime, displayedComponents: .hourAndMinute)
                        .font(.system(size: 13))
                        .tint(Clinical.accent)
                }
            }

            Divider().overlay(Clinical.hairline).padding(.top, 12)
        }
    }

    // MARK: 24-week gate + treatments (unchanged evidence framing)

    private var gateExplainer: some View {
        ClinicalCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 16)).foregroundStyle(Clinical.accent)
                Text("Hair-density change is judged at 24 weeks in clinical trials. Each treatment shows its progress toward that milestone — resist judging sooner.")
                    .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
            }
        }
    }

    /// One card that opens the full week-N progress report, sitting next to the assessment
    /// clock it serves. Gets an accent border when the current week IS a review milestone
    /// (4 · 12 · 24, then every 12). When more than one active daily treatment exists, a
    /// segmented picker sits above the tappable row so a second treatment (e.g. finasteride
    /// added after two years of minoxidil) gets its own week clock and honest read instead of
    /// always reusing the earliest treatment's report — the picker sits outside the Button so
    /// choosing a segment never also opens the sheet.
    private func progressReportCard(_ report: ProgressReport) -> some View {
        let milestone = report.isMilestoneWeek
        return ClinicalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if dailyActiveTreatments.count > 1 {
                    Picker("Report focus", selection: reportFocusBinding) {
                        ForEach(dailyActiveTreatments) { t in
                            Text(t.name.isEmpty ? t.treatmentClass.title : t.name).tag(Optional(t))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Button { showReport = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(milestone ? Clinical.surface : Clinical.accent)
                            .frame(width: 38, height: 38)
                            .background(milestone ? Clinical.accent : Clinical.accentSoft,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Progress report")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                                if milestone {
                                    Text("MILESTONE")
                                        .font(Clinical.eyebrow(8)).tracking(0.8)
                                        .foregroundStyle(Clinical.gold)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Clinical.gold.opacity(0.14), in: Capsule())
                                }
                            }
                            Text(milestone
                                 ? "Week \(report.weekNumber) is a review milestone — read the full picture."
                                 : "Week \(report.weekNumber) · next report at week \(report.nextMilestoneWeek).")
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Text("View report")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Clinical.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Clinical.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Clinical.accent.opacity(milestone ? 0.55 : 0), lineWidth: 1.5)
        )
    }

    /// Binding for the report-focus picker: reads/writes `reportFocusTreatment`, but a nil
    /// selection (nothing explicitly chosen yet) resolves to the earliest daily treatment so the
    /// segmented control always shows a selected segment instead of none.
    private var reportFocusBinding: Binding<Treatment?> {
        Binding(
            get: {
                reportFocusTreatment ?? dailyActiveTreatments.min { $0.startDate < $1.startDate }
            },
            set: { reportFocusTreatment = $0 }
        )
    }

    private var empty: some View {
        ClinicalCard {
            VStack(spacing: 8) {
                // The laurel medallion as the empty-state emblem — the 24-week journey this
                // card invites you to start, in the brand's own hand rather than an SF Symbol.
                Image(BrandArt.medallion)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Eyebrow(text: "No treatments")
                Text("Add minoxidil, finasteride, or a procedure to build your daily routine and track the 24-week window.")
                    .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
                Button("Add treatment") { showAdd = true }
                    .buttonStyle(ClinicalButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Procedures

    /// Compact entry card mirroring the treatment cards: the next couple of upcoming
    /// appointments (if any) plus an add action. The full booked/done list lives in
    /// `ProceduresView`, one tap away — this card never disturbs the treatment content around it.
    private var proceduresCard: some View {
        Button { showProcedures = true } label: {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Eyebrow(text: "Procedures")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                    if upcomingProcedures.isEmpty {
                        Text("Book PRP, microneedling, or another in-clinic procedure and get a reminder the day before.")
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(upcomingProcedures.prefix(2)) { appt in
                            HStack(spacing: 10) {
                                Image(systemName: appt.type.symbol)
                                    .font(.system(size: 13)).foregroundStyle(Clinical.sage)
                                    .frame(width: 28, height: 28)
                                    .background(Clinical.sage.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(appt.type.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                                    Text(appt.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                                }
                                Spacer()
                            }
                        }
                        if upcomingProcedures.count > 2 {
                            Text("+ \(upcomingProcedures.count - 2) more")
                                .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                    Text(upcomingProcedures.isEmpty ? "Add procedure" : "See all")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Clinical.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Life events (dated TE triggers)

    /// A compact entry card in the same family as `proceduresCard`: the most recent recorded
    /// event (if any) plus an add action. Kept quiet and optional — this is a record, never a
    /// prompt suggesting something is wrong.
    private var lifeEventCard: some View {
        Button { showAddTrigger = true } label: {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Eyebrow(text: "Life events")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                    if let latest = triggerEvents.sorted(by: { $0.date > $1.date }).first {
                        HStack(spacing: 10) {
                            Image(systemName: latest.type.symbol)
                                .font(.system(size: 13)).foregroundStyle(Clinical.warning)
                                .frame(width: 28, height: 28)
                                .background(Clinical.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(latest.type.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                                Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                            }
                            Spacer()
                        }
                    } else {
                        Text("An illness, a crash diet, childbirth, major stress, or a new medication — dating it lets a shedding change 2–3 months later explain itself instead of looking random.")
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(triggerEvents.isEmpty ? "Log an event" : "Log another")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Clinical.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Progress check-in

    /// "You've been on {name} for {N} weeks." from the first active treatment — read against
    /// the clinician's own between-visit framing ("after starting a medication or a
    /// procedure"). nil when there's no active treatment yet, in which case the sheet just
    /// omits the context line.
    private var progressCheckInTreatmentContext: String? {
        guard let first = activeTreatments.first else { return nil }
        let name = first.name.isEmpty ? first.treatmentClass.title : first.name
        let weeks = HairAnalytics.weeksElapsed(since: first.startDate)
        return "You've been on \(name) for \(weeks) week\(weeks == 1 ? "" : "s")."
    }

    /// Due once it's been ≥ 30 days since the last check-in, or there's never been one.
    private var isProgressCheckInDue: Bool {
        guard let last = checkIns.first else { return true }
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: .now) else { return false }
        return last.date < cutoff
    }

    /// The dermatologist's between-visit questions (new regrowth, density/shedding/hairline
    /// trend, overall, scalp red flag), captured monthly. A compact entry card in the same
    /// family as `proceduresCard`/`guidanceCard` — last date, a "Due" chip, and a trailing
    /// link-style action rather than a full-bleed button, so it reads as one more item in the
    /// card stack rather than a standalone form.
    private var progressCheckInCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Progress check-in")
                    Spacer()
                    if isProgressCheckInDue {
                        statusChip("Due", symbol: "calendar.badge.exclamationmark", tint: Clinical.warning)
                    }
                }
                Text(checkIns.first.map { "Last check-in \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "Not done yet")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                Text("The between-visit questions a dermatologist asks — new baby hairs, density, shedding, hairline, scalp symptoms.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showProgressCheckIn = true
                } label: {
                    HStack(spacing: 4) {
                        Text("New check-in").font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func treatmentCard(_ t: Treatment) -> some View {
        let weeks = HairAnalytics.weeksElapsed(since: t.startDate)
        let progress = HairAnalytics.outcomeProgress(weeksElapsed: weeks)
        let ready = HairAnalytics.outcomeReady(weeksElapsed: weeks)
        let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
        // Expected-per-day comes from the actual schedule, so `.other`-class daily items
        // (e.g. products added from the science list) accrue adherence like any medication.
        let adherence = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.slots.count)

        return ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: t.treatmentClass.symbol)
                        .font(.system(size: 16)).foregroundStyle(Clinical.accent)
                        .frame(width: 38, height: 38)
                        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Clinical.ink)
                        Text("\(t.treatmentClass.title)\(t.dose.isEmpty ? "" : " · \(t.dose)")")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Refill & side effects") { detailTreatment = t }
                        Button(t.isActive ? "Mark inactive" : "Reactivate") {
                            t.isActive.toggle()
                            // Records the user's own decision and its date — never advises it.
                            // The stop date lets the trend explain itself later (shedding
                            // changes after stopping a treatment often lag by 2–3 months).
                            t.endDate = t.isActive ? nil : .now
                        }
                        Button("Delete", role: .destructive) { context.delete(t) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Clinical.tertiary)
                            .frame(width: 30, height: 30)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Week \(weeks) of \(HairAnalytics.outcomeWindowWeeks)")
                            .font(Clinical.number(13)).foregroundStyle(Clinical.ink)
                        Spacer()
                        Text(ready ? "Ready to assess" : "Too early to judge")
                            .font(Clinical.eyebrow(11))
                            .foregroundStyle(ready ? Clinical.positive : Clinical.tertiary)
                    }
                    ProgressBar(value: progress, tint: ready ? Clinical.positive : Clinical.accent).frame(height: 8)
                }

                if let adherence {
                    HStack {
                        Text("14-day adherence").font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        Spacer()
                        Text("\(Int((adherence * 100).rounded()))%")
                            .font(Clinical.number(13))
                            .foregroundStyle(adherence >= 0.8 ? Clinical.positive : Clinical.warning)
                    }
                } else {
                    Text("Periodic treatment · logged per session")
                        .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                }

                let urgency = HairAnalytics.refillUrgency(daysLeft: t.daysUntilRefill)
                if urgency == .soon || urgency == .urgent || urgency == .overdue || !t.sideEffects.isEmpty {
                    HStack(spacing: 6) {
                        if let days = t.daysUntilRefill {
                            switch urgency {
                            case .overdue:
                                statusChip("Refill overdue", symbol: "pills.circle", tint: Clinical.critical)
                            case .urgent, .soon:
                                statusChip(days == 0 ? "Refill due today" : "Refill in \(days) day\(days == 1 ? "" : "s")",
                                           symbol: "pills.circle", tint: Clinical.warning)
                            case .ok, .none:
                                EmptyView()
                            }
                        }
                        if !t.sideEffects.isEmpty {
                            statusChip("\(t.sideEffects.count) side effect\(t.sideEffects.count == 1 ? "" : "s")",
                                       symbol: "waveform.path.ecg", tint: Clinical.tertiary)
                        }
                    }
                }

                if !t.isActive {
                    Text(t.endDate.map { "Stopped \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Inactive")
                        .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
                }

                // The strongest evidence for the week-24 judgment is a dated baseline photo set
                // taken at treatment start (Compare/the Visit PDF both depend on one existing) —
                // a quiet, easy-to-dismiss nudge rather than a blocking requirement.
                if t.isActive && !hasBaselinePhoto(for: t) {
                    Label("No baseline photo on record — the week-24 comparison starts from your earliest one.", systemImage: "camera.badge.ellipsis")
                        .font(.system(size: 11.5)).foregroundStyle(Clinical.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .opacity(t.isActive ? 1 : 0.6)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { detailTreatment = t }
    }

    /// True when a progress photo exists within ±7 days of the treatment's start — close enough
    /// to count as its baseline set.
    private func hasBaselinePhoto(for t: Treatment) -> Bool {
        HairAnalytics.hasNearbyDate(anchor: t.startDate, candidates: photoRecords.map(\.createdAt))
    }

    /// Small tinted status pill used on treatment cards (refill countdown, side-effect count).
    private func statusChip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(Clinical.eyebrow(10)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: Dose logging (shared pattern with Today)

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
                    && $0.slot == slot && calendar.isDateInToday($0.loggedAt)
            }) {
                context.delete(existing)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            context.insert(TreatmentDose(treatment: treatment, loggedAt: .now, slot: slot))
            // Light impact, paired with the check circle's spring pop — one quiet tap, not a fanfare.
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

/// One routine step: a class-tinted symbol chip leading, the step text, the info affordance, and
/// a trailing check circle that fills copper with a white checkmark and a spring pop when logged.
/// The tap/log behavior and the info button's action are unchanged from the old row.
private struct RoutineStepRow: View {
    let treatment: Treatment
    let slot: String
    let periodic: Bool
    let done: Bool
    let expanded: Bool
    let onToggle: () -> Void
    let onInfo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop = false
    /// The check circle's diameter, scaled with Dynamic Type so the actual tap target grows
    /// alongside the surrounding row text instead of staying a fixed 24pt dot.
    @ScaledMetric(relativeTo: .body) private var checkDiameter: CGFloat = 24

    /// Meds read copper, device/in-office work reads sage — both straight from the palette.
    private var classTint: Color {
        switch treatment.treatmentClass {
        case .microneedling, .prp, .lllt: return Clinical.sage
        default: return Clinical.accent
        }
    }

    private var name: String {
        treatment.name.isEmpty ? treatment.treatmentClass.title : treatment.name
    }

    /// "08:00 · Minoxidil" collapses to "08:00" when the class title is already in the name.
    private var subtitle: String {
        let lead = periodic ? "As scheduled" : slot
        let cls = treatment.treatmentClass.title
        return name.localizedCaseInsensitiveContains(cls) ? lead : "\(lead) · \(cls)"
    }

    /// Round: dropped the separate (i) button — every row used to carry a filled checkmark AND
    /// an (i) button, redundant chrome on every single step. The whole leading content (icon +
    /// name + subtitle) is now the tap target for the dosing-instruction disclosure; the
    /// checkmark stays its own trailing tap target for logging the dose.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onInfo) {
                    HStack(spacing: 12) {
                        Image(systemName: treatment.treatmentClass.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(classTint)
                            .frame(width: 31, height: 31)
                            .background(classTint.opacity(done ? 0.06 : 0.12),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .opacity(done ? 0.6 : 1)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            // No strikethrough: this is a current-medication list, and a
                            // struck-through drug name reads clinically as "discontinued" —
                            // precisely what this app must never imply. Done-ness is conveyed by
                            // the filled check + dimmed text only.
                            Text(name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(done ? Clinical.secondary : Clinical.ink)
                            Text(subtitle)
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name), \(subtitle)")
                .accessibilityHint("Shows dosing instructions")
                Spacer()
                checkButton
            }
            if expanded {
                Text(TreatmentGuide.instruction(for: treatment.treatmentClass))
                    .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    .padding(.leading, 43)   // aligns under the text column (31pt chip + 12 gap)
            }
        }
    }

    private var checkButton: some View {
        Button {
            let willCheck = !done
            onToggle()
            guard willCheck, !reduceMotion else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pop = true
            } completion: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
            }
        } label: {
            ZStack {
                // Unchecked reads as an actionable empty checkbox — a faint copper fill plus a
                // stronger copper stroke — rather than the old near-invisible hairline dot that
                // lost to the (i) info glyph for visual weight on the row.
                Circle().fill(done ? Clinical.accent : Clinical.accent.opacity(0.06))
                Circle().strokeBorder(done ? Clinical.accent : Clinical.accent.opacity(0.45), lineWidth: 2)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Clinical.surface)
                }
            }
            .frame(width: checkDiameter, height: checkDiameter)
            .scaleEffect(pop ? 1.15 : 1)
            // Reduce Motion: the fill lands instantly and the pop above never fires.
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: done)
            .frame(width: max(44, checkDiameter + 20), height: max(44, checkDiameter + 20))   // >=44pt hit target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(done ? "Logged" : "Not logged")
    }
}

/// A copper hairline that fills left-to-right as today's routine steps complete — the coach
/// card's one surviving progress visual, now a single living line instead of a separate ring
/// widget. Draws in once with a spring on appear (instant under Reduce Motion), then springs to
/// each new value as steps get checked off.
private struct RoutineHairlineProgress: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Clinical.hairline).frame(height: 2)
                Capsule().fill(Clinical.accent)
                    .frame(width: geo.size.width * (shown ? fraction : 0), height: 2)
            }
        }
        .frame(height: 2)
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: fraction)
        .onAppear {
            guard !shown else { return }
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) { shown = true }
            }
        }
    }
}

/// A simple rounded progress bar in the warm palette — replaces the repeated GeometryReader capsules.
struct ProgressBar: View {
    let value: Double
    var tint: Color = Clinical.accent
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Clinical.canvas)
                Capsule().fill(tint).frame(width: max(6, geo.size.width * min(1, max(0, value))))
            }
        }
    }
}
