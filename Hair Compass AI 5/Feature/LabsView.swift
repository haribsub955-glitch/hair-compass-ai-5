import SwiftData
import SwiftUI

struct LabsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LabResult.collectedAt, order: .reverse) private var labs: [LabResult]
    @State private var showAdd = false
    @State private var showProposalDetail = false

    /// The most recent result (labs are sorted newest-first) that maps to a proposal — so the
    /// banner surfaces the latest thing actually worth acting on, not just the latest draw.
    private var latestProposal: LabProposal? {
        labs.lazy.compactMap { LabProposal.for($0) }.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Bloodwork",
                    title: "Labs",
                    trailing: AnyView(
                        HeaderActionButton(systemName: "plus", accessibilityLabel: "Add lab result") {
                            showAdd = true
                        }
                    )
                )
                .padding(.top, 8)
                // Unboxed brand accent bleeding from the top-right — behind the header, so the
                // add button stays tappable and no layout space is taken (no horizontal scroll).
                .background(alignment: .topTrailing) { CornerSprig() }

                ClinicalCard(padding: 0) {
                    ZStack {
                        LivingArtwork(art: BrandArt.labsContextV2, travel: 3.5, zoom: 0.012, phase: 1.7)
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .clipped()
                            .opacity(0.50)
                        LinearGradient(
                            stops: [
                                .init(color: Clinical.surface.opacity(0.99), location: 0),
                                .init(color: Clinical.surface.opacity(0.94), location: 0.58),
                                .init(color: Clinical.surface.opacity(0.42), location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        VStack(alignment: .leading, spacing: 7) {
                            Label("Lab context", systemImage: "testtube.2")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Clinical.ink)
                            Text("Use reference ranges as context—not a diagnosis. Choose tests with a clinician rather than ordering a blanket panel.")
                                .font(.system(size: 13))
                                .foregroundStyle(Clinical.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 245, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                }
                .staggeredEntrance(index: 0)

                if let proposal = latestProposal {
                    deficiencyBanner(proposal)
                        .staggeredEntrance(index: 1)
                }

                if labs.isEmpty {
                    reference
                        .staggeredEntrance(index: 1)
                } else {
                    ForEach(Array(labs.enumerated()), id: \.element.id) { index, lab in
                        labRow(lab)
                            .staggeredEntrance(index: min(index + 1, 8))
                    }
                    reference
                        .staggeredEntrance(index: min(labs.count + 1, 9))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .clinicalScreen()
        .sheet(isPresented: $showAdd) { AddLabSheet() }
        // Persists the honest proposal beyond the one-shot pop-up in AddLabSheet — tapping the
        // banner reopens the same card any time, not just right after logging the value.
        .sheet(isPresented: $showProposalDetail) {
            if let proposal = latestProposal {
                LabProposalSheet(proposal: proposal)
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_ADDLAB") { showAdd = true }
            #endif
        }
    }

    /// A compact, tappable card for the latest lab-confirmed deficiency or medical finding —
    /// the honest surface that persists after the one-shot pop-up in `AddLabSheet` closes.
    private func deficiencyBanner(_ proposal: LabProposal) -> some View {
        Button {
            showProposalDetail = true
        } label: {
            ClinicalCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: proposal.kind == .clinician ? "stethoscope" : "leaf.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Clinical.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "What this may mean")
                        Text(proposal.deficiency)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Clinical.ink)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Clinical.tertiary)
                        .padding(.top, 3)
                }
            }
        }
        .buttonStyle(.clinicalPressable)
    }

    /// Each result reads as a gauge — the value dotted along a 0→high axis with the
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
                            // Soft halo behind the reading — the same flag color at whisper
                            // opacity, drawn as a background so it takes no layout space and
                            // the gauge math above is untouched.
                            .background(
                                Circle()
                                    .fill(Clinical.flagColor(lab.flag).opacity(0.18))
                                    .frame(width: 26, height: 26)
                            )
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
