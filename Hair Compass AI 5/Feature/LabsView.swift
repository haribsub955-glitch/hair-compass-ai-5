import SwiftData
import SwiftUI

struct LabsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LabResult.collectedAt, order: .reverse) private var labs: [LabResult]
    @State private var showAdd = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Bloodwork",
                    title: "Labs",
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

                ClinicalCard(padding: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Clinical.accent)
                        Text("Order tests individually with a clinician, not as a blanket panel. Ranges shown for context only — not a diagnosis.")
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                    }
                }

                if labs.isEmpty {
                    reference
                } else {
                    ForEach(labs) { lab in labRow(lab) }
                    reference
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
        .sheet(isPresented: $showAdd) { AddLabSheet() }
    }

    private func labRow(_ lab: LabResult) -> some View {
        // .swipeActions only functions inside a List row — this screen uses a plain
        // ScrollView, so deletion is a context menu instead (same pattern as Photos/Care).
        ClinicalCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lab.test.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                    Text(lab.collectedAt.formatted(.dateTime.month().day().year()))
                        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    if !lab.note.isEmpty {
                        Text(lab.note).font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(lab.value.formatted(.number.precision(.fractionLength(0...1)))) \(lab.test.unit)")
                        .font(Clinical.number(16)).foregroundStyle(Clinical.ink)
                    Text(lab.flag.title)
                        .font(Clinical.eyebrow(10))
                        .foregroundStyle(Clinical.flagColor(lab.flag))
                }
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) { context.delete(lab) }
        }
    }

    private var reference: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Tests derms order for hair loss")
                ForEach(LabTest.allCases) { test in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(test.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Text("\(test.referenceRange.lowerBound.formatted())–\(test.referenceRange.upperBound.formatted()) \(test.unit)")
                                .font(Clinical.number(12)).foregroundStyle(Clinical.secondary)
                        }
                        Text(test.note).font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                    if test != LabTest.allCases.last { Divider().overlay(Clinical.hairline) }
                }
            }
        }
    }
}
