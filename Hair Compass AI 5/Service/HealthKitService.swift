import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif

/// Reads only the evidence-defensible HealthKit metrics (see docs/TrackingSpec.md + the
/// 2026-07-02 pass) and caches them as a daily `HealthSnapshot`. HRV/resting-HR are surfaced
/// elsewhere strictly as a *stress proxy*, never as a hair-loss predictor.
///
/// Fully usable with HealthKit off: every value is optional and the UI degrades honestly.
@MainActor
@Observable
final class HealthKitService: SignalSource {
    private(set) var authorization: HealthAuthorizationState
    private(set) var lastRefresh: Date?

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    /// The read set — deliberately narrow. Only types with a defensible link to hair loss.
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .mindfulSession) { types.insert(t) }
        for id: HKQuantityTypeIdentifier in [.heartRateVariabilitySDNN, .restingHeartRate,
                                             .bodyMass, .bodyMassIndex, .dietaryProtein] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        return types
    }
    #endif

    init() {
        #if canImport(HealthKit)
        authorization = HKHealthStore.isHealthDataAvailable() ? .notDetermined : .unavailable
        #else
        authorization = .unavailable
        #endif
    }

    func requestAuthorization() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { authorization = .unavailable; return }
        authorization = .requesting
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorization = .authorized
        } catch {
            authorization = .denied
        }
        #else
        authorization = .unavailable
        #endif
    }

    /// Re-derives real authorization at every launch. `init()` alone can only ever see
    /// `.notDetermined` — HealthKit doesn't persist our enum across process restarts, and
    /// this app never asks Apple to re-request. Without this, RootView's launch snapshot
    /// refresh and the dashboard's manual "Update from Health" row silently stop working
    /// after the very first session, and an already-granted user sees the connect prompt
    /// again on every relaunch. Call once, early, from RootView's launch `.task`.
    ///
    /// `statusForAuthorizationRequest` only reports whether a *new* system prompt would be
    /// shown — never whether read access was actually granted (Apple hides that for
    /// privacy). `.unnecessary` means "already asked", which for a read-only request set
    /// like this one is the closest honest signal to "usable": queries will run as before,
    /// even if some come back empty. `.shouldRequest` means truly never asked.
    func bootstrap() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { authorization = .unavailable; return }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            authorization = Self.resolvedAuthorization(for: status, current: authorization)
        } catch {
            // Leave authorization as-is; a failed status check shouldn't promote us.
        }
        #else
        authorization = .unavailable
        #endif
    }

    #if canImport(HealthKit)
    /// The state-machine step `bootstrap()` runs, pulled out as a pure function so it can be
    /// exercised in a unit test without a live `HKHealthStore` — tests can't actually grant
    /// HealthKit authorization, but they can construct an `HKAuthorizationRequestStatus` and
    /// assert the resulting `HealthAuthorizationState`.
    static func resolvedAuthorization(
        for status: HKAuthorizationRequestStatus,
        current: HealthAuthorizationState
    ) -> HealthAuthorizationState {
        switch status {
        case .unnecessary:
            return .authorized
        case .shouldRequest:
            return .notDetermined
        case .unknown:
            return current // genuinely can't say — leave the current/default state alone
        @unknown default:
            return current
        }
    }
    #endif

    /// Reads the latest metrics and upserts today's snapshot. Returns the snapshot (or nil if
    /// HealthKit is unavailable / no data). Safe to call repeatedly — it updates in place.
    @discardableResult
    func refreshSnapshot(context: ModelContext) async -> HealthSnapshot? {
        #if canImport(HealthKit)
        guard authorization == .authorized else { return nil }

        async let sleep = sleepHoursLastNight()
        async let hrv = mostRecent(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli))
        async let rhr = mostRecent(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let mass = mostRecent(.bodyMass, unit: .gramUnit(with: .kilo))
        async let bmi = mostRecent(.bodyMassIndex, unit: .count())
        async let protein = sumToday(.dietaryProtein, unit: .gram())

        let snapshot = upsertToday(context: context)
        snapshot.sleepHours = await sleep
        snapshot.hrvSDNN = await hrv
        snapshot.restingHR = await rhr
        snapshot.bodyMassKg = await mass
        snapshot.bmi = await bmi
        snapshot.dietaryProteinG = await protein
        snapshot.updatedAt = .now
        lastRefresh = .now
        return snapshot.hasAnyValue ? snapshot : nil
        #else
        return nil
        #endif
    }

    // MARK: - Persistence

    private func upsertToday(context: ModelContext) -> HealthSnapshot {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.date >= start && $0.date < startOfTomorrow },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = HealthSnapshot(date: .now)
        context.insert(fresh)
        return fresh
    }

    // MARK: - HealthKit queries

    #if canImport(HealthKit)
    /// Most-recent single reading of a quantity type, in the requested unit.
    private func mostRecent(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Cumulative sum of a quantity type since the start of today (e.g. dietary protein).
    private func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let value = stats?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Total asleep hours over the last night (looks back ~36h to catch late/early sleepers).
    private func sleepHoursLastNight() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let seconds = (samples as? [HKCategorySample])?
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }
    #endif
}
