//
//  ConcernFlowTests.swift
//  Hair Compass AI 5Tests
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct ConcernFlowTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9))!
    }

    private func record(
        sheddingAboveUsual: Bool = false,
        flagIDs: [String] = [],
        treatments: [ConcernRecord.TreatmentSummary] = [
            .init(name: "Minoxidil 5%", treatmentClass: .minoxidil, weeks: 5, sideEffectCount: 1)
        ],
        pregnancy: PregnancyStatus = .no,
        photo: PhotoCadence.Status = .upcoming(daysUntil: 11),
        keepChecking: Int = 0
    ) -> ConcernRecord {
        let treatment = Treatment(
            name: "Minoxidil 5%", treatmentClass: .minoxidil, scheduleTimes: "08:00",
            startDate: calendar.date(byAdding: .day, value: -33, to: now)!, isActive: true
        )
        return ConcernRecord(
            recentShed: [1, 1, 1, 1, 1, 1, 2],
            washDaysLast7: 3,
            sheddingAboveUsual: sheddingAboveUsual,
            scalpAverage: 4.2,
            phase: EvidencePhase.current(treatments: [treatment], entries: [], now: now, calendar: calendar),
            consistency30: .init(completed: 26, planned: 30, scored: 30),
            photo: photo,
            flagIDs: flagIDs,
            treatments: treatments,
            pregnancy: pregnancy,
            keepCheckingCount14d: keepChecking
        )
    }

    @Test func sevenKindsHaveHumanTitles() {
        #expect(ConcernKind.allCases.count == 7)
        #expect(ConcernKind.moreShedding.title == "More shedding")
        #expect(ConcernKind.keepChecking.title == "I keep checking")
        #expect(ConcernKind.somethingElse.title == "Something else")
    }

    @Test func questionsNeverExceedTwoAndSkipKnownFacts() {
        for kind in ConcernKind.allCases {
            #expect(ConcernResponder.questions(for: kind, record: record()).count <= 2, "\(kind)")
        }
        #expect(ConcernResponder.questions(for: .moreShedding, record: record()).isEmpty)
        #expect(ConcernResponder.questions(for: .sideEffect, record: record()).count == 1)
        let twoTreatments = record(treatments: [
            .init(name: "Minoxidil", treatmentClass: .minoxidil, weeks: 5, sideEffectCount: 0),
            .init(name: "Finasteride", treatmentClass: .finasteride, weeks: 5, sideEffectCount: 0)
        ])
        #expect(ConcernResponder.questions(for: .sideEffect, record: twoTreatments).count == 2)
    }

    @Test func moreSheddingSeparatesMomentFromPattern() {
        let response = ConcernResponder.respond(
            kind: .moreShedding,
            answers: [],
            record: record(sheddingAboveUsual: true)
        )
        #expect(response.headline == "Let's separate one moment from the pattern")
        #expect(response.recordShows.contains("higher shedding yesterday"))
        #expect(response.cannotConclude.contains("cannot show"))
        #expect(response.nextStep.contains("next two wash days"))
        #expect(response.seekHelp == nil)
        let flagged = ConcernResponder.respond(
            kind: .moreShedding,
            answers: [],
            record: record(flagIDs: ["heavyShed"])
        )
        #expect(flagged.seekHelp?.contains("clinician") == true)
    }

    @Test func sideEffectsAlwaysUseDeterministicSafetyCopy() {
        let severe = ConcernResponder.respond(kind: .sideEffect, answers: ["Severe"], record: record())
        #expect(severe.seekHelp?.contains("prescriber promptly") == true)
        #expect(severe.seekHelp?.contains(ConcernResponder.urgentLine) == true)
        #expect(severe.primary == .openTreatment(name: "Minoxidil 5%"))
        let mild = ConcernResponder.respond(kind: .sideEffect, answers: ["Mild"], record: record())
        #expect(mild.seekHelp?.contains("Do not change the dose on your own") == true)
    }

    @Test func treatmentDoubtAboutASideEffectAlsoRoutesToSafety() {
        let response = ConcernResponder.respond(kind: .doubt, answers: ["A side effect"], record: record())
        #expect(response.seekHelp?.contains(ConcernResponder.urgentLine) == true)
        #expect(response.primary == .openTreatment(name: "Minoxidil 5%"))
    }

    @Test func pregnancyCautionJoinsSideEffectSafety() {
        let response = ConcernResponder.respond(
            kind: .sideEffect,
            answers: ["Mild"],
            record: record(pregnancy: .pregnant)
        )
        #expect(response.seekHelp?.contains("Minoxidil isn't established as safe in pregnancy") == true)
    }

    @Test func persistentScalpPainRequestsPromptReview() {
        let pain = ConcernResponder.respond(
            kind: .scalpSymptom,
            answers: ["Pain or tenderness", "Weeks"],
            record: record()
        )
        #expect(pain.seekHelp?.contains("prompt clinical review") == true)
        #expect(pain.primary == .logCheckIn)
        let itch = ConcernResponder.respond(
            kind: .scalpSymptom,
            answers: ["Itch", "Today"],
            record: record()
        )
        #expect(itch.seekHelp == nil)
        #expect(itch.recordShows.contains("scalp score"))
    }

    @Test func photoConcernHonorsTheActualCadence() {
        let waiting = ConcernResponder.respond(kind: .looksDifferent, answers: ["Not sure"], record: record())
        #expect(waiting.primary == .done)
        #expect(waiting.recordShows.contains("in 11 days"))
        let due = ConcernResponder.respond(
            kind: .looksDifferent,
            answers: ["Not sure"],
            record: record(photo: .due(daysOverdue: 0))
        )
        #expect(due.primary == .openPhotos)
    }

    @Test func treatmentDoubtNamesTheReviewClockAndHonestDenominators() {
        let response = ConcernResponder.respond(kind: .doubt, answers: ["No visible change yet"], record: record())
        #expect(response.recordShows.contains("week 5"))
        #expect(response.recordShows.contains("26 of 30 due"))
        #expect(response.cannotConclude.contains("week 24"))
        #expect(response.primary == .openPlan)
    }

    @Test func repeatedCheckingOffersAdditionalSupportWithoutLabelling() {
        let first = ConcernResponder.respond(kind: .keepChecking, answers: ["Several"], record: record())
        #expect(!first.offersFewerChecks)
        #expect(first.nextStep.contains("permission"))
        let repeated = ConcernResponder.respond(
            kind: .keepChecking,
            answers: ["Lost count"],
            record: record(keepChecking: 2)
        )
        #expect(repeated.offersFewerChecks)
        #expect(repeated.nextStep.contains("support from a professional"))
        #expect(!repeated.nextStep.lowercased().contains("anxiety"))
        #expect(!repeated.nextStep.lowercased().contains("disorder"))
    }

    @Test func everyResponseKeepsTheNonDiagnosticFraming() {
        let banned = ["diagnos", "cure", "you have", "you should", "you must", "start taking",
                      "stop taking", "double", "anxious", "anxiety", "disorder", "!", "getting worse"]
        var responses: [ConcernResponse] = []
        for kind in ConcernKind.allCases where kind != .somethingElse {
            let questions = ConcernResponder.questions(for: kind, record: record())
            responses.append(ConcernResponder.respond(
                kind: kind,
                answers: questions.map { $0.options[0] },
                record: record()
            ))
        }
        for response in responses {
            for text in [response.headline, response.recordShows, response.cannotConclude,
                         response.nextStep, response.seekHelp ?? "", response.closure, response.primaryLabel] {
                for word in banned {
                    #expect(!text.lowercased().contains(word), "\(response.headline): \(text) contains \(word)")
                }
            }
        }
    }

    @Test func logRemembersTodayCountsTrueCalendarWindowsAndCapsStorage() {
        let defaults = UserDefaults(suiteName: "ConcernFlowTests.\(UUID().uuidString)")!
        #expect(ConcernLog.today(now: now, calendar: calendar, defaults: defaults) == nil)
        ConcernLog.record(.keepChecking, now: calendar.date(byAdding: .day, value: -3, to: now)!, calendar: calendar, defaults: defaults)
        ConcernLog.record(.keepChecking, now: calendar.date(byAdding: .day, value: -20, to: now)!, calendar: calendar, defaults: defaults)
        ConcernLog.record(.moreShedding, now: now, calendar: calendar, defaults: defaults)
        #expect(ConcernLog.today(now: now, calendar: calendar, defaults: defaults) == .moreShedding)
        #expect(ConcernLog.count(.keepChecking, withinDays: 14, now: now, calendar: calendar, defaults: defaults) == 1)
        #expect(ConcernLog.count(.keepChecking, withinDays: 30, now: now, calendar: calendar, defaults: defaults) == 2)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        #expect(ConcernLog.today(now: tomorrow, calendar: calendar, defaults: defaults) == nil)

        for offset in 1...35 {
            ConcernLog.record(
                .doubt,
                now: calendar.date(byAdding: .minute, value: offset, to: now)!,
                calendar: calendar,
                defaults: defaults
            )
        }
        #expect(ConcernLog.count(.doubt, withinDays: 2, now: tomorrow, calendar: calendar, defaults: defaults) == 30)
    }
}
