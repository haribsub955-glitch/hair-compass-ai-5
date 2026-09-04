//
//  PhotoCadence.swift
//  Hair Compass AI 5
//
//  When the next comparable photo is due: twenty-eight days after the last one, never earlier.
//  Photos taken too often are distorted by light, styling and angle, so the app gives permission
//  to wait. No photo at all means a baseline is pending — an invitation, not an overdue task.
//

import Foundation

enum PhotoCadence {
    static let intervalDays = 28

    enum Status: Equatable {
        case noBaseline
        case due(daysOverdue: Int)
        case upcoming(daysUntil: Int)
    }

    static func status(photos: [PhotoRecord], now: Date, calendar: Calendar) -> Status {
        guard let last = photos.map(\.createdAt).max() else { return .noBaseline }
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.startOfDay(for: last)
        guard let dueDay = calendar.date(byAdding: .day, value: intervalDays, to: lastDay) else { return .noBaseline }
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        return days <= 0 ? .due(daysOverdue: -days) : .upcoming(daysUntil: days)
    }

    static func hasPhoto(withinDays days: Int, photos: [PhotoRecord], now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let floor = calendar.date(byAdding: .day, value: -days, to: today) else { return false }
        return photos.contains { $0.createdAt >= floor && $0.createdAt <= now }
    }
}

/// The single condition-matching rule used by Photos, exports and the Evidence lens. Keeping it
/// here prevents one surface from accepting a pair that another warns about. Empty legacy metadata
/// remains unknown rather than a mismatch; known values must agree.
enum PhotoComparability {
    /// A visible caution for comparison surfaces. Missing legacy metadata is different from a
    /// mismatch, but it still means the pair cannot support a confident visual comparison.
    static func cautionCaption(_ a: PhotoRecord, _ b: PhotoRecord) -> String? {
        if let mismatch = mismatchCaption(a, b) { return mismatch }
        guard !hasCompleteSetup(a) || !hasCompleteSetup(b) else { return nil }
        return "Setup details are incomplete — lighting, distance and parting must be recorded for a reliable comparison."
    }

    static func mismatchCaption(_ a: PhotoRecord, _ b: PhotoRecord) -> String? {
        var notes: [String] = []
        if a.isWet != b.isWet {
            notes.append("wet vs dry — wet hair looks thinner")
        }
        if knownValuesDiffer(a.lighting, b.lighting) {
            notes.append("different lighting")
        }
        if knownValuesDiffer(a.distance, b.distance) {
            notes.append("different distance")
        }
        if knownValuesDiffer(a.parting, b.parting) {
            notes.append("different parting")
        }
        guard !notes.isEmpty else { return nil }
        return "These shots differ: " + notes.joined(separator: ", ")
    }

    static func isEvidenceGradePair(_ a: PhotoRecord, _ b: PhotoRecord) -> Bool {
        hasCompleteSetup(a) && hasCompleteSetup(b) && mismatchCaption(a, b) == nil
    }

    private static func hasCompleteSetup(_ photo: PhotoRecord) -> Bool {
        !normalized(photo.lighting).isEmpty
            && !normalized(photo.distance).isEmpty
            && !normalized(photo.parting).isEmpty
    }

    private static func knownValuesDiffer(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        return !left.isEmpty && !right.isEmpty && left.caseInsensitiveCompare(right) != .orderedSame
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
