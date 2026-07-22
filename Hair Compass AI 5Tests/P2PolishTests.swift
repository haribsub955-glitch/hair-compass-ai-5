import Foundation
import SwiftUI
import Testing
@testable import Hair_Compass_AI_5

struct P2PolishTests {
    @Test func missingAndCorruptWidgetDataUseSafePlaceholder() {
        let missing = WidgetSnapshotDecoder.decode(nil)
        let corrupt = WidgetSnapshotDecoder.decode(Data("not-json".utf8))

        #expect(missing.hasLoggedToday == false)
        #expect(missing.score == 0)
        #expect(missing.dueTitles.isEmpty)
        #expect(corrupt.hasLoggedToday == false)
        #expect(corrupt.score == 0)
        #expect(corrupt.dueTitles.isEmpty)
    }

    @Test func everyWidgetSurfaceDeepLinkRoundTrips() {
        for surface in WidgetDeepLinkSurface.allCases {
            #expect(DeepLinkRouter.destination(for: surface.url) == surface.destination)
        }
        #expect(DeepLinkRouter.destination(for: URL(string: "https://example.com")!) == nil)
    }

    @Test func liveActivityStateIsIdenticalForEverySystemPresentation() {
        let end = Date(timeIntervalSince1970: 1_700_000_060)
        let snapshot = RitualActivitySnapshot(
            kind: .massage, title: "Breathe",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            stepName: "Slow circles", progress: 0.42, endDate: end,
            staleDate: Date(timeIntervalSince1970: 1_700_000_120)
        )

        for presentation in RitualActivityPresentation.allCases {
            let state = RitualActivityContentStateBuilder.build(from: snapshot, for: presentation)
            #expect(state.stepName == "Slow circles")
            #expect(state.stepIndex == 1)
            #expect(state.totalSteps == 1)
            #expect(state.progress == 0.42)
            #expect(state.endDate == end)
        }
    }

    @Test func inactiveBackgroundActiveOrderingKeepsSnapshotsCovered() {
        let inactive = ScenePhaseDecision.reduce(phase: .inactive, isLocked: false, ritualPresented: false)
        let background = ScenePhaseDecision.reduce(phase: .background, isLocked: false, ritualPresented: false)
        let active = ScenePhaseDecision.reduce(phase: .active, isLocked: false, ritualPresented: false)

        #expect(inactive.shouldShowPrivacyOverlay)
        #expect(background.shouldShowPrivacyOverlay)
        #expect(background.shouldMarkBackgrounded)
        #expect(!active.shouldShowPrivacyOverlay)
    }

    @Test func repeatedCallbacksAreIdempotentDecisions() {
        let first = ScenePhaseDecision.reduce(phase: .inactive, isLocked: false, ritualPresented: true)
        let repeated = ScenePhaseDecision.reduce(phase: .inactive, isLocked: false, ritualPresented: true)
        #expect(first == repeated)
    }

    @Test func lockOverlapNeverUncoversANonActiveScene() {
        let inactive = ScenePhaseDecision.reduce(phase: .inactive, isLocked: true, ritualPresented: false)
        let background = ScenePhaseDecision.reduce(phase: .background, isLocked: true, ritualPresented: false)
        #expect(inactive.shouldShowPrivacyOverlay)
        #expect(background.shouldShowPrivacyOverlay)
    }

    @Test func presentedRitualActivityEndsWhenLeavingForegroundOnly() {
        #expect(ScenePhaseDecision.reduce(phase: .inactive, isLocked: false,
                                         ritualPresented: true).shouldEndRitualActivity)
        #expect(ScenePhaseDecision.reduce(phase: .background, isLocked: false,
                                         ritualPresented: true).shouldEndRitualActivity)
        #expect(!ScenePhaseDecision.reduce(phase: .active, isLocked: false,
                                          ritualPresented: true).shouldEndRitualActivity)
        #expect(!ScenePhaseDecision.reduce(phase: .inactive, isLocked: false,
                                          ritualPresented: false).shouldEndRitualActivity)
    }
}
