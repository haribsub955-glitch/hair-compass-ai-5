import Foundation
import SwiftData

/// Shared dated context for Trends, its chart, and the comparison builder.
/// A highlight records what the user logged; it does not assert a cause or an outcome.
struct TrendHighlight: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case start = "Plan added", stop = "Plan stopped", procedure = "Procedure"
        case photo = "Photo", regrowth = "Baby hairs", sideEffect = "Side effect"
        case trigger = "Life event", note = "Note"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .start: return "plus.circle"
            case .stop: return "pause.circle"
            case .procedure: return "cross.case"
            case .photo: return "camera"
            case .regrowth: return "leaf"
            case .sideEffect: return "waveform.path.ecg"
            case .trigger: return "calendar"
            case .note: return "text.bubble"
            }
        }
    }
    let id: String
    let kind: Kind
    let date: Date
    let title: String
    let detail: String
    var photo: PhotoRecord? = nil
    var trigger: TriggerEvent? = nil
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

enum TrendContext {
    /// PersistentIdentifier's human-readable description can omit its unique storage key.
    /// Its Codable representation preserves identity; sorted keys keep picker tags deterministic.
    static func recordKey(_ record: some PersistentModel) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let encoded = try? encoder.encode(record.persistentModelID) { return encoded.base64EncodedString() }
        // Only a transient fallback if a future store provides a non-encodable identifier.
        return String(describing: ObjectIdentifier(record))
    }

    static func highlights(
        treatments: [Treatment] = [], procedures: [ProcedureAppointment] = [],
        photos: [PhotoRecord] = [], progress: [ProgressCheckIn] = [],
        sideEffects: [SideEffectLog] = [], triggers: [TriggerEvent] = [],
        entries: [DailyEntry] = [], start: Date, end: Date
    ) -> [TrendHighlight] {
        var result: [TrendHighlight] = []
        func append(_ item: TrendHighlight) {
            if item.date >= start && item.date <= end { result.append(item) }
        }
        for treatment in treatments {
            let id = recordKey(treatment)
            let name = treatment.name.isEmpty ? treatment.treatmentClass.title : treatment.name
            append(.init(id: "start.\(id)", kind: .start, date: treatment.startDate,
                         title: "Started \(name)", detail: treatment.dose))
            // A stop inside this window remains visible even if its start was years earlier.
            if let date = treatment.endDate {
                append(.init(id: "stop.\(id)", kind: .stop, date: date,
                             title: "Stopped \(name)", detail: "Recorded plan change"))
            }
        }
        for procedure in procedures where procedure.isCompleted {
            append(.init(id: "procedure.\(recordKey(procedure))", kind: .procedure,
                         date: procedure.completedAt ?? procedure.date,
                         title: procedure.type.title, detail: procedure.note.isEmpty ? "Completed procedure" : procedure.note))
        }
        for photo in photos {
            append(.init(id: "photo.\(recordKey(photo))", kind: photo.babyHairsNoticed ? .regrowth : .photo,
                         date: photo.createdAt, title: photo.babyHairsNoticed ? "Baby hairs noticed" : "Progress photo",
                         detail: "\(photo.region.title) · \(photo.babyHairsNoticed ? "Your observation" : "Photo recorded")", photo: photo))
        }
        for checkIn in progress where checkIn.regrowth != .none {
            append(.init(id: "regrowth.\(recordKey(checkIn))", kind: .regrowth, date: checkIn.date,
                         title: "Baby hairs noticed", detail: "Monthly check-in · \(checkIn.regrowth.title) · Self-reported"))
        }
        for effect in sideEffects {
            let name = effect.treatment.map { $0.name.isEmpty ? $0.treatmentClass.title : $0.name }
            append(.init(id: "effect.\(recordKey(effect))", kind: .sideEffect, date: effect.date,
                         title: effect.type.title,
                         detail: "Severity \(effect.severity)/3\(name.map { " · Logged with \($0)" } ?? "")\(effect.note.isEmpty ? "" : " · \(effect.note)")"))
        }
        for trigger in triggers {
            append(.init(id: "trigger.\(recordKey(trigger))", kind: .trigger,
                         date: trigger.date, title: trigger.type.title, detail: trigger.note, trigger: trigger))
        }
        for entry in entries where !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append(.init(id: "note.\(recordKey(entry))", kind: .note, date: entry.date,
                         title: "Daily note", detail: entry.note))
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    /// Highest reported severity per day. An unlogged day is unknown, never "no side effects".
    static func sideEffectSeries(
        _ logs: [SideEffectLog], type: SideEffectType? = nil,
        start: Date, end: Date, calendar: Calendar = .current
    ) -> [(day: Date, value: Double)] {
        let recorded = logs.filter { $0.date >= start && $0.date <= end && (type == nil || $0.type == type) }
        return Dictionary(grouping: recorded) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, value: Double($0.value.map(\.severity).max() ?? 1)) }
            .sorted { $0.day < $1.day }
    }

    /// Record-based plan signal: only days with a dose or an explicit missed-dose record.
    static func doseSeries(
        treatment: Treatment, doses: [TreatmentDose], missed: [MissedDoseRecord],
        start: Date, end: Date, calendar: Calendar = .current
    ) -> [(day: Date, value: Double)] {
        let first = max(start, treatment.startDate)
        let last = min(end, treatment.endDate ?? end)
        var counts: [Date: Double] = [:]
        for record in missed where record.treatment?.persistentModelID == treatment.persistentModelID && record.date >= first && record.date <= last {
            counts[calendar.startOfDay(for: record.date)] = 0
        }
        let recorded = doses.filter { $0.treatment?.persistentModelID == treatment.persistentModelID && $0.loggedAt >= first && $0.loggedAt <= last }
        for (day, records) in Dictionary(grouping: recorded, by: { calendar.startOfDay(for: $0.loggedAt) }) {
            let namedSlots = Set(records.filter { !$0.slot.isEmpty }.map(\.slot)).count
            counts[day] = Double(namedSlots + records.filter { $0.slot.isEmpty }.count)
        }
        return counts.map { (day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
    }

    struct EventComparison {
        let before: [Double]
        let after: [Double]
        let beforeStart: Date
        let afterStart: Date
        let afterEnd: Date
        var hasEnoughDays: Bool { before.count >= 5 && after.count >= 5 }
    }

    /// Equal calendar windows around an event. The event day belongs only to "after".
    /// Optional delay affects only the after window; future observations never enter either.
    static func compare(
        points: [(day: Date, value: Double)], event: Date, days: Int,
        delay: Int = 0, now: Date = .now, calendar: Calendar = .current
    ) -> EventComparison {
        let anchor = calendar.startOfDay(for: event)
        let beforeStart = calendar.date(byAdding: .day, value: -days, to: anchor) ?? anchor
        let afterStart = calendar.date(byAdding: .day, value: delay, to: anchor) ?? anchor
        let afterEnd = calendar.date(byAdding: .day, value: days, to: afterStart) ?? afterStart
        let daily = ChartMath.dailyAverages(points.filter { $0.day <= now }, calendar: calendar)
        return .init(before: daily.filter { $0.day >= beforeStart && $0.day < anchor }.map(\.value),
                     after: daily.filter { $0.day >= afterStart && $0.day < afterEnd }.map(\.value),
                     beforeStart: beforeStart, afterStart: afterStart, afterEnd: afterEnd)
    }

    /// Move context forward so a point from N days earlier aligns with today's outcome.
    static func aligned(
        _ points: [(day: Date, value: Double)], lagDays: Int,
        start: Date, end: Date, calendar: Calendar = .current
    ) -> [(day: Date, value: Double)] {
        ChartMath.dailyAverages(points, calendar: calendar).compactMap { point in
            guard let day = calendar.date(byAdding: .day, value: lagDays, to: point.day),
                  day >= start, day <= end else { return nil }
            return (day: day, value: point.value)
        }
    }
}
