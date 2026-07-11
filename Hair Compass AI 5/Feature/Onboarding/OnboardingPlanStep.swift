import Charts
import StoreKit
import SwiftUI

/// Onboarding step 12 — "your plan". The honest Pro offer: a scientifically grounded projection
/// (the ONLY quantitative number is the published male-AGA combination-therapy average from
/// `docs/TrackingSpec.md`; everyone else gets qualitative milestones), three "what Pro adds"
/// rows, and purchase buttons that never show a placeholder price — they simply don't render
/// until real products load. "Continue free" sits directly under them, same size of voice, and
/// there is no countdown, no fake discount, no back navigation trap: this screen only moves
/// forward, either through a purchase or through the free path.
struct OnboardingPlanStep: View {
    let profile: Profile
    var onContinue: () -> Void

    @Environment(PurchaseService.self) private var purchases
    @State private var isPurchasing = false
    @State private var yearlyIntroEligible = false

    private var model: ProjectionModel {
        ProjectionModel.make(condition: profile.condition, sex: profile.sex)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    projectionCard
                    proAdds
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            footer
        }
        .task(id: purchases.yearly?.id) {
            guard let yearly = purchases.yearly else { return }
            yearlyIntroEligible = await purchases.isEligibleForIntro(yearly)
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
                .font(.system(size: 14))
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
                        .font(.system(size: 11))
                        .foregroundStyle(Clinical.secondary)
                    Text(model.disclaimer)
                        .font(.system(size: 11))
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
                .font(.system(size: 11))
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
                        .font(.system(size: 13))
                        .foregroundStyle(Clinical.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: What Pro adds

    private var proAdds: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "What Pro adds")
            proRow("bubble.left.and.text.bubble.right", "AI hair chat", "Ask anything about your data")
            proRow("photo.on.rectangle.angled", "AI deep photo analysis", "Standardized, objective photo reads")
            proRow("bell.badge", "Smart reminders & trends", "Stay consistent through week 6")
        }
    }

    private func proRow(_ symbol: String, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Clinical.accent)
                .frame(width: 30, height: 30)
                .background(Clinical.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Clinical.ink)
                Text(line).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    // MARK: Footer — purchase, free path, restore. No back navigation, no timers.

    private var footer: some View {
        VStack(spacing: 10) {
            if !purchases.products.isEmpty {
                purchaseButtons
            }

            Button {
                onContinue()
            } label: {
                Text("Continue free")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityIdentifier("onboardContinueFree")

            Button {
                Task { await purchases.restore() }
            } label: {
                Text("Restore purchases")
                    .font(.system(size: 12))
                    .foregroundStyle(Clinical.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var purchaseButtons: some View {
        if let yearly = purchases.yearly {
            let showsTrial = yearlyIntroEligible && purchases.introOffer(for: yearly) != nil
            Button {
                buy(yearly)
            } label: {
                VStack(spacing: 2) {
                    if showsTrial {
                        Text("Start 3-day free trial")
                        Text("then \(yearly.displayPrice)/year · cancel anytime — no charge for 3 days")
                            .font(.system(size: 11))
                            .foregroundStyle(Clinical.secondary)
                    } else {
                        Text("Start with yearly — \(yearly.displayPrice)/year")
                        if let perMonth = yearly.monthlyEquivalentDisplay {
                            Text(perMonth)
                                .font(.system(size: 11, weight: .regular))
                        }
                    }
                }
            }
            .buttonStyle(ClinicalButtonStyle())
            .disabled(isPurchasing)
            .accessibilityIdentifier("onboardPurchaseYearly")
        }
        if let monthly = purchases.monthly {
            Button {
                buy(monthly)
            } label: {
                Text("Monthly — \(monthly.displayPrice)/month")
            }
            .buttonStyle(ClinicalButtonStyle(filled: false))
            .disabled(isPurchasing)
            .accessibilityIdentifier("onboardPurchaseMonthly")
        }
    }

    private func buy(_ product: Product) {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            let bought = await purchases.purchase(product)
            isPurchasing = false
            if bought { onContinue() }
        }
    }
}
