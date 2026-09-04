//
//  WidgetSnapshotCompatibilityTests.swift
//  Hair Compass AI 5Tests
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct WidgetSnapshotCompatibilityTests {
    @Test func oldSnapshotDecodesWithInteractiveFieldsEmpty() {
        let old = """
        {"generatedAt": 0, "hasLoggedToday": true, "score": 71, "ringLog": 1,
         "ringCare": null, "ringLens": 0, "shedLabel": "Normal", "scalpLabel": "",
         "streakDays": 3, "shieldsHeld": 0,
         "dueTitles": ["Minoxidil 5% · 21:00"]}
        """
        let snapshot = WidgetSnapshotDecoder.decode(Data(old.utf8))
        #expect(snapshot.score == 71)
        #expect(snapshot.dueTitles == ["Minoxidil 5% · 21:00"])
        #expect(snapshot.dueItems.isEmpty)
        #expect(snapshot.pendingKeys.isEmpty)
    }

    @Test func newInteractiveFieldsRoundTrip() throws {
        let due = WidgetSnapshot.DueItem(
            title: "Minoxidil 5% · 21:00", treatmentName: "Minoxidil 5%", slot: "21:00"
        )
        let snapshot = WidgetSnapshot(
            generatedAt: .now, hasLoggedToday: false, score: 0, ringLog: 0,
            ringCare: 0, ringLens: 0, shedLabel: "", scalpLabel: "",
            streakDays: 0, shieldsHeld: 0, dueTitles: [due.title],
            dueItems: [due], pendingKeys: ["Minoxidil 5%|21:00"]
        )
        let back = WidgetSnapshotDecoder.decode(try JSONEncoder().encode(snapshot))
        #expect(back == snapshot)
    }
}
