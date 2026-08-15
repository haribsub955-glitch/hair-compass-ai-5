import Charts
import StoreKit
import SwiftUI

/// Onboarding step 12 — "your plan". The honest Pro offer: a scientifically grounded projection
/// (the ONLY quantitative number is the published male-AGA combination-therapy average from
/// `docs/TrackingSpec.md`; everyone else gets qualitative milestones), a checklist of everything
/// `ProFeature.allCases` gates — all twelve, not just the two that need Apple Intelligence — and
/// purchase buttons that never show a placeholder price. Until real products load they're replaced
/// by `StoreUnavailableView` (a spinner, or an honest "can't reach the store" message with Retry).
/// "Continue free" sits directly under them, same size of voice, and there is no countdown, no
/// fake discount, no back navigation trap: this screen only moves forward, either through a
/// purchase or through the free path.
struct OnboardingPlanStep: View {
    let profile: Profile
    var onContinue: () -> Void

    @Environment(PurchaseService.self) private var purchases
    /// The product ID currently mid-purchase, or `nil`. A per-product id (not a plain `Bool`) so
    /// only the button the user actually tapped shows its spinner.
    @State private var purchasingProductID: String?
    @State private var yearlyIntroEligible = false
    @State private var monthlyIntroEligible = false

    private var isBusy: Bool { purchasingProductID != nil || purchases.isRestoring }

    /// Read fresh on every body evaluation rather than cached in `@State`: Apple Intelligence can
    /// be switched on, or finish downloading, while this step is on screen.
    private var availability: OnDeviceAvailability { ProAvailability.current }

    /// Scroll target for the DEBUG bottom-of-page screenshot hook.
    private static let footerAnchor = "planFooter"

