//
//  CompanionTests.swift
//  Hair Compass AI 5Tests
//
//  The Wren companion's personality is a pure mapping (moment -> pose asset + optional copy).
//  This is the only unit-tested part of the companion feature; the views are verified by build.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct CompanionTests {

    @Test func nameIsWren() {
        #expect(Companion.name == "Wren")
    }

    @Test func everyMomentMapsToANonEmptyWrenPose() {
        for moment in CompanionMoment.allCases {
            let pose = Companion.pose(for: moment)
            #expect(pose.hasPrefix("wren-"))
            #expect(!pose.isEmpty)
        }
    }

    @Test func poseMappingIsExact() {
        #expect(Companion.pose(for: .resting) == CompanionArt.resting)
        #expect(Companion.pose(for: .greeting) == CompanionArt.greeting)
        #expect(Companion.pose(for: .listening) == CompanionArt.listening)
        #expect(Companion.pose(for: .thinking) == CompanionArt.thinking)
        #expect(Companion.pose(for: .searching) == CompanionArt.searching)
        #expect(Companion.pose(for: .celebrating) == CompanionArt.listening)
    }

    @Test func motionProfilesStaySubtleAndNeverDriftSideways() {
        for moment in CompanionMoment.allCases {
            let motion = Companion.motion(for: moment)
            #expect(motion.breath <= 0.005)
            #expect(motion.verticalTravel <= 0.8)
            #expect(motion.tiltDegrees <= 0.7)
            #expect(motion.period >= 9)
        }
    }

    @Test func warmMomentsCarryCopyAmbientMomentsDoNot() {
        #expect(Companion.line(for: .greeting)?.isEmpty == false)
        #expect(Companion.line(for: .searching)?.isEmpty == false)
        #expect(Companion.line(for: .celebrating)?.isEmpty == false)
        #expect(Companion.line(for: .resting) == nil)
        #expect(Companion.line(for: .listening) == nil)
        #expect(Companion.line(for: .thinking) == nil)
    }

    @Test func copyNeverSoundsDiagnostic() {
        let banned = ["diagnos", "cure", "you have", "condition", "prescrib", "moves hair"]
        for moment in CompanionMoment.allCases {
            guard let line = Companion.line(for: moment)?.lowercased() else { continue }
            for word in banned {
                #expect(!line.contains(word), "Companion copy must not sound diagnostic: \(line)")
            }
        }
    }

    @Test func personaIsCalmHonestAndActionableWithoutMakingAClinicalPromise() {
        #expect(Companion.role.localizedCaseInsensitiveContains("calm"))
        #expect(Companion.introduction.localizedCaseInsensitiveContains("cannot"))
        #expect(Companion.introduction.localizedCaseInsensitiveContains("next step"))

        let allGuideCopy = CompanionGuideAction.allCases.flatMap {
            [$0.title, $0.instruction, $0.buttonTitle]
        } + [Companion.introduction, Companion.newcomerReassurance]
        let banned = ["diagnos", "cure", "start treatment", "guarantee"]
        for line in allGuideCopy.map({ $0.lowercased() }) {
            for word in banned {
                #expect(!line.contains(word), "Wren's guide must remain non-diagnostic: \(line)")
            }
        }
    }

    @Test func newcomerGuideExistsOnlyForTheFirstSevenDaysAfterOnboarding() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let daySeven = calendar.date(byAdding: .day, value: 6, to: start)!
        let dayEight = calendar.date(byAdding: .day, value: 7, to: start)!

        #expect(Companion.newcomerGuide(
            profileCreatedAt: start, firstEntryDate: start, hasOnboarded: false,
            hasLoggedToday: false, hasRoutine: false, hasBaselinePhoto: false,
            now: start, calendar: calendar
        ) == nil)
        #expect(Companion.newcomerGuide(
            profileCreatedAt: start, firstEntryDate: start, hasOnboarded: true,
            hasLoggedToday: false, hasRoutine: false, hasBaselinePhoto: false,
            now: daySeven, calendar: calendar
        )?.dayNumber == 7)
        #expect(Companion.newcomerGuide(
            profileCreatedAt: start, firstEntryDate: start, hasOnboarded: true,
            hasLoggedToday: false, hasRoutine: false, hasBaselinePhoto: false,
            now: dayEight, calendar: calendar
        ) == nil)
    }

    @Test func newcomerGuideUsesTheRecordForProgressAndKeepsTheInstructionOrder() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let guide = try #require(Companion.newcomerGuide(
            profileCreatedAt: now, firstEntryDate: now, hasOnboarded: true,
            hasLoggedToday: true, hasRoutine: false, hasBaselinePhoto: true,
            now: now
        ))

        #expect(guide.steps.map(\.action) == [.checkIn, .routine, .baselinePhoto])
        #expect(guide.steps.map(\.isComplete) == [true, false, true])
        #expect(guide.completedCount == 2)
    }
}
