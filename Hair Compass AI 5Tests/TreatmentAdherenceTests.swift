//
//  TreatmentAdherenceTests.swift
//  Hair Compass AI 5Tests
//
//  Pure trailing-14-day-average adherence math (see Model/TreatmentAdherence.swift).
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct TreatmentAdherenceTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
    }

    private func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now)!
    }

    @Test func fullyAdheredTwiceDailyReachesTwoOnTheFinalDay() {
        let treatment = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, startDate: daysAgo(30))
        var doses: [TreatmentDose] = []
        for d in 0..<14 {
            doses.append(TreatmentDose(treatment: treatment, loggedAt: daysAgo(d)))
            doses.append(TreatmentDose(treatment: treatment, loggedAt: daysAgo(d)))
        }
        let series = TreatmentAdherence.dailyAverage(
            treatment: treatment, doses: doses, window: 30, now: now, calendar: calendar
        )
        #expect(abs((series.last?.value ?? -1) - 2.0) < 0.001)
    }

    @Test func doseExactlyFourteenDaysAgoFallsOutsideTheTrailingWindow() {
        let treatment = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, startDate: daysAgo(20))
        let dose = TreatmentDose(treatment: treatment, loggedAt: daysAgo(14))
        let series = TreatmentAdherence.dailyAverage(
            treatment: treatment, doses: [dose], window: 20, now: now, calendar: calendar
        )
        #expect(series.last?.value == 0)
    }

    @Test func doseThirteenDaysAgoIsCountedInTheTrailingWindow() {
        let treatment = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, startDate: daysAgo(20))
        let dose = TreatmentDose(treatment: treatment, loggedAt: daysAgo(13))
        let series = TreatmentAdherence.dailyAverage(
            treatment: treatment, doses: [dose], window: 20, now: now, calendar: calendar
        )
        #expect(abs((series.last?.value ?? -1) - (1.0 / 14.0)) < 0.001)
    }

    @Test func noDosesYieldsAnAllZeroSeriesSpanningTheFullWindow() {
        let treatment = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, startDate: daysAgo(60))
        let series = TreatmentAdherence.dailyAverage(
            treatment: treatment, doses: [], window: 30, now: now, calendar: calendar
        )
        #expect(series.count == 30)
        #expect(series.allSatisfy { $0.value == 0 })
    }

    @Test func daysBeforeStartDateAreOmitted() {
        let treatment = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, startDate: daysAgo(5))
        let series = TreatmentAdherence.dailyAverage(
            treatment: treatment, doses: [], window: 30, now: now, calendar: calendar
        )
        #expect(series.count <= 6)
    }

    @Test func dosesFromAnUnrelatedTreatmentAreNotCounted() {
        let treatment = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, startDate: daysAgo(20))
        let otherTreatment = Treatment(name: "Finasteride", treatmentClass: .finasteride, startDate: daysAgo(20))
        let dose = TreatmentDose(treatment: otherTreatment, loggedAt: daysAgo(0))
        let series = TreatmentAdherence.dailyAverage(
            treatment: treatment, doses: [dose], window: 20, now: now, calendar: calendar
        )
        #expect(series.last?.value == 0)
    }
}
