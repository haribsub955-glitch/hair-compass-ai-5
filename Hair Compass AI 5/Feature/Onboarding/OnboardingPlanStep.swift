import Charts
import StoreKit
import SwiftUI

/// Onboarding step 12 — "your plan". The honest Pro offer: a scientifically grounded projection
/// (the ONLY quantitative number is the published male-AGA combination-therapy average from
/// `docs/TrackingSpec.md`; everyone else gets qualitative milestones), an illustrated card per
/// genuinely-gated feature — there are exactly two, and only what `hasPro` actually gates may be
/// listed here — and purchase buttons that never show a placeholder price. Until real products load
/// they're replaced by `StoreUnavailableView` (a spinner, or an honest "can't reach the store"
/// message with Retry). "Continue free" sits directly under them, same size of voice, and there
/// is no countdown, no fake discount, no back navigation trap: this screen only moves forward,
/// either through a purchase or through the free path.
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

    @Environment(\.scenePhase) private var scenePhase
    /// Bumped on every return to the foreground — `ProAvailability.current` is a static system
    /// read SwiftUI does not track, so without this a person who enables Apple Intelligence in
    /// Settings and comes back would find the purchase buttons still withheld.
    @State private var availabilityRefresh = 0

    /// Read fresh on every body evaluation, and invalidated by `availabilityRefresh` when the
    /// app foregrounds: Apple Intelligence can be switched on, or finish downloading, while
    /// this step is on screen or while the person is away in Settings.
    private var availability: OnDeviceAvailability {
        _ = availabilityRefresh
        return ProAvailability.current
    }

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

    /// Exactly the two things `hasPro` actually gates — `HairChatSheet` and `DeepAnalysisSheet`.
    ///
    /// This list previously carried a third row, "Smart reminders & trends". Nothing gates those:
    /// `PurchaseService` is referenced in five files total and `hasPro` appears at two feature
    /// call sites, so reminders and trends ship free to everyone. Selling them here was a claim
    /// the app doesn't honour, so the row is gone. If a benefit isn't behind `hasPro`, it does not
    /// belong on this screen — check before adding one.
    private var proAdds: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "What Pro adds")
            ProFeatureCard(
                art: CompanionArt.listening,
                title: "Ask \(Companion.name) anything",
                line: "Your record, in plain language. \"Is my shedding actually improving?\" — answered from your own entries, on-device.",
                footnote: "Runs on Apple Intelligence. Nothing leaves your phone."
            )
            ProFeatureCard(
                art: "pro-analysis",
                title: "Deep record analysis",
                line: "\(Companion.name) reads months of your entries at once and surfaces what moved together — the connections you'd need a spreadsheet to spot.",
                footnote: "A reading of your record, never a diagnosis."
            )
        }
    }

    // MARK: Footer — purchase, free path, restore. No back navigation, no timers.

    private var footer: some View {
        VStack(spacing: 10) {
            wrenClose

            // Directly above the price. `proAdds` has just promised two Apple Intelligence
            // features; if this iPhone can't run them, that has to be said before the buttons,
            // not discovered after the charge.
            ProAvailabilityNotice(status: availability)

            if !ProAvailability.sellable(availability) {
                // No purchase while the model can't run right now (off, downloading, or
                // ineligible hardware) — the free path below becomes the only forward move,
                // which is the honest outcome here.
                EmptyView()
            } else if !purchases.products.isEmpty {
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

            PaywallLegal(showsRenewalDisclosure: ProAvailability.sellable(availability))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { availabilityRefresh += 1 }
        }
        // Watch availability every 2 s in BOTH directions while this step is on screen: toward
        // available (waiting out a model download here) and away from it (a one-way watch that
        // stops once available would leave live purchase buttons on a feature that can no longer
        // run). Bumps only on change.
        .task {
            var last = ProAvailability.current
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let now = ProAvailability.current
                if now != last { last = now; availabilityRefresh += 1 }
            }
        }
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

/// One genuinely-gated feature, sold with its own gouache emblem rather than a 15pt SF Symbol.
/// The `footnote` line is load-bearing: each card states its own limit (on-device, not a
/// diagnosis) so the honesty sits *with* the claim instead of in a disclaimer far below it.
private struct ProFeatureCard: View {
    let art: String
    let title: String
    let line: String
    var footnote: String? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Art beside copy normally; stacked once the text is large enough that an 84pt emblem
        // would squeeze the words into a sliver.
        let stacked = typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 10) {
            if stacked { emblem }
            HStack(alignment: .top, spacing: 14) {
                if !stacked { emblem }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Clinical.body(15, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line)
                        .font(Clinical.caption(13))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let footnote {
                        Text(footnote)
                            .font(Clinical.caption(11))
                            .foregroundStyle(Clinical.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Clinical.surfaceWash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
        .shadow(color: Clinical.cardShadow, radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }

    private var emblem: some View {
        Image(art)
            .resizable()
            .scaledToFit()
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
    }
}
