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
        #expect(Companion.pose(for: .celebrating) == CompanionArt.celebrating)
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
        let banned = ["diagnos", "cure", "you have", "condition", "prescrib"]
        for moment in CompanionMoment.allCases {
            guard let line = Companion.line(for: moment)?.lowercased() else { continue }
            for word in banned {
                #expect(!line.contains(word), "Companion copy must not sound diagnostic: \(line)")
            }
        }
    }
}
