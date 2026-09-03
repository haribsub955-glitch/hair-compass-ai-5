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
