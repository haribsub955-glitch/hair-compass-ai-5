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

    @State private var showAdd = false
    @State private var showRecommender = false
    @State private var remindersOn = false
    @State private var expandedSteps: Set<String> = []

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

                coachCard
                if let milestone = Milestones.achieved(streak: streak, treatments: treatmentWeeks).first {
                    milestoneCard(milestone)
                }
                if !routine.isEmpty { routineCard }
                guidanceCard
                remindersCard
                gateExplainer

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
            #endif
        }
        .task(id: treatmentFingerprint) {
            await notifications.reschedule(treatments: notifTreatments)
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
    private var treatmentFingerprint: String {
        activeTreatments.map { "\($0.name)\($0.scheduleTimes)\($0.isActive)" }.joined(separator: "|")
    }
    private var streak: Int { HairAnalytics.loggingStreak(entryDates: entries.map(\.date)) }

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

    private var coachCard: some View {
        let msg = AdherenceCoach.message(doneToday: doneToday, totalToday: dailySteps.count, streak: streak, weeklyAdherence: nil)
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow(text: "Coach")
                    Spacer()
                    if streak > 0 {
                        Label("\(streak)-day streak", systemImage: "flame")
                            .font(Clinical.eyebrow(11)).foregroundStyle(Clinical.accent)
                    }
                }
                Text(msg.headline).font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
                Text(msg.detail).font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                if dailySteps.count > 0 {
                    ProgressBar(value: Double(doneToday) / Double(dailySteps.count))
                        .frame(height: 8).padding(.top, 2)
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
                            let granted = await notifications.enable(treatments: notifTreatments)
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

    private var empty: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "No treatments")
                Text("Add minoxidil, finasteride, or a procedure to build your daily routine and track the 24-week window.")
                    .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                Button("Add treatment") { showAdd = true }
                    .buttonStyle(ClinicalButtonStyle())
                    .padding(.top, 4)
            }
        }
    }

    private func treatmentCard(_ t: Treatment) -> some View {
        let weeks = HairAnalytics.weeksElapsed(since: t.startDate)
        let progress = HairAnalytics.outcomeProgress(weeksElapsed: weeks)
        let ready = HairAnalytics.outcomeReady(weeksElapsed: weeks)
        let dates = doses.filter { $0.treatment?.persistentModelID == t.persistentModelID }.map(\.loggedAt)
        let adherence = HairAnalytics.adherence(doseDates: dates, expectedPerDay: t.treatmentClass.defaultDailyCount)

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

                if !t.isActive {
                    Text("Inactive").font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
        .opacity(t.isActive ? 1 : 0.6)
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
