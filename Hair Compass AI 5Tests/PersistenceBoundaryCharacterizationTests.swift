import Foundation
import SwiftData
import Testing
import UIKit
@testable import Hair_Compass_AI_5

/// Pins the persistence behavior at the view/service call sites before their writes move behind
/// repositories. These helpers deliberately mirror the existing mutations, including their use
/// of `HairAnalytics` for day identity and exact dose-slot matching.
@MainActor
struct PersistenceBoundaryCharacterizationTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, LabResult.self, PhotoRecord.self, HealthSnapshot.self,
            TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @Test func currentDailySaveUpdatesTheExistingCalendarDay() throws {
        let context = ModelContext(try makeContainer())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Muscat"))
        let morning = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 8
        )))
        let evening = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 20
        )))

        let first = try currentDailySave(day: morning, shed: .heavy, note: "keep me",
                                         context: context, calendar: calendar)
        let second = try currentDailySave(day: evening, shed: .minimal, note: "updated",
                                          context: context, calendar: calendar)
        let rows = try context.fetch(FetchDescriptor<DailyEntry>())

        #expect(rows.count == 1)
        #expect(first.persistentModelID == second.persistentModelID)
        #expect(rows.first?.shed == .minimal)
        #expect(rows.first?.note == "updated")
    }

    @Test func currentDoseLoggingIsUniqueByTreatmentCalendarDayAndExactSlot() throws {
        let context = ModelContext(try makeContainer())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Muscat"))
        let treatment = Treatment(name: "Minoxidil")
        let other = Treatment(name: "Finasteride")
        context.insert(treatment)
        context.insert(other)
        let morning = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 8
        )))
        let evening = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 20
        )))

        _ = currentDoseSave(treatment: treatment, day: morning, slot: "08:00",
                            context: context, calendar: calendar)
        _ = currentDoseSave(treatment: treatment, day: evening, slot: "08:00",
                            context: context, calendar: calendar)
        _ = currentDoseSave(treatment: treatment, day: evening, slot: "21:00",
                            context: context, calendar: calendar)
        _ = currentDoseSave(treatment: other, day: evening, slot: "08:00",
                            context: context, calendar: calendar)

        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 3)
        #expect(treatment.doses.count == 2)
        #expect(other.doses.count == 1)
    }

    @Test func currentPhotoCreateAndDeletePairFileWithRow() throws {
        let context = ModelContext(try makeContainer())
        let files = CharacterizationPhotoFiles()

        let record = try #require(currentPhotoCreate(context: context, files: files))
        #expect(files.paths == [record.imagePath])
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).count == 1)

        currentPhotoDelete(record, context: context, files: files)
        #expect(files.paths.isEmpty)
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).isEmpty)
    }

    private func currentDailySave(
        day: Date,
        shed: ShedLevel,
        note: String,
        context: ModelContext,
        calendar: Calendar
    ) throws -> DailyEntry {
        let bounds = HairAnalytics.dayBounds(for: day, calendar: calendar)
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        var descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date >= lower && $0.date < upper },
            sortBy: [SortDescriptor(\DailyEntry.date)]
        )
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        let entry = existing
            ?? DailyEntry(date: HairAnalytics.normalizedLogDate(for: day, now: day, calendar: calendar))
        if existing == nil { context.insert(entry) }
        entry.shed = shed
        entry.note = note
        return entry
    }

    private func currentDoseSave(
        treatment: Treatment,
        day: Date,
        slot: String,
        context: ModelContext,
        calendar: Calendar
    ) -> TreatmentDose {
        let doses = (try? context.fetch(FetchDescriptor<TreatmentDose>())) ?? []
        if let existing = doses.first(where: {
            $0.treatment?.persistentModelID == treatment.persistentModelID
                && $0.slot == slot && calendar.isDate($0.loggedAt, inSameDayAs: day)
        }) {
            return existing
        }
        let dose = TreatmentDose(treatment: treatment, loggedAt: day, slot: slot)
        context.insert(dose)
        return dose
    }

    private func currentPhotoCreate(
        context: ModelContext,
        files: CharacterizationPhotoFiles
    ) -> PhotoRecord? {
        guard let path = files.save() else { return nil }
        let record = PhotoRecord(region: .vertex, imagePath: path)
        context.insert(record)
        return record
    }

    private func currentPhotoDelete(
        _ record: PhotoRecord,
        context: ModelContext,
        files: CharacterizationPhotoFiles
    ) {
        files.delete(record.imagePath)
        context.delete(record)
    }
}

