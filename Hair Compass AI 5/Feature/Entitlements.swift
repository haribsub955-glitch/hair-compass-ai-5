import Foundation

/// Everything Pro gates, as data rather than as twenty scattered `hasPro` checks.
///
/// Adding a feature here and applying `.proGated(_:)` at its surface is the whole job — the
/// policy stays readable in one place, and `EntitlementsTests` fails if the free tier ever
/// widens by accident.
enum ProFeature: CaseIterable, Hashable {
    case history, trends, compare, journey, photos, labs,
         procedures, treatments, reports, bodySignals
    case askWren, deepAnalysis

    /// The two features that run on Apple Intelligence with no cloud fallback.
    ///
    /// This is a property of the FEATURE, not of the subscription — which is the distinction
    /// that lets a subscription sell on hardware that can't run these two. Before this existed,
    /// `ProAvailability.sellable` withdrew the purchase buttons entirely and the app could not
    /// be sold on an iPhone 14 at all.
    var requiresAppleIntelligence: Bool {
        switch self {
        case .askWren, .deepAnalysis: true
        default: false
        }
    }
}

/// What someone is entitled to right now.
///
/// `taster` is deliberately identical to `pro`: three days of the real product, no payment
/// method, no turn caps. On-device inference means a farmed taster costs nothing to honour, so
/// there is no abuse defence to build and no reason to make it feel like a demo.
/// `Equatable` for the tier assertions in `EntitlementsTests`; `CustomStringConvertible` because
/// `RootView.widgetFingerprint` interpolates it (Task 9) and the default enum description would
/// change the fingerprint format if a case were ever renamed.
enum EntitlementTier: Equatable, CustomStringConvertible {
    case free
    case taster
    case pro

    var description: String {
        switch self {
        case .free: "free"
        case .taster: "taster"
        case .pro: "pro"
        }
    }
}

struct Entitlements {
    let tier: EntitlementTier

    func canAccess(_ feature: ProFeature) -> Bool {
        switch tier {
        case .free: false
        case .taster, .pro: true
        }
    }
}

/// Three days of the whole app, no payment method, on the device's own clock.
///
/// Reinstalling resets it, and that is accepted rather than defended: the model runs on-device,
/// so a farmed taster costs nothing. Building device binding to protect $0 would be effort spent
/// on nothing.
struct TasterWindow {
    static let durationDays = 3

    let firstLaunch: Date

    func isActive(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: Self.durationDays, to: firstLaunch)
        else { return false }
        return now < end
    }
}

extension Entitlements {
    /// The one place a tier is decided. `hasPro` covers both a paid subscription and an active
    /// Apple trial, because `Transaction.currentEntitlements` reports them identically.
    static func resolve(
        hasPro: Bool,
        firstLaunch: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> EntitlementTier {
        if hasPro { return .pro }
        if TasterWindow(firstLaunch: firstLaunch).isActive(now: now, calendar: calendar) { return .taster }
        return .free
    }
}
