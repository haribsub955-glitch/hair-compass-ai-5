import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    let profile: Profile?
    var onOpenBaseline: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]

    @State private var showLog = false
    @State private var insight: DailyInsight?
    @State private var showDeepAnalysis = false
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader
                VStack(alignment: .leading, spacing: 16) {
                    logCard
                    insightCard
                    learnStrip
                    statusCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
        }
        .clinicalScreen()
        .task(id: insightFingerprint) { await refreshInsight() }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_LEARN") { showLearn = true }
            if ProcessInfo.processInfo.arguments.contains("HC_LOG") { showLog = true }
            #endif
        }
        .sheet(isPresented: $showLog) {
            LogSheet(existing: todayEntry, condition: profile?.condition ?? .unsure)
        }
        .sheet(isPresented: $showDeepAnalysis) {
            DeepAnalysisSheet(context: buildContext(), images: analysisImages())
        }
        .sheet(isPresented: $showLearn) {
            NavigationStack {
                LearnView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showLearn = false } } }
            }
        }
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
                Button("Deep analysis with photos") { showDeepAnalysis = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                    .padding(.top, 2)
            }
        }
    }

    /// Redesign v2: the greeting sits *inside* a full-bleed hero, with the profile button and the
    /// streak chip floating over it — one block instead of a separate header + banner.
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Image(BrandArt.todayHero)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(height: 224).frame(maxWidth: .infinity).clipped()
            LinearGradient(
                colors: [Clinical.canvas.opacity(0.06), Clinical.canvas.opacity(0.72), Clinical.canvas],
                startPoint: .top, endPoint: .bottom
            )
            VStack {
                HStack {
                    Spacer()
                    Button(action: onOpenBaseline) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Clinical.ink.opacity(0.85), Clinical.surface.opacity(0.9))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 14)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                        .font(Clinical.eyebrow(10)).tracking(1.4).foregroundStyle(Clinical.secondary)
                    Text(greeting).font(Clinical.headline(31)).foregroundStyle(Clinical.ink)
                }
                Spacer()
                Label("\(streak)-day streak", systemImage: "flame.fill")
                    .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Clinical.surface.opacity(0.85), in: Capsule())
                    .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
        }
        .frame(height: 224)
    }

    private var greeting: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let hour = calendar.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// Redesign v2: log stats and today's routine live in ONE card, not two.
    private var logCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Daily log")
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
