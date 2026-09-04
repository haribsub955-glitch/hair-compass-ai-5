import StoreKit

/// Presentation only. No entitlement, recommendation or trial decisions live here.
enum OnboardingOfferPhase: String, CaseIterable {
    case plan, preview, pricing

    var previous: Self? {
        switch self {
        case .plan: nil
        case .preview: .plan
        case .pricing: .preview
        }
    }

    var next: Self? {
        switch self {
        case .plan: .preview
        case .preview: .pricing
        case .pricing: nil
        }
    }
}

enum OnboardingPlanSummary {
    /// Keep the existing plan's identity, ordering and wording all the way to the Plan tab.
    static func items(from plan: [StarterPlanItem]) -> [StarterPlanItem] {
        let priorities = ["setup.baselinePhoto", "procedure.consultation", "discussion.labs", "discussion.care"]
        return Array(priorities.compactMap { id in plan.first { $0.id == id && !$0.isDone } }.prefix(3))
    }
}

/// Prices are already localized by StoreKit. Only the connecting words are ours. In particular,
/// a paid introductory offer is NOT necessarily a discounted first year: use its actual period
/// and number of periods, and state the regular renewal alongside it.
struct OnboardingPriceCopy: Equatable {
    let price: String
    let detail: String
    let action: String

    init(price: String, period: String, introPrice: String? = nil,
         introPeriod: String? = nil, introCount: Int = 1, mode: IntroMode? = nil) {
        self.price = price
        let renewal = "\(price) every \(period)"
        guard let introPrice, let introPeriod, let mode, introCount > 0 else {
            detail = "\(renewal). Auto-renews until cancelled."
            action = "Continue with Pro"
            return
        }
        switch mode {
        case .freeTrial:
            detail = "Free for \(introPeriod), then \(renewal). Auto-renews until cancelled."
            action = "Start free trial"
        case .payUpFront:
            detail = "\(introPrice) for the first \(introPeriod), then \(renewal). Auto-renews until cancelled."
            action = "Continue with Pro"
        case .payAsYouGo:
            detail = "\(introPrice) every \(introPeriod) for \(introCount) payments, then \(renewal). Auto-renews until cancelled."
            action = "Continue with Pro"
        }
    }

    enum IntroMode { case freeTrial, payUpFront, payAsYouGo }

    init(product: Product, introEligible: Bool) {
        let period = product.subscription?.subscriptionPeriod
        let offer = introEligible ? product.subscription?.introductoryOffer : nil
        let mode: IntroMode?
        switch offer?.paymentMode {
        case .freeTrial: mode = .freeTrial
        case .payUpFront: mode = .payUpFront
        case .payAsYouGo: mode = .payAsYouGo
        default: mode = nil
        }
        self.init(
            price: product.displayPrice,
            period: period.map { Self.period($0.value, unit: $0.unit) } ?? "subscription period",
            introPrice: offer?.displayPrice,
            introPeriod: offer.map {
                let count = $0.paymentMode == .payAsYouGo ? 1 : $0.periodCount
                return Self.period($0.period.value * count, unit: $0.period.unit)
            },
            introCount: offer?.periodCount ?? 1,
            mode: mode
        )
    }

    static func period(_ value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let name: String
        switch unit {
        case .day: name = "day"
        case .week: name = "week"
        case .month: name = "month"
        case .year: name = "year"
        @unknown default: name = "period"
        }
        return "\(value) \(name)\(value == 1 ? "" : "s")"
    }
}
