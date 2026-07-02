import Foundation
import SwiftData

/// A source of automatically-fetched lifestyle/health signals. HealthKit is the first
/// implementation; a direct Whoop (or Oura, Garmin, …) connector can conform later without
/// touching any caller. This is the seam the design keeps open for wearables beyond Health.
@MainActor
protocol SignalSource: AnyObject {
    var authorization: HealthAuthorizationState { get }
    func requestAuthorization() async
    /// Fetch today's metrics and upsert a `HealthSnapshot` for today into the context.
    @discardableResult
    func refreshSnapshot(context: ModelContext) async -> HealthSnapshot?
}

/// Authorization state for an auto source. Read access can't be truly introspected on
/// HealthKit (Apple hides it for privacy), so `.authorized` means "asked and querying".
enum HealthAuthorizationState: Equatable {
    case unavailable      // no HealthKit on this device
    case notDetermined    // never asked
    case requesting
    case authorized       // asked; queries will run (data may still be empty)
    case denied

    var isUsable: Bool { self == .authorized }
    var canConnect: Bool { self == .notDetermined || self == .denied }
}
