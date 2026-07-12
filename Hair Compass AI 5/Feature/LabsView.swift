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

    /// Repeat draws of the same test only answer "is it correcting?" when they're read
    /// together — grouped by test, oldest-first within each group, ordered by whichever test
    /// was drawn most recently overall (keeping the prior newest-first feel at the group level).
    private var groupedLabs: [(test: LabTest, results: [LabResult])] {
        let byTest = Dictionary(grouping: labs, by: \.test)
        return LabTest.allCases
            .compactMap { test -> (LabTest, [LabResult])? in
                guard let results = byTest[test], !results.isEmpty else { return nil }
                return (test, results.sorted { $0.collectedAt < $1.collectedAt })
            }
            .sorted { ($0.1.last?.collectedAt ?? .distantPast) > ($1.1.last?.collectedAt ?? .distantPast) }
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

                // The full illustrated disclaimer only earns its space on a first visit — once
                // there's real data, a returning user needs results, not ambiance, so it
                // collapses to a slim one-row banner that still carries the same guidance.
                if labs.isEmpty {
                    labContextCard
                        .staggeredEntrance(index: 0)
                } else {
                    labContextBanner
                        .staggeredEntrance(index: 0)
                }

                if let proposal = latestProposal {
                    deficiencyBanner(proposal)
                        .staggeredEntrance(index: 1)
                }

                if labs.isEmpty {
                    reference
                        .staggeredEntrance(index: 1)
                } else {
                    ForEach(Array(groupedLabs.enumerated()), id: \.element.test) { index, group in
                        labGroupCard(test: group.test, results: group.results)
                            .staggeredEntrance(index: min(index + 1, 8))
                    }
                    reference
                        .staggeredEntrance(index: min(groupedLabs.count + 1, 9))
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

    /// First-visit-only illustrated disclaimer — full LivingArtwork treatment, shown while the
    /// list is still empty and there's nothing else competing for the top of the screen.
    private var labContextCard: some View {
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
    }

    /// Returning-visitor version of the same guidance — one slim row (icon + two short lines,
    /// no artwork) so results start well above the fold instead of behind a decoration tax paid
    /// on every visit.
    private var labContextBanner: some View {
        ClinicalCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Context, not a diagnosis")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                    Text("Choose tests with a clinician rather than a blanket panel.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Clinical.secondary)
                }
                Spacer(minLength: 0)
            }
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

    /// One card per test: the latest draw reads as a gauge exactly as before, but when there's
    /// a history it leads with the delta since the prior draw and a compact sparkline — the
    /// whole reason to re-test is "is it correcting?", and that question deserves a direct
    /// answer instead of three disconnected cards a user has to compare mentally.
    private func labGroupCard(test: LabTest, results: [LabResult]) -> some View {
        let latest = results.last!
        // The user's own "range from your lab report" override, when set, is what the gauge,
        // sparkline and flag all actually judge this draw against — the built-in default only
        // when there's no override.
        let range = latest.effectiveRange
        let lo = range.lowerBound
        let hi = range.upperBound
        let domainHi = hi * 1.1               // headroom above the range
        let previous = results.count > 1 ? results[results.count - 2] : nil
        let pct = min(1, max(0, latest.value / domainHi))
        let bandStart = lo / domainHi
        let bandWidth = (hi - lo) / domainHi
        let improving = previous.map {
            HairAnalytics.labImproving(previous: $0.value, latest: latest.value, range: range)
        } ?? false

        return ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(test.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Clinical.ink)
                        if let previous {
                            Text("\(oneDecimal(previous.value)) → \(oneDecimal(latest.value)) \(test.unit) since \(previous.collectedAt.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                        } else {
                            Text(latest.collectedAt.formatted(.dateTime.month().day().year()))
                                .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                        }
                        if !latest.note.isEmpty {
                            Text(latest.note).font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(oneDecimal(latest.value)) \(test.unit)")
                            .font(Clinical.number(17)).foregroundStyle(Clinical.ink)
                        Text(latest.flag.title).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.flagColor(latest.flag))
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Clinical.hairline.opacity(0.5)).frame(height: 6).offset(y: 4)
                        Capsule().fill(Clinical.positive.opacity(0.22))
                            .frame(width: geo.size.width * bandWidth, height: 6)
                            .offset(x: geo.size.width * bandStart, y: 4)
                        Circle().fill(Clinical.flagColor(latest.flag))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Clinical.surface, lineWidth: 2.5))
                            // Soft halo behind the reading — the same flag color at whisper
                            // opacity, drawn as a background so it takes no layout space and
                            // the gauge math above is untouched.
                            .background(
                                Circle()
                                    .fill(Clinical.flagColor(latest.flag).opacity(0.18))
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
                if latest.hasCustomRange {
                    Text("Range from your lab report, not the app default.")
                        .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                }

                if results.count > 1 {
                    Divider().overlay(Clinical.hairline)
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "\(results.count) draws since \(results.first!.collectedAt.formatted(.dateTime.month(.abbreviated).year()))")
                        LabSparkline(results: results, range: range, domainHi: domainHi)
                            .frame(height: 36)
                    }
                }

                if improving {
                    Label("Moving toward range — worth confirming with your clinician.", systemImage: "arrow.up.forward")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Clinical.positive)
                }
            }
        }
        .contextMenu {
            Button("Delete latest draw", role: .destructive) { context.delete(latest) }
        }
    }

    private func oneDecimal(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)))
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

/// A compact draws-over-time chart for one test: the reference band shaded as a horizontal
/// strip, each draw plotted chronologically against it, and a connecting line so "is it
/// correcting?" reads as a shape instead of a mental diff between separate cards.
private struct LabSparkline: View {
    let results: [LabResult]     // chronological, oldest first
    let range: ClosedRange<Double>
    let domainHi: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bandTop = y(range.upperBound, height: h)
            let bandBottom = y(range.lowerBound, height: h)

            ZStack {
                Rectangle()
                    .fill(Clinical.positive.opacity(0.16))
                    .frame(width: w, height: max(2, bandBottom - bandTop))
                    .position(x: w / 2, y: (bandTop + bandBottom) / 2)

                if results.count > 1 {
                    Path { path in
                        for (index, result) in results.enumerated() {
                            let point = CGPoint(x: x(index, width: w), y: y(result.value, height: h))
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }
                    .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                    let isLatest = index == results.count - 1
                    Circle()
                        .fill(isLatest ? Clinical.accent : Clinical.tertiary)
                        .frame(width: isLatest ? 7 : 5, height: isLatest ? 7 : 5)
                        .position(x: x(index, width: w), y: y(result.value, height: h))
                }
            }
        }
        .accessibilityHidden(true)   // the delta line above already states the trend in words
    }

    private func x(_ index: Int, width: CGFloat) -> CGFloat {
        results.count > 1 ? width * CGFloat(index) / CGFloat(results.count - 1) : width / 2
    }

    private func y(_ value: Double, height: CGFloat) -> CGFloat {
        height - CGFloat(min(1, max(0, value / domainHi))) * height
    }
}
