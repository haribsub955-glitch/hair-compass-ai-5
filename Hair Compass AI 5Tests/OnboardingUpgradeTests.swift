import Foundation
import Testing
@testable import Hair_Compass_AI_5

@Test func dayOneEntryCarriesAllAnswers() {
    let e = OnboardingSeed.dayOneEntry(shedIntensity: 0.9, oiliness: 2, flaking: 3, itch: 1, stress: 4, sleepQuality: 2)
    #expect(e.shed == .heavy)
    #expect(e.oiliness == 2); #expect(e.flaking == 3); #expect(e.itch == 1)
    #expect(e.stress == 4); #expect(e.sleepQuality == 2); #expect(e.erythema == 0)
}

@Test func dayOneEntryClampsOutOfRange() {
    let e = OnboardingSeed.dayOneEntry(shedIntensity: 0, oiliness: 9, flaking: -2, itch: 5, stress: 0, sleepQuality: 99)
    #expect(e.oiliness == 3); #expect(e.flaking == 0); #expect(e.itch == 3)
    #expect(e.stress == 1); #expect(e.sleepQuality == 5)
}

@Test func triggerEventsMatchSelection() {
    let events = OnboardingSeed.triggerEvents([.illness, .majorStress])
    #expect(events.count == 2)
    #expect(Set(events.map(\.type)) == Set([TriggerType.illness, .majorStress]))
    #expect(events.allSatisfy { !$0.note.isEmpty })
}

@Test func plainLanguageIsExhaustiveAndDistinct() {
    for c in HairCondition.allCases {
        #expect(!c.plainTitle.isEmpty)
        #expect(!c.plainSummary.isEmpty)
        #expect(!c.demoCaption.isEmpty)
    }
    #expect(Set(HairCondition.allCases.map(\.plainTitle)).count == HairCondition.allCases.count)
}
