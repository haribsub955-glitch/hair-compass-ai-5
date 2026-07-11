import Foundation
import StoreKit

/// StoreKit 2 wrapper for the Pro subscription. Entitlement-driven: `hasPro` reflects
/// `Transaction.currentEntitlements`, refreshed on launch, after purchases, and on
/// transaction updates. Fully usable with the store unreachable — products just stay empty
/// and the UI degrades to the free path.
@MainActor
@Observable
final class PurchaseService {
    static let monthlyID = "com.harib.haircompass.pro.monthly"
    static let yearlyID  = "com.harib.haircompass.pro.yearly"

    private(set) var products: [Product] = []
    private(set) var hasPro = false
    private(set) var isLoading = false
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        products = (try? await Product.products(for: [Self.monthlyID, Self.yearlyID])) ?? []
        await refreshEntitlement()
    }

    /// Returns true when the purchase completed (verified). Pending/cancelled return false.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            if case .verified(let t) = verification { await t.finish() }
            await refreshEntitlement()
            return hasPro
        default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement,
               t.productID == Self.monthlyID || t.productID == Self.yearlyID,
               t.revocationDate == nil {
                hasPro = true
                return
            }
        }
        hasPro = false
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }

    /// The product's introductory offer, if any (e.g. the 3-day free trial).
    func introOffer(for product: Product) -> Product.SubscriptionOffer? {
        product.subscription?.introductoryOffer
    }

    /// Whether THIS Apple ID can still use the group's intro offer (one per group).
    func isEligibleForIntro(_ product: Product) async -> Bool {
        guard let sub = product.subscription else { return false }
        return await sub.isEligibleForIntroOffer
    }

    /// "3-day free trial, then $4.99/month" — nil when no offer / ineligible handled by caller.
    func trialDescriptor(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial
        else { return nil }
        let period = offer.period
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = "days"
        }
        return "\(period.value)-\(unit) free trial, then \(product.displayPrice)"
    }
}

extension Product {
    /// The per-month equivalent for a multi-month subscription period (e.g. "$2.50/mo" shown
    /// under a yearly price) — derived from the product's own price and formatted with its own
    /// `priceFormatStyle` so it always matches the storefront's locale/currency. `nil` for
    /// non-subscription products or periods StoreKit reports as zero-length.
    var monthlyEquivalentDisplay: String? {
        guard let period = subscription?.subscriptionPeriod else { return nil }
        let months: Double
        switch period.unit {
        case .year: months = Double(period.value) * 12
        case .month: months = Double(period.value)
        case .week: months = Double(period.value) * 7 / 30.44
        case .day: months = Double(period.value) / 30.44
        @unknown default: return nil
        }
        guard months > 0 else { return nil }
        let perMonth = price / Decimal(months)
        return (perMonth.formatted(priceFormatStyle)) + "/mo"
    }
}
