//
//  EvidencePhaseTests.swift
//  Hair Compass AI 5Tests
//
//  Where the person is in the plan, as data: the anchor (earliest active daily treatment, else
//  the first entry), the day and week, the phase word, and the next review on the 4/12/24-week
//  clock the progress report already keeps.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct EvidencePhaseTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return c
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9))! }
    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now)! }

    @Test func anchorsOnTheEarliestActiveDailyTreatment() throws {
        let later = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                              scheduleTimes: "21:00", startDate: daysAgo(10), isActive: true)
        let earlier = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, dose: "1 mL",
                                scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        let paused = Treatment(name: "Old", treatmentClass: .minoxidil, dose: "",
                               scheduleTimes: "08:00", startDate: daysAgo(200), isActive: false)
        let phase = try #require(EvidencePhase.current(treatments: [later, earlier, paused], entries: [],
                                                       now: now, calendar: calendar))
        #expect(phase.anchor == .treatment(name: "Minoxidil"))
        #expect(phase.dayNumber == 34)
        #expect(phase.week == 4)
        #expect(phase.label == "Early evidence")
        #expect(phase.nextReviewWeek == 12)
        #expect(phase.daysToReview == 84 - 33)
        #expect(phase.isMilestoneWeek)
    }

    @Test func fallsBackToTheFirstEntry() throws {
        let entries = [DailyEntry(date: daysAgo(2)), DailyEntry(date: daysAgo(9))]
        let phase = try #require(EvidencePhase.current(treatments: [], entries: entries, now: now, calendar: calendar))
        #expect(phase.anchor == .record)
        #expect(phase.dayNumber == 10)
        #expect(phase.week == 1)
        #expect(phase.label == "Building the baseline")
        #expect(phase.nextReviewWeek == 4)
        #expect(!phase.isMilestoneWeek)
    }

    @Test func nothingToAnchorOnIsNil() {
        #expect(EvidencePhase.current(treatments: [], entries: [], now: now, calendar: calendar) == nil)
    }

    @Test func labelsFollowTheReviewClock() {
        #expect(EvidencePhase.label(forWeek: 0) == "Building the baseline")
        #expect(EvidencePhase.label(forWeek: 3) == "Building the baseline")
        #expect(EvidencePhase.label(forWeek: 4) == "Early evidence")
        #expect(EvidencePhase.label(forWeek: 11) == "Early evidence")
        #expect(EvidencePhase.label(forWeek: 12) == "Assessment")
        #expect(EvidencePhase.label(forWeek: 23) == "Assessment")
        #expect(EvidencePhase.label(forWeek: 24) == "Review-ready")
        #expect(EvidencePhase.label(forWeek: 40) == "Review-ready")
    }

    @Test func daysIntoWeekCountsFromTheWeekBoundary() throws {
        let t = Treatment(name: "M", treatmentClass: .minoxidil, dose: "", scheduleTimes: "08:00",
                          startDate: daysAgo(28), isActive: true)
        let phase = try #require(EvidencePhase.current(treatments: [t], entries: [], now: now, calendar: calendar))
        #expect(phase.week == 4 && phase.daysIntoWeek == 0)
    }

    @Test func progressToReviewTracksTheReviewClock() {
        let dayOne = EvidencePhase(anchor: .record, start: now, dayNumber: 1, week: 0,
                                   label: "Building the baseline", nextReviewWeek: 4,
                                   nextReviewDate: now, daysToReview: 27)
        #expect(dayOne.progressToReview == 0)

        // Day 34 of a week-12 review: 33/84.
        let day34 = EvidencePhase(anchor: .record, start: now, dayNumber: 34, week: 4,
                                  label: "Early evidence", nextReviewWeek: 12,
                                  nextReviewDate: now, daysToReview: 50)
        #expect(abs(day34.progressToReview - 33.0 / 84.0) < 0.0001)

        // The review day itself: dayNumber - 1 == nextReviewWeek * 7.
        let reviewDay = EvidencePhase(anchor: .record, start: now, dayNumber: 85, week: 12,
                                      label: "Assessment", nextReviewWeek: 12,
                                      nextReviewDate: now, daysToReview: 0)
        #expect(reviewDay.progressToReview == 1)
    }

    @Test func weekMatchesProgressReportsClock() throws {
        let t = Treatment(name: "M", treatmentClass: .minoxidil, dose: "", scheduleTimes: "08:00",
                          startDate: daysAgo(33), isActive: true)
        let phase = try #require(EvidencePhase.current(treatments: [t], entries: [], now: now, calendar: calendar))
        let progressWeek = HairAnalytics.weeksElapsed(since: phase.start, now: now, calendar: calendar)
        #expect(phase.week == progressWeek)
    }
}
