import Foundation
import StoreKit

/// The current purchase attempt's lifecycle — surfaced by callers so a failed purchase (network
/// error, payment declined) or an Ask-to-Buy hold never leaves a silently re-enabled button.
/// `.userCancelled` is deliberately NOT a case here: cancelling the system sheet resolves straight
/// back to `.idle`, since that's an intentional dismissal, not a failure worth a message.
enum PurchaseFlowState: Equatable {
    case idle
    case purchasing
    case pending
    case failed(String)
}

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
    /// Whether StoreKit has actually answered yet. `hasPro` starts `false` because there is no
    /// third state to start in — but "no subscription" and "not asked yet" are not the same
    /// claim, and treating them as one downgrades a paying subscriber for the first moments of
    /// every cold launch (paywalls over a paid app, and a suppressed widget snapshot written to
    /// the App Group that outlives the launch if the app is killed first). Callers must read
    /// this before acting on `hasPro` — see `Entitlements.effectiveHasPro`.
    private(set) var isEntitlementResolved = false
    private(set) var isLoading = false
    /// Lifecycle of the most recent `purchase(_:)` call — `.idle` once it's been consumed or
    /// before any attempt. Callers reset it themselves (e.g. on the next tap) rather than this
    /// service auto-clearing it, so a failure message stays visible until the user acts again.
    private(set) var purchaseState: PurchaseFlowState = .idle
    /// One-line, human-readable outcome of the most recent `restore()` call — "Pro restored." or
    /// "No previous purchase found." `nil` before the first restore attempt.
    private(set) var restoreResult: String?
    private(set) var isRestoring = false
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refreshEntitlement()
            }
        }
        // Set synchronously so the very first render (before the load Task below actually runs)
        // never shows the "can't reach the store" empty state for a frame.
        isLoading = true
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Entitlement first: it's a local `Transaction.currentEntitlements` walk, so a genuine
        // subscriber is recognised before — not after — the App Store round-trip for products.
        // The old order left `isEntitlementResolved` waiting on the network fetch, which was
        // only ever over-permissive for the free tier but slow for the paying one.
        await refreshEntitlement()
        do {
            products = try await Product.products(for: [Self.monthlyID, Self.yearlyID])
        } catch {
            products = []
        }
    }

    /// Clears a stale `.failed`/`.pending` state — call when the user dismisses the message or
    /// navigates away, so a later screen visit doesn't reopen on an old error.
    func resetPurchaseState() {
        purchaseState = .idle
    }

    /// Returns true when the purchase completed (verified). Pending/cancelled return false;
    /// `purchaseState` carries the detail (pending vs. a genuine failure) for the UI.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let t):
                    await t.finish()
                    await refreshEntitlement()
                    purchaseState = .idle
                    return hasPro
                case .unverified:
                    purchaseState = .failed("We couldn't verify that purchase. Please try again.")
                    return false
                }
            case .pending:
                purchaseState = .pending
                return false
            case .userCancelled:
                purchaseState = .idle
                return false
            @unknown default:
                purchaseState = .idle
                return false
            }
        } catch is CancellationError {
            purchaseState = .idle
            return false
        } catch StoreKitError.userCancelled {
            purchaseState = .idle
            return false
        } catch {
            purchaseState = .failed(Self.message(for: error))
            return false
        }
    }

    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch is CancellationError {
            return
        } catch StoreKitError.userCancelled {
            return
        } catch {
            restoreResult = Self.message(for: error)
            return
        }
        await refreshEntitlement()
        restoreResult = hasPro ? "Pro restored." : "No previous purchase found."
    }

    /// One honest, plain-language line for a thrown StoreKit error — never the raw error text.
    private static func message(for error: Error) -> String {
        if let error = error as? Product.PurchaseError {
            switch error {
            case .productUnavailable:
                return "This plan isn't available right now."
            case .purchaseNotAllowed:
                return "Purchases aren't allowed on this device."
            case .ineligibleForOffer:
                return "You're not eligible for that offer."
            case .invalidOfferIdentifier, .invalidOfferPrice, .invalidOfferSignature, .missingOfferParameters:
                return "That offer couldn't be applied. Please try again."
            case .invalidQuantity:
                return "That purchase couldn't be completed."
            @unknown default:
                return "That purchase couldn't be completed."
            }
        }
        if let error = error as? StoreKitError {
            switch error {
            case .networkError:
                return "Can't reach the App Store right now."
            case .systemError:
                return "A system error stopped the purchase."
            case .notAvailableInStorefront:
                return "This plan isn't available in your storefront."
            case .notEntitled:
                return "You're not entitled to make this purchase."
            case .unsupported:
                return "Purchases aren't supported on this device."
            case .unknown, .userCancelled:
                return "The purchase couldn't be completed. Please try again."
            @unknown default:
                return "The purchase couldn't be completed. Please try again."
            }
        }
        return "The purchase couldn't be completed. Please try again."
    }

    private func refreshEntitlement() async {
        // `isEntitlementResolved` is set on BOTH exits: once StoreKit has enumerated the current
        // entitlements, "no subscription" is a real answer and may be acted on.
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement,
               t.productID == Self.monthlyID || t.productID == Self.yearlyID,
               t.revocationDate == nil {
                hasPro = true
                isEntitlementResolved = true
                return
            }
        }
        hasPro = false
        isEntitlementResolved = true
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

    /// "3-day free trial, then $9.99" — nil when no offer / ineligible handled by caller.
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

    /// What a year on the **monthly** plan actually costs, versus the yearly plan — e.g.
    /// "$118.80" vs "$39.99", 66% saved.
    ///
    /// This is the only "was/now" style comparison this app is allowed to draw, and the
    /// distinction is legal, not stylistic:
    ///
    /// - **Legitimate** (this): 12 × the *real, currently-sold* monthly price. The customer
    ///   genuinely would pay that much over a year, so it is a true comparison — provided the UI
    ///   labels it as the monthly-plan cost ("billed monthly") and never as a former price of the
    ///   yearly plan. Apple's own subscription sheets present savings this way.
    /// - **Illegal** (never do this): inventing a higher "original" yearly price the product was
    ///   never sold at. That is a fictitious reference price under the FTC Act, the EU Omnibus
    ///   Directive and the UK CPRs, and it breaches App Store Review 3.1.2.
    ///
    /// Returns `nil` unless both products are loaded, so the UI simply omits the comparison
    /// rather than inventing one. A genuine App Store Connect introductory offer is a separate,
    /// also-legitimate mechanism — see `launchOffer(for:)`.
    func yearlyVersusMonthly() -> (monthlyForAYear: String, yearly: String, percentOff: Int)? {
        guard let yearly, let monthly, monthly.price > 0, yearly.price > 0 else { return nil }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > yearly.price else { return nil }
        let pct = ((twelveMonths - yearly.price) / twelveMonths * 100)
        return (
            monthlyForAYear: twelveMonths.formatted(monthly.priceFormatStyle),
            yearly: yearly.displayPrice,
            percentOff: Int((pct as NSDecimalNumber).doubleValue.rounded())
        )
    }

    /// For a product whose intro offer is a paid launch discount (pay-up-front / pay-as-you-go):
    /// the intro price, the base price, and the honest rounded percent off — all from real prices.
    func launchOffer(for product: Product) -> (intro: String, base: String, percentOff: Int)? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .payUpFront || offer.paymentMode == .payAsYouGo,
              product.price > 0 else { return nil }
        let base = product.price
        let intro = offer.price
        let pct = ((base - intro) / base * 100)
        let percentOff = Int((pct as NSDecimalNumber).doubleValue.rounded())
        return (intro: offer.displayPrice, base: product.displayPrice, percentOff: percentOff)
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
