import SwiftData
import SwiftUI
import UIKit

/// The Plan tab: what to do today (routine), how you're doing (coach + milestones), reminders to
/// keep you on track, and the treatment regimen with its 24-week judging gate. Guidance is
/// non-prescriptive — it helps you follow treatments you added, it doesn't tell you what to start.
struct CareView: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationService.self) private var notifications
    @Environment(DeepLinkRouter.self) private var deepLinks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
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
    /// Whether the collapsed "Reminders · Off" footnote is sprung open to its two toggles —
    /// starts collapsed every fresh appearance of the screen, same as the ledger's own
    /// collapsed-unlogged row.
    @State private var remindersExpanded = false
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
    /// Opens `LifeEventsSheet` — the full list of dated `TriggerEvent`s, view/edit/delete —
    /// rather than jumping straight to the add form; mirrors `showProcedures`.
    @State private var showLifeEvents = false
    /// 0…1 fraction driving the header's scroll-condense (see `ScreenHeader.condensed`) — set
    /// directly from the ScrollView's own content offset.
    @State private var headerCondense: CGFloat = 0
    /// Non-nil while the "Delete" confirmation dialog is up for a treatment card's ellipsis
    /// menu — deleting cascades away every logged dose and side-effect entry (`Models.swift`'s
    /// `.cascade` delete rules), so this is a confirm-first path with "Mark inactive instead"
    /// offered alongside the destructive action.
    @State private var deleteTreatmentCandidate: Treatment?

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
                    eyebrow: "Ritual",
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
                // missing conditional card just leaves an invisible 50ms gap. The coach card —
                // and the "N steps left today" subtitle that briefly replaced it — are both gone:
                // that fact already lives in Today's ROUTINE annotation and in the unchecked
                // circles of the list below, so the header now flows straight into the routine
                // section itself, the page's uncontested focal object.
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
                proceduresSection.staggeredEntrance(index: 12)

                // New card, new trailing index — appended past the capped treatment/procedures
                // beat rather than renumbering any index above.
                progressCheckInSection.staggeredEntrance(index: 13)

                // Same trailing pattern one index later — a life event (illness, crash diet,
                // childbirth, a new medication…) is the only entry point to `TriggerEvent`
                // outside onboarding, so every downstream surface that reads dated triggers
                // (journey markers, insights, the clinician export) stays usable for the whole
                // life of the record, not just its first day.
                lifeEventSection.staggeredEntrance(index: 14)

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
        // Deleting a treatment cascades away every logged dose and side-effect entry
        // (`Models.swift`'s `.cascade` delete rules) — the adherence history the 24-week
        // judgment depends on — so this confirms first and offers "Mark inactive instead" as a
        // non-destructive way to stop a treatment without losing its record.
        .confirmationDialog(
            deleteTreatmentTitle,
            isPresented: Binding(
                get: { deleteTreatmentCandidate != nil },
                set: { if !$0 { deleteTreatmentCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let t = deleteTreatmentCandidate {
                Button("Mark inactive instead") {
                    t.isActive = false
                    t.endDate = .now
                    deleteTreatmentCandidate = nil
                }
                Button("Delete", role: .destructive) {
                    context.delete(t)
                    deleteTreatmentCandidate = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteTreatmentCandidate = nil }
        } message: {
            Text(deleteTreatmentMessage)
        }
        .sheet(isPresented: $showProcedures) { ProceduresView() }
        .sheet(isPresented: $showLifeEvents) { LifeEventsSheet() }
        .sheet(isPresented: $showProgressCheckIn) {
            ProgressCheckInSheet(
                treatmentContext: progressCheckInTreatmentContext,
                showsPatchQuestion: profile?.condition == .alopeciaAreata
            )
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
        // A procedure-reminder tap (the day-before consultation nudge) lands here already on
        // Plan — open the procedures list, whose appointment detail sheet offers "Prepare visit
        // report" for consultations, delivering on what the reminder promised.
        .onChange(of: deepLinks.openProceduresRequested) { _, requested in
            guard requested else { return }
            deepLinks.openProceduresRequested = false
            showProcedures = true
        }
        // The monthly progress check-in reminder lands here already on Plan — open the sheet
        // directly instead of leaving the user to find it at staggered index 13.
        .onChange(of: deepLinks.openProgressCheckInRequested) { _, requested in
            guard requested else { return }
            deepLinks.openProgressCheckInRequested = false
            showProgressCheckIn = true
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

    /// "Delete "Minoxidil"?" — the treatment name, quoted, falling back to its class title for
    /// treatments the user never named.
    private var deleteTreatmentTitle: String {
        guard let t = deleteTreatmentCandidate else { return "" }
        let name = t.name.isEmpty ? t.treatmentClass.title : t.name
        return "Delete \"\(name)\"?"
    }

    /// Spells out exactly what the cascade delete takes with it, so the destructive button in
    /// the dialog above is never a surprise — and points at the non-destructive alternative.
    private var deleteTreatmentMessage: String {
        guard let t = deleteTreatmentCandidate else { return "" }
        let doseCount = t.doses.count
        let sideEffectCount = t.sideEffects.count
        var parts: [String] = []
        if doseCount > 0 { parts.append("\(doseCount) logged dose\(doseCount == 1 ? "" : "s")") }
        if sideEffectCount > 0 { parts.append("\(sideEffectCount) side-effect entr\(sideEffectCount == 1 ? "y" : "ies")") }
        let consequence = parts.isEmpty
            ? "This can't be undone."
            : "This also deletes \(parts.joined(separator: " and ")) — it can't be undone."
        return consequence + " Consider \"Mark inactive instead\" to keep the history."
    }

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
    private var notifProcedures: [(id: String, title: String, date: Date, isConsultation: Bool)] {
        upcomingProcedures.map { (String($0.persistentModelID.hashValue), $0.type.title, $0.date, $0.type == .consultation) }
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
        NotificationService.eveningCheckInComponents(minutesSinceMidnight: eveningCheckInMinutes)
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
    // MARK: Routine progress

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
    /// Round-7: restyled to match the Evidence/Reminders footnote family below it — the hourglass
    /// glyph and mono small-caps face are gone, replaced by a 12pt copper circular-progress ring
    /// (the same reading `milestoneProgress` already computed) and a plain 13pt sentence. The tail
    /// used to mix four typographic families across five rows; this is now one of them.
    private func milestoneFootnote(_ m: Milestone) -> some View {
        let progress = milestoneProgress(m)
        return HStack(spacing: 8) {
            MilestoneProgressRing(progress: progress ?? 1)
            Text(milestoneDisplayTitle(m, progress: progress))
                .font(Clinical.body(13, weight: .medium))
                .foregroundStyle(Clinical.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.title). \(m.body)")
    }

    /// "Finasteride 1mg · 83% to week 24" — one internally-true clause. Round-8: a "half-"
    /// milestone's own title always says the fixed phrase "halfway there" regardless of whether
    /// the treatment is at week 12 or week 23, so pasting the live percentage next to it produced
    /// a footnote that disagreed with itself ("halfway there · 83%"). A "half-" milestone now
    /// drops the stale tier phrase and states the one number the ring is also drawing; the
    /// streak/24-week-reached titles (which don't carry a stale bucket phrase) keep the original
    /// "·"-joined wording.
    private func milestoneDisplayTitle(_ m: Milestone, progress: Double?) -> String {
        if m.id.hasPrefix("half-") {
            let name = String(m.id.dropFirst("half-".count))
            if let progress {
                return "\(name) · \(Int((progress * 100).rounded()))% to week 24"
            }
            return name
        }
        var text = m.title.replacingOccurrences(of: ": ", with: " · ")
        if let progress, progress < 1 {
            text += " · \(Int((progress * 100).rounded()))%"
        }
        return text
    }

    /// A single hairline-ruled footnote row — decongested from an icon-tile card with its own
    /// subtitle. "Education, not a prescription" now lives inside the sheet this opens (see
    /// `TreatmentRecommender.disclaimer` in `RecommenderView`) instead of being said twice.
    /// Round-9: the leading stethoscope glyph is gone — the last purely decorative icon among
    /// this tail's three footnote rows — so this row reads exactly like `remindersCard` below it:
    /// text in ink, chevron in the margin, hairline above, nothing else.
    private var guidanceCard: some View {
        Button { showRecommender = true } label: {
            VStack(spacing: 0) {
                Divider().overlay(Clinical.hairline)
                HStack(spacing: 10) {
                    Text("What the evidence supports for you")
                        .font(Clinical.body(14, weight: .medium))
                        .foregroundStyle(Clinical.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(Clinical.body(11, weight: .semibold))
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
                    .font(Clinical.caption(16)).foregroundStyle(Clinical.critical)
                Text("You logged a severe side effect — worth discussing with your prescriber.")
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.ink)
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

    /// A one-line footnote — "Reminders · Off" — in the same family as the Evidence row above it,
    /// replacing the permanent two-toggle settings block that used to sit on this doing-page every
    /// visit. Springs open inline (opacity-only under Reduce Motion) to reveal the same two toggles,
    /// unchanged, so nothing about the reminder controls themselves is lost — only their default
    /// visibility.
    private var remindersSummaryLabel: String {
        switch (remindersOn, eveningCheckInEnabled) {
        case (true, true): return "Routine + evening"
        case (true, false): return "Routine"
        case (false, true): return "Evening"
        case (false, false): return "Off"
        }
    }

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline)
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                if reduceMotion {
                    remindersExpanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { remindersExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Reminders · \(remindersSummaryLabel)")
                        .font(Clinical.body(14, weight: .medium))
                        .foregroundStyle(Clinical.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(Clinical.body(11, weight: .semibold))
                        .foregroundStyle(Clinical.accent)
                        .rotationEffect(.degrees(remindersExpanded ? 90 : 0))
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.clinicalPressable)
            .accessibilityLabel("Reminders, \(remindersSummaryLabel)")
            .accessibilityHint(remindersExpanded ? "Collapses reminder settings" : "Expands reminder settings")

            if remindersExpanded {
                remindersDetail
                    .padding(.bottom, 12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            Divider().overlay(Clinical.hairline)
        }
    }

    private var remindersDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $remindersOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Routine reminders").font(Clinical.body(15, weight: .medium)).foregroundStyle(Clinical.ink)
                        Text("Nudge me at my routine times.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
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
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)

            Divider().overlay(Clinical.hairline).padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $eveningCheckInEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evening check-in").font(Clinical.body(15, weight: .medium)).foregroundStyle(Clinical.ink)
                        Text("One invite at a time you pick — off until you turn it on.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }
                }
                .tint(Clinical.accent)
                if eveningCheckInEnabled {
                    DatePicker("Reminder time", selection: eveningCheckInTime, displayedComponents: .hourAndMinute)
                        .font(Clinical.caption(13))
                        .tint(Clinical.accent)
                }
            }

            if notifications.authorization == .denied {
                notifDeniedNotice
            }
            if let schedulingError = notifications.schedulingError {
                Label(schedulingError, systemImage: "exclamationmark.triangle.fill")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    /// iOS never re-presents the system permission sheet once someone has answered it, so a
    /// toggle attempt while `.denied` fails silently — no sheet, no explanation, just the switch
    /// snapping back off, indistinguishable from a broken control. This row replaces that silence:
    /// shown both proactively (this only renders inside `remindersDetail`, i.e. while the section
    /// is expanded) and immediately after either toggle above reverts itself, since both flip
    /// `notifications.authorization` to `.denied` on the same read. `.notDetermined` — someone who
    /// hasn't been asked yet — gets no special copy here; that toggle attempt still shows the
    /// normal system prompt and only earns this row if they decline it.
    private var notifDeniedNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Clinical.hairline).padding(.vertical, 4)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bell.slash.fill")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.warning)
                    .padding(.top, 1)
                Text("Notifications are off for Hair Compass in iOS Settings.")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            }
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(ClinicalButtonStyle(filled: false))
            .accessibilityIdentifier("careRemindersOpenSettings")
        }
    }

    // MARK: 24-week gate + treatments (unchanged evidence framing)

    /// Round-5: demoted from a boxed `ClinicalCard` with its own icon tile — the page's last
    /// surviving box — to a plain hairline-ruled footnote row in the same family as
    /// `guidanceCard`/`remindersCard`. Round-7: shortened from a three-line paragraph to the one
    /// sentence that actually matters — the tail was stacking four typographic families across
    /// five rows, and this closing line was the longest of them. Round-9: promoted to the shared
    /// `Colophon` component — the app's one closing-sentence voice — so this line and Labs'
    /// equivalent "context, not a diagnosis" line read as the same hand's writing.
    private var gateExplainer: some View {
        Colophon(text: "Density change is judged at 24 weeks — resist judging sooner.")
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
                            .font(Clinical.caption(16))
                            .foregroundStyle(milestone ? Clinical.surface : Clinical.accent)
                            .frame(width: 38, height: 38)
                            .background(milestone ? Clinical.accent : Clinical.accentSoft,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Progress report")
                                    .font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.ink)
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
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Text("View report")
                                .font(Clinical.body(13, weight: .semibold)).foregroundStyle(Clinical.accent)
                            Image(systemName: "chevron.right")
                                .font(Clinical.body(11, weight: .semibold)).foregroundStyle(Clinical.accent)
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
                .font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
            Button("Add treatment") { showAdd = true }
                .buttonStyle(ClinicalButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Procedures

    /// Round-6: dissolved out of its own `ClinicalCard` into a continuation of the same
    /// hairline-ruled ledger the rest of the page reads as — an eyebrow heading row that opens
    /// `ProceduresView`, then each upcoming appointment as a dated entry row. Same data, same
    /// destination, no card edge.
    private var proceduresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline)
            ledgerSectionHeader("Procedures") { showProcedures = true }
            if upcomingProcedures.isEmpty {
                Text("Book PRP, microneedling, or another in-clinic procedure and get a reminder the day before.")
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 13)
            } else {
                ForEach(upcomingProcedures.prefix(2)) { appt in
                    LedgerEntryRow(
                        date: appt.date.formatted(.dateTime.month(.abbreviated).day()),
                        title: appt.type.title,
                        caption: appt.date.formatted(date: .omitted, time: .shortened)
                    )
                }
                if upcomingProcedures.count > 2 {
                    Text("+ \(upcomingProcedures.count - 2) more")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
                        .padding(.bottom, 10)
                }
            }
            Divider().overlay(Clinical.hairline)
        }
    }

    // MARK: Life events (dated TE triggers)

    /// A ledger section in the same family as `proceduresSection`: the most recent recorded
    /// event (if any) as a dated row, an eyebrow heading that opens the full `LifeEventsSheet`
    /// list — view, edit, or delete any dated event, not just add another one. Kept quiet and
    /// optional — this is a record, never a prompt suggesting something is wrong.
    private var lifeEventSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline)
            ledgerSectionHeader("Life events") { showLifeEvents = true }
            if let latest = triggerEvents.sorted(by: { $0.date > $1.date }).first {
                LedgerEntryRow(
                    date: latest.date.formatted(.dateTime.month(.abbreviated).day()),
                    title: latest.type.title
                )
                .padding(.bottom, 10)
            } else {
                Text("An illness, a crash diet, childbirth, major stress, or a new medication — dating it lets a shedding change 2–3 months later explain itself instead of looking random.")
                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 13)
            }
            Divider().overlay(Clinical.hairline)
        }
    }

    /// A quiet eyebrow-heading row that opens a destination — the shared header for Plan's
    /// below-the-fold ledger sections (Procedures, Life events, Progress check-in). Replaces each
    /// section's old boxed `Eyebrow + chevron` row with the exact same tap target and chevron,
    /// just without the card it used to sit inside.
    private func ledgerSectionHeader(_ title: String, trailing: AnyView? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Eyebrow(text: title)
                if let trailing { trailing }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(Clinical.body(11, weight: .semibold))
                    .foregroundStyle(Clinical.tertiary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
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
    /// trend, overall, scalp red flag), captured monthly. Round-6: dissolved into the same
    /// ledger section language as `proceduresSection`/`lifeEventSection` — the heading row itself
    /// opens the new check-in sheet, the "Due" chip rides beside it, and the last-check-in date
    /// plus the explainer sentence continue underneath as plain lines instead of a boxed form.
    private var progressCheckInSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline)
            ledgerSectionHeader(
                "Progress check-in",
                trailing: isProgressCheckInDue
                    ? AnyView(statusChip("Due", symbol: "calendar.badge.exclamationmark", tint: Clinical.warning))
                    : nil
            ) { showProgressCheckIn = true }
            Text(checkIns.first.map { "Last check-in \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "Not done yet")
                .font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.ink)
            Text("The between-visit questions a dermatologist asks — new baby hairs, density, shedding, hairline, scalp symptoms.")
                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 13)
            Divider().overlay(Clinical.hairline)
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
                        .font(Clinical.caption(16)).foregroundStyle(Clinical.accent)
                        .frame(width: 38, height: 38)
                        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(Clinical.body(16, weight: .semibold)).foregroundStyle(Clinical.ink)
                        Text("\(t.treatmentClass.title)\(t.dose.isEmpty ? "" : " · \(t.dose)")")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
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
                        Button("Delete", role: .destructive) { deleteTreatmentCandidate = t }
                    } label: {
                        Image(systemName: "ellipsis").font(Clinical.caption(16)).foregroundStyle(Clinical.tertiary)
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
                        Text("14-day adherence").font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                        Spacer()
                        Text("\(Int((adherence * 100).rounded()))%")
                            .font(Clinical.number(13))
                            .foregroundStyle(adherence >= 0.8 ? Clinical.positive : Clinical.warning)
                    }
                } else {
                    Text("Periodic treatment · logged per session")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
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
                        .font(Clinical.caption(11.5)).foregroundStyle(Clinical.warning)
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
    /// Round-5: the row's one purposeful "ink" gesture on completion — a copper underline draws
    /// itself in beneath the step's name, holds while the text settles to its dimmed secondary
    /// color, then fades for good. Round-9: the flourish itself moved into the shared
    /// `completionInkUnderline` view modifier (Clinical.swift) so Today's ledger row completes
    /// with the exact same ink gesture — this just flips `inkTrigger` on a genuine check-off
    /// (never on uncheck).
    @State private var inkTrigger = false
    /// The check circle's diameter, scaled with Dynamic Type so the actual tap target grows
    /// alongside the surrounding row text instead of staying a fixed 24pt dot.
    @ScaledMetric(relativeTo: .body) private var checkDiameter: CGFloat = 24

    private var name: String {
        treatment.name.isEmpty ? treatment.treatmentClass.title : treatment.name
    }

    /// The left-hand ledger column — a slot time ("08:00") or, for a periodic care product with
    /// no clock time, a short "TODAY" in the same monospaced column, matching Today's own signal
    /// ledger typography instead of a tinted class-icon square.
    private var timeLabel: String {
        periodic ? "TODAY" : slot
    }

    /// The class title only shows up as its own line when the treatment's own name doesn't
    /// already say it (e.g. a treatment literally named "Minoxidil" doesn't need "Minoxidil"
    /// repeated underneath).
    private var classSubtitle: String? {
        let cls = treatment.treatmentClass.title
        return name.localizedCaseInsensitiveContains(cls) ? nil : cls
    }

    /// Round-6: the 31pt tinted class-icon square is gone — the last card-chrome holdout inside
    /// the ritual column. What replaces it is ledger typography: a small monospaced time/"TODAY"
    /// column on the left (matching Today's signal ledger), the treatment name in ink, and its
    /// class as a secondary line only when it isn't already implied by the name.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onInfo) {
                    HStack(spacing: 12) {
                        Text(timeLabel.uppercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Clinical.secondary)
                            .frame(width: 46, alignment: .leading)
                            .opacity(done ? 0.55 : 1)
                        VStack(alignment: .leading, spacing: 2) {
                            // No strikethrough: this is a current-medication list, and a
                            // struck-through drug name reads clinically as "discontinued" —
                            // precisely what this app must never imply. Done-ness is conveyed by
                            // the filled check + dimmed text, animated so the settle itself reads
                            // as purposeful, plus the transient copper underline flourish below
                            // (never permanent, so it can't be misread as a strike).
                            Text(name)
                                .font(Clinical.body(15, weight: .medium))
                                .foregroundStyle(done ? Clinical.secondary : Clinical.ink)
                                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: done)
                                .completionInkUnderline(trigger: $inkTrigger)
                            if let classSubtitle {
                                Text(classSubtitle)
                                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Shows dosing instructions")
                Spacer()
                checkButton
            }
            if expanded {
                Text(TreatmentGuide.instruction(for: treatment.treatmentClass))
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    .padding(.leading, 58)   // aligns under the text column (46pt time column + 12 gap)
            }
        }
    }

    /// Spoken form of what the row now shows visually — the time/"as scheduled" lead plus the
    /// class, exactly what the old combined `subtitle` string used to say.
    private var accessibilityLabel: String {
        let lead = periodic ? "As scheduled" : slot
        let cls = classSubtitle.map { ", \($0)" } ?? ""
        return "\(name), \(lead)\(cls)"
    }

    private var checkButton: some View {
        Button {
            let willCheck = !done
            onToggle()
            guard willCheck else { return }
            if !reduceMotion {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                    pop = true
                } completion: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
                }
            }
            inkTrigger = true
        } label: {
            ZStack {
                // Unchecked reads as an actionable empty checkbox — a faint copper fill plus a
                // stronger copper stroke — rather than the old near-invisible hairline dot that
                // lost to the (i) info glyph for visual weight on the row.
                Circle().fill(done ? Clinical.accent : Clinical.accent.opacity(0.06))
                Circle().strokeBorder(done ? Clinical.accent : Clinical.accent.opacity(0.45), lineWidth: 2)
                if done {
                    Image(systemName: "checkmark")
                        .font(Clinical.body(11, weight: .bold))
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

/// Round-7: the milestone footnote's leading mark — a tiny 12pt copper ring standing in for the
/// hourglass glyph + mono percentage it replaced. Its arc fills once on first appearance with a
/// soft spring, matching every other one-time draw-in in this file; under Reduce Motion it simply
/// appears already at its final reading, with no arc animation.
private struct MilestoneProgressRing: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        ZStack {
            Circle().stroke(Clinical.hairline, lineWidth: 2)
            Circle()
                .trim(from: 0, to: filled ? min(1, max(0, progress)) : 0)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .onAppear {
            guard !filled else { return }
            if reduceMotion {
                filled = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.15)) { filled = true }
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

/// A quiet ledger entry row: a small monospaced date column on the left, a title in ink, and an
/// optional caption line — used by Plan's below-the-fold sections (Procedures, Life events) once
/// they dissolved out of their `ClinicalCard`s. No card, no icon tile; hairline `Divider`s drawn
/// by the section around it separate entries.
private struct LedgerEntryRow: View {
    let date: String
    let title: String
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(date.uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Clinical.tertiary)
                .frame(width: 40, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.ink)
                if let caption {
                    Text(caption).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.map { "\(title), \($0), \(date)" } ?? "\(title), \(date)")
    }
}