    private var model: ProjectionModel {
        ProjectionModel.make(condition: profile.condition, sex: profile.sex)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        // Sits above the projection card: the felt version of the same claim the
                        // card then makes with data. Both describe visibility, never regrowth.
                        ClarityContrast(sex: profile.sex)
                        projectionCard
                        proAdds
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    footer.id(Self.footerAnchor)
                }
            }
            .onAppear {
                // This screen is taller than any phone, so QA screenshots of the offer itself
                // need a way to land below the fold. DEBUG-only, same spirit as HC_ONBOARD_STEP.
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("HC_PAYWALL_BOTTOM") {
                    Task { @MainActor in
                        // Long enough for the step transition and the store's product load to
                        // settle, or the anchor moves out from under the scroll.
                        try? await Task.sleep(for: .milliseconds(1800))
                        proxy.scrollTo(Self.footerAnchor, anchor: .bottom)
                    }
                }
                #endif
            }
        }
        .task(id: purchases.yearly?.id) {
            guard let yearly = purchases.yearly else { return }
            yearlyIntroEligible = await purchases.isEligibleForIntro(yearly)
        }
        .task(id: purchases.monthly?.id) {
            guard let monthly = purchases.monthly else { return }
            monthlyIntroEligible = await purchases.isEligibleForIntro(monthly)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Your plan")
            Text("Make the next 6 months count")
                .font(Clinical.headline(28))
                .foregroundStyle(Clinical.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(personalLine)
                .font(Clinical.caption(14))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var personalLine: String {
        var facts = [profile.condition.plainTitle.lowercased()]
        if profile.familyHistory != .none { facts.append("family history") }
        if profile.hasTractionRisk { facts.append("hair-care habits worth watching") }
        let joined = facts.joined(separator: ", ")
        return "You told us: \(joined). Here's what consistent tracking does with that."
    }

    // MARK: Projection card

    private var projectionCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                projectionBanner
                Eyebrow(text: "Projection")
                Text(model.headline)
                    .font(Clinical.headline(19))
                    .foregroundStyle(Clinical.ink)

                if let curve = model.evidenceCurve {
                    evidenceChart(curve)
                } else {
                    milestoneTimeline(model.milestones)
                }

                differenceChart(model.differenceCurve)

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.citation)
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.secondary)
                    Text(model.disclaimer)
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.tertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Full-bleed gouache banner across the card's top edge — decorative and honest (no
    /// hair-regrowth or before/after imagery). Negative padding cancels the card's own 18pt inset
    /// for just this child so it reaches all three top edges; `ClinicalCard`'s outer 22pt corner
    /// clip then rounds the banner's top corners to match the card.
    private var projectionBanner: some View {
        Image("onboard-difference")
            .resizable()
            .scaledToFill()
            .frame(height: 132)
            .frame(maxWidth: .infinity)
            .clipped()
            .padding(.horizontal, -18)
            .padding(.top, -18)
            .accessibilityHidden(true)
    }

    private func evidenceChart(_ curve: [ProjectionModel.CurvePoint]) -> some View {
        Chart {
            ForEach(curve, id: \.week) { p in
                AreaMark(x: .value("Week", p.week), y: .value("Δ hairs/cm²", p.hairsPerCm2))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Clinical.accent.opacity(0.16), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                LineMark(x: .value("Week", p.week), y: .value("Δ hairs/cm²", p.hairsPerCm2))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .foregroundStyle(Clinical.accent)
            }
            if let last = curve.last {
                PointMark(x: .value("Week", last.week), y: .value("Δ hairs/cm²", last.hairsPerCm2))
                    .symbolSize(50)
                    .foregroundStyle(Clinical.accent)
                    .annotation(position: .top) {
                        Text("+\(last.hairsPerCm2, format: .number.precision(.fractionLength(1)))")
                            .font(Clinical.eyebrow(9))
                            .foregroundStyle(Clinical.accent)
                    }
            }
        }
        .frame(height: 130)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                AxisValueLabel {
                    if let w = value.as(Int.self) {
                        Text("W\(w)").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                AxisValueLabel().font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }
        }
        .accessibilityLabel("Projected hair density change through 24 weeks, from published averages, not a prediction of your results")
    }

    /// The universal "tracking vs guessing" illustration — shown for EVERY profile, unlike
    /// `evidenceChart` which only exists for male AGA. Honesty rule: the y-axis is explicitly
    /// "signal clarity", never hair count — tracking doesn't grow hair, it's how you see whether
    /// a plan is working. Fixed to a 0…1 domain so the copper "tracking" line visibly rises while
    /// the dashed grey "guessing" line reads as flat and low, never negative.
    private func differenceChart(_ curve: [ProjectionModel.DifferencePoint]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Signal clarity (illustrative)")
                .font(Clinical.caption(11))
                .foregroundStyle(Clinical.tertiary)

            Chart {
                // Explicit `series:` on both mark groups — LineMarks without it merge into ONE
                // series and draw a single zigzag line in one color (see docs/DesignSystem.md
                // Swift Charts note; this bit the CheckIns chart before the rebuild too).
                ForEach(curve, id: \.week) { p in
                    LineMark(x: .value("Week", p.week), y: .value("Tracking daily", p.withTracking),
                             series: .value("Series", "tracking"))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(Clinical.accent)
                }
                ForEach(curve, id: \.week) { p in
                    LineMark(x: .value("Week", p.week), y: .value("Guessing", p.without),
                             series: .value("Series", "guessing"))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .foregroundStyle(Clinical.tertiary)
                }
            }
            .frame(height: 140)
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [0, 12, 24]) { value in
                    AxisGridLine().foregroundStyle(Clinical.hairline.opacity(0.6))
                    AxisValueLabel {
                        if let w = value.as(Int.self) {
                            Text("W\(w)").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                }
            }
            .accessibilityLabel("Illustrative signal clarity: rises steadily while tracking daily, stays low and flat while guessing. Not a prediction of hair count or results.")

            HStack(spacing: 14) {
                differenceLegendKey(color: Clinical.accent, dashed: false, label: "Tracking daily")
                differenceLegendKey(color: Clinical.tertiary, dashed: true, label: "Guessing")
            }
        }
    }

    /// A small inline swatch + label — deliberately not `.chartLegend()`, so the two rows read as
    /// plain body content rather than a chart-owned legend.
    private func differenceLegendKey(color: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 2) {
                    Capsule().fill(color).frame(width: 5, height: 2)
                    Capsule().fill(color).frame(width: 5, height: 2)
                }
            } else {
                Capsule().fill(color).frame(width: 14, height: 3)
            }
            Text(label)
                .font(Clinical.eyebrow(9))
                .foregroundStyle(Clinical.secondary)
        }
    }

    private func milestoneTimeline(_ milestones: [ProjectionModel.Milestone]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(milestones, id: \.week) { m in
                HStack(alignment: .top, spacing: 10) {
                    Text("W\(m.week)")
                        .font(Clinical.eyebrow(10))
                        .foregroundStyle(Clinical.surface)
                        .frame(width: 36, height: 22)
                        .background(Clinical.accent, in: Capsule())
                    Text(m.label)
                        .font(Clinical.caption(13))
                        .foregroundStyle(Clinical.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: What Pro adds

    /// Every `ProFeature`, not just the two AI ones — this was previously hand-limited to Ask
    /// Wren and Deep analysis, which made the screen advertise exactly what it disclaimed on
    /// ineligible hardware. Driven by `ProFeature.allCases` so it can never drift from
    /// `Entitlements`'s policy table again: a thirteenth case shows up here automatically, with
    /// real copy, because `EntitlementsTests.everyFeatureHasGateCopy` fails the build otherwise.
    /// The ten that run everywhere read as a plain checkmark list; the two Apple Intelligence
    /// features get their own marked rows, with `ProAvailabilityNotice` sitting beside them —
    /// never above the (unconditional) purchase buttons below, which sell all twelve regardless
    /// of what this iPhone can run.
    private var proAdds: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "What Pro adds")

            FlowLayout(spacing: 8) {
                ForEach(ProFeature.allCases.filter { !$0.requiresAppleIntelligence }, id: \.self) { feature in
                    ProFeatureChip(feature: feature)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(ProFeature.allCases.filter(\.requiresAppleIntelligence), id: \.self) { feature in
                    ProFeatureChip(feature: feature)
                }
                ProAvailabilityNotice(status: availability)
            }
        }
    }

    // MARK: Footer — purchase, free path, restore. No back navigation, no timers.

    private var footer: some View {
        VStack(spacing: 10) {
            wrenClose

            // The purchase buttons are UNCONDITIONAL: even on hardware that can never run Ask
            // Wren or Deep analysis, the subscription still unlocks the other ten Pro features,
            // so withdrawing the sale here would be the same mistake `ProAvailabilityNotice`
            // beside the two AI rows above already warned about. Routed through
            // `ProAvailability.showsPurchaseButtons` so both purchase surfaces ask the one
            // function that `ProAvailabilityTests` pins to "availability is not an input".
            if ProAvailability.showsPurchaseButtons(status: availability, hasLoadedProducts: !purchases.products.isEmpty) {
                purchaseButtons
            } else {
                StoreUnavailableView(isLoading: purchases.isLoading) {
                    Task { await purchases.load() }
                }
            }

            PurchaseStatusLine(purchaseState: purchases.purchaseState, restoreResult: purchases.restoreResult)

            Button {
                onContinue()
            } label: {
                Text("Continue free")
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("onboardContinueFree")

            Button {
                Task { await purchases.restore() }
            } label: {
                HStack(spacing: 6) {
                    if purchases.isRestoring {
                        ProgressView().tint(Clinical.tertiary)
                    }
                    Text("Restore purchases")
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            PaywallLegal(showsRenewalDisclosure: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    /// The last thing before the price. Wren is not decoration here — she *is* the thing being
    /// sold (the chat's face and name), so putting her at the decision point is both the warmest
    /// and the most accurate close available. Deliberately no urgency, no scarcity, no countdown:
    /// this screen's whole design contract is that it only ever moves forward honestly.
    private var wrenClose: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanionView(moment: .greeting, variant: .avatar, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Companion.name) comes with Pro")
                    .font(Clinical.body(14, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                Text("Six months from now you'll either have a record worth reading — or you'll be asking the same questions with nothing to check them against.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Clinical.accent.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var purchaseButtons: some View {
        if let yearly = purchases.yearly {
            // Eligibility-gated: the launch offer only renders for Apple IDs that haven't
            // already used the group's introductory offer — never a placeholder discount.
            let offer = yearlyIntroEligible ? purchases.launchOffer(for: yearly) : nil
            // Only shown when there's no real intro offer to display instead, so the screen never
            // stacks two different discount stories on top of each other.
            let versus = offer == nil ? purchases.yearlyVersusMonthly() : nil
            VStack(spacing: 8) {
                if let offer {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(offer.base)
                            .font(Clinical.caption(14))
                            .strikethrough()
                            .foregroundStyle(Clinical.tertiary)
                        Text(offer.intro)
                            .font(Clinical.body(18, weight: .semibold))
                            .foregroundStyle(Clinical.ink)
                        Text("/year")
                            .font(Clinical.caption(13))
                            .foregroundStyle(Clinical.secondary)
                    }
                } else if let versus {
                    // "$118.80 billed monthly / $39.99 / year". The struck figure is the REAL cost
                    // of a year on the monthly plan — never a former price of the yearly plan —
                    // and the words "billed monthly" sit with it so it cannot be read as one.
                    // See `PurchaseService.yearlyVersusMonthly()` for why that distinction is legal
                    // rather than cosmetic.
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(versus.monthlyForAYear)
                                .font(Clinical.caption(14))
                                .strikethrough()
                                .foregroundStyle(Clinical.tertiary)
                            Text(versus.yearly)
                                .font(Clinical.body(18, weight: .semibold))
                                .foregroundStyle(Clinical.ink)
                            Text("/year")
                                .font(Clinical.caption(13))
                                .foregroundStyle(Clinical.secondary)
                        }
                        Text("\(versus.monthlyForAYear) is what a year costs billed monthly")
                            .font(Clinical.caption(11))
                            .foregroundStyle(Clinical.tertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(versus.yearly) per year, versus \(versus.monthlyForAYear) for the same "
                        + "year billed monthly. Save \(versus.percentOff) percent."
                    )
                }
                Button {
                    buy(yearly)
                } label: {
                    PurchaseButtonLabel(isPurchasing: purchasingProductID == yearly.id, tint: Clinical.surface) {
                        VStack(spacing: 2) {
                            if let offer {
                                Text("Start yearly — \(offer.intro) first year")
                                Text("First year — save \(offer.percentOff)%, then \(offer.base)/year · Limited-time")
                                    .font(Clinical.caption(11))
                                    .foregroundStyle(Clinical.secondary)
                            } else {
                                Text("Start with yearly — \(yearly.displayPrice)/year")
                                if let perMonth = yearly.monthlyEquivalentDisplay, let versus {
                                    // Both halves are derived from the two real products: the
                                    // per-month figure from the yearly price, the percentage from
                                    // the yearly-vs-monthly comparison.
                                    Text("\(perMonth) · save \(versus.percentOff)% vs monthly")
                                        .font(Clinical.body(11, weight: .regular))
                                } else if let perMonth = yearly.monthlyEquivalentDisplay {
                                    Text(perMonth)
                                        .font(Clinical.body(11, weight: .regular))
                                }
                            }
                        }
                    }
                }
                .buttonStyle(ClinicalButtonStyle())
                .disabled(isBusy)
                .accessibilityIdentifier("onboardPurchaseYearly")
            }
        }
        if let monthly = purchases.monthly {
            let trialText = monthlyIntroEligible ? purchases.trialDescriptor(for: monthly) : nil
            Button {
                buy(monthly)
            } label: {
                PurchaseButtonLabel(isPurchasing: purchasingProductID == monthly.id, tint: Clinical.ink) {
                    if let trialText {
                        Text("\(trialText)/month")
                    } else {
                        Text("Monthly — \(monthly.displayPrice)/month")
                    }
                }
            }
            .buttonStyle(ClinicalButtonStyle(filled: false))
            .disabled(isBusy)
            .accessibilityIdentifier("onboardPurchaseMonthly")
        }
    }

    private func buy(_ product: Product) {
        guard !isBusy else { return }
        purchasingProductID = product.id
        Task {
            let bought = await purchases.purchase(product)
            purchasingProductID = nil
            if bought { onContinue() }
        }
    }
}

/// One row in `proAdds`'s checklist — a checkmark for the ten features every iPhone runs, or a
/// marked row for the two that need Apple Intelligence. Deliberately plain (no card background,
/// no border, no shadow): twelve of these is already a lot of ink on one screen, and this
/// codebase's screen-art grammar reserves heavier chrome for the one thing per screen that's
/// meant to be looked at, not read past. `gateDescription` isn't shown on screen — the row itself
/// is a title-only chip so the list stays scannable — but it still does its job as the
/// accessibility label, so VoiceOver hears the same one-line explanation `ProGate` shows visually.
private struct ProFeatureChip: View {
    let feature: ProFeature

    private var isAI: Bool { feature.requiresAppleIntelligence }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isAI ? "exclamationmark.triangle" : "checkmark")
                .font(Clinical.caption(11))
                .foregroundStyle(isAI ? Clinical.warning : Clinical.accent)
            Text(feature.gateTitle)
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.ink)
            if isAI {
                Spacer(minLength: 8)
                Text("Needs Apple Intelligence")
                    .font(Clinical.caption(11))
                    .foregroundStyle(Clinical.tertiary)
            }
        }
        .frame(maxWidth: isAI ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isAI
                ? "\(feature.gateTitle). \(feature.gateDescription). Needs Apple Intelligence."
                : "\(feature.gateTitle). \(feature.gateDescription). Included with Pro."
        )
    }
}

/// A minimal left-to-right wrap, used only by `proAdds`'s ten-item checklist: items pack by
/// their own width and wrap to a new line, rather than sitting in a fixed column count that
/// would leave uneven gaps next to short titles like "Photos" or "Labs".
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : origin.x, height: origin.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
