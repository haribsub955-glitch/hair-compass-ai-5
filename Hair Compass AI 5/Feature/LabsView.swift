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

    /// Redesign v2: each result reads as a gauge — the value dotted along a 0→high axis with the
    /// healthy reference band shaded, so "in / below / above range" is visible at a glance.
    private func labRow(_ lab: LabResult) -> some View {
        let lo = lab.test.referenceRange.lowerBound
        let hi = lab.test.referenceRange.upperBound
        let domainHi = hi * 1.1               // headroom above the range
        let pct = min(1, max(0, lab.value / domainHi))
        let bandStart = lo / domainHi
        let bandWidth = (hi - lo) / domainHi

        return ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lab.test.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Clinical.ink)
                        Text(lab.collectedAt.formatted(.dateTime.month().day().year()))
                            .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                        if !lab.note.isEmpty {
                            Text(lab.note).font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(lab.value.formatted(.number.precision(.fractionLength(0...1)))) \(lab.test.unit)")
                            .font(Clinical.number(17)).foregroundStyle(Clinical.ink)
                        Text(lab.flag.title).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.flagColor(lab.flag))
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Clinical.hairline.opacity(0.5)).frame(height: 6).offset(y: 4)
                        Capsule().fill(Clinical.positive.opacity(0.22))
                            .frame(width: geo.size.width * bandWidth, height: 6)
                            .offset(x: geo.size.width * bandStart, y: 4)
                        Circle().fill(Clinical.flagColor(lab.flag))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Clinical.surface, lineWidth: 2.5))
                            .offset(x: min(geo.size.width - 14, max(0, geo.size.width * pct - 7)))
                    }
                }
                .frame(height: 14)
                HStack {
                    Text("0").font(Clinical.number(9)).foregroundStyle(Clinical.tertiary)
                    Spacer()
                    Text("RANGE \(lo.formatted())–\(hi.formatted())").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.secondary)
                    Spacer()
                    Text("\(domainHi.formatted(.number.precision(.fractionLength(0))))").font(Clinical.number(9)).foregroundStyle(Clinical.tertiary)
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
