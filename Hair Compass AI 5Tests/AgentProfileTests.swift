import Foundation
import Testing

@testable import Hair_Compass_AI_5

/// The profile the agent sees, and the identifiers it must never see.
///
/// `AIContextBuilder` already states the rule — *"the profile section deliberately has NO name
/// field"* — and the agent runs on a server, so breaking it would ship a direct identifier off the
/// device, change the app's App Privacy labels, and widen the PDPL cross-border consent. These
/// tests are what stop that happening by accident during a refactor.
struct AgentProfileTests {

    private func profile(
        name: String = "Mohammed",
        birthDate: Date? = nil,
        ageBand: String = ""
    ) -> Profile {
        Profile(
            name: name,
            sex: .male,
            ageBand: ageBand,
            condition: .androgenetic,
            familyHistory: .paternal,
            baselineStage: "Norwood 3",
            wearsTightStyles: true,
            birthDate: birthDate
        )
    }

    // MARK: - Identifiers never travel

    @Test func encodedProfileContainsNoName() throws {
        let projected = AgentProfile.from(profile(name: "Mohammed"))
        let json = String(data: try JSONEncoder().encode(projected), encoding: .utf8) ?? ""
        #expect(!json.contains("Mohammed"))
        #expect(!json.lowercased().contains("\"name\""))
    }

    @Test func encodedProfileContainsNoBirthDate() throws {
        let born = Calendar.current.date(from: DateComponents(year: 1990, month: 6, day: 15))!
        let projected = AgentProfile.from(profile(birthDate: born))
        let json = String(data: try JSONEncoder().encode(projected), encoding: .utf8) ?? ""
        #expect(!json.contains("1990"))
        #expect(!json.lowercased().contains("birth"))
    }

    @Test func promptBlockNeverContainsTheName() {
        let block = AgentProfile.from(profile(name: "Mohammed")).promptBlock
        #expect(!block.contains("Mohammed"))
        #expect(block.contains(AgentProfile.nameToken))
    }

    // MARK: - Age

    @Test func exactAgeIsDerivedFromBirthDate() {
        let born = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))!
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        #expect(AgentProfile.derivedAge(from: profile(birthDate: born), now: now) == 36)
    }

    @Test func ageFallsBackToTheBandsLowerBound() {
        // Conservative on purpose: every age-gated caution tightens as age rises, so guessing low
        // can never loosen a safeguard.
        #expect(AgentProfile.derivedAge(from: profile(ageBand: "35-44")) == 35)
    }

    @Test func aNonsenseBirthDateIsIgnoredRatherThanTrusted() {
        let future = Calendar.current.date(byAdding: .year, value: 5, to: .now)!
        #expect(AgentProfile.derivedAge(from: profile(birthDate: future, ageBand: "25-34")) == 25)
    }

    @Test func noAgeInformationYieldsNil() {
        #expect(AgentProfile.derivedAge(from: profile()) == nil)
    }

    // MARK: - What the model is told

    @Test func promptBlockCarriesTheFactsThatGateAdvice() {
        let block = AgentProfile.from(profile(ageBand: "35-44")).promptBlock
        #expect(block.contains("age: 35"))
        #expect(block.contains("sex: male"))
        #expect(block.contains("family history"))
        #expect(block.contains("tight styles"))
    }

    @Test func aModelIsToldNotToInventAName() {
        let block = AgentProfile.from(profile(name: "  ")).promptBlock
        #expect(block.contains("do not invent"))
        #expect(!block.contains(AgentProfile.nameToken))
    }

    @Test func anEmptyProfileProducesNoBlockAtAll() {
        // Every turn pays for this block, so an empty one must cost nothing.
        #expect(AgentProfile.from(nil).promptBlock.isEmpty)
    }

    // MARK: - Substitution happens on the device

    @Test func theTokenIsReplacedLocally() {
        let personalised = AgentProfile.personalise(
            "Good news \(AgentProfile.nameToken) — shedding is down.", name: "Mohammed"
        )
        #expect(personalised == "Good news Mohammed — shedding is down.")
    }

    @Test func aMissingNameStripsTheTokenRatherThanShowingIt() {
        let personalised = AgentProfile.personalise(
            "Good news \(AgentProfile.nameToken) — shedding is down.", name: ""
        )
        #expect(!personalised.contains("{{"))
    }

    @Test func textWithoutTheTokenIsUnchanged() {
        let text = "Shedding is down."
        #expect(AgentProfile.personalise(text, name: "Mohammed") == text)
    }
}
