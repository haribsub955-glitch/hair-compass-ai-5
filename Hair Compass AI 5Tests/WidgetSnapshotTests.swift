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

    /// Mirrors the widget-extension declaration. Cross-decoding in both directions makes a field
    /// rename/type change fail in the app test target even though the two targets cannot import
    /// one another.
    private struct WidgetTargetSnapshot: Codable, Equatable {
        struct DueItem: Codable, Equatable {
            let title: String
            let treatmentName: String
            let slot: String
        }

        let generatedAt: Date
        let hasLoggedToday: Bool
        let score: Int
        let ringLog: Double
        let ringCare: Double?
        let ringLens: Double
        let shedLabel: String
        let scalpLabel: String
        let streakDays: Int
        let shieldsHeld: Int
        let dueTitles: [String]
        let dueItems: [DueItem]
        let pendingKeys: [String]
    }

    private struct WidgetTargetRitualAttributes: Codable, Equatable {
        struct ContentState: Codable, Equatable {
            var stepName: String
            var stepIndex: Int
            var totalSteps: Int
            var progress: Double
            var endDate: Date?
        }
        var ritualName: String
        var ritualKind: String
        var startDate: Date
    }

    // MARK: - Log + Lens rings close, score matches CompassScore

    @Test @MainActor func loggedTodayWithPhotoThisWeekClosesLogAndLensRings() {
        let now = Date.now
        let entry = DailyEntry(date: now, shed: .elevated, flaking: 1, erythema: 1, itch: 1)
        let photo = PhotoRecord(region: .frontal, createdAt: now)

        let snap = WidgetSnapshotBuilder.build(
            entries: [entry], treatments: [], doses: [], missed: [], photos: [photo], now: now
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
            entries: [], treatments: [], doses: [], missed: [], photos: [], now: now
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
            entries: [], treatments: [minoxidil], doses: [morningDose], missed: [], photos: [], now: now
        )

        #expect(snap.dueTitles == ["Minoxidil · 21:00"])
        #expect(snap.dueItems == [WidgetSnapshot.DueItem(
            title: "Minoxidil · 21:00", treatmentName: "Minoxidil", slot: "21:00"
        )])
        #expect(snap.ringCare == 0.5)   // 1 of 2 slots logged
    }

    // MARK: - Due list reads PlanAdherence.today (same fixed calendar as PlanAdherenceTests:
    // Asia/Muscat, Monday-first, Wednesday 2026-09-09 09:30).

    private var fixedCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        c.firstWeekday = 2 // Monday
        return c
    }

    /// Wednesday 2026-09-09, 09:30 local.
    private var fixedNow: Date {
        fixedCalendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
    }

    private func fixedDay(_ offset: Int, hour: Int = 12) -> Date {
        let base = fixedCalendar.date(byAdding: .day, value: offset, to: fixedCalendar.startOfDay(for: fixedNow))!
        return fixedCalendar.date(byAdding: .hour, value: hour, to: base)!
    }

    @Test @MainActor func treatmentStartingTomorrowYieldsNoDueTitlesAndNoCareRing() {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: fixedDay(1), isActive: true)
        let snap = WidgetSnapshotBuilder.build(
            entries: [], treatments: [t], doses: [], missed: [], photos: [],
            now: fixedNow, calendar: fixedCalendar
        )
        #expect(snap.dueTitles.isEmpty)
        #expect(snap.ringCare == nil)
    }

    @Test @MainActor func weekdayShampooWithNoClockTimeIsNotDueOnAnOffDay() {
        let shampoo = Treatment(name: "Ketoconazole shampoo", treatmentClass: .shampoo, dose: "",
                                scheduleTimes: "", startDate: fixedDay(-30), isActive: true)
        shampoo.scheduledWeekdays = [2, 5] // Monday, Thursday — today is Wednesday.
        let snap = WidgetSnapshotBuilder.build(
            entries: [], treatments: [shampoo], doses: [], missed: [], photos: [],
            now: fixedNow, calendar: fixedCalendar
        )
        #expect(snap.dueTitles.isEmpty)
    }

    @Test @MainActor func minoxidilWithMorningLoggedLeavesEveningDue() {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: fixedDay(-30), isActive: true)
        let morningDose = TreatmentDose(treatment: t, loggedAt: fixedDay(0, hour: 8), slot: "08:00")
        let snap = WidgetSnapshotBuilder.build(
            entries: [], treatments: [t], doses: [morningDose], missed: [], photos: [],
            now: fixedNow, calendar: fixedCalendar
        )
        #expect(snap.dueTitles == ["Minoxidil 5% · 21:00"])
        #expect(snap.ringCare == 0.5) // doneCount 1, totalCount 2
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
            entries: entries, treatments: [], doses: [], missed: [], photos: [], now: now, calendar: cal
        )

        let expected = HairAnalytics.shieldedStreak(entryDates: entries.map(\.date), now: now, calendar: cal)
        #expect(snap.streakDays == expected.streak)
        #expect(snap.shieldsHeld == expected.shieldsHeld)
        #expect(snap.streakDays == 7)
        #expect(snap.shieldsHeld == 1)
    }

    // MARK: - Round-trip + pinned wire keys (the widget copy must be updated in lockstep —
    // this test can't see the widget target, see the KEEP IN SYNC header on WidgetSnapshot).

    @Test func widgetSnapshotRoundTripsAndKeysAreStable() throws {
        let snap = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            hasLoggedToday: true, score: 71, ringLog: 1, ringCare: 0.5, ringLens: 0,
            shedLabel: "Elevated", scalpLabel: "Scalp mild", streakDays: 4, shieldsHeld: 1,
            dueTitles: ["Minoxidil · 21:00"])
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(back == snap)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(obj.keys) == ["generatedAt","hasLoggedToday","score","ringLog","ringCare",
            "ringLens","shedLabel","scalpLabel","streakDays","shieldsHeld","dueTitles",
            "dueItems","pendingKeys"])
    }

    @Test func appAndWidgetSnapshotShapesCrossDecode() throws {
        let app = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000), hasLoggedToday: true,
            score: 71, ringLog: 1, ringCare: 0.5, ringLens: 0, shedLabel: "Elevated",
            scalpLabel: "Scalp mild", streakDays: 4, shieldsHeld: 1,
            dueTitles: ["Minoxidil · 21:00"]
        )
        let widget = try JSONDecoder().decode(WidgetTargetSnapshot.self, from: JSONEncoder().encode(app))
        let appAgain = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(widget))
        #expect(appAgain == app)
    }

    @Test func appAndWidgetRitualActivityShapesCrossDecode() throws {
        let app = RitualActivityAttributes(
            ritualName: "Breathe", ritualKind: "massage",
            startDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let widget = try JSONDecoder().decode(
            WidgetTargetRitualAttributes.self, from: JSONEncoder().encode(app)
        )
        #expect(widget.ritualName == app.ritualName)
        #expect(widget.ritualKind == app.ritualKind)
        #expect(widget.startDate == app.startDate)

        let state = RitualActivityAttributes.ContentState(
            stepName: "Breathe", stepIndex: 1, totalSteps: 1, progress: 0.5,
            endDate: Date(timeIntervalSince1970: 1_700_000_030)
        )
        let widgetState = try JSONDecoder().decode(
            WidgetTargetRitualAttributes.ContentState.self, from: JSONEncoder().encode(state)
        )
        let appState = try JSONDecoder().decode(
            RitualActivityAttributes.ContentState.self, from: JSONEncoder().encode(widgetState)
        )
        #expect(appState == state)
    }
}
