//
//  AIContextTests.swift
//  Hair Compass AI 5Tests
//
//  The canonical, versioned AI context (AIContextBuilder.swift): the one JSON shape every
//  AI feature reads. Determinism, capping, gate math, lab flags, and the no-identifiers rule.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct AIContextTests {

    private let calendar = Calendar.current

    /// Fixed reference "now": a mid-day moment so day arithmetic never straddles midnight.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    /// One rich, deterministic fixture reused across the stability/round-trip assertions.
    private func makeRichContext() -> AIContext {
        let entries = (0..<30).map { offset in
            DailyEntry(date: day(-offset), shed: offset < 10 ? .normal : .elevated,
                       flaking: 1, erythema: 1, itch: 0,
                       sleepQuality: 3, stress: 2, oiliness: 1)
        }
        let minox = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil,
                              dose: "1 mL", scheduleTimes: "08:00,21:00",
                              startDate: day(-175), refillBy: day(20))
        let doses = (0..<14).map { offset in
            TreatmentDose(treatment: minox, loggedAt: day(-offset), slot: "08:00")
        }
        let sideEffects = [
            SideEffectLog(treatment: minox, type: .scalpIrritation, severity: 2, date: day(-5)),
            SideEffectLog(treatment: minox, type: .itching, severity: 1, date: day(-60)),  // stale
        ]
        let snapshots = (0..<60).map { offset in
            HealthSnapshot(date: day(-offset), sleepHours: 7.2, hrvSDNN: 48,
                           restingHR: 61, bodyMassKg: 80 - Double(60 - offset) * 0.02,
                           dietaryProteinG: 110)
        }
        let triggers = [TriggerEvent(type: .illness, date: day(-70))]
        let labs = [LabResult(test: .ferritin, value: 22.34, collectedAt: day(-40))]
        let photos = [
            PhotoRecord(region: .frontal, imagePath: "a.jpg", createdAt: day(-90)),
            PhotoRecord(region: .vertex, imagePath: "b.jpg", createdAt: day(-1)),
        ]
        let profile = Profile(name: "Casimir Fairweather", sex: .male, ageBand: "30-39",
                              condition: .androgenetic, familyHistory: .oneParent,
                              baselineStage: "Norwood 3", usesHeat: true)
        return AIContext.build(
            entries: entries, treatments: [minox], doses: doses, snapshots: snapshots,
            triggers: triggers, labs: labs, sideEffects: sideEffects, photos: photos,
            profile: profile, now: now, calendar: calendar)
    }

    // MARK: - Version & envelope

    @Test func schemaVersionIsStampedAndSerialized() {
        let empty = AIContext.build(
            entries: [], treatments: [], doses: [], snapshots: [], triggers: [],
            labs: [], sideEffects: [], photos: [], profile: nil, now: now, calendar: calendar)
        #expect(empty.schemaVersion == 2)
        #expect(empty.schemaVersion == AIContext.currentSchemaVersion)
        #expect(empty.jsonString().contains("\"schemaVersion\":2"))
        // generatedAt is derived from the passed-in now, not a hidden Date.now.
        #expect(empty.generatedAt == AIContext.iso8601(now))
    }

    // MARK: - Daily series

    @Test func dailySeriesIsCappedAt120AndDateAscending() {
        // 200 days of history, handed over in shuffled order.
        let entries = (0..<200).map { DailyEntry(date: day(-$0), shed: .normal) }.shuffled()
        let ctx = AIContext.build(
            entries: entries, treatments: [], doses: [], snapshots: [], triggers: [],
            labs: [], sideEffects: [], photos: [], profile: nil, now: now, calendar: calendar)

        #expect(ctx.dailySeries.days.count == 120)
        let dates = ctx.dailySeries.days.map(\.date)
        #expect(dates == dates.sorted())                                  // "yyyy-MM-dd" sorts as dates
        #expect(dates.last == AIContext.dayString(now, calendar: calendar))   // ends at today
        // entryCount reports the full history even though the series is capped.
        #expect(ctx.meta.entryCount == 200)
    }

    @Test func dailySeriesCarriesTheLoggedFieldsAndRollingStats() throws {
        // 14 days: elevated (2) for the older week, minimal (0) for the recent week → falling.
        let entries = (0..<14).map { offset in
            DailyEntry(date: day(-offset), shed: offset < 7 ? .minimal : .elevated,
                       flaking: 2, erythema: 1, itch: 1, sleepQuality: 4, stress: 5, oiliness: 3)
        }
        let ctx = AIContext.build(
            entries: entries, treatments: [], doses: [], snapshots: [], triggers: [],
            labs: [], sideEffects: [], photos: [], profile: nil, now: now, calendar: calendar)

        let today = try #require(ctx.dailySeries.days.last)
        #expect(today.shed == 0)
        #expect(today.scalpTotal == 8)     // flaking band 2 → 6, + erythema 1 + itch 1
        #expect(today.sleepQuality == 4)
        #expect(today.stress == 5)
        #expect(today.oiliness == 3)

        // The precomputed stats agree with the reused math (ChartMath / HairAnalytics).
        let shedValues = entries.sorted { $0.date < $1.date }.map { Double($0.shed.rawValue) }
        let expectedEndpoint = AIContext.round1(ChartMath.rollingMean(shedValues, window: 7).last!)
        #expect(ctx.dailySeries.shed7d == expectedEndpoint)
        let direction = try #require(ctx.dailySeries.shedDirection)
        #expect(direction < 0)             // elevated → minimal reads as falling
    }

    // MARK: - Treatments

    @Test func treatmentWeeksElapsedAndOutcomeGate() throws {
        let ready = Treatment(name: "Fin", treatmentClass: .finasteride, startDate: day(-25 * 7))
        let early = Treatment(name: "Minox", treatmentClass: .minoxidil, startDate: day(-4 * 7))
        let ctx = AIContext.build(
            entries: [], treatments: [ready, early], doses: [], snapshots: [], triggers: [],
            labs: [], sideEffects: [], photos: [], profile: nil, now: now, calendar: calendar)

        let fin = try #require(ctx.treatments.first { $0.name == "Fin" })
        #expect(fin.weeksElapsed == 25)
        #expect(fin.outcomeReady == true)
        #expect(fin.treatmentClass == "finasteride")
        #expect(fin.startDate == AIContext.dayString(day(-25 * 7), calendar: calendar))

        let minox = try #require(ctx.treatments.first { $0.name == "Minox" })
        #expect(minox.weeksElapsed == 4)
        #expect(minox.outcomeReady == false)
        #expect(minox.slots == ["08:00", "21:00"])   // class default cadence

        // Ordered by start date, oldest first — deterministic regardless of input order.
        #expect(ctx.treatments.map(\.name) == ["Fin", "Minox"])
    }

    @Test func treatmentSideEffectsAreWindowedToThirtyDays() throws {
        let ctx = makeRichContext()
        let minox = try #require(ctx.treatments.first)
        // Only the recent (day -5) log survives; the day -60 one is out of window.
        #expect(minox.recentSideEffects.count == 1)
        #expect(minox.recentSideEffects.first?.name == "Scalp irritation")
        #expect(minox.recentSideEffects.first?.severity == 2)
        // Adherence: 14 once-a-day logs against a 2-slot regimen over 14 days = 50%.
        #expect(minox.adherencePercent == 50)
        #expect(minox.refillBy == AIContext.dayString(day(20), calendar: calendar))
    }

    // MARK: - Labs

    @Test func labsCarryTheFlagMappingAndReferenceRange() throws {
        let labs = [
            LabResult(test: .ferritin, value: 10, collectedAt: day(-30)),    // < 30 → low
            LabResult(test: .tsh, value: 2.0, collectedAt: day(-20)),        // in range
            LabResult(test: .vitaminD, value: 150, collectedAt: day(-10)),   // > 100 → high
        ]
        let ctx = AIContext.build(
            entries: [], treatments: [], doses: [], snapshots: [], triggers: [],
            labs: labs, sideEffects: [], photos: [], profile: nil, now: now, calendar: calendar)

        #expect(ctx.labs.map(\.flag) == ["low", "normal", "high"])
        let ferritin = try #require(ctx.labs.first)
        #expect(ferritin.test == "ferritin")
        #expect(ferritin.title == "Ferritin")
        #expect(ferritin.unit == "ng/mL")
        #expect(ferritin.referenceLow == 30)
        #expect(ferritin.referenceHigh == 300)
        #expect(ferritin.collectedAt == AIContext.dayString(day(-30), calendar: calendar))
    }

    // MARK: - Triggers & body signals

    @Test func triggersAndBodySignalsReuseTheDeterministicMath() throws {
        let ctx = makeRichContext()

        let trigger = try #require(ctx.triggers.first)
        #expect(trigger.type == "illness")
        #expect(trigger.weeksAgo == 10)    // 70 days = 10 whole weeks

        // Every snapshot field has readings → all five signals present, with 30d deltas.
        #expect(Set(ctx.bodySignals.signals.map(\.id))
            == Set(["sleep", "hrv", "restingHR", "weight", "protein"]))
        let sleep = try #require(ctx.bodySignals.signals.first { $0.id == "sleep" })
        #expect(sleep.latest == 7.2)
        // The steady 0.02 kg/day drop is ~1.5% over 90 days — below the 5% rule, so no alarm.
        #expect(ctx.bodySignals.rapidWeightLossPercent == nil)
    }

    @Test func rapidWeightLossSurfacesWhenTheRuleFires() {
        let snapshots = [
            HealthSnapshot(date: day(-60), bodyMassKg: 80),
            HealthSnapshot(date: day(-2), bodyMassKg: 74),   // 7.5% in-window drop
        ]
        let ctx = AIContext.build(
            entries: [], treatments: [], doses: [], snapshots: snapshots, triggers: [],
            labs: [], sideEffects: [], photos: [], profile: nil, now: now, calendar: calendar)
        #expect(ctx.bodySignals.rapidWeightLossPercent == 7.5)
    }

    // MARK: - Serialization: round-trip & stability

    @Test func jsonRoundTripsThroughCodable() throws {
        let ctx = makeRichContext()
        let decoded = try JSONDecoder().decode(AIContext.self, from: Data(ctx.jsonString().utf8))
        #expect(decoded == ctx)
        // Pretty vs compact is formatting only — same content.
        let prettyDecoded = try JSONDecoder().decode(
            AIContext.self, from: Data(ctx.jsonString(pretty: true).utf8))
        #expect(prettyDecoded == ctx)
    }

    @Test func sortedKeysMakeTwoBuildsByteIdentical() {
        // Two independent builds over equal fixtures must serialize to the same string —
        // the property tests and prompt caching both rely on.
        let a = makeRichContext().jsonString()
        let b = makeRichContext().jsonString()
        #expect(a == b)
        #expect(!a.isEmpty && a != "{}")
    }

    // MARK: - Privacy: no direct identifiers

    @Test func profileNameNeverEntersTheContext() {
        let json = makeRichContext().jsonString()
        // The fixture profile's name must not appear anywhere in the payload…
        #expect(!json.contains("Casimir"))
        #expect(!json.contains("Fairweather"))
        // …while the non-identifying baseline facts do flow through.
        #expect(json.contains("\"condition\":\"Androgenetic\""))
        #expect(json.contains("\"tractionRisk\":true"))
        #expect(json.contains("\"familyHistory\":\"oneParent\""))
        // Photos are metadata only — the stored image paths stay on-device too.
        #expect(!json.contains("a.jpg"))
        #expect(json.contains("\"regions\":[\"frontal\",\"vertex\"]"))
    }
}
