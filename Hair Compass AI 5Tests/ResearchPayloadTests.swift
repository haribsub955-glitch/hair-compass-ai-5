import Foundation
import Testing
@testable import Hair_Compass_AI_5

/// These tests are the enforcement mechanism for the contribution privacy guarantees, not a
/// description of them. `ResearchPayload`'s doc comment promises that certain data categorically
/// never leaves the device; a promise in a comment survives exactly as long as the next person who
/// edits the struct. `encodedPayloadOmitsIdentifyingFields` fails the build if anyone ever adds a
/// name, a note, a photo reference or a device identifier to the payload — including by accident,
/// via a field they thought was harmless.
@Suite("Research contribution payload")
struct ResearchPayloadTests {

    // MARK: Fixtures

    private func profile(
        name: String = "Alexandra Fitzgerald",
        condition: HairCondition = .androgenetic,
        sex: BiologicalSex = .female,
        ageBand: String = "26–35"
    ) -> Profile {
        let p = Profile()
        p.name = name
        p.conditionRaw = condition.rawValue
        p.sexRaw = sex.rawValue
        p.ageBand = ageBand
        p.wearsTightStyles = true
        return p
    }

    /// `count` consecutive days ending today, so the tracked window is deterministic.
    private func entries(
        count: Int,
        note: String = "",
        washEvery: Int? = nil,
        calendar: Calendar = .current
    ) -> [DailyEntry] {
        (0..<count).map { i in
            let e = DailyEntry()
            e.date = calendar.date(byAdding: .day, value: -i, to: .now) ?? .now
            e.note = note
            e.shedRaw = 2
            e.flaking = 1
            e.itch = 1
            e.stress = 3
            e.sleepQuality = 4
            if let washEvery { e.washedHair = i % washEvery == 0 }
            return e
        }
    }

    private func build(
        consentGiven: Bool = true,
        version: Int? = ResearchConsent.currentTermsVersion,
        profile p: Profile? = nil,
        entries e: [DailyEntry]? = nil
    ) -> ResearchPayload? {
        ResearchAggregator.build(
            consentGiven: consentGiven,
            consentTermsVersion: version,
            profile: p ?? profile(),
            entries: e ?? entries(count: 90),
            treatments: [],
            hasLabs: false,
            hasTriggers: false
        )
    }

    // MARK: Consent is a gate, not a preference

    @Test("No consent means no payload at all")
    func noConsentNoPayload() {
        #expect(build(consentGiven: false) == nil)
    }

    @Test("Consent without a recorded terms version is not consent")
    func missingTermsVersionYieldsNothing() {
        // A stored `true` with no version is the shape a botched migration would leave behind.
        // It must fail closed.
        #expect(build(version: nil) == nil)
    }

    @Test("A record too thin to be safe contributes nothing")
    func belowMinimumYieldsNothing() {
        let short = entries(count: ResearchPayload.minimumLoggedDays - 1)
        #expect(build(entries: short) == nil)
        let atThreshold = entries(count: ResearchPayload.minimumLoggedDays)
        #expect(build(entries: atThreshold) != nil)
    }

    // MARK: The core guarantee

    @Test("Encoded payload contains no identifying data")
    func encodedPayloadOmitsIdentifyingFields() throws {
        let p = profile(name: "Alexandra Fitzgerald")
        let e = entries(count: 120, note: "Saw Dr Okonkwo at St Mary's, my email is a@b.com")
        let payload = try #require(build(profile: p, entries: e))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(payload), encoding: .utf8) ?? ""
        let haystack = json.lowercased()

        // Direct identifiers and free text must not appear anywhere in the encoded output,
        // by value or by key.
        for forbidden in ["alexandra", "fitzgerald", "okonkwo", "st mary", "a@b.com",
                          "note", "name", "photo", "deviceid", "device_id",
                          "identifier", "uuid", "email"] {
            #expect(!haystack.contains(forbidden), "payload leaked \"\(forbidden)\": \(json)")
        }
    }

    @Test("No absolute dates survive — only relative durations")
    func noAbsoluteDates() throws {
        let payload = try #require(build())
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? ""
        let year = Calendar.current.component(.year, from: .now)
        // A calendar of someone's activity is a quasi-identifier; the payload carries weeks
        // tracked, never a date.
        #expect(!json.contains("\(year)"))
        #expect(!json.contains("Z\""))
        #expect(payload.weeksTracked > 0)
    }

    // MARK: Suppression of small cells

    @Test("Wash-day split is suppressed until both arms are statistics")
    func washDaySplitSuppressedWhenSparse() throws {
        // Wash day every 40th day over 90 days = 3 wash days: a description of three specific
        // days, not a statistic. Must be withheld.
        let sparse = try #require(build(entries: entries(count: 90, washEvery: 40)))
        #expect(sparse.meanShedOnWashDays == nil)

        // Every 3rd day = 30 wash days, comfortably a statistic.
        let dense = try #require(build(entries: entries(count: 90, washEvery: 3)))
        #expect(dense.meanShedOnWashDays != nil)
        #expect(dense.meanShedOnNonWashDays != nil)
    }

    @Test("Exact record counts are bucketed, not reported")
    func recordCountIsBucketed() throws {
        let a = try #require(build(entries: entries(count: 61)))
        let b = try #require(build(entries: entries(count: 118)))
        // Two different people in the same bucket are indistinguishable by record count.
        #expect(a.loggedDaysBucket == b.loggedDaysBucket)
        #expect(a.loggedDaysBucket == "60-119")
    }

    @Test("Unrecognised age bands generalise instead of passing through")
    func unknownAgeBandGeneralised() throws {
        let odd = profile(ageBand: "born 1987, Tuesday")
        let payload = try #require(build(profile: odd))
        #expect(payload.ageBand == ResearchPayload.generalisedAgeBand)

        let known = try #require(build(profile: profile(ageBand: "36–45")))
        #expect(known.ageBand == "36–45")
    }

    @Test("Adherence is rounded to 5% so it can't fingerprint")
    func adherenceRounded() throws {
        let payload = try #require(build(entries: entries(count: 77)))
        #expect(payload.adherencePercent % 5 == 0)
        #expect(payload.adherencePercent <= 100)
    }

    // MARK: Contributions must not be linkable

    @Test("Two builds from the same device produce no linking token")
    func contributionsAreUnlinkable() throws {
        let one = try #require(build())
        let two = try #require(build())
        // Identical inputs give identical output — there is no nonce, session or install id that
        // would let a server join two submissions from one person.
        #expect(one == two)
    }
}
