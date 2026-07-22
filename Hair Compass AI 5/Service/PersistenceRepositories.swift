import Foundation
import SwiftData
import UIKit

/// The write boundary for the one-log-per-calendar-day invariant. Views keep using `@Query`
/// for reads; this type only owns the fetch-or-insert decision that must be consistent.
@MainActor
struct DailyEntryRepository {
    let context: ModelContext
    var calendar: Calendar = .current
    var now: () -> Date = { .now }

    @discardableResult
    func upsert(
        day: Date,
        updateExisting: Bool = true,
        update: (DailyEntry) -> Void = { _ in }
    ) throws -> DailyEntry {
        let bounds = HairAnalytics.dayBounds(for: day, calendar: calendar)
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        var descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date >= lower && $0.date < upper },
            sortBy: [SortDescriptor(\DailyEntry.date)]
        )
        descriptor.fetchLimit = 1

        let entry: DailyEntry
        let inserted: Bool
        if let existing = try context.fetch(descriptor).first {
            entry = existing
            inserted = false
        } else {
            entry = DailyEntry(date: HairAnalytics.normalizedLogDate(
                for: day, now: now(), calendar: calendar
            ))
            context.insert(entry)
            inserted = true
        }
        if inserted || updateExisting { update(entry) }
        return entry
    }
}

/// The write boundary for a dose's natural key: treatment + calendar day + exact slot.
@MainActor
struct DoseRepository {
    let context: ModelContext
    var calendar: Calendar = .current
    var now: () -> Date = { .now }

    @discardableResult
    func log(treatment: Treatment, day: Date? = nil, slot: String) throws -> TreatmentDose {
        let loggedAt = day ?? now()
        if let existing = try matchingDose(treatment: treatment, day: loggedAt, slot: slot) {
            return existing
        }
        let dose = TreatmentDose(treatment: treatment, loggedAt: loggedAt, slot: slot)
        context.insert(dose)
        return dose
    }

    @discardableResult
    func delete(treatment: Treatment, day: Date? = nil, slot: String) throws -> Bool {
        guard let dose = try matchingDose(treatment: treatment, day: day ?? now(), slot: slot) else {
            return false
        }
        context.delete(dose)
        return true
    }

    private func matchingDose(treatment: Treatment, day: Date, slot: String) throws -> TreatmentDose? {
        let bounds = HairAnalytics.dayBounds(for: day, calendar: calendar)
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        let candidates = try context.fetch(FetchDescriptor<TreatmentDose>(
            predicate: #Predicate {
                $0.loggedAt >= lower && $0.loggedAt < upper && $0.slot == slot
            },
            sortBy: [SortDescriptor(\TreatmentDose.loggedAt)]
        ))
        return candidates.first {
            $0.treatment?.persistentModelID == treatment.persistentModelID
        }
    }
}

@MainActor
struct MissedDoseRepository {
    let context: ModelContext
    var calendar: Calendar = .current

    @discardableResult
    func record(treatment: Treatment, day: Date = .now, slot: String, reason: MissedDoseReason) throws -> MissedDoseRecord {
        let bounds = HairAnalytics.dayBounds(for: day, calendar: calendar)
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        let records = try context.fetch(FetchDescriptor<MissedDoseRecord>(predicate: #Predicate {
            $0.date >= lower && $0.date < upper && $0.slot == slot
        }))
        if let existing = records.first(where: { $0.treatment?.persistentModelID == treatment.persistentModelID }) {
            existing.reason = reason
            return existing
        }
        let record = MissedDoseRecord(treatment: treatment, date: day, slot: slot, reason: reason)
        context.insert(record)
        return record
    }
}

struct PhotoDeletion: Equatable {
    let originalPath: String
    let stagedPath: String?
}

@MainActor
protocol PhotoStoring {
    func save(_ image: UIImage, quality: CGFloat) -> String?
    func deleteCreatedFile(_ path: String)
    func stageDeletion(_ path: String) throws -> PhotoDeletion
    func restoreDeletion(_ deletion: PhotoDeletion)
    func finalizeDeletion(_ deletion: PhotoDeletion)
}

extension PhotoStore: PhotoStoring {}

enum PhotoRepositoryError: Error {
    case fileWriteFailed
}

/// Keeps a progress-photo file and its SwiftData row paired across create/delete failures.
@MainActor
struct PhotoRepository {
    let context: ModelContext
    let store: any PhotoStoring

    init(context: ModelContext, store: any PhotoStoring = PhotoStore.shared) {
        self.context = context
        self.store = store
    }

    @discardableResult
    func create(
        image: UIImage,
        region: PhotoRegion,
        createdAt: Date = .now,
        lighting: String = "",
        distance: String = "",
        parting: String = "",
        isWet: Bool = false,
        note: String = "",
        patchSeriesLabel: String = ""
    ) throws -> PhotoRecord {
        guard let path = store.save(image, quality: 0.82) else {
            throw PhotoRepositoryError.fileWriteFailed
        }
        let record = PhotoRecord(
            region: region, imagePath: path, createdAt: createdAt, lighting: lighting,
            distance: distance, parting: parting, isWet: isWet, note: note,
            patchSeriesLabel: region == .patch ? patchSeriesLabel : ""
        )
        context.insert(record)
        do {
            try context.save()
            return record
        } catch {
            context.delete(record)
            store.deleteCreatedFile(path)
            throw error
        }
    }

    func delete(_ record: PhotoRecord) throws {
        let deletion = try store.stageDeletion(record.imagePath)
        context.delete(record)
        do {
            try context.save()
            store.finalizeDeletion(deletion)
        } catch {
            context.rollback()
            store.restoreDeletion(deletion)
            throw error
        }
    }
}
