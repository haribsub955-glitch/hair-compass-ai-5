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

/// Request/query state for HealthKit. Apple deliberately does not reveal read grants, so this
/// never models a read request as "authorized" or "denied".
enum HealthAuthorizationState: Equatable {
    case unavailable      // no HealthKit on this device
    case notRequested
    case requesting
    case requestedQueryable

    var isQueryable: Bool { self == .requestedQueryable }
    var canRequest: Bool { self == .notRequested }
}
