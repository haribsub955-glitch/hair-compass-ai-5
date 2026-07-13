import SwiftData
import SwiftUI

/// The Plan tab: what to do today (routine), how you're doing (coach + milestones), reminders to
/// keep you on track, and the treatment regimen with its 24-week judging gate. Guidance is
/// non-prescriptive — it helps you follow treatments you added, it doesn't tell you what to start.
struct CareView: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationService.self) private var notifications
    @Environment(DeepLinkRouter.self) private var deepLinks
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
                    )
                ).padding(.top, 8)
                    // Same corner-sprig family as Trends/Labs — Plan and Photos were the two
                    // headers left undressed.
                    .background(alignment: .topTrailing) { CornerSprig() }
                    .staggeredEntrance(index: 0)

                // One entrance sequence down the card stack; indices are fixed positions, so a
                // missing conditional card just leaves an invisible 50ms gap.
                if hasRecentSevereSideEffect { severeSideEffectBanner.staggeredEntrance(index: 1) }
                coachCard.staggeredEntrance(index: 2)
                if let milestone = Milestones.achieved(streak: streak, treatments: treatmentWeeks).first {
                    milestoneCard(milestone).staggeredEntrance(index: 3)
                }
                if !routine.isEmpty { routineCard.staggeredEntrance(index: 4) }
                guidanceCard.staggeredEntrance(index: 5)
                remindersCard.staggeredEntrance(index: 6)
                gateExplainer.staggeredEntrance(index: 7)
                if let report = progressReport { progressReportCard(report).staggeredEntrance(index: 8) }

                if treatments.isEmpty {
                    empty.staggeredEntrance(index: 9)
                } else {
                    ForEach(Array(treatments.enumerated()), id: \.element.id) { i, t in
                        // Capped: everything past here is below the fold at load anyway.
                        treatmentCard(t).staggeredEntrance(index: min(9 + i, 13))
                    }
                }

                // Same cap as the last treatment card above — lands in the same beat, no
                // renumbering of the fixed indices elsewhere in this stack required.
                proceduresCard.staggeredEntrance(index: 13)

                // New card, new trailing index — appended past the capped treatment/procedures
                // beat rather than renumbering any index above.
                progressCheckInCard.staggeredEntrance(index: 14)

                // Same trailing pattern one index later — a life event (illness, crash diet,
                // childbirth, a new medication…) is the only entry point to `TriggerEvent`
                // outside onboarding, so every downstream surface that reads dated triggers
                // (journey markers, insights, the clinician export) stays usable for the whole
                // life of the record, not just its first day.
                lifeEventCard.staggeredEntrance(index: 15)

                // No entrance on the science section — HC_SCROLL_PRODUCTS screenshots jump
                // straight to it and must never catch a mid-fade frame.
                ScienceProductsSection().id("science")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
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

    // MARK: Coach

    /// Redesign v3: the text block now drives the card's height in the normal layout flow —
    /// the artwork moved to `.background` (round-3 fix) so it can never stretch the card past
    /// what the copy needs. `msg.detail` used to be clipped mid-word by a fixed-size,
    /// two-line-capped, 220pt-wide `Text` (round-2 regression): it's one sentence, so it now
    /// wraps freely at whatever size Dynamic Type asks for.
    private var coachCard: some View {
        let msg = AdherenceCoach.message(doneToday: doneToday, totalToday: dailySteps.count, streak: streak, weeklyAdherence: nil)
        let progress = dailySteps.isEmpty ? 0 : Double(doneToday) / Double(dailySteps.count)
        return ClinicalCard(padding: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Eyebrow(text: "Coach")
                        if streak > 0 {
                            Label("\(streak)d", systemImage: "flame")
                                .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
                        }
                    }
                    Text(msg.headline).font(Clinical.headline(19)).foregroundStyle(Clinical.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(msg.detail).font(.system(size: 12.5)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if dailySteps.count > 0 {
                    CoachProgressRing(done: doneToday, total: dailySteps.count, progress: progress)
                        .background(
                            // Round-4 fix: the ring used to sit directly on the bottle artwork,
                            // where its pale track nearly vanished against similarly-valued
                            // amber. A dedicated surface disc restores figure/ground for the
                            // ring specifically, on top of the card-wide gradient scrim below.
                            Circle().fill(Clinical.surface.opacity(0.85)).padding(-6)
                        )
                }
            }
            .padding(16)
            .background {
                ZStack {
                    LivingArtwork(art: BrandArt.planRitualV2, travel: 4, zoom: 0.014, phase: 0.4)
                        .opacity(0.28)
                    // The ring sits at the trailing edge, so the gradient's most-faded stop now
                    // sits in the middle (over the artwork, behind neither text nor ring) —
                    // both the headline/detail on the left and the ring on the right land on a
                    // near-opaque stop, so neither reads washed-out or fights the illustration.
                    LinearGradient(
                        stops: [
                            .init(color: Clinical.surface.opacity(0.99), location: 0),
                            // Mid stop kept fairly solid (0.72) so a long two-line detail that
                            // reaches toward centre never sits on washed-out artwork.
                            .init(color: Clinical.surface.opacity(0.72), location: 0.5),
                            .init(color: Clinical.surface.opacity(0.94), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .clipped()
            }
        }
    }

    private var guidanceCard: some View {
        Button { showRecommender = true } label: {
            ClinicalCard(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 16)).foregroundStyle(Clinical.accent)
                        .frame(width: 38, height: 38)
                        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What the evidence supports for you")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                        Text("Ranked options for \(profile?.condition.title.lowercased() ?? "your pattern") — education, not a prescription.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
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

    private func milestoneCard(_ m: Milestone) -> some View {
        ClinicalCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: m.symbol)
                    .font(.system(size: 18)).foregroundStyle(Clinical.gold)
                    .frame(width: 40, height: 40)
                    .background(Clinical.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                    Text(m.body).font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                }
            }
        }
    }

    // MARK: Routine

    private var routineCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Today's routine")
                ForEach(routine, id: \.block.id) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text(entry.block.title)
                        } icon: {
                            Image(systemName: entry.block.symbol)
                                .foregroundStyle(Self.blockTint(entry.block))
                        }
                        .font(Clinical.eyebrow(11)).foregroundStyle(Clinical.tertiary)
                        ForEach(Array(entry.steps.enumerated()), id: \.offset) { _, step in
                            routineRow(step.treatment, slot: step.slot, periodic: entry.block == .periodic)
                        }
                    }
                }
            }
        }
    }

    /// Morning sunrise reads gold, evening moon reads sage; the periodic calendar stays quiet.
    private static func blockTint(_ block: RoutineBlock) -> Color {
        switch block {
        case .morning: return Clinical.gold
        case .evening: return Clinical.sage
        case .periodic: return Clinical.tertiary
        }
    }

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

    private var remindersCard: some View {
        ClinicalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $remindersOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reminders").font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
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

                Divider().overlay(Clinical.hairline)

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
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    // No strikethrough: this is a current-medication list, and a struck-through
                    // drug name reads clinically as "discontinued" — precisely what this app must
                    // never imply. Done-ness is conveyed by the filled check + dimmed text only.
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(done ? Clinical.secondary : Clinical.ink)
                    Text(subtitle)
                        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                }
                Spacer()
                Button(action: onInfo) {
                    Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Clinical.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About this step")
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

/// The coach's adherence ring: full-strength copper over an accent-0.15 track — the same recipe
/// as the Today MEDS tile. Draws once with a spring on appear (Reduce Motion renders instantly);
/// checking a step springs the fill to the new value.
private struct CoachProgressRing: View {
    let done: Int
    let total: Int
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().stroke(Clinical.accent.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: shown ? progress : 0)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(done)").font(Clinical.headline(17)).foregroundStyle(Clinical.ink)
                Text("OF \(total)").font(Clinical.eyebrow(8)).foregroundStyle(Clinical.tertiary)
            }
        }
        .frame(width: 60, height: 60)
        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8), value: progress)
        .onAppear {
            guard !shown else { return }
            if reduceMotion {
                shown = true
            } else {
                // Delayed past the coach card's own entrance so the ring draws after it lands.
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.3)) { shown = true }
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
