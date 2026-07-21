//
//  BackupServiceTests.swift
//  Hair Compass AI 5Tests
//
//  Full backup/restore: the versioned JSON envelope round-trips every entity (photos as
//  base64), and restore is a merge-safe upsert — the same payload twice inserts nothing.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct BackupServiceTests {

    private let validImageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    /// Fresh in-memory store over the full app schema — nothing touches disk.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self,
            ProcedureAppointment.self, ProgressCheckIn.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// The standing fixture: 2 entries, 1 treatment with 2 doses + 1 side effect,
    /// 1 lab, 1 trigger, 1 snapshot, 1 photo — built as plain DTOs.
    private func fixtureEnvelope(now: Date, calendar: Calendar = .current) -> BackupService.Envelope {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        var env = BackupService.Envelope(createdAt: now)
        env.profile = BackupService.ProfileDTO(
            name: "Harib", sexRaw: BiologicalSex.male.rawValue, ageBand: "26–35",
            conditionRaw: HairCondition.androgenetic.rawValue,
            familyHistoryRaw: FamilyHistory.oneParent.rawValue,
            baselineStage: "Norwood III", createdAt: yesterday,
            hasOnboarded: true, wearsTightStyles: false, usesHeat: true,
            usesChemicalTreatments: false
        )
        env.entries = [
            .init(date: yesterday, shedRaw: ShedLevel.heavy.rawValue, flaking: 2, erythema: 1,
                  itch: 1, sleepQuality: 2, stress: 4, cigarettes: 0, alcoholDrinks: 1,
                  oiliness: 2, note: "windy day"),
            .init(date: now, shedRaw: ShedLevel.normal.rawValue, flaking: 0, erythema: 0,
                  itch: 0, sleepQuality: 4, stress: 2, cigarettes: 0, alcoholDrinks: 0,
                  oiliness: 0, note: "")
        ]
        env.treatments = [
            .init(name: "Minoxidil 5%", classRaw: TreatmentClass.minoxidil.rawValue,
                  dose: "1 mL", scheduleTimes: "08:00,21:00", startDate: yesterday,
                  isActive: true, refillBy: nil,
                  doses: [.init(loggedAt: yesterday, slot: "08:00"),
                          .init(loggedAt: now, slot: "21:00")],
                  sideEffects: [.init(date: now, severity: 2,
                                      typeRaw: SideEffectType.scalpIrritation.rawValue,
                                      note: "stings after the evening dose")])
        ]
        env.labs = [.init(testRaw: LabTest.ferritin.rawValue, value: 38,
                          collectedAt: yesterday, note: "baseline")]
        env.photos = [.init(regionRaw: PhotoRegion.vertex.rawValue, createdAt: yesterday,
                            lighting: "daylight", distance: "arm's length", parting: "center",
                            isWet: false, note: "",
                            imageBase64: validImageData.base64EncodedString())]
        env.snapshots = [.init(date: yesterday, sleepHours: 7.2, hrvSDNN: 44, restingHR: 58,
                               bodyMassKg: 78, bmi: 24.1, dietaryProteinG: 110, updatedAt: now)]
        env.triggers = [.init(typeRaw: TriggerType.illness.rawValue, date: yesterday,
                              note: "flu, ran a fever")]
        env.procedures = [.init(typeRaw: ProcedureType.prp.rawValue, date: yesterday,
                                location: "Downtown Derm", isCompleted: true,
                                completedAt: yesterday, note: "session 1")]
        env.progressCheckIns = [.init(date: yesterday, regrowthRaw: RegrowthLevel.few.rawValue,
                                      densityRaw: ProgressTrend.better.rawValue,
                                      sheddingRaw: ProgressTrend.same.rawValue,
                                      hairlineRaw: ProgressTrend.same.rawValue,
                                      overallRaw: ProgressTrend.better.rawValue,
                                      scalpPain: false, scalpPainNote: "", note: "month 1")]
        return env
    }

    // MARK: - Round trip

    @Test func roundTripPreservesCountsValuesAndDates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        let now = Date.now
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: now))

        // Build the fixture through real models so makeEnvelope's relationship
        // traversal (doses/sideEffects nested inside their treatment) is exercised.
        let profile = Profile(name: "Harib", sex: .male, ageBand: "26–35",
                              condition: .androgenetic, familyHistory: .oneParent,
                              baselineStage: "Norwood III", hasOnboarded: true, usesHeat: true)
        context.insert(profile)
        context.insert(DailyEntry(date: yesterday, shed: .heavy, flaking: 2, note: "windy day"))
        context.insert(DailyEntry(date: now, shed: .normal))
        let minox = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                              scheduleTimes: "08:00,21:00", startDate: yesterday)
        context.insert(minox)
        context.insert(TreatmentDose(treatment: minox, loggedAt: yesterday, slot: "08:00"))
        context.insert(TreatmentDose(treatment: minox, loggedAt: now, slot: "21:00"))
        context.insert(SideEffectLog(treatment: minox, type: .scalpIrritation, severity: 2,
                                     date: now, note: "stings"))
        context.insert(LabResult(test: .ferritin, value: 38, collectedAt: yesterday, note: "baseline"))
        context.insert(PhotoRecord(region: .vertex, imagePath: "fixture.jpg",
                                   createdAt: yesterday, lighting: "daylight"))
        context.insert(HealthSnapshot(date: yesterday, sleepHours: 7.2))
        context.insert(TriggerEvent(type: .illness, date: yesterday, note: "flu"))
        context.insert(ProcedureAppointment(type: .prp, date: yesterday, location: "Downtown Derm",
                                            isCompleted: true, completedAt: yesterday, note: "session 1"))
        context.insert(ProgressCheckIn(date: yesterday, regrowth: .few, density: .better,
                                       shedding: .same, hairline: .same, overall: .better,
                                       note: "month 1"))
        try context.save()

        let envelope = BackupService.makeEnvelope(
            profile: profile,
            entries: try context.fetch(FetchDescriptor<DailyEntry>()),
            treatments: try context.fetch(FetchDescriptor<Treatment>()),
            labs: try context.fetch(FetchDescriptor<LabResult>()),
            photos: try context.fetch(FetchDescriptor<PhotoRecord>()),
            snapshots: try context.fetch(FetchDescriptor<HealthSnapshot>()),
            triggers: try context.fetch(FetchDescriptor<TriggerEvent>()),
            procedures: try context.fetch(FetchDescriptor<ProcedureAppointment>()),
            progressCheckIns: try context.fetch(FetchDescriptor<ProgressCheckIn>()),
            createdAt: now,
            photoData: { path in path == "fixture.jpg" ? validImageData : nil }
        )
        let data = try BackupService.encode(envelope)
        let decoded = try BackupService.decode(data)

        // Counts — including the nested relationships.
        #expect(decoded.version == 1)
        #expect(decoded.entries.count == 2)
        #expect(decoded.treatments.count == 1)
        #expect(decoded.treatments.first?.doses.count == 2)
        #expect(decoded.treatments.first?.sideEffects.count == 1)
        #expect(decoded.labs.count == 1)
        #expect(decoded.photos.count == 1)
        #expect(decoded.snapshots.count == 1)
        #expect(decoded.triggers.count == 1)
        #expect(decoded.procedures.count == 1)
        #expect(decoded.progressCheckIns.count == 1)

        // Spot values, with enums stored as raw values.
        #expect(decoded.profile?.name == "Harib")
        #expect(decoded.profile?.conditionRaw == HairCondition.androgenetic.rawValue)
        #expect(decoded.treatments.first?.name == "Minoxidil 5%")
        #expect(decoded.treatments.first?.classRaw == "minoxidil")
        #expect(decoded.treatments.first?.sideEffects.first?.typeRaw == "scalpIrritation")
        #expect(decoded.labs.first?.value == 38)
        #expect(decoded.snapshots.first?.sleepHours == 7.2)
        #expect(decoded.photos.first?.imageBase64 == validImageData.base64EncodedString())
        #expect(decoded.procedures.first?.typeRaw == ProcedureType.prp.rawValue)
        #expect(decoded.procedures.first?.location == "Downtown Derm")
        #expect(decoded.progressCheckIns.first?.regrowthRaw == RegrowthLevel.few.rawValue)
        #expect(decoded.progressCheckIns.first?.note == "month 1")

        // Dates survive ISO8601 at whole-second fidelity and stay on the same calendar day.
        let labDate = try #require(decoded.labs.first?.collectedAt)
        #expect(BackupService.secondKey(labDate) == BackupService.secondKey(yesterday))
        #expect(cal.isDate(labDate, inSameDayAs: yesterday))
        let doseDate = try #require(decoded.treatments.first?.doses.first?.loggedAt)
        #expect(BackupService.secondKey(doseDate) == BackupService.secondKey(yesterday))

        // The archive really is versioned ISO8601 JSON.
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"version\":1"))
    }

    // MARK: - Version guard

    @Test func rejectsNewerMajorVersionWithAClearError() {
        let newer = Data(#"{"version":2,"createdAt":"2026-01-01T00:00:00Z"}"#.utf8)
        #expect(throws: BackupService.BackupError.unsupportedVersion(2)) {
            _ = try BackupService.decode(newer)
        }
        let garbage = Data("not json at all".utf8)
        #expect(throws: BackupService.BackupError.unreadableFile) {
            _ = try BackupService.decode(garbage)
        }
    }

    // MARK: - Merge-safe restore (upsert by natural keys)

    @Test func restoringTheSamePayloadTwiceInsertsNothingNew() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // A fresh phone: Seed.bootstrapIfNeeded leaves an untouched default profile.
        context.insert(Profile())
        try context.save()

        let now = Date.now
        let envelope = fixtureEnvelope(now: now)

        final class WriterLog { var writes = 0 }
        let log = WriterLog()
        let writer: (Data) -> String? = { _ in log.writes += 1; return "restored-\(log.writes).jpg" }

        // First pass: everything lands — profile applied (local was default) + 2 entries
        // + 1 treatment + 2 doses + 1 side effect + 1 lab + 1 photo + 1 snapshot + 1 trigger
        // + 1 procedure + 1 progress check-in.
        let first = try BackupService.restore(envelope, into: context, photoWriter: writer)
        #expect(first.inserted == 13)
        #expect(first.skipped == 0)
        #expect(first.photosRestored == 1)
        #expect(log.writes == 1)

        // The default profile took the backup's fields.
        let profile = try #require(try context.fetch(FetchDescriptor<Profile>()).first)
        #expect(profile.name == "Harib")
        #expect(profile.hasOnboarded == true)

        // Second pass: every record matches its natural key — nothing inserted, no photo
        // bytes rewritten, and the (now non-default) profile is kept as-is.
        let second = try BackupService.restore(envelope, into: context, photoWriter: writer)
        #expect(second.inserted == 0)
        #expect(second.photosRestored == 0)
        #expect(second.skipped == first.inserted)
        #expect(log.writes == 1)

        // Store totals confirm no duplicates.
        #expect(try context.fetch(FetchDescriptor<Profile>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DailyEntry>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<Treatment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<SideEffectLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<LabResult>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<HealthSnapshot>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TriggerEvent>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProcedureAppointment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProgressCheckIn>()).count == 1)
    }

    @Test func restoreKeepsAFilledInLocalProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let local = Profile(name: "Someone Else", hasOnboarded: true)
        context.insert(local)
        try context.save()

        let summary = try BackupService.restore(fixtureEnvelope(now: .now), into: context,
                                                photoWriter: { _ in "p.jpg" })
        // The profile was skipped (kept local), everything else landed.
        #expect(summary.skipped == 1)
        #expect(local.name == "Someone Else")
        #expect(try context.fetch(FetchDescriptor<Profile>()).count == 1)
    }

    @Test func dailyEntriesDedupeByCalendarDayNotExactTimestamp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        // A local entry logged at 09:00 today.
        let day = cal.startOfDay(for: .now)
        let morning = try #require(cal.date(byAdding: .hour, value: 9, to: day))
        context.insert(DailyEntry(date: morning, shed: .minimal))
        try context.save()

        // The backup carries the same day at 14:00 — same calendar day, so it's a skip.
        var env = BackupService.Envelope()
        let afternoon = try #require(cal.date(byAdding: .hour, value: 14, to: day))
        env.entries = [.init(date: afternoon, shedRaw: ShedLevel.heavy.rawValue,
                             flaking: 0, erythema: 0, itch: 0, sleepQuality: 3, stress: 3,
                             cigarettes: 0, alcoholDrinks: 0, oiliness: 0, note: "")]
        let summary = try BackupService.restore(env, into: context, photoWriter: { _ in nil })
        #expect(summary.inserted == 0)
        #expect(summary.skipped == 1)
        #expect(try context.fetch(FetchDescriptor<DailyEntry>()).count == 1)
    }

    // MARK: - Pure key helpers

    @Test func naturalKeysMatchAtSecondGranularity() {
        // ISO8601 drops fractional seconds, so an on-device Date with sub-second precision
        // must still match its restored twin.
        let fractional = Date(timeIntervalSince1970: 1_750_000_123.987)
        let truncated = Date(timeIntervalSince1970: 1_750_000_123)
        #expect(BackupService.secondKey(fractional) == BackupService.secondKey(truncated))
        #expect(BackupService.doseKey(loggedAt: fractional, slot: "08:00")
                == BackupService.doseKey(loggedAt: truncated, slot: "08:00"))
        #expect(BackupService.labKey(testRaw: "ferritin", collectedAt: fractional)
                == BackupService.labKey(testRaw: "ferritin", collectedAt: truncated))
        #expect(BackupService.photoKey(createdAt: fractional, regionRaw: "vertex")
                == BackupService.photoKey(createdAt: truncated, regionRaw: "vertex"))
        // Different natural identity → different key.
        #expect(BackupService.treatmentKey(name: "Minoxidil", startDate: truncated)
                != BackupService.treatmentKey(name: "Finasteride", startDate: truncated))
        #expect(BackupService.triggerKey(typeRaw: "illness", date: truncated)
                != BackupService.triggerKey(typeRaw: "majorStress", date: truncated))
        #expect(BackupService.procedureKey(typeRaw: "prp", date: fractional)
                == BackupService.procedureKey(typeRaw: "prp", date: truncated))
        #expect(BackupService.procedureKey(typeRaw: "prp", date: truncated)
                != BackupService.procedureKey(typeRaw: "transplant", date: truncated))
    }

    @Test func defaultProfileDetection() {
        #expect(BackupService.isDefaultProfile(Profile()))                       // untouched
        #expect(!BackupService.isDefaultProfile(Profile(name: "Harib")))         // named
        #expect(!BackupService.isDefaultProfile(Profile(hasOnboarded: true)))    // onboarded
    }

    @Test func manifestCoversEveryModelAndTreatmentRelationships() {
        #expect(BackupService.manifest.count == HairCompassSchemaV1.models.count)
        #expect(BackupService.manifest.contains("TreatmentDose → Treatment?"))
        #expect(BackupService.manifest.contains("SideEffectLog → Treatment?"))
    }

    @Test func exportRefusesAMissingPhotoFile() {
        let photo = PhotoRecord(region: .vertex, imagePath: "missing.jpg")
        #expect(throws: BackupService.BackupError.missingPhotoFiles(["missing.jpg"])) {
            _ = try BackupService.exportBackup(profile: nil, entries: [], treatments: [],
                                                labs: [], photos: [photo], snapshots: [], triggers: [],
                                                photoData: { _ in nil })
        }
    }

    @Test func restoreRejectsInvalidImageBeforeWriting() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var envelope = BackupService.Envelope()
        envelope.photos = [.init(regionRaw: PhotoRegion.vertex.rawValue,
                                 imageBase64: Data("not-an-image".utf8).base64EncodedString())]
        final class Writer { var calls = 0 }
        let writer = Writer()
        #expect(throws: BackupService.BackupError.invalidPhotoData) {
            _ = try BackupService.restore(envelope, into: context, photoWriter: { _ in
                writer.calls += 1
                return "should-not-write.jpg"
            })
        }
        #expect(writer.calls == 0)
    }
}
