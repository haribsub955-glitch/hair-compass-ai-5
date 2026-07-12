//
//  ProgressReportFocusTests.swift
//  Hair Compass AI 5Tests
//
//  Round 5: `ProgressReport.build` used to always anchor to the earliest active daily
//  treatment. A user two years into minoxidil who adds finasteride would get milestone
//  reminders for finasteride that opened a report about minoxidil instead. `focus:` lets a
//  caller pick which treatment the report is about; these tests pin that down, plus the
//  photo-evidence pairing that rides along with it.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct ProgressReportFocusTests {

    private let calendar = Calendar.current

    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    @Test func focusSelectsTheNamedTreatmentInsteadOfTheEarliestOne() {
        let now = Date.now
        let minoxidil = Treatment(name: "Minoxidil", treatmentClass: .minoxidil,
                                   startDate: day(-800, from: now))
        minoxidil.scheduleTimes = "08:00,20:00"
        let finasteride = Treatment(name: "Finasteride", treatmentClass: .finasteride,
                                     startDate: day(-90, from: now))
        finasteride.scheduleTimes = "08:00"

        let report = ProgressReport.build(
            entries: [], treatments: [minoxidil, finasteride], doses: [],
            labs: [], sideEffects: [], triggers: [], focus: finasteride, now: now
        )

        #expect(report?.treatment?.name == "Finasteride")
        #expect(report?.periodStart == finasteride.startDate)
    }

    @Test func defaultsToEarliestTreatmentWhenNoFocusGiven() {
        let now = Date.now
        let minoxidil = Treatment(name: "Minoxidil", treatmentClass: .minoxidil,
                                   startDate: day(-800, from: now))
        minoxidil.scheduleTimes = "08:00,20:00"
        let finasteride = Treatment(name: "Finasteride", treatmentClass: .finasteride,
                                     startDate: day(-90, from: now))
        finasteride.scheduleTimes = "08:00"

        let report = ProgressReport.build(
            entries: [], treatments: [minoxidil, finasteride], doses: [],
            labs: [], sideEffects: [], triggers: [], now: now
        )

        #expect(report?.treatment?.name == "Minoxidil")
    }

    @Test func photoPairAnchorsBaselineToPeriodStartWhenFocused() {
        let now = Date.now
        let finasteride = Treatment(name: "Finasteride", treatmentClass: .finasteride,
                                     startDate: day(-90, from: now))
        finasteride.scheduleTimes = "08:00"

        let report = ProgressReport.build(
            entries: [], treatments: [finasteride], doses: [],
            labs: [], sideEffects: [], triggers: [], focus: finasteride, now: now
        )
        let report2 = try! #require(report)

        // Three captures of the same region: one long before the focused treatment even
        // started, one right at its start, one recent. The pair should anchor to the
        // near-start photo, not the ancient one.
        let ancient = PhotoRecord(region: .frontal, createdAt: day(-700, from: now))
        let atStart = PhotoRecord(region: .frontal, createdAt: day(-89, from: now))
        let recent = PhotoRecord(region: .frontal, createdAt: day(-1, from: now))

        let pair = try! #require(report2.photoPair(in: [ancient, atStart, recent]))
        #expect(pair.baseline === atStart)
        #expect(pair.latest === recent)
    }

    @Test func photoPairFallsBackToPlainEarliestLatestWithoutATreatment() {
        let now = Date.now
        // No active daily treatment, but enough entries to qualify for a baseline-only report.
        var entries: [DailyEntry] = []
        for offset in -70...0 {
            entries.append(DailyEntry(date: day(offset, from: now), shed: .normal))
        }
        let report = ProgressReport.build(
            entries: entries, treatments: [], doses: [],
            labs: [], sideEffects: [], triggers: [], now: now
        )
        let report2 = try! #require(report)
        #expect(report2.treatment == nil)

        let first = PhotoRecord(region: .vertex, createdAt: day(-60, from: now))
        let last = PhotoRecord(region: .vertex, createdAt: day(-1, from: now))
        let pair = try! #require(report2.photoPair(in: [first, last]))
        #expect(pair.baseline === first)
        #expect(pair.latest === last)
    }

    @Test func photoPairIsNilWithFewerThanTwoCaptures() {
        let now = Date.now
        let finasteride = Treatment(name: "Finasteride", treatmentClass: .finasteride,
                                     startDate: day(-90, from: now))
        finasteride.scheduleTimes = "08:00"
        let report = ProgressReport.build(
            entries: [], treatments: [finasteride], doses: [],
            labs: [], sideEffects: [], triggers: [], focus: finasteride, now: now
        )
        let report2 = try! #require(report)
        let solo = PhotoRecord(region: .frontal, createdAt: day(-30, from: now))
        #expect(report2.photoPair(in: [solo]) == nil)
    }
}
