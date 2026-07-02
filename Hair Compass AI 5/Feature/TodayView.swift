import SwiftData
import SwiftUI

struct TodayView: View {
    let profile: Profile?
    var onOpenBaseline: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]

    @State private var showLog = false

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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                logCard
                if !activeDaily.isEmpty { treatmentsCard }
                readoutCard
                if let profile { baselineCard(profile) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
        .sheet(isPresented: $showLog) {
            LogSheet(existing: todayEntry, condition: profile?.condition ?? .unsure)
        }
    }

    private var header: some View {
        ScreenHeader(
            eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month().day()),
            title: greeting,
            trailing: AnyView(
                Button(action: onOpenBaseline) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Clinical.ink)
                }
            )
        )
        .padding(.top, 8)
    }

    private var greeting: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let hour = calendar.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var logCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow(text: "Daily log")
                    Spacer()
                    Label("\(streak)-day streak", systemImage: "flame")
                        .font(Clinical.eyebrow(11))
                        .foregroundStyle(streak > 0 ? Clinical.accent : Clinical.tertiary)
                }
                if let entry = todayEntry {
                    HStack(spacing: 18) {
                        miniStat("\(entry.shed.title)", "Shedding")
                        Divider().frame(height: 34)
                        miniStat("\(entry.scalpTotal)/16", "Scalp")
                        Divider().frame(height: 34)
                        miniStat("\(entry.sleepQuality)/5", "Sleep")
                    }
                    Button("Edit today's log") { showLog = true }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                } else {
                    Text("Log shedding, scalp signs, sleep and stress. It takes about 20 seconds.")
                        .font(.system(size: 14))
                        .foregroundStyle(Clinical.secondary)
                    Button("Log today") { showLog = true }
                        .buttonStyle(ClinicalButtonStyle())
                }
            }
        }
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Clinical.number(18))
                .foregroundStyle(Clinical.ink)
            Text(label.uppercased())
                .font(Clinical.eyebrow(9))
                .tracking(1)
                .foregroundStyle(Clinical.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var treatmentsCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Today's treatments")
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

    private func treatmentRow(_ treatment: Treatment, slot: String) -> some View {
        let done = isLogged(treatment, slot: slot)
        return Button {
            toggle(treatment, slot: slot, currentlyDone: done)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Clinical.accent : Clinical.tertiary)
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

    private var readoutCard: some View {
        let condition = profile?.condition ?? .unsure
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Current readout")
                if let entry = latestEntry {
                    if condition.usesScalpScale {
                        readoutRow(
                            "Scalp severity",
                            value: "\(entry.scalpTotal)/16 · \(entry.scalpBand.title)",
                            color: Clinical.bandColor(entry.scalpBand)
                        )
                    }
                    readoutRow("Shedding", value: entry.shed.title, color: Clinical.ink)
                    readoutRow("Recorded", value: entry.date.formatted(.dateTime.month().day()), color: Clinical.secondary)
                } else {
                    Text("No entries yet. Your readout appears after the first daily log.")
                        .font(.system(size: 14))
                        .foregroundStyle(Clinical.secondary)
                }
            }
        }
    }

    private var latestEntry: DailyEntry? { entries.first }

    private func readoutRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Clinical.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func baselineCard(_ profile: Profile) -> some View {
        let notes = HairAnalytics.baselineRiskNotes(familyHistory: profile.familyHistory, condition: profile.condition)
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Baseline")
                    Spacer()
                    Text(profile.condition.shortLabel)
                        .font(Clinical.eyebrow(11))
                        .foregroundStyle(Clinical.accent)
                }
                ForEach(notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Clinical.tertiary).frame(width: 4, height: 4).padding(.top, 7)
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Clinical.secondary)
                    }
                }
                Button("Edit baseline") { onOpenBaseline() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                    .padding(.top, 2)
            }
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
