import Foundation

/// Pure precedence decision for the one surface allowed to own the top of the app.
///
/// RootView still owns all launch and lifecycle effects. Moving those effects into a coordinator,
/// along with changing window/presenter ownership, is intentionally deferred to a future pass.
struct LaunchPresentationState: Equatable {
    enum Surface: Equatable {
        case persistenceRecovery
        case privacy
        case lock
        case onboarding
        case pendingRoute
        case ritual
        case normal
    }

    struct Input: Equatable {
        var persistenceFailed: Bool
        var isLocked: Bool
        var hasOnboarded: Bool
        var hasPendingRoute: Bool
        var ritualDueOrForced: Bool
        var appActive: Bool
    }

    let surface: Surface
    /// A privacy window obscures a presented flow; it must not tear that flow down. StoreKit,
    /// HealthKit and photo permission sheets all make the scene briefly inactive. Dismissing
    /// onboarding then discards its answers/phase and can cancel the system sheet above it.
    let keepsOnboardingMounted: Bool

    static func reduce(_ input: Input) -> LaunchPresentationState {
        let surface: Surface
        if input.persistenceFailed {
            surface = .persistenceRecovery
        } else if !input.appActive {
            surface = .privacy
        } else if input.isLocked {
            surface = .lock
        } else if !input.hasOnboarded {
            surface = .onboarding
        } else if input.hasPendingRoute {
            surface = .pendingRoute
        } else if input.ritualDueOrForced {
            surface = .ritual
        } else {
            surface = .normal
        }
        return LaunchPresentationState(
            surface: surface,
            keepsOnboardingMounted: !input.persistenceFailed && !input.isLocked && !input.hasOnboarded
        )
    }
}
