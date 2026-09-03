import SwiftData
import SwiftUI

/// The full life-events list — every dated `TriggerEvent` (illness, crash diet, major stress,
/// childbirth, a new medication…), newest first. Before this existed, `TriggerEvent` had four
/// insert paths (onboarding, `AddTriggerSheet`, LogSheet's "anything notable happen recently?",
/// and seed data) and no way to see, correct, or delete one — yet triggers drive the journey
/// chart's amber echo bands, Today's telogen-effluvium watch tile, the clinician review flags,
/// and the AI context fed to chat/deep-analysis, for the whole life of the record. Reached from
/// `CareView`'s "Life events" ledger header; presented as its own sheet, mirroring
/// `ProceduresView`'s list-sheet pattern. Tapping a row opens `AddTriggerSheet` in edit mode;
/// context-menu delete is confirm-first, matching every other irreversible delete in the app.
struct LifeEventsSheet: View {
    @Query(sort: \TriggerEvent.date, order: .reverse) private var events: [TriggerEvent]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editing: TriggerEvent?
    /// Non-nil while the delete confirmation dialog is up for a row's context menu — deleting
    /// takes the event's journey-chart marker and amber band with it, so this confirms first.
    @State private var deleteCandidate: TriggerEvent?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(
                        eyebrow: "Dated context",
                        title: "Life events",
                        trailing: AnyView(
                            HeaderActionButton(systemName: "plus", accessibilityLabel: "Log a life event") {
                                showAdd = true
                            }
                        )
                    )
                    .padding(.top, 8)

                    if events.isEmpty {
                        empty
                    } else {
                        ledger
                        Colophon(text: "A private record of your own timeline — not a diagnosis of what caused anything.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .clinicalScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showAdd) { AddTriggerSheet() }
            .sheet(item: $editing) { AddTriggerSheet(existing: $0) }
            .confirmationDialog(
                "Delete this life event?",
                isPresented: Binding(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let event = deleteCandidate { context.delete(event) }
                    deleteCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
            } message: {
                Text("Its journey-chart marker and amber band go with it — this can't be undone.")
            }
        }
    }

    private var empty: some View {
        ClinicalCard {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(Clinical.caption(32)).foregroundStyle(Clinical.accent)
                Eyebrow(text: "No life events logged")
                Text("An illness, a crash diet, childbirth, major stress, or a new medication — dating it lets a shedding change 2–3 months later explain itself instead of looking random.")
                    .font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
                Button("Log a life event") { showAdd = true }
                    .buttonStyle(ClinicalButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline)
            ForEach(events) { event in
                row(event)
                Divider().overlay(Clinical.hairline)
            }
        }
    }

    private func row(_ event: TriggerEvent) -> some View {
        Button { editing = event } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.type.symbol)
                    .font(Clinical.caption(15))
                    .foregroundStyle(Clinical.warning)
                    .frame(width: 34, height: 34)
                    .background(Clinical.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.type.title).font(Clinical.body(15, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text(subtitle(event)).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    if !event.note.isEmpty {
                        Text(event.note)
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") { editing = event }
            Button("Delete", role: .destructive) { deleteCandidate = event }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this event to edit or delete it")
    }

    /// "Jul 12, 2026 · effect may show ~Sep–Oct" — the dated event plus the ~8–12-week window it
    /// teaches, so a mis-remembered date is easy to spot from the list alone, without opening the
    /// journey chart to check it against the amber band.
    private func subtitle(_ event: TriggerEvent) -> String {
        let when = event.date.formatted(date: .abbreviated, time: .omitted)
        return "\(when) · effect may show ~\(echoWindowLabel(event.date))"
    }

    /// Month range 8–12 weeks after the event's date — matches `JourneyData.EchoBand`'s own
    /// 8...12-week math in `JourneyChart.swift` so this list never disagrees with the chart.
    private func echoWindowLabel(_ date: Date) -> String {
        let week: TimeInterval = 7 * 24 * 3600
        let start = date.addingTimeInterval(8 * week)
        let end = date.addingTimeInterval(12 * week)
        let startMonth = start.formatted(.dateTime.month(.abbreviated))
        let endMonth = end.formatted(.dateTime.month(.abbreviated))
        return startMonth == endMonth ? startMonth : "\(startMonth)–\(endMonth)"
    }
}
