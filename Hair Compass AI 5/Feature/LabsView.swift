import SwiftData
import SwiftUI

struct LabsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \LabResult.collectedAt, order: .reverse) private var labs: [LabResult]
    @State private var showAdd = false
    @State private var showProposalDetail = false
    /// Sprung open by tapping the "Tests derms order for hair loss" footnote row — collapsed on
    /// every fresh appearance of the screen, same as the routine's own collapsed footnote rows.
    @State private var referenceExpanded = false
    /// 0…1 fraction driving the header's scroll-condense (see `ScreenHeader.condensed`) — set
    /// directly from the ScrollView's own content offset.
    @State private var headerCondense: CGFloat = 0

    /// The most recent result (labs are sorted newest-first) that maps to a proposal — kept as
    /// the result itself, not just the derived proposal, so the matching test's card
    /// (`labGroupCard`) can attach the annotation inline instead of a standalone banner.
    private var latestFlaggedResult: LabResult? {
        labs.first { LabProposal.for($0) != nil }
    }
    private var latestProposal: LabProposal? {
        latestFlaggedResult.flatMap { LabProposal.for($0) }
    }

    /// Repeat draws of the same test only answer "is it correcting?" when they're read
    /// together — grouped by test, oldest-first within each group. Groups themselves lead with
    /// whichever test is currently out of range (the exact result the banner above points to),
    /// then fall back to newest-drawn-first — so the flagged card the banner references is
    /// always the first one under it, instead of buried behind in-range results.
    private var groupedLabs: [(test: LabTest, results: [LabResult])] {
        let byTest = Dictionary(grouping: labs, by: \.test)
        return LabTest.allCases
            .compactMap { test -> (LabTest, [LabResult])? in
                guard let results = byTest[test], !results.isEmpty else { return nil }
                return (test, results.sorted { $0.collectedAt < $1.collectedAt })
            }
            .sorted { lhs, rhs in
                let lhsFlagged = lhs.1.last?.flag != .normal
                let rhsFlagged = rhs.1.last?.flag != .normal
                if lhsFlagged != rhsFlagged { return lhsFlagged && !rhsFlagged }
                return (lhs.1.last?.collectedAt ?? .distantPast) > (rhs.1.last?.collectedAt ?? .distantPast)
            }
    }

    /// When every visible test's most recent draw happened on the same calendar day (the common
    /// case — one panel, one blood draw), the date is worth saying exactly once, up top, instead
    /// of on every single-draw row underneath (`labLedgerRow`'s own fallback date line skips
    /// itself whenever this is non-nil). nil the moment draws span more than one day, so the
    /// per-row "since <date>" and single-draw date lines carry the full story again.
    private var sharedDrawDate: Date? {
        let calendar = Calendar.current
        let latestDates = groupedLabs.map { calendar.startOfDay(for: $0.results.last!.collectedAt) }
        guard let first = latestDates.first, Set(latestDates).count == 1 else { return nil }
        return first
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
                    ),
                    condensed: headerCondense
                )
                .padding(.top, 8)

                // The full illustrated disclaimer only earns its space on a first visit, before
                // there's any data to compete with it.
                if labs.isEmpty {
                    labContextCard
                        .staggeredEntrance(index: 0)
                    reference
                        .staggeredEntrance(index: 1)
                } else {
                    // Data leads now — no disclaimer banner and no standalone "what this may
                    // mean" card occupying the prime viewport before any result, and no stacked
                    // per-test boxes either: one continuous hairline-ruled ledger instead of
                    // three near-identical cards. The flagged lab's own row still carries the
                    // "what this may mean" disclosure inline, and the "context, not a diagnosis"
                    // line stays a footnote at the very bottom.
                    if let sharedDrawDate {
                        Text("Drawn \(sharedDrawDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                    labLedger
                    referenceFootnote
                        .staggeredEntrance(index: min(groupedLabs.count, 9))
                    contextFootnote
                        .staggeredEntrance(index: min(groupedLabs.count + 1, 10))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Condenses the header's serif title as the page scrolls — direct 1:1 offset tracking.
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, newY in
            headerCondense = Clinical.headerCondenseFraction(newY)
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

    /// The disclaimer that used to lead every returning visit as its own banner is now a
    /// one-line footnote at the bottom of the list — data leads, honesty still gets said, just
    /// not ahead of every result on every visit. Round-9: promoted to the shared `Colophon`
    /// component (mono eyebrow type + leading test-tube icon are gone) so this line reads in the
    /// same voice as Plan's "density judged at 24 weeks" colophon instead of a second dialect.
    private var contextFootnote: some View {
        Colophon(text: "Context, not a diagnosis — choose tests with a clinician rather than a blanket panel.")
    }

    /// One continuous ledger instead of three near-identical card boxes: every lab is a row on
    /// the ivory, separated by full-width hairlines top and between entries.
    private var labLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline)
            ForEach(Array(groupedLabs.enumerated()), id: \.element.test) { index, group in
                labLedgerRow(test: group.test, results: group.results, index: index)
                    .staggeredEntrance(index: min(index, 8))
                Divider().overlay(Clinical.hairline)
            }
        }
    }

    /// One ledger row per test: the latest draw's name/value share a baseline, the gauge line +
    /// dot sit directly beneath with range endpoints in small ink, and — when there's a
    /// history — the delta since the prior draw plus a compact sparkline answer the whole reason
    /// to re-test: "is it correcting?" In-range rows carry no status badge text at all (the
    /// sage-vs-copper dot position already says it); only the one flagged lab additionally
    /// carries the "what this may mean" disclosure, inline on its own row.
    private func labLedgerRow(test: LabTest, results: [LabResult], index: Int) -> some View {
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
        let isFlagged = test == latestFlaggedResult?.test

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(test.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Clinical.ink)
                    if let previous {
                        Text("\(oneDecimal(previous.value)) → \(oneDecimal(latest.value)) \(test.unit) since \(previous.collectedAt.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    } else if sharedDrawDate == nil {
                        // When every visible test shares one draw date, it's already said once
                        // at the top of the ledger (see `sharedDrawDate`) — repeating it on every
                        // single-draw row below would say the same date three times down the page.
                        Text(latest.collectedAt.formatted(.dateTime.month().day().year()))
                            .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                    if !latest.note.isEmpty {
                        Text(latest.note).font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    }
                }
                Spacer()
                Text("\(oneDecimal(latest.value)) \(test.unit)")
                    .font(Clinical.number(17)).foregroundStyle(Clinical.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Hairline vow: the gauge is a read-only annotation, not a slider — its track
                    // and in-range band now draw at the same 2pt weight every other margin rule
                    // in the ledger uses. The in-range band still says "range" by tint (sage),
                    // never by extra stroke weight.
                    Capsule().fill(Clinical.hairline.opacity(0.5)).frame(height: 2).offset(y: 6)
                    Capsule().fill(Clinical.positive.opacity(0.32))
                        .frame(width: geo.size.width * bandWidth, height: 2)
                        .offset(x: geo.size.width * bandStart, y: 6)
                    // The dot slides in from the range's own start to its actual reading —
                    // draws once with a soft spring on appear, staggered per row so the ledger
                    // settles in sequence rather than all at once.
                    AnimatedGaugeDot(
                        color: Clinical.flagColor(latest.flag),
                        width: geo.size.width,
                        finalPct: pct,
                        startPct: bandStart,
                        pulseBelowRange: latest.flag == .low,
                        delay: Double(index) * 0.08
                    )
                }
            }
            .frame(height: 14)
            HStack {
                Text(lo.formatted()).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                Spacer()
                // Round-7: "RANGE" used to stamp every gauge — an ornament said three times on a
                // three-test ledger. The endpoint numbers either side already say what the band
                // is; the word itself now appears once, on the first row, as the one-time key
                // that teaches what the two numbers mean.
                if index == 0 {
                    Text("RANGE").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.secondary)
                }
                Spacer()
                Text(hi.formatted()).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }
            if latest.hasCustomRange {
                Text("Range from your lab report, not the app default.")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            }

            if results.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "\(results.count) draws since \(results.first!.collectedAt.formatted(.dateTime.month(.abbreviated).year()))")
                    LabSparkline(results: results, range: range, domainHi: domainHi)
                        .frame(height: 32)
                }
            }

            if improving {
                Label("Moving toward range — worth confirming with your clinician.", systemImage: "arrow.up.forward")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Clinical.positive)
            }

            // The only lab that speaks in copper: the flagged result's "what this may mean"
            // disclosure, inline on its own row instead of a standalone banner disconnected
            // from the card it described.
            if isFlagged, let proposal = latestProposal {
                Button { showProposalDetail = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: proposal.kind == .clinician ? "stethoscope" : "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Clinical.accent)
                        Text(proposal.deficiency)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Clinical.accent)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Clinical.accent.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What this may mean: \(proposal.deficiency)")
                .accessibilityHint("Opens more detail")
            }
        }
        .padding(.vertical, 16)
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

    /// The same reference list, collapsed into a footnote disclosure at the ledger's end once
    /// there's real data to lead with — a full always-open card only earns its place on the
    /// empty first visit (`reference`, above).
    ///
    /// Round-5: restyled from a `DisclosureGroup` with a shouting all-caps mono
    /// "TESTS DERMS ORDER FOR HAIR LOSS" label to the same quiet footnote-row family as Plan's
    /// "Reminders" row — plain-weight sentence case, no caps, one hairline top and bottom.
    /// Round-9: no longer supplies its own trailing hairline — `contextFootnote` right below it
    /// is now a `Colophon`, which draws that rule itself, so this row borrows its neighbor's
    /// hairline on both ends instead of doubling it.
    private var referenceFootnote: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No leading hairline here — `labLedger`'s last row already closes with one, so this
            // row continues straight from it instead of doubling the rule.
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                if reduceMotion {
                    referenceExpanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { referenceExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Tests derms order for hair loss")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Clinical.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Clinical.accent)
                        .rotationEffect(.degrees(referenceExpanded ? 90 : 0))
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.clinicalPressable)
            .accessibilityLabel("Tests derms order for hair loss")
            .accessibilityHint(referenceExpanded ? "Collapses the list" : "Expands the list")

            if referenceExpanded {
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// The gauge's reading dot, drawn sliding in from the range's own lower bound to its actual
/// resting position — one spring on appear (staggered per card via `delay`), instant under
/// Reduce Motion. A below-range reading gets one subtle gold pulse once it settles, so a
/// low result reads as *measured*, not just printed.
private struct AnimatedGaugeDot: View {
    let color: Color
    let width: CGFloat
    /// 0…1 fraction of `width` for the dot's final resting x.
    let finalPct: CGFloat
    /// 0…1 fraction of `width` for the range's own lower bound — the dot's starting position.
    let startPct: CGFloat
    let pulseBelowRange: Bool
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var pulsed = false

    private func x(for pct: CGFloat) -> CGFloat {
        min(width - 10, max(0, width * pct - 5))
    }

    var body: some View {
        // Hairline vow: the reading dot and its ring thin down to margin-annotation weight —
        // this is a printed value, not a slider thumb waiting to be dragged.
        Circle().fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Clinical.surface, lineWidth: 1.5))
            // Soft halo behind the reading — the same flag color at whisper opacity, drawn as a
            // background so it takes no layout space and the gauge math above is untouched.
            .background(Circle().fill(color.opacity(0.14)).frame(width: 18, height: 18))
            .scaleEffect(pulsed ? 1.22 : 1)
            .shadow(color: Clinical.gold.opacity(pulsed ? 0.75 : 0), radius: pulsed ? 9 : 0)
            .offset(x: shown ? x(for: finalPct) : x(for: startPct))
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                    return
                }
                withAnimation(.spring(response: 0.65, dampingFraction: 0.78).delay(delay)) {
                    shown = true
                }
                guard pulseBelowRange else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64((delay + 0.65) * 1_000_000_000))
                    withAnimation(.easeOut(duration: 0.3)) { pulsed = true }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.easeOut(duration: 0.3)) { pulsed = false }
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
