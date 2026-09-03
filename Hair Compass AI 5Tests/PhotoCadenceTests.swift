//
//  PhotoCadenceTests.swift
//  Hair Compass AI 5Tests
//
//  The comparable-photo cadence is monthly (28 days) and never earlier — the spec retires the
//  weekly photo as a score input. No photo yet means a baseline is pending, not overdue.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct PhotoCadenceTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return c
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9))! }
    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now)! }

    @Test func noPhotoMeansBaselinePending() {
        #expect(PhotoCadence.status(photos: [], now: now, calendar: calendar) == .noBaseline)
    }

    @Test func nextPhotoIsTwentyEightDaysAfterTheLast() {
        let photos = [PhotoRecord(createdAt: daysAgo(20)), PhotoRecord(createdAt: daysAgo(40))]
        #expect(PhotoCadence.status(photos: photos, now: now, calendar: calendar) == .upcoming(daysUntil: 8))
    }

    @Test func dueOnTheDayAndAfter() {
        #expect(PhotoCadence.status(photos: [PhotoRecord(createdAt: daysAgo(28))], now: now, calendar: calendar) == .due(daysOverdue: 0))
        #expect(PhotoCadence.status(photos: [PhotoRecord(createdAt: daysAgo(35))], now: now, calendar: calendar) == .due(daysOverdue: 7))
    }

    @Test func hasPhotoWithinDays() {
        let photos = [PhotoRecord(createdAt: daysAgo(10))]
        #expect(PhotoCadence.hasPhoto(withinDays: 14, photos: photos, now: now, calendar: calendar))
        #expect(!PhotoCadence.hasPhoto(withinDays: 7, photos: photos, now: now, calendar: calendar))
    }
}
