//
//  HealthInsightsStore.swift
//  Hair Compass AI 5
//
//  Created by Codex on 25/03/2026.
//

import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthInsightsStore {
    enum AuthorizationState {
        case unavailable
        case idle
        case requesting
        case authorized
        case denied
    }

    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    var authorizationState: AuthorizationState = HKHealthStore.isHealthDataAvailable() ? .idle : .unavailable
    var dailyMetrics: [HealthDailyMetric] = []
    var lastSyncDate: Date?
    var isSyncing = false
    var errorMessage: String?

    var metricsByDay: [Date: HealthDailyMetric] {
        Dictionary(uniqueKeysWithValues: dailyMetrics.map { ($0.date, $0) })
    }

    var isAvailable: Bool {
        authorizationState != .unavailable
    }

    func requestAccessAndRefresh() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            errorMessage = "Health data is not available on this device."
            return
        }

        authorizationState = .requesting
        errorMessage = nil

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            authorizationState = .authorized
            await refresh()
        } catch {
            authorizationState = .denied
            errorMessage = error.localizedDescription
        }
    }

    func refresh(days: Int = 366) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            dailyMetrics = []
            return
        }

        isSyncing = true
        errorMessage = nil

        let endDate = Date()
        let rawStartDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        let startDate = calendar.startOfDay(for: rawStartDate)

        do {
            let sleepByDay = try await fetchSleepHours(startDate: startDate, endDate: endDate)
            let exerciseByDay = try await fetchDailySums(
                identifier: .appleExerciseTime,
                startDate: startDate,
                endDate: endDate,
                unit: .minute()
            )
            let proteinByDay = try await fetchDailySums(
                identifier: .dietaryProtein,
                startDate: startDate,
                endDate: endDate,
                unit: .gram()
            )
            let waterMillilitersByDay = try await fetchDailySums(
                identifier: .dietaryWater,
                startDate: startDate,
                endDate: endDate,
                unit: HKUnit.literUnit(with: .milli)
            )

            let allDays = Set(sleepByDay.keys)
                .union(exerciseByDay.keys)
                .union(proteinByDay.keys)
                .union(waterMillilitersByDay.keys)

            dailyMetrics = allDays
                .sorted()
                .map { day in
                    HealthDailyMetric(
                        date: day,
                        sleepHours: sleepByDay[day] ?? 0,
                        exerciseMinutes: exerciseByDay[day] ?? 0,
                        proteinGrams: proteinByDay[day] ?? 0,
                        waterLiters: (waterMillilitersByDay[day] ?? 0) / 1000
                    )
                }

            lastSyncDate = .now
            authorizationState = .authorized
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncing = false
    }

    private func fetchSleepHours(startDate: Date, endDate: Date) async throws -> [Date: Double] {
        guard let sampleType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }

            healthStore.execute(query)
        }

        var sleepByDay: [Date: Double] = [:]
        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))

        for sample in samples where asleepValues.contains(sample.value) {
            accumulateHours(from: sample.startDate, to: sample.endDate, into: &sleepByDay)
        }

        return sleepByDay
    }

    private func fetchDailySums(
        identifier: HKQuantityTypeIdentifier,
        startDate: Date,
        endDate: Date,
        unit: HKUnit
    ) async throws -> [Date: Double] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let anchorDate = calendar.startOfDay(for: startDate)
        let interval = DateComponents(day: 1)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Date: Double], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var values: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let day = self.calendar.startOfDay(for: statistics.startDate)
                    values[day] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                }

                continuation.resume(returning: values)
            }

            self.healthStore.execute(query)
        }
    }

    private func accumulateHours(from startDate: Date, to endDate: Date, into bucket: inout [Date: Double]) {
        guard endDate > startDate else { return }

        var current = startDate
        while current < endDate {
            let dayStart = calendar.startOfDay(for: current)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? endDate
            let segmentEnd = min(endDate, nextDay)

            bucket[dayStart, default: 0] += segmentEnd.timeIntervalSince(current) / 3600
            current = segmentEnd
        }
    }

    private static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exercise)
        }
        if let protein = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            types.insert(protein)
        }
        if let water = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }

        return types
    }
}