@MainActor
struct PersistenceRepositoryInvariantTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, LabResult.self, PhotoRecord.self, HealthSnapshot.self,
            TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private var muscatCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return calendar
    }

    @Test func dailyRepositoryUpsertUpdatesWithoutDuplicateOrReplacement() throws {
        let context = ModelContext(try makeContainer())
        let calendar = muscatCalendar
        let morning = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 7
        ))!
        let evening = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 22
        ))!
        let repository = DailyEntryRepository(context: context, calendar: calendar, now: { morning })

        let original = try repository.upsert(day: morning) {
            $0.note = "rich existing note"
            $0.washedHair = true
            $0.shed = .heavy
        }
        let updated = try repository.upsert(day: evening) { $0.shed = .minimal }
        let rows = try context.fetch(FetchDescriptor<DailyEntry>())

        #expect(rows.count == 1)
        #expect(original.persistentModelID == updated.persistentModelID)
        #expect(updated.note == "rich existing note")
        #expect(updated.washedHair)
        #expect(updated.shed == .minimal)
    }

    @Test func dailyRepositoryCanSeedOnlyWhenDayIsMissing() throws {
        let context = ModelContext(try makeContainer())
        let day = Date(timeIntervalSince1970: 1_753_180_000)
        let repository = DailyEntryRepository(context: context, calendar: muscatCalendar, now: { day })
        let existing = try repository.upsert(day: day) { $0.note = "do not replace" }

        let result = try repository.upsert(day: day, updateExisting: false) {
            $0.note = "seed"
        }

        #expect(result.persistentModelID == existing.persistentModelID)
        #expect(result.note == "do not replace")
        #expect(try context.fetch(FetchDescriptor<DailyEntry>()).count == 1)
    }

    @Test func doseRepositoryPreventsDuplicateNaturalKeysAndKeepsRelationships() throws {
        let context = ModelContext(try makeContainer())
        let calendar = muscatCalendar
        let treatment = Treatment(name: "Minoxidil")
        let other = Treatment(name: "Finasteride")
        context.insert(treatment)
        context.insert(other)
        let morning = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 8
        ))!
        let evening = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 21
        ))!
        let repository = DoseRepository(context: context, calendar: calendar, now: { morning })

        let first = try repository.log(treatment: treatment, day: morning, slot: "08:00")
        let duplicate = try repository.log(treatment: treatment, day: evening, slot: "08:00")
        _ = try repository.log(treatment: treatment, day: evening, slot: "21:00")
        _ = try repository.log(treatment: other, day: evening, slot: "08:00")

        #expect(first.persistentModelID == duplicate.persistentModelID)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).count == 3)
        #expect(treatment.doses.count == 2)
        #expect(other.doses.count == 1)
    }

    @Test func photoRepositoryCreatesAndDeletesFileAndRowTogether() throws {
        let context = ModelContext(try makeContainer())
        let store = RepositoryPhotoStore()
        let repository = PhotoRepository(context: context, store: store)

        let record = try repository.create(image: UIImage(), region: .vertex, note: "baseline")
        #expect(store.livePaths == [record.imagePath])
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).count == 1)

        try repository.delete(record)
        #expect(store.livePaths.isEmpty)
        #expect(store.stagedPaths.isEmpty)
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).isEmpty)
    }

    @Test func photoRepositoryDoesNotInsertRowWhenFileWriteFails() throws {
        let context = ModelContext(try makeContainer())
        let store = RepositoryPhotoStore()
        store.failSave = true

        #expect(throws: PhotoRepositoryError.self) {
            try PhotoRepository(context: context, store: store).create(
                image: UIImage(), region: .frontal
            )
        }
        #expect(store.livePaths.isEmpty)
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).isEmpty)
    }

    @Test func photoRepositoryKeepsRowWhenDeletionCannotBeStaged() throws {
        let context = ModelContext(try makeContainer())
        let store = RepositoryPhotoStore()
        let repository = PhotoRepository(context: context, store: store)
        let record = try repository.create(image: UIImage(), region: .frontal)
        store.failStageDeletion = true

        #expect(throws: RepositoryPhotoStore.Failure.self) {
            try repository.delete(record)
        }
        #expect(store.livePaths == [record.imagePath])
        #expect(try context.fetch(FetchDescriptor<PhotoRecord>()).count == 1)
    }
}

@MainActor
private final class CharacterizationPhotoFiles {
    var paths: Set<String> = []

    func save() -> String? {
        let path = "current.jpg"
        paths.insert(path)
        return path
    }

    func delete(_ path: String) {
        paths.remove(path)
    }
}

@MainActor
private final class RepositoryPhotoStore: PhotoStoring {
    enum Failure: Error { case stagedDeletion }

    var livePaths: Set<String> = []
    var stagedPaths: Set<String> = []
    var failSave = false
    var failStageDeletion = false
    private var nextID = 0

    func save(_ image: UIImage, quality: CGFloat) -> String? {
        guard !failSave else { return nil }
        nextID += 1
        let path = "photo-\(nextID).jpg"
        livePaths.insert(path)
        return path
    }

    func deleteCreatedFile(_ path: String) {
        livePaths.remove(path)
    }

    func stageDeletion(_ path: String) throws -> PhotoDeletion {
        guard !failStageDeletion else { throw Failure.stagedDeletion }
        let staged = "staged-\(path)"
        livePaths.remove(path)
        stagedPaths.insert(staged)
        return PhotoDeletion(originalPath: path, stagedPath: staged)
    }

    func restoreDeletion(_ deletion: PhotoDeletion) {
        if let staged = deletion.stagedPath { stagedPaths.remove(staged) }
        livePaths.insert(deletion.originalPath)
    }

    func finalizeDeletion(_ deletion: PhotoDeletion) {
        if let staged = deletion.stagedPath { stagedPaths.remove(staged) }
    }
}
