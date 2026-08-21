import Foundation

/// Everything Pro gates, as data rather than as twenty scattered `hasPro` checks.
///
/// Adding a feature here and applying `.proGated(_:)` at its surface is the whole job — the
/// policy stays readable in one place, and `EntitlementsTests` fails if the free tier ever
/// widens by accident.
enum ProFeature: CaseIterable, Hashable, Identifiable {
    case history, trends, compare, journey, photos, labs,
         procedures, treatments, reports, bodySignals
    case askWren, deepAnalysis

    /// Lets a feature drive a `.sheet(item:)` directly — used where a single sheet has to
    /// present whichever feature's paywall a free-tier write-path was aimed at (e.g. the
    /// Recommender's `.addToPlan`/`.startPatchPhotoSeries`/`.addLabResult` actions).
    var id: Self { self }

    /// The two AI features. With the cloud model configured (`CloudAIConfig`) they run on every
    /// iPhone; in a build without it they need Apple Intelligence hardware — `ProAvailability`
    /// folds that build-time fact into what the paywalls disclose.
    ///
    /// This is a property of the FEATURE, not of the subscription — which is the distinction
    /// that lets a subscription sell on hardware that can't run these two. Before this existed,
    /// `ProAvailability.sellable` withdrew the purchase buttons entirely and the app could not
    /// be sold on an iPhone 14 at all.
    var usesAI: Bool {
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

/// Gate copy for every feature, in one switch so a new case cannot ship with a blank paywall
/// card — `EntitlementsTests.everyFeatureHasGateCopy` asserts none of the three is ever empty.
extension ProFeature {
    var gateTitle: String {
        switch self {
        case .history: "Your full record"
        case .trends: "Trends"
        case .compare: "Compare"
        case .journey: "Your journey"
        case .photos: "Photos"
        case .labs: "Lab results"
        case .procedures: "Procedures"
        case .treatments: "Treatments"
        case .reports: "Progress reports"
        case .bodySignals: "Body signals"
        case .askWren: "Ask Wren"
        case .deepAnalysis: "Deep analysis"
        }
    }

    var gateSymbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .trends: "chart.xyaxis.line"
        case .compare: "rectangle.split.2x1"
        case .journey: "map"
        case .photos: "camera"
        case .labs: "testtube.2"
        case .procedures: "cross.case"
        case .treatments: "pills"
        case .reports: "doc.text"
        case .bodySignals: "heart.text.square"
        case .askWren: "bubble.left.and.text.bubble.right"
        case .deepAnalysis: "sparkles"
        }
    }

    var gateDescription: String {
        switch self {
        case .history: "Every check-in you've recorded, not just today."
        case .trends: "How shed, scalp and consistency move over weeks."
        case .compare: "Two dates side by side, on the same scale."
        case .journey: "Your whole record as one timeline."
        case .photos: "Capture, revisit and compare your own photos."
        case .labs: "Record results and see which are flagged."
        case .procedures: "Keep appointments and outcomes in one place."
        case .treatments: "Track what you're using and whether you're consistent."
        case .reports: "A summary you can read or hand to a clinician."
        case .bodySignals: "Sleep, stress and the rest, next to your hair record."
        case .askWren: "Ask about your own record, in plain language."
        case .deepAnalysis: "A closer read of everything you've logged."
        }
    }
}

extension Entitlements {
    /// `@AppStorage` cannot store an optional `Date`, so the stamp is a `TimeInterval` with `0`
    /// meaning "never written". Treating `0` as 1970 would hand every existing installation an
    /// expired taster on the update that ships this.
    static func firstLaunchStamp(stored: TimeInterval, now: Date = .now) -> Date {
        stored > 0 ? Date(timeIntervalSince1970: stored) : now
    }

    /// StoreKit answers asynchronously, so `PurchaseService.hasPro` is `false` for the first
    /// moments of every cold launch — including a paying subscriber's. Resolving that "not asked
    /// yet" state as `false` briefly renders paywalls over a paid app and (worse) writes a
    /// suppressed widget snapshot that survives if the app is killed before the answer lands.
    ///
    /// An unresolved answer therefore never downgrades: until StoreKit replies, the last tier it
    /// actually reported stands. It can only be over-permissive for the few hundred milliseconds
    /// between launch and `refreshEntitlement()` — and only for someone who genuinely was Pro on
    /// the previous launch.
    static func effectiveHasPro(resolved: Bool, current: Bool, lastKnown: Bool) -> Bool {
        resolved ? current : lastKnown
    }
}

#if DEBUG
extension Entitlements {
    /// `HC_TIER free | taster | pro` — forces the resolved tier for QA and App Review.
    ///
    /// Without it the free tier is unreachable on a device: `RootView` stamps `firstLaunchAt` on
    /// every fresh install, so every fresh install is a `.taster` for three days, and nobody
    /// (implementer, reviewer or App Reviewer) could see `LockedHistoryCard`, any `ProGate` or the
    /// suppressed widget snapshot without waiting out the clock or hand-editing `UserDefaults`.
    /// Same shape as `HC_AI_STATUS` (see `ProAvailability.forcedStatus`), and compiled out of
    /// release entirely rather than merely hidden behind an argument a shipping user could pass.
    static func forcedTier(arguments: [String] = ProcessInfo.processInfo.arguments) -> EntitlementTier? {
        guard let i = arguments.firstIndex(of: "HC_TIER"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "free": return .free
        case "taster": return .taster
        case "pro": return .pro
        default: return nil
        }
    }
}
#endif
