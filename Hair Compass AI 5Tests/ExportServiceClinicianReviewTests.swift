//
//  ExportServiceClinicianReviewTests.swift
//  Hair Compass AI 5Tests
//
//  The consolidated "worth a clinician review" flags (Model/ClinicianReviewFlags.swift) now
//  surface as one honest line near the top of `ExportService.clinicianSummary`, ahead of the
//  Baseline section, whenever any flag fires — and are silent otherwise.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct ExportServiceClinicianReviewTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    @Test func summaryNamesAFiredFlagAheadOfBaseline() {
        let now = Date.now
        let checkIn = ProgressCheckIn(date: day(-10, from: now), scalpPain: true, scalpPainNote: "sore")

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [], treatments: [], doses: [],
            labs: [], triggers: [], progressCheckIns: [checkIn], now: now
        )

        #expect(summary.contains("PATTERNS WORTH A CLINICIAN'S REVIEW"))
        #expect(summary.contains("Scalp pain reported"))
        #expect(summary.contains("not a diagnosis"))

        // The flags line comes before the BASELINE section starts.
        let flagsIndex = summary.range(of: "PATTERNS WORTH A CLINICIAN'S REVIEW")!.lowerBound
        if let baselineIndex = summary.range(of: "BASELINE")?.lowerBound {
            #expect(flagsIndex < baselineIndex)
        }
    }

    @Test func summaryOmitsTheSectionWhenNoFlagsFire() {
        let now = Date.now
        let entry = DailyEntry(date: day(-1, from: now), shed: .normal)

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [entry], treatments: [], doses: [],
            labs: [], triggers: [], progressCheckIns: [], now: now
        )

        #expect(!summary.contains("PATTERNS WORTH A CLINICIAN'S REVIEW"))
    }

    @Test func summaryCombinesMultipleFiredFlagsInOneLine() {
        let now = Date.now
        let checkIn = ProgressCheckIn(date: day(-5, from: now), scalpPain: true)
        let sideEffect = SideEffectLog(type: .headache, severity: 3, date: day(-2, from: now))

        let summary = ExportService.clinicianSummary(
            profile: nil, entries: [], treatments: [], doses: [],
            labs: [], triggers: [], progressCheckIns: [checkIn], sideEffects: [sideEffect], now: now
        )

        #expect(summary.contains("Scalp pain reported"))
        #expect(summary.contains("Severe side effect logged"))
    }
}
