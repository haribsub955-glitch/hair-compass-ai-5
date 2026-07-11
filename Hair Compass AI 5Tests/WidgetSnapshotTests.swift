//
//  WidgetSnapshotTests.swift
//  Hair Compass AI 5Tests
//
//  Widget snapshot v2 — the Compass Rings score, shielded streak, and today's remaining plan
//  steps that WidgetSnapshotBuilder.build hands to the widget target. Models are built directly
//  in-memory (no ModelContainer needed — the builder only reads plain array/relationship
//  properties, never fetches), the same way the rest of Hair_Compass_AI_5Tests.swift does.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct WidgetSnapshotTests {

    // MARK: - Log + Lens rings close, score matches CompassScore

    @Test @MainActor func loggedTodayWithPhotoThisWeekClosesLogAndLensRings() {
        let now = Date.now
        let entry = DailyEntry(date: now, shed: .elevated, flaking: 1, erythema: 1, itch: 1)
        let photo = PhotoRecord(region: .frontal, createdAt: now)

        let snap = WidgetSnapshotBuilder.build(
            entries: [entry], treatments: [], doses: [], photos: [photo], now: now
        )

        #expect(snap.hasLoggedToday == true)
        #expect(snap.ringLog == 1)
        #expect(snap.ringLens == 1)
        // No active treatments → Care ring excluded from the score entirely.
        #expect(snap.ringCare == nil)

        let expected = CompassScore(hasLoggedToday: true, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: true)
        #expect(snap.score == expected.score)
        #expect(snap.shedLabel == ShedLevel.elevated.title)
        #expect(snap.scalpLabel == "Scalp \(entry.scalpBand.title.lowercased())")
    }

    // MARK: - No treatments → no Care ring, nothing due

    @Test @MainActor func noTreatmentsLeavesCareRingNilAndDueTitlesEmpty() {
        let now = Date.now
        let snap = WidgetSnapshotBuilder.build(
            entries: [], treatments: [], doses: [], photos: [], now: now
        )

        #expect(snap.ringCare == nil)
        #expect(snap.dueTitles.isEmpty)
        #expect(snap.hasLoggedToday == false)
        #expect(snap.shedLabel.isEmpty)
        #expect(snap.scalpLabel.isEmpty)
    }

    // MARK: - Due titles: one of two daily slots still open

    @Test @MainActor func dueTitlesListsTheUnloggedSlotOfATwoSlotTreatment() {
        let now = Date.now
        let minoxidil = Treatment(
            name: "Minoxidil", treatmentClass: .minoxidil,
            scheduleTimes: "08:00,21:00", startDate: now, isActive: true
        )
        let morningDose = TreatmentDose(treatment: minoxidil, loggedAt: now, slot: "08:00")

        let snap = WidgetSnapshotBuilder.build(
            entries: [], treatments: [minoxidil], doses: [morningDose], photos: [], now: now
        )

        #expect(snap.dueTitles == ["Minoxidil · 21:00"])
        #expect(snap.ringCare == 0.5)   // 1 of 2 slots logged
    }

    // MARK: - Shielded streak passthrough

    @Test @MainActor func streakAndShieldsPassThroughFromShieldedStreak() {
        let cal = Calendar.current
        let now = Date.now
        // Seven straight logged days ending today earns exactly one shield
        // (see HairAnalytics.shieldedStreak / StreakShieldTests.swift).
        let entries = (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: now).map { DailyEntry(date: $0) }
        }

        let snap = WidgetSnapshotBuilder.build(
            entries: entries, treatments: [], doses: [], photos: [], now: now, calendar: cal
        )

        let expected = HairAnalytics.shieldedStreak(entryDates: entries.map(\.date), now: now, calendar: cal)
        #expect(snap.streakDays == expected.streak)
        #expect(snap.shieldsHeld == expected.shieldsHeld)
        #expect(snap.streakDays == 7)
        #expect(snap.shieldsHeld == 1)
    }
}
