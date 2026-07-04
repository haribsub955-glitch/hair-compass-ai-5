import SwiftData
import SwiftUI

/// The Plan tab: what to do today (routine), how you're doing (coach + milestones), reminders to
/// keep you on track, and the treatment regimen with its 24-week judging gate. Guidance is
/// non-prescriptive — it helps you follow treatments you added, it doesn't tell you what to start.
struct CareView: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationService.self) private var notifications
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query private var sideEffectLogs: [SideEffectLog]
    @Query private var labs: [LabResult]
    @Query private var triggerEvents: [TriggerEvent]

    @State private var showAdd = false
    @State private var showRecommender = false
    @State private var remindersOn = false
    @State private var expandedSteps: Set<String> = []
    @State private var detailTreatment: Treatment?
    @State private var showReport = false

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
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Clinical.surface)
                                .frame(width: 34, height: 34)
                                .background(Clinical.ink, in: Circle())
                        }
                    )
                ).padding(.top, 8)

                if hasRecentSevereSideEffect { severeSideEffectBanner }
                coachCard
                if let milestone = Milestones.achieved(streak: streak, treatments: treatmentWeeks).first {
                    milestoneCard(milestone)
                }
                if !routine.isEmpty { routineCard }
                guidanceCard
                remindersCard
                gateExplainer
                if let report = progressReport { progressReportCard(report) }

                if treatments.isEmpty {
                    empty
                } else {
                    ForEach(treatments) { t in treatmentCard(t) }
                }

                ScienceProductsSection().id("science")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
        .sheet(isPresented: $showAdd) { AddTreatmentSheet() }
        .sheet(item: $detailTreatment) { TreatmentDetailSheet(treatment: $0) }
        .sheet(isPresented: $showReport) {
            if let report = progressReport { ProgressReportSheet(report: report) }
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
            #endif
        }
        .task(id: treatmentFingerprint) {
            await notifications.reschedule(treatments: notifTreatments, refills: notifRefills)
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
    private var treatmentFingerprint: String {
        activeTreatments.map { "\($0.name)\($0.scheduleTimes)\($0.isActive)\($0.refillBy?.timeIntervalSince1970 ?? 0)" }.joined(separator: "|")
    }
    private var streak: Int { HairAnalytics.loggingStreak(entryDates: entries.map(\.date)) }
    private var hasRecentSevereSideEffect: Bool {
        HairAnalytics.hasRecentSevereSideEffect(logs: sideEffectLogs.map { ($0.severity, $0.date) })
    }

    /// The periodic synthesis — nil until there's an active daily treatment or ≥ 8 weeks of logs.
    private var progressReport: ProgressReport? {
        ProgressReport.build(
            entries: entries, treatments: treatments, doses: doses,
            labs: labs, sideEffects: sideEffectLogs, triggers: triggerEvents
        )
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

    /// Redesign v2: progress reads as a ring on the trailing side, not a bar.
    private var coachCard: some View {
        let msg = AdherenceCoach.message(doneToday: doneToday, totalToday: dailySteps.count, streak: streak, weeklyAdherence: nil)
        let progress = dailySteps.isEmpty ? 0 : Double(doneToday) / Double(dailySteps.count)
        return ClinicalCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Eyebrow(text: "Coach")
                        if streak > 0 {
                            Label("\(streak)d", systemImage: "flame")
                                .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
                        }
                    }
                    Text(msg.headline).font(Clinical.headline(21)).foregroundStyle(Clinical.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(msg.detail).font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if dailySteps.count > 0 {
                    ZStack {
                        Circle().stroke(Clinical.hairline, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text("\(doneToday)").font(Clinical.headline(17)).foregroundStyle(Clinical.ink)
                            Text("OF \(dailySteps.count)").font(Clinical.eyebrow(8)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                    .frame(width: 60, height: 60)
                }
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
                        Label(entry.block.title, systemImage: entry.block.symbol)
                            .font(Clinical.eyebrow(11)).foregroundStyle(Clinical.tertiary)
                        ForEach(Array(entry.steps.enumerated()), id: \.offset) { _, step in
                            routineRow(step.treatment, slot: step.slot, periodic: entry.block == .periodic)
                        }
                    }
                }
            }
        }
    }

    private func routineRow(_ t: Treatment, slot: String, periodic: Bool) -> some View {
        let key = "\(t.persistentModelID.hashValue)|\(slot)"
        let done = isLogged(t, slot: slot)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    toggle(t, slot: slot, currentlyDone: done)
                } label: {
                    ZStack {
                        Circle().strokeBorder(done ? Clinical.accent : Clinical.hairline, lineWidth: 1.5).frame(width: 24, height: 24)
                        if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Clinical.accent) }
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name.isEmpty ? t.treatmentClass.title : t.name)
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                        .strikethrough(done, color: Clinical.tertiary)
                    Text(periodic ? "As scheduled · \(t.treatmentClass.title)" : "\(slot) · \(t.treatmentClass.title)")
                        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                }
                Spacer()
                Button {
                    if expandedSteps.contains(key) { expandedSteps.remove(key) } else { expandedSteps.insert(key) }
                } label: {
                    Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Clinical.tertiary)
                }
                .buttonStyle(.plain)
            }
            if expandedSteps.contains(key) {
                Text(TreatmentGuide.instruction(for: t.treatmentClass))
                    .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    .padding(.leading, 36)
            }
        }
    }

    // MARK: Reminders

    private var remindersCard: some View {
        ClinicalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $remindersOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminders").font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                        Text("Nudge me at my routine times and each evening.")
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
    /// (4 · 12 · 24, then every 12).
    private func progressReportCard(_ report: ProgressReport) -> some View {
        let milestone = report.isMilestoneWeek
        return Button { showReport = true } label: {
            ClinicalCard(padding: 16) {
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
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Clinical.accent.opacity(milestone ? 0.55 : 0), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
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
                        Button(t.isActive ? "Mark inactive" : "Reactivate") { t.isActive.toggle() }
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
                    Text("Inactive").font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
        .opacity(t.isActive ? 1 : 0.6)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { detailTreatment = t }
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
