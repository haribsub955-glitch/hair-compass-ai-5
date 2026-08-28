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
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self, MissedDoseRecord.self,
            SideEffectLog.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self,
            ProcedureAppointment.self, ProgressCheckIn.self, AgentMemory.self
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

    @Test func patchSeriesLabelSurvivesBackupAndRestore() throws {
        let source = try makeContainer()
        let sourceContext = ModelContext(source)
        let photo = PhotoRecord(region: .patch, imagePath: "patch.jpg", patchSeriesLabel: "Back patch")
        sourceContext.insert(photo)
        try sourceContext.save()

        let envelope = BackupService.makeEnvelope(
            profile: nil, entries: [], treatments: [], doses: [], sideEffects: [], labs: [],
            photos: [photo], snapshots: [], triggers: [], procedures: [], progressCheckIns: [],
            photoData: { _ in self.validImageData }
        )
        let decoded = try BackupService.decode(BackupService.encode(envelope))
        #expect(decoded.photos.first?.patchSeriesLabel == "Back patch")

        let destination = try makeContainer()
        let destinationContext = ModelContext(destination)
        _ = try BackupService.restore(decoded, into: destinationContext, photoWriter: { _ in "restored.jpg" })
        let restored = try #require(destinationContext.fetch(FetchDescriptor<PhotoRecord>()).first)
        #expect(restored.patchSeriesLabel == "Back patch")
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
            doses: try context.fetch(FetchDescriptor<TreatmentDose>()),
            sideEffects: try context.fetch(FetchDescriptor<SideEffectLog>()),
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

    /// Guards the regression this fixes: `makeEnvelope`'s `doses:`/`sideEffects:` parameters
    /// must actually reach the archive and restore back out. A reintroduced `= []` default at
    /// a call site (like ExportSheet once had) would make this test's counts fall to zero.
    @Test func unattachedDosesAndSideEffectsRoundTripThroughMakeEnvelopeAndRestore() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date.now

        // No treatment attached — this is the array-level path `doses:`/`sideEffects:` cover,
        // distinct from the doses/side effects nested inside a treatment.
        let dose = TreatmentDose(loggedAt: now, slot: "08:00")
        let sideEffect = SideEffectLog(type: .scalpIrritation, severity: 2, date: now, note: "unattached log")
        context.insert(dose)
        context.insert(sideEffect)
        try context.save()

        let envelope = BackupService.makeEnvelope(
            profile: nil, entries: [], treatments: [],
            doses: try context.fetch(FetchDescriptor<TreatmentDose>()),
            sideEffects: try context.fetch(FetchDescriptor<SideEffectLog>()),
            labs: [], photos: [], snapshots: [], triggers: [],
            procedures: [], progressCheckIns: [],
            createdAt: now,
            photoData: { _ in nil }
        )
        #expect(envelope.unattachedDoses?.count == 1)
        #expect(envelope.unattachedSideEffects?.count == 1)

        let restoreContainer = try makeContainer()
        let restoreContext = ModelContext(restoreContainer)
        let summary = try BackupService.restore(envelope, into: restoreContext, photoWriter: { _ in nil })
        #expect(summary.inserted == 2)

        let restoredDoses = try restoreContext.fetch(FetchDescriptor<TreatmentDose>())
        let restoredSideEffects = try restoreContext.fetch(FetchDescriptor<SideEffectLog>())
        #expect(restoredDoses.count == 1)
        #expect(restoredDoses.first?.slot == "08:00")
        #expect(restoredDoses.first?.treatment == nil)
        #expect(restoredSideEffects.count == 1)
        #expect(restoredSideEffects.first?.note == "unattached log")
        #expect(restoredSideEffects.first?.typeRaw == SideEffectType.scalpIrritation.rawValue)
        #expect(restoredSideEffects.first?.treatment == nil)
    }

    @Test func missedDoseRecordsRoundTripAttachedAndUnattachedWithoutDuplicates() throws {
        let source = try makeContainer()
        let sourceContext = ModelContext(source)
        let date = Date.now
        let treatment = Treatment(name: "Topical record", startDate: date)
        sourceContext.insert(treatment)
        sourceContext.insert(MissedDoseRecord(treatment: treatment, date: date, slot: "21:00", reason: .supply))
        sourceContext.insert(MissedDoseRecord(date: date.addingTimeInterval(-86_400), slot: "08:00", reason: .travel))
        try sourceContext.save()

        let envelope = BackupService.makeEnvelope(
            profile: nil, entries: [], treatments: [treatment], doses: [], sideEffects: [],
            labs: [], photos: [], snapshots: [], triggers: [], procedures: [], progressCheckIns: [],
            missedDoses: try sourceContext.fetch(FetchDescriptor<MissedDoseRecord>()),
            photoData: { _ in nil }
        )
        let decoded = try BackupService.decode(BackupService.encode(envelope))
        #expect(decoded.treatments.first?.missedDoses?.first?.reasonRaw == MissedDoseReason.supply.rawValue)
        #expect(decoded.unattachedMissedDoses?.first?.reasonRaw == MissedDoseReason.travel.rawValue)

        let destination = try makeContainer()
        let destinationContext = ModelContext(destination)
        _ = try BackupService.restore(decoded, into: destinationContext, photoWriter: { _ in nil })
        _ = try BackupService.restore(decoded, into: destinationContext, photoWriter: { _ in nil })
        let restored = try destinationContext.fetch(FetchDescriptor<MissedDoseRecord>())
        #expect(restored.count == 2)
        #expect(restored.contains { $0.treatment?.name == "Topical record" && $0.slot == "21:00" && $0.reason == .supply })
        #expect(restored.contains { $0.treatment == nil && $0.reason == .travel })
    }

    @Test func backupsWithoutNewOptionalFieldsStillDecode() throws {
        var envelope = fixtureEnvelope(now: .now)
        envelope.treatments[0].missedDoses = [.init(reasonRaw: MissedDoseReason.forgot.rawValue)]
        envelope.procedures[0].agendaMainConcern = "Review timeline"
        envelope.progressCheckIns[0].hairFeelingRaw = HairFeeling.moreDifficult.rawValue
        let encoded = try BackupService.encode(envelope)
        var json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        if var treatments = json["treatments"] as? [[String: Any]] {
            treatments[0].removeValue(forKey: "missedDoses")
            json["treatments"] = treatments
        }
        if var procedures = json["procedures"] as? [[String: Any]] {
            procedures[0].removeValue(forKey: "agendaMainConcern")
            procedures[0].removeValue(forKey: "agendaChangedWhen")
            procedures[0].removeValue(forKey: "agendaTreatmentsToReview")
            procedures[0].removeValue(forKey: "agendaSafetyConcerns")
            procedures[0].removeValue(forKey: "agendaQuestionsRaw")
            json["procedures"] = procedures
        }
        if var checkIns = json["progressCheckIns"] as? [[String: Any]] {
            checkIns[0].removeValue(forKey: "hairFeelingRaw")
            checkIns[0].removeValue(forKey: "hairFeelingNote")
            json["progressCheckIns"] = checkIns
        }
        let oldStyleData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try BackupService.decode(oldStyleData)
        #expect(decoded.treatments[0].missedDoses == nil)
        #expect(decoded.procedures[0].agendaMainConcern == nil)
        #expect(decoded.progressCheckIns[0].hairFeelingRaw == nil)
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

    @Test func attachedDosesDedupeByTreatmentCalendarDayAndSlot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let morning = try #require(calendar.date(byAdding: .hour, value: 8, to: day))
        let afternoon = try #require(calendar.date(byAdding: .hour, value: 15, to: day))
        let startDate = try #require(calendar.date(byAdding: .day, value: -30, to: day))

        let treatment = Treatment(name: "Minoxidil", treatmentClass: .minoxidil,
                                  startDate: startDate)
        context.insert(treatment)
        context.insert(TreatmentDose(treatment: treatment, loggedAt: morning, slot: "08:00"))
        try context.save()

        var envelope = BackupService.Envelope()
        envelope.treatments = [
            .init(name: "Minoxidil", classRaw: TreatmentClass.minoxidil.rawValue,
                  startDate: startDate, doses: [.init(loggedAt: afternoon, slot: "08:00")])
        ]

        let summary = try BackupService.restore(envelope, into: context, photoWriter: { _ in nil })
        #expect(summary.inserted == 0)
        #expect(summary.skipped == 2) // matched treatment + matched dose
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 1)
    }

    @Test func unattachedDosesDedupeByCalendarDayAndSlot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let morning = try #require(calendar.date(byAdding: .hour, value: 8, to: day))
        let evening = try #require(calendar.date(byAdding: .hour, value: 20, to: day))
        context.insert(TreatmentDose(loggedAt: morning, slot: "08:00"))
        try context.save()

        var envelope = BackupService.Envelope()
        envelope.unattachedDoses = [
            .init(loggedAt: evening, slot: "08:00"),
            .init(loggedAt: evening, slot: "21:00")
        ]

        let first = try BackupService.restore(envelope, into: context, photoWriter: { _ in nil })
        #expect(first.inserted == 1)
        #expect(first.skipped == 1)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 2)

        let second = try BackupService.restore(envelope, into: context, photoWriter: { _ in nil })
        #expect(second.inserted == 0)
        #expect(second.skipped == 2)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 2)
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

    /// `AgentMemory` joined the SwiftData schema with the agent work but never joined the
    /// backup, so restoring silently dropped everything the agent had learned about the person.
    @Test func agentMemoriesRoundTripThroughMakeEnvelopeAndRestore() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let context = ModelContext(try makeContainer())
        let remembered = AgentMemory(
            scope: .global, sessionID: "conversation-1",
            text: "prefers evening applications", kind: .preference, createdAt: now
        )

        let envelope = BackupService.makeEnvelope(
            profile: nil, entries: [], treatments: [], doses: [], sideEffects: [], labs: [],
            photos: [], snapshots: [], triggers: [], procedures: [], progressCheckIns: [],
            agentMemories: [remembered], createdAt: now, photoData: { _ in nil }
        )
        _ = try BackupService.restore(envelope, into: context, photoWriter: { _ in nil })

        let restored = try context.fetch(FetchDescriptor<AgentMemory>())
        #expect(restored.count == 1)
        #expect(restored.first?.text == "prefers evening applications")
        #expect(restored.first?.scope == .global)
        #expect(restored.first?.kind == .preference)
        #expect(restored.first?.sessionID == "conversation-1")
    }

    /// A memory the user asked to forget is kept as a tombstone rather than deleted. If the
    /// tombstone doesn't survive the archive, restoring a backup resurrects something the
    /// person explicitly asked the agent to forget — the one outcome this must never produce.
    @Test func aForgottenMemoryIsStillForgottenAfterRestore() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let context = ModelContext(try makeContainer())
        let forgotten = AgentMemory(scope: .global, sessionID: "s", text: "an old aside", createdAt: now)
        forgotten.forgottenAt = now

        let envelope = BackupService.makeEnvelope(
            profile: nil, entries: [], treatments: [], doses: [], sideEffects: [], labs: [],
            photos: [], snapshots: [], triggers: [], procedures: [], progressCheckIns: [],
            agentMemories: [forgotten], createdAt: now, photoData: { _ in nil }
        )
        _ = try BackupService.restore(envelope, into: context, photoWriter: { _ in nil })

        let restored = try context.fetch(FetchDescriptor<AgentMemory>())
        #expect(restored.first?.isForgotten == true)
        #expect(AgentMemoryStore.recall([restored.first!], scope: nil, sessionID: "s",
                                        query: "aside", limit: 5).isEmpty)
    }

    /// Restore is a merge-safe upsert everywhere else; memories must not be the exception, or
    /// restoring the same file twice doubles everything the agent knows.
    @Test func restoringTheSameAgentMemoriesTwiceInsertsNothingNew() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let context = ModelContext(try makeContainer())
        let memory = AgentMemory(scope: .session, sessionID: "s1", text: "sleeps badly", createdAt: now)
        let envelope = BackupService.makeEnvelope(
            profile: nil, entries: [], treatments: [], doses: [], sideEffects: [], labs: [],
            photos: [], snapshots: [], triggers: [], procedures: [], progressCheckIns: [],
            agentMemories: [memory], createdAt: now, photoData: { _ in nil }
        )

        _ = try BackupService.restore(envelope, into: context, photoWriter: { _ in nil })
        let second = try BackupService.restore(envelope, into: context, photoWriter: { _ in nil })

        #expect(try context.fetch(FetchDescriptor<AgentMemory>()).count == 1)
        #expect(second.inserted == 0)
        #expect(second.skipped == 1)
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
                                                doses: [], sideEffects: [],
                                                labs: [], photos: [photo], snapshots: [], triggers: [],
                                                procedures: [], progressCheckIns: [],
                                                photoData: { _ in nil })
        }
    }

    /// The async, off-main export path (round 6) must write the exact same archive the
    /// synchronous path does — only *where* the base64 encoding happens changes, not what
    /// ends up in the file.
    @Test func exportBackupAsyncProducesTheSameArchiveAsTheSyncPath() async throws {
        let now = Date.now
        let photo = PhotoRecord(region: .vertex, imagePath: "fixture.jpg", createdAt: now, lighting: "daylight")
        let photoData: @Sendable (String) -> Data? = { $0 == "fixture.jpg" ? validImageData : nil }

        let syncURL = try BackupService.exportBackup(
            profile: nil, entries: [], treatments: [], doses: [], sideEffects: [],
            labs: [], photos: [photo], snapshots: [], triggers: [],
            procedures: [], progressCheckIns: [], now: now, photoData: photoData
        )
        let syncEnvelope = try BackupService.decode(Data(contentsOf: syncURL))

        let asyncURL = try await BackupService.exportBackupAsync(
            profile: nil, entries: [], treatments: [], doses: [], sideEffects: [],
            labs: [], photos: [photo], snapshots: [], triggers: [],
            procedures: [], progressCheckIns: [], now: now, photoData: photoData
        )
        let asyncEnvelope = try BackupService.decode(Data(contentsOf: asyncURL))

        #expect(asyncEnvelope.version == syncEnvelope.version)
        #expect(asyncEnvelope.photos.count == syncEnvelope.photos.count)
        #expect(asyncEnvelope.photos.first?.imageBase64 == validImageData.base64EncodedString())
        #expect(asyncEnvelope.photos.first?.imageBase64 == syncEnvelope.photos.first?.imageBase64)
    }

    @Test func exportBackupAsyncRefusesAMissingPhotoFile() async {
        let photo = PhotoRecord(region: .vertex, imagePath: "missing.jpg")
        await #expect(throws: BackupService.BackupError.missingPhotoFiles(["missing.jpg"])) {
            _ = try await BackupService.exportBackupAsync(profile: nil, entries: [], treatments: [],
                                                           doses: [], sideEffects: [],
                                                           labs: [], photos: [photo], snapshots: [], triggers: [],
                                                           procedures: [], progressCheckIns: [],
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

    @Test func treatmentIngredientAnalysisRoundTripsExactly() throws {
        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)
        let treatment = Treatment(
            name: "Custom serum", treatmentClass: .other, dose: "3 drops",
            startDate: Date(timeIntervalSince1970: 1_750_000_000),
            ingredientPhotoPath: "ingredient-label.jpg",
            aiIngredientSummary: "Record note: contains niacinamide; no diagnosis."
        )
        sourceContext.insert(treatment)
        try sourceContext.save()

        let envelope = BackupService.makeEnvelope(
            profile: nil, entries: [], treatments: [treatment], doses: [], sideEffects: [],
            labs: [], photos: [], snapshots: [], triggers: [], procedures: [],
            progressCheckIns: [], photoData: { path in
                path == "ingredient-label.jpg" ? self.validImageData : nil
            }
        )
        let archive = try BackupService.encode(envelope)
        let decoded = try BackupService.decode(archive)

        let restoredContainer = try makeContainer()
        let restoredContext = ModelContext(restoredContainer)
        var restoredBytes: [String: Data] = [:]
        _ = try BackupService.restore(decoded, into: restoredContext, photoWriter: { data in
            let path = "restored-ingredient.jpg"
            restoredBytes[path] = data
            return path
        }, photoRemover: { restoredBytes.removeValue(forKey: $0) })

        let restored = try #require(restoredContext.fetch(FetchDescriptor<Treatment>()).first)
        #expect(restored.aiIngredientSummary == treatment.aiIngredientSummary)
        #expect(restored.ingredientPhotoPath == "restored-ingredient.jpg")
        #expect(restoredBytes[restored.ingredientPhotoPath] == validImageData)
    }

    @Test func invalidLatePhotoLeavesNoFilesOrPendingDatabaseChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var envelope = fixtureEnvelope(now: .now)
        envelope.photos.append(.init(
            regionRaw: PhotoRegion.templeLeft.rawValue,
            createdAt: Date.now.addingTimeInterval(1),
            imageBase64: Data("late-corruption".utf8).base64EncodedString()
        ))
        var files: [String: Data] = [:]

        #expect(throws: BackupService.BackupError.invalidPhotoData) {
            _ = try BackupService.restore(envelope, into: context, photoWriter: { data in
                let path = "staged-\(files.count).jpg"
                files[path] = data
                return path
            }, photoRemover: { files.removeValue(forKey: $0) })
        }

        #expect(files.isEmpty)
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<Profile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Treatment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).isEmpty)
    }

    @Test func secondPhotoCommitFailureRemovesRowsAndEveryFile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var envelope = BackupService.Envelope()
        envelope.photos = [
            .init(regionRaw: PhotoRegion.vertex.rawValue, createdAt: Date(timeIntervalSince1970: 1),
                  imageBase64: validImageData.base64EncodedString()),
            .init(regionRaw: PhotoRegion.templeLeft.rawValue, createdAt: Date(timeIntervalSince1970: 2),
                  imageBase64: validImageData.base64EncodedString())
        ]
        var staged = Set<String>()
        var finalized = Set<String>()
        var writes = 0
        var commits = 0

        #expect(throws: (any Error).self) {
            _ = try BackupService.restore(envelope, into: context, photoWriter: { _ in
                writes += 1
                let path = "photo-\(writes).jpg"
                staged.insert(path)
                return path
            }, photoRemover: { staged.remove($0) }, photoCommitter: { path in
                commits += 1
                if commits == 2 { throw CocoaError(.fileWriteUnknown) }
                staged.remove(path)
                finalized.insert(path)
            }, finalizedPhotoRemover: { finalized.remove($0) })
        }

        #expect(staged.isEmpty)
        #expect(finalized.isEmpty)
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).isEmpty)
    }

    @Test func databaseSaveFailureRemovesFinalizedPhotosAndRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var envelope = BackupService.Envelope()
        envelope.photos = [.init(regionRaw: PhotoRegion.vertex.rawValue,
                                 imageBase64: validImageData.base64EncodedString())]
        var staged = Set<String>()
        var finalized = Set<String>()

        #expect(throws: (any Error).self) {
            _ = try BackupService.restore(envelope, into: context, photoWriter: { _ in
                staged.insert("photo.jpg")
                return "photo.jpg"
            }, photoRemover: { staged.remove($0) }, photoCommitter: { path in
                staged.remove(path)
                finalized.insert(path)
            }, finalizedPhotoRemover: { finalized.remove($0) }, databaseSaver: {
                throw CocoaError(.fileWriteUnknown)
            })
        }

        #expect(staged.isEmpty)
        #expect(finalized.isEmpty)
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).isEmpty)
    }
}
