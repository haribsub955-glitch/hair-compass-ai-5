# Sub-project G1: Plan Adherence Engine + Today's Plan Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Today a one-tap plan: every scheduled treatment occurrence is a row with one obvious completion target, safe Undo, Skip and Pause behind a long press, a seven-day continuity strip, and a calm closure line when the day's plan is complete — all driven by one pure adherence engine that Plan, export and the grounding card reuse later.

**Architecture:** `PlanAdherence` (Model) turns `Treatment` + `TreatmentDose` + `MissedDoseRecord` into occurrences with one state each and folds them into today's plan, per-treatment consistency and week marks; nothing in it reads the clock or a `ModelContext`. `TodayPlanSection` (Feature) renders the fold and hands every write back to `TodayView`, which owns the repositories, the skip-reason and pause dialogs, and the treatment detail sheet. The routine rows leave the signal ledger (`TodayTileGrid`) because the plan section now owns them.

**Tech Stack:** SwiftUI, SwiftData (read-only queries in views; writes through `DoseRepository` / `MissedDoseRepository`), Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-03-daily-grounding-adherence-design.md` — §3 (completed-day state), §6.1 (occurrence states, denominator rules, no catch-up dosing), §6.2 (Today action list, seven-day strip), §6.4 (recovery: no broken-streak modal, no red, easy correction), §7 (tokens, motion, accessibility), §14 (acceptance).

## Global Constraints

- Framing rule: record-keeping and education, never diagnosis; no directive copy; no exclamation marks. Adherence measures completed planned actions, never hair outcomes; copy never says "failed", "poor", "non-compliant"; the app never suggests doubling or catching up a missed dose.
- No palette/typeface/dark-mode change, no new dependencies, `Clinical.*` tokens only. Completion is `Clinical.sage`; the one filled copper button on Today stays the log button; missed states are neutral (`Clinical.tertiary`), never `Clinical.critical`.
- No SwiftData schema change: no new `@Model`, no new stored attribute. Every write goes through `DoseRepository` / `MissedDoseRepository` (`Service/PersistenceRepositories.swift`).
- Occurrence rules (spec §6.1): future, paused (`Treatment.isActive == false`), clinician-directed pauses (`MissedDoseReason.clinicianDirectedPause`) and not-scheduled days are excluded from the denominator; an as-needed item (no clock slots and not a care product) never gets a percentage; a skipped occurrence (any other `MissedDoseReason`) stays in the denominator; today's still-open occurrences are excluded until the day ends.
- Accessibility: every action target is at least 44 × 44 pt; VoiceOver labels name the treatment and the state; Reduce Motion drops animation but keeps every end state; state is never conveyed by colour alone (a check, a dot, a dash, an outline).
- Unit tests are Swift Testing (`@Test`, `#expect`); UI tests are XCTest with `-parallel-testing-enabled NO`.
- Every command runs from the worktree root; quote every path; version control only as plain single commands (no chaining, no heredocs containing them; commit with `-F <file>`); discard xcodebuild's scheme rewrite before committing: `git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"`.
- Test helper (`DD` given in the dispatch):

```bash
utest() { xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5Tests/$1" 2>&1 | grep -E 'error:|✘|✔|Test run with|TEST (SUCCEEDED|FAILED)|BUILD FAILED' | tail -20; }
```

- Commit messages end with:
```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

---

## File structure

| File | Responsibility |
|---|---|
| Create `Hair Compass AI 5/Model/PlanAdherence.swift` | the engine: `OccurrenceState`, `Occurrence`, `Consistency`, `TodayPlan`, `DayMark`/`DayState`, `expectedSlots`, `occurrences`, `consistency`, `today`, `week`, slot helpers |
| Create `Hair Compass AI 5Tests/PlanAdherenceTests.swift` | engine tests on an in-memory container with a fixed calendar |
| Create `Hair Compass AI 5/Feature/TodayPlanSection.swift` | `TodayPlanCopy`, `TodayPlanSection`, `PlanActionRow`, `ContinuityStrip`, `DayCapsule` |
| Create `Hair Compass AI 5Tests/TodayPlanCopyTests.swift` | the framing rule over the section's copy |
| Modify `Hair Compass AI 5/Service/PersistenceRepositories.swift:89-109` | `MissedDoseRepository.delete(treatment:day:slot:)` |
| Modify `Hair Compass AI 5/Feature/TodayView.swift` | queries, the fold, the section, dialogs, detail sheet; drop the routine plumbing |
| Modify `Hair Compass AI 5/Feature/TodayTiles.swift:480-620, 856-924` | remove routine rows, meds row and `RoutineLedgerRow` from the ledger |
| Modify `Hair Compass AI 5/Model/Seed.swift:145-160` | DEBUG `ensureNoDosesToday(context:calendar:now:)` for `HC_PLANOPEN` |
| Modify `Hair Compass AI 5/App/RootView.swift:287-298` | `HC_PLANOPEN` call site next to `HC_NOTODAY` |
| Modify `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift` | `testPlanRowCompletesAndUndoes` |

---

### Task 1: The adherence engine

**Files:**
- Create: `Hair Compass AI 5/Model/PlanAdherence.swift`
- Test: `Hair Compass AI 5Tests/PlanAdherenceTests.swift`

**Interfaces:**
- Consumes: `Treatment` (`Model/Models.swift:149-250`: `slots`, `isDueToday(now:calendar:)`, `startDate`, `isActive`, `endDate`, `treatmentClass.isCareProduct`), `TreatmentDose` (`:428-438`: `treatment`, `loggedAt`, `slot`), `MissedDoseRecord` (`:466-483`: `treatment`, `date`, `slot`, `reason`), `MissedDoseReason.clinicianDirectedPause`, `HairAnalytics.dayBounds(for:calendar:)` (`Model/Analytics.swift:204-208`).
- Produces (later tasks and G2/G3 rely on these exact names):
  - `enum PlanAdherence.OccurrenceState: String { case upcoming, due, completed, skipped, missed, notExpected }`
  - `struct PlanAdherence.Occurrence: Identifiable { let treatment: Treatment; let day: Date; let slot: String; let state: OccurrenceState; let completedAt: Date?; var id: String; var isOpen: Bool; var isSettled: Bool }`
  - `struct PlanAdherence.Consistency: Equatable { let completed: Int; let expected: Int; var fraction: Double; var percent: Int }`
  - `struct PlanAdherence.TodayPlan { let occurrences: [Occurrence]; var completedCount: Int; var settledCount: Int; var openCount: Int; var isComplete: Bool; var nothingExpected: Bool; var nextOpen: Occurrence? }`
  - `enum PlanAdherence.DayMark { case complete, partial, missed, notExpected, today, upcoming }`; `struct PlanAdherence.DayState: Identifiable, Equatable { let day: Date; let mark: DayMark; let completed: Int; let expected: Int }`
  - `static func hasSchedule(_:) -> Bool`, `static func expectedSlots(_:on:calendar:) -> [String]`, `static func occurrences(treatment:doses:missed:from:through:now:calendar:) -> [Occurrence]`, `static func consistency(occurrences:) -> Consistency?`, `static func consistency(treatment:doses:missed:windowDays:now:calendar:) -> Consistency?`, `static func consistency(treatments:doses:missed:from:through:now:calendar:) -> Consistency?`, `static func today(treatments:doses:missed:now:calendar:) -> TodayPlan`, `static func week(treatments:doses:missed:now:calendar:) -> [DayState]`, `static func slotMinutes(_:) -> Int?`, `static func slotDate(_:on:calendar:) -> Date?`, `static func isReached(slot:now:calendar:) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/PlanAdherenceTests.swift`:

```swift
//
//  PlanAdherenceTests.swift
//  Hair Compass AI 5Tests
//
//  The adherence engine's rules, pinned on an in-memory store with a fixed calendar so no test
//  depends on the clock: which occurrences exist, what state each carries, who counts in the
//  denominator, and how today's plan and the week strip fold from them.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct PlanAdherenceTests {

    // MARK: Fixture

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, MissedDoseRecord.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        c.firstWeekday = 2 // Monday
        return c
    }

    /// Wednesday 2026-09-09, 09:30 local.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))!
    }

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: base)!
    }

    private func minoxidil(in context: ModelContext, startedDaysAgo: Int = 30) -> Treatment {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: day(-startedDaysAgo), isActive: true)
        context.insert(t)
        return t
    }

    private func log(_ t: Treatment, dayOffset: Int, slot: String, in context: ModelContext) {
        let hour = PlanAdherence.slotMinutes(slot).map { $0 / 60 } ?? 12
        context.insert(TreatmentDose(treatment: t, loggedAt: day(dayOffset, hour: hour), slot: slot))
    }

    private func fetchAll(_ context: ModelContext) throws -> (doses: [TreatmentDose], missed: [MissedDoseRecord]) {
        (try context.fetch(FetchDescriptor<TreatmentDose>()), try context.fetch(FetchDescriptor<MissedDoseRecord>()))
    }

    // MARK: Occurrences

    @Test func dailyTreatmentYieldsOneOccurrencePerSlotPerDueDay() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: [], missed: [],
                                            from: day(-2), through: day(0), now: now, calendar: calendar)
        #expect(occ.count == 6)
        #expect(occ.map(\.slot) == ["08:00", "21:00", "08:00", "21:00", "08:00", "21:00"])
    }

    @Test func doseMarksCompletedWithItsTimestamp() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        log(t, dayOffset: -1, slot: "08:00", in: context)
        let all = try fetchAll(context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: all.doses, missed: all.missed,
                                            from: day(-1), through: day(-1), now: now, calendar: calendar)
        #expect(occ[0].state == .completed)
        #expect(occ[0].completedAt.map { calendar.component(.hour, from: $0) } == 8)
        #expect(occ[1].state == .missed)
    }

    @Test func todaysSlotsAreDueOnceReachedAndUpcomingBefore() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: [], missed: [],
                                            from: day(0), through: day(0), now: now, calendar: calendar)
        #expect(occ.map(\.state) == [.due, .upcoming]) // 09:30: 08:00 has passed, 21:00 has not
        #expect(occ[0].isOpen && occ[1].isOpen)
    }

    @Test func skipRecordCountsAgainstButClinicianPauseIsNotExpected() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        context.insert(MissedDoseRecord(treatment: t, date: day(-1), slot: "08:00", reason: .travel))
        context.insert(MissedDoseRecord(treatment: t, date: day(-1), slot: "21:00", reason: .clinicianDirectedPause))
        let all = try fetchAll(context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: all.doses, missed: all.missed,
                                            from: day(-1), through: day(-1), now: now, calendar: calendar)
        #expect(occ.map(\.state) == [.skipped, .notExpected])
        let c = try #require(PlanAdherence.consistency(occurrences: occ))
        #expect(c.completed == 0 && c.expected == 1)
    }

    @Test func pausedTreatmentEmitsNothingFromItsEndDate() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        t.isActive = false
        t.endDate = day(-1, hour: 10)
        let occ = PlanAdherence.occurrences(treatment: t, doses: [], missed: [],
                                            from: day(-3), through: day(0), now: now, calendar: calendar)
        #expect(occ.count == 4) // -3 and -2 only
        #expect(occ.allSatisfy { $0.day < calendar.startOfDay(for: day(-1)) })
    }

    @Test func startDateClampsTheWindow() throws {
        let context = try makeContext()
        let t = minoxidil(in: context, startedDaysAgo: 2)
        log(t, dayOffset: -2, slot: "08:00", in: context)
        log(t, dayOffset: -2, slot: "21:00", in: context)
        log(t, dayOffset: -1, slot: "21:00", in: context)
        let all = try fetchAll(context)
        let c = try #require(PlanAdherence.consistency(treatment: t, doses: all.doses, missed: all.missed,
                                                       windowDays: 30, now: now, calendar: calendar))
        #expect(c.expected == 4) // two past days × two slots; today's open slots do not count yet
        #expect(c.completed == 3)
        #expect(c.percent == 75)
    }

    @Test func asNeededTreatmentHasNoConsistency() throws {
        let context = try makeContext()
        let prp = Treatment(name: "PRP session", treatmentClass: .prp, dose: "",
                            scheduleTimes: "", startDate: day(-50), isActive: true)
        context.insert(prp)
        #expect(!PlanAdherence.hasSchedule(prp))
        #expect(PlanAdherence.consistency(treatment: prp, doses: [], missed: [],
                                          windowDays: 30, now: now, calendar: calendar) == nil)
    }

    @Test func periodicCareProductCountsOnlyItsWeekdays() throws {
        let context = try makeContext()
        let shampoo = Treatment(name: "Ketoconazole shampoo", treatmentClass: .shampoo, dose: "",
                                scheduleTimes: "", startDate: day(-30), isActive: true)
        shampoo.scheduledWeekdays = [2, 5] // Monday, Thursday
        context.insert(shampoo)
        let occ = PlanAdherence.occurrences(treatment: shampoo, doses: [], missed: [],
                                            from: day(-6), through: day(0), now: now, calendar: calendar)
        // Wed 9 Sep back to Thu 3 Sep: Thu 3 and Mon 7 are scheduled.
        #expect(occ.count == 2)
        #expect(occ.allSatisfy { $0.slot == "" })
        #expect(occ.map(\.state) == [.missed, .missed])
    }

    @Test func todaysOpenOccurrencesStayOutOfTheDenominator() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        log(t, dayOffset: 0, slot: "08:00", in: context)
        let all = try fetchAll(context)
        let occ = PlanAdherence.occurrences(treatment: t, doses: all.doses, missed: all.missed,
                                            from: day(0), through: day(0), now: now, calendar: calendar)
        let c = try #require(PlanAdherence.consistency(occurrences: occ))
        #expect(c.completed == 1 && c.expected == 1)
    }

    // MARK: Today

    @Test func todayPlanSortsBySlotAndKnowsWhenItIsComplete() throws {
        let context = try makeContext()
        let minox = minoxidil(in: context)
        let fin = Treatment(name: "Finasteride 1mg", treatmentClass: .finasteride, dose: "1 mg",
                            scheduleTimes: "21:00", startDate: day(-30), isActive: true)
        context.insert(fin)
        var plan = PlanAdherence.today(treatments: [fin, minox], doses: [], missed: [], now: now, calendar: calendar)
        #expect(plan.occurrences.map { "\($0.treatment.name)@\($0.slot)" }
                == ["Minoxidil 5%@08:00", "Finasteride 1mg@21:00", "Minoxidil 5%@21:00"])
        #expect(plan.openCount == 3 && !plan.isComplete && !plan.nothingExpected)
        #expect(plan.nextOpen?.slot == "08:00")

        log(minox, dayOffset: 0, slot: "08:00", in: context)
        log(minox, dayOffset: 0, slot: "21:00", in: context)
        context.insert(MissedDoseRecord(treatment: fin, date: day(0), slot: "21:00", reason: .supply))
        let all = try fetchAll(context)
        plan = PlanAdherence.today(treatments: [fin, minox], doses: all.doses, missed: all.missed, now: now, calendar: calendar)
        #expect(plan.isComplete)
        #expect(plan.completedCount == 2 && plan.settledCount == 3 && plan.openCount == 0)
    }

    @Test func todayPlanIsEmptyWhenNothingIsScheduled() throws {
        let context = try makeContext()
        let paused = minoxidil(in: context)
        paused.isActive = false
        paused.endDate = day(-1)
        let plan = PlanAdherence.today(treatments: [paused], doses: [], missed: [], now: now, calendar: calendar)
        #expect(plan.nothingExpected && !plan.isComplete)
    }

    // MARK: Week

    @Test func weekMarksEveryStateWithoutRed() throws {
        let context = try makeContext()
        let t = minoxidil(in: context)
        // Mon 7: both slots. Tue 8: one slot. Wed 9 (today): none yet. Thu–Sun: future.
        log(t, dayOffset: -2, slot: "08:00", in: context)
        log(t, dayOffset: -2, slot: "21:00", in: context)
        log(t, dayOffset: -1, slot: "08:00", in: context)
        let all = try fetchAll(context)
        let week = PlanAdherence.week(treatments: [t], doses: all.doses, missed: all.missed, now: now, calendar: calendar)
        #expect(week.count == 7)
        #expect(week.map(\.mark) == [.complete, .partial, .today, .upcoming, .upcoming, .upcoming, .upcoming])
        #expect(week[0].completed == 2 && week[0].expected == 2)
        #expect(week[1].completed == 1 && week[1].expected == 2)
    }

    @Test func weekShowsMissedAndNotExpectedDays() throws {
        let context = try makeContext()
        let shampoo = Treatment(name: "Shampoo", treatmentClass: .shampoo, dose: "",
                                scheduleTimes: "", startDate: day(-30), isActive: true)
        shampoo.scheduledWeekdays = [2] // Monday only
        context.insert(shampoo)
        let week = PlanAdherence.week(treatments: [shampoo], doses: [], missed: [], now: now, calendar: calendar)
        #expect(week.map(\.mark) == [.missed, .notExpected, .notExpected, .upcoming, .upcoming, .upcoming, .upcoming])
    }

    // MARK: Slots

    @Test func slotHelpers() {
        #expect(PlanAdherence.slotMinutes("08:00") == 480)
        #expect(PlanAdherence.slotMinutes("21:15") == 1275)
        #expect(PlanAdherence.slotMinutes("") == nil)
        #expect(PlanAdherence.isReached(slot: "08:00", now: now, calendar: calendar))
        #expect(!PlanAdherence.isReached(slot: "21:00", now: now, calendar: calendar))
        #expect(PlanAdherence.isReached(slot: "", now: now, calendar: calendar))
        let at = PlanAdherence.slotDate("21:00", on: now, calendar: calendar)
        #expect(at.map { calendar.component(.hour, from: $0) } == 21)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `utest PlanAdherenceTests`
Expected: build failure — `PlanAdherence` not found.

- [ ] **Step 3: Write the engine**

Create `Hair Compass AI 5/Model/PlanAdherence.swift`:

```swift
//
//  PlanAdherence.swift
//  Hair Compass AI 5
//
//  The plan-adherence engine (spec: 2026-09-03 Daily Grounding + Plan Adherence, §6). Treatments,
//  logged doses and missed-dose records in; occurrences with one state each out, then the counts
//  Today and Plan show. Pure and deterministic — every date decision uses the calendar passed in,
//  nothing here reads the clock or a ModelContext. It measures completed planned actions, never
//  hair outcomes, and it never scores a pause, a future day or an as-needed item.
//

import Foundation
import SwiftData

enum PlanAdherence {

    // MARK: Types

    enum OccurrenceState: String, Equatable {
        /// Today, slot time not yet reached — or a future day.
        case upcoming
        /// Today, slot time reached (slotless items are due all day), nothing recorded yet.
        case due
        case completed
        /// A missed-dose record with any reason other than a clinician-directed pause.
        case skipped
        /// A past expected occurrence with no dose and no record.
        case missed
        /// Excluded from every count: a clinician-directed pause, a paused treatment, a day
        /// before the start or after the end, a weekday the item is not scheduled for.
        case notExpected
    }

    struct Occurrence: Identifiable {
        let treatment: Treatment
        /// Start of the calendar day.
        let day: Date
        /// "HH:mm", or "" for a slotless periodic item.
        let slot: String
        let state: OccurrenceState
        let completedAt: Date?

        var id: String {
            "\(treatment.persistentModelID.hashValue)|\(Int(day.timeIntervalSince1970))|\(slot)"
        }
        var isOpen: Bool { state == .due || state == .upcoming }
        var isSettled: Bool { state == .completed || state == .skipped }
    }

    /// Completed planned actions over the actions that counted. `expected` never includes a
    /// future, paused, not-expected or still-open occurrence.
    struct Consistency: Equatable {
        let completed: Int
        let expected: Int
        var fraction: Double { expected == 0 ? 0 : Double(completed) / Double(expected) }
        var percent: Int { Int((fraction * 100).rounded()) }
    }

    struct TodayPlan {
        /// Today's occurrences, `notExpected` omitted, sorted by slot time then name.
        let occurrences: [Occurrence]
        var completedCount: Int { occurrences.filter { $0.state == .completed }.count }
        var settledCount: Int { occurrences.filter(\.isSettled).count }
        var openCount: Int { occurrences.filter(\.isOpen).count }
        var isComplete: Bool { !occurrences.isEmpty && openCount == 0 }
        var nothingExpected: Bool { occurrences.isEmpty }
        var nextOpen: Occurrence? {
            occurrences.first { $0.state == .due } ?? occurrences.first { $0.state == .upcoming }
        }
    }

    enum DayMark: Equatable {
        case complete, partial, missed, notExpected, today, upcoming
    }

    struct DayState: Identifiable, Equatable {
        let day: Date
        let mark: DayMark
        let completed: Int
        let expected: Int
        var id: Date { day }
    }

    // MARK: Schedule

    /// Whether the engine can score this item: clock slots, or a care product on its weekdays.
    /// Anything else (a procedure, an as-needed item) is recorded as usage and never given a
    /// percentage.
    static func hasSchedule(_ treatment: Treatment) -> Bool {
        !treatment.slots.isEmpty || treatment.treatmentClass.isCareProduct
    }

    /// The slots expected on `day` — empty when the item is not scheduled that weekday, has not
    /// started, or has been paused (an inactive treatment with no end date is never expected).
    static func expectedSlots(_ treatment: Treatment, on day: Date, calendar: Calendar) -> [String] {
        guard hasSchedule(treatment) else { return [] }
        let start = calendar.startOfDay(for: treatment.startDate)
        guard day >= start else { return [] }
        if !treatment.isActive {
            guard let end = treatment.endDate, day < calendar.startOfDay(for: end) else { return [] }
        }
        guard treatment.isDueToday(now: day, calendar: calendar) else { return [] }
        return treatment.slots.isEmpty ? [""] : treatment.slots
    }

    // MARK: Occurrences

    static func occurrences(
        treatment: Treatment,
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        from firstDay: Date,
        through lastDay: Date,
        now: Date,
        calendar: Calendar
    ) -> [Occurrence] {
        let id = treatment.persistentModelID
        let ownDoses = doses.filter { $0.treatment?.persistentModelID == id }
        let ownMissed = missed.filter { $0.treatment?.persistentModelID == id }
        let today = calendar.startOfDay(for: now)
        let last = calendar.startOfDay(for: lastDay)
        var day = calendar.startOfDay(for: firstDay)
        var out: [Occurrence] = []
        while day <= last {
            let bounds = HairAnalytics.dayBounds(for: day, calendar: calendar)
            for slot in expectedSlots(treatment, on: day, calendar: calendar) {
                let dose = ownDoses.first { $0.slot == slot && bounds.contains($0.loggedAt) }
                let record = ownMissed.first { $0.slot == slot && bounds.contains($0.date) }
                let state: OccurrenceState
                if dose != nil {
                    state = .completed
                } else if let record {
                    state = record.reason == .clinicianDirectedPause ? .notExpected : .skipped
                } else if day < today {
                    state = .missed
                } else if day > today {
                    state = .upcoming
                } else {
                    state = isReached(slot: slot, now: now, calendar: calendar) ? .due : .upcoming
                }
                out.append(Occurrence(treatment: treatment, day: day, slot: slot,
                                      state: state, completedAt: dose?.loggedAt))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    // MARK: Folds

    /// nil when nothing counted — a fresh item, an as-needed item, a window with no expected day.
    static func consistency(occurrences: [Occurrence]) -> Consistency? {
        let scored = occurrences.filter {
            $0.state == .completed || $0.state == .skipped || $0.state == .missed
        }
        guard !scored.isEmpty else { return nil }
        return Consistency(completed: scored.filter { $0.state == .completed }.count,
                           expected: scored.count)
    }

    /// One treatment over the trailing `windowDays` (today included; the start date clamps it).
    static func consistency(
        treatment: Treatment,
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        windowDays: Int,
        now: Date,
        calendar: Calendar
    ) -> Consistency? {
        guard hasSchedule(treatment) else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else { return nil }
        return consistency(occurrences: occurrences(
            treatment: treatment, doses: doses, missed: missed,
            from: first, through: today, now: now, calendar: calendar
        ))
    }

    /// Every treatment over an explicit day range — the week ribbon and the overall plan rhythm.
    static func consistency(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        from firstDay: Date,
        through lastDay: Date,
        now: Date,
        calendar: Calendar
    ) -> Consistency? {
        consistency(occurrences: treatments.flatMap {
            occurrences(treatment: $0, doses: doses, missed: missed,
                        from: firstDay, through: lastDay, now: now, calendar: calendar)
        })
    }

    static func today(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        now: Date,
        calendar: Calendar
    ) -> TodayPlan {
        let day = calendar.startOfDay(for: now)
        let occ = treatments
            .flatMap {
                occurrences(treatment: $0, doses: doses, missed: missed,
                            from: day, through: day, now: now, calendar: calendar)
            }
            .filter { $0.state != .notExpected }
            .sorted { lhs, rhs in
                let l = slotMinutes(lhs.slot) ?? Int.max
                let r = slotMinutes(rhs.slot) ?? Int.max
                if l != r { return l < r }
                return lhs.treatment.name.localizedCaseInsensitiveCompare(rhs.treatment.name) == .orderedAscending
            }
        return TodayPlan(occurrences: occ)
    }

    /// The current calendar week (the calendar's own first weekday), one mark per day.
    static func week(
        treatments: [Treatment],
        doses: [TreatmentDose],
        missed: [MissedDoseRecord],
        now: Date,
        calendar: Calendar
    ) -> [DayState] {
        let today = calendar.startOfDay(for: now)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        var states: [DayState] = []
        var day = interval.start
        for _ in 0..<7 {
            let occ = treatments
                .flatMap {
                    occurrences(treatment: $0, doses: doses, missed: missed,
                                from: day, through: day, now: now, calendar: calendar)
                }
                .filter { $0.state != .notExpected }
            let expected = occ.count
            let completed = occ.filter { $0.state == .completed }.count
            let mark: DayMark
            if day > today {
                mark = .upcoming
            } else if expected == 0 {
                mark = .notExpected
            } else if completed == expected {
                mark = .complete
            } else if day == today {
                mark = .today
            } else if completed > 0 {
                mark = .partial
            } else {
                mark = .missed
            }
            states.append(DayState(day: day, mark: mark, completed: completed, expected: expected))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return states
    }

    // MARK: Slots

    static func slotMinutes(_ slot: String) -> Int? {
        let parts = slot.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// The slot's clock time on `day`'s calendar day; nil for a slotless item.
    static func slotDate(_ slot: String, on day: Date, calendar: Calendar) -> Date? {
        guard let minutes = slotMinutes(slot) else { return nil }
        return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day))
    }

    /// True once the slot's clock time has passed today; slotless items are reached all day.
    static func isReached(slot: String, now: Date, calendar: Calendar) -> Bool {
        guard let minutes = slotMinutes(slot) else { return true }
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0) >= minutes
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `utest PlanAdherenceTests`
Expected: `✔ Test run with 14 tests in 1 suite passed`. If `periodicCareProductCountsOnlyItsWeekdays` or `weekShowsMissedAndNotExpectedDays` disagree by one day, check that the fixture calendar is the one passed to `isDueToday(now:calendar:)` (weekday numbers are calendar-relative) — the engine must never fall back to `Calendar.current`.

- [ ] **Step 5: Commit**

Message (write to a scratch file, commit with `-F`):

```
Plan adherence engine: occurrences, consistency, today, week

Treatments, doses and missed-dose records fold into occurrences with one
state each; pauses, future days and as-needed items never enter the
denominator, a skip does, and today's open slots wait for the day to end.
Pure, calendar-driven, tested on an in-memory store.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git checkout -- "<scheme>"`, `git add "Hair Compass AI 5/Model/PlanAdherence.swift" "Hair Compass AI 5Tests/PlanAdherenceTests.swift"`, `git commit -F`.

---

### Task 2: The Today plan section

**Files:**
- Create: `Hair Compass AI 5/Feature/TodayPlanSection.swift`
- Test: `Hair Compass AI 5Tests/TodayPlanCopyTests.swift`

**Interfaces:**
- Consumes: `PlanAdherence.*` (Task 1); `Eyebrow(text:color:)` (`Design/Clinical.swift:776`), `Clinical.sage/accent/hairline/ink/secondary/tertiary/surface`, `Clinical.body/caption/eyebrow`, `.clinicalPressable`, `.minimumHitTarget()`, `.completionInkUnderline(trigger:)` (`Clinical.swift:701`), `TreatmentClass.title`.
- Produces: `enum TodayPlanCopy`; `struct TodayPlanSection: View { init(plan:week:weekSummary:onComplete:onUndo:onSkip:onPause:onOpenDetail:onOpenPlan:) }`; `struct ContinuityStrip: View { init(days:summary:) }`; accessibility identifiers `todayPlan`, `planRow.<i>`, `planRowComplete.<i>`, `planRowUndo.<i>`, `planClosure`, `planClosureShow`, `planQuiet`, `continuityStrip`; accessibility values on the circle: `Not yet`, `Completed at <time>`, `Skipped`.

- [ ] **Step 1: Write the failing copy test**

Create `Hair Compass AI 5Tests/TodayPlanCopyTests.swift`:

```swift
//
//  TodayPlanCopyTests.swift
//  Hair Compass AI 5Tests
//
//  The plan section's copy is data. Pinned so it stays record-keeping: no diagnosis words, no
//  directives, no exclamation marks, no shame vocabulary.
//

import Testing
@testable import Hair_Compass_AI_5

struct TodayPlanCopyTests {

    private var everyLine: [String] {
        [
            TodayPlanCopy.eyebrow, TodayPlanCopy.closureTitle, TodayPlanCopy.closureBody,
            TodayPlanCopy.quietTitle, TodayPlanCopy.quietBody, TodayPlanCopy.skippedLabel,
            TodayPlanCopy.undo, TodayPlanCopy.recordedLine(1), TodayPlanCopy.recordedLine(3),
            TodayPlanCopy.weekEyebrow, TodayPlanCopy.weekLine(completed: 6, expected: 7),
            TodayPlanCopy.weekEmpty, TodayPlanCopy.viewPlan,
            TodayPlanCopy.skipTitle, TodayPlanCopy.skipMessage,
            TodayPlanCopy.pauseTitle("Minoxidil"), TodayPlanCopy.pauseMessage, TodayPlanCopy.pauseAction
        ]
    }

    @Test func copyStaysRecordKeeping() {
        let banned = ["diagnos", "cure", "you have", "prescrib", "you should", "you must",
                      "failed", "poor", "non-compliant", "streak", "!"]
        for line in everyLine {
            let lower = line.lowercased()
            for word in banned {
                #expect(!lower.contains(word), "\(line) contains \(word)")
            }
        }
    }

    @Test func closureSaysNothingElseIsNeeded() {
        #expect(TodayPlanCopy.closureBody.lowercased().contains("nothing else"))
        #expect(TodayPlanCopy.recordedLine(1) == "1 action recorded")
        #expect(TodayPlanCopy.recordedLine(2) == "2 actions recorded")
        #expect(TodayPlanCopy.weekLine(completed: 6, expected: 7) == "6 of 7 planned actions")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `utest TodayPlanCopyTests`
Expected: build failure — `TodayPlanCopy` not found.

- [ ] **Step 3: Write the section**

Create `Hair Compass AI 5/Feature/TodayPlanSection.swift`:

```swift
//
//  TodayPlanSection.swift
//  Hair Compass AI 5
//
//  Today's plan: one row per scheduled occurrence with a single obvious completion target, Undo
//  for five seconds after a check-off (and always in the long-press menu), Skip and Pause behind
//  the same menu so they never compete with completing, a seven-day continuity strip, and a calm
//  closure line once every occurrence is settled. The section renders and hands every write to
//  its owner; it never touches a ModelContext.
//

import SwiftUI
import UIKit

/// The section's copy, kept as data so tests can pin the framing rule.
enum TodayPlanCopy {
    static let eyebrow = "Today's plan"
    static let closureTitle = "Your plan is complete for today"
    static let closureBody = "You showed up. Nothing else needs to be checked today."
    static let quietTitle = "Nothing is scheduled today"
    static let quietBody = "Your plan will list the next action when one is due."
    static let viewPlan = "View plan"
    static let skippedLabel = "Skipped"
    static let undo = "Undo"
    static func recordedLine(_ count: Int) -> String {
        count == 1 ? "1 action recorded" : "\(count) actions recorded"
    }
    static let weekEyebrow = "This week"
    static func weekLine(completed: Int, expected: Int) -> String {
        "\(completed) of \(expected) planned actions"
    }
    static let weekEmpty = "No planned actions yet this week"
    static let skipTitle = "Skip this one today?"
    static let skipMessage = "This records a skipped application. It does not change or start any treatment."
    static func pauseTitle(_ name: String) -> String { "Pause \(name)?" }
    static let pauseMessage = "It leaves today's plan until you resume it from the Plan tab. This records your decision; it does not advise one."
    static let pauseAction = "Pause"
}

struct TodayPlanSection: View {
    let plan: PlanAdherence.TodayPlan
    let week: [PlanAdherence.DayState]
    let weekSummary: PlanAdherence.Consistency?
    var onComplete: (PlanAdherence.Occurrence) -> Void
    var onUndo: (PlanAdherence.Occurrence) -> Void
    var onSkip: (PlanAdherence.Occurrence) -> Void
    var onPause: (PlanAdherence.Occurrence) -> Void
    var onOpenDetail: (PlanAdherence.Occurrence) -> Void
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while the person has asked to see the recorded rows under the closure line.
    @State private var showsRecorded = false
    /// The occurrence whose inline Undo is still showing.
    @State private var undoableID: String?
    @State private var undoTimer: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: TodayPlanCopy.eyebrow)
                .padding(.bottom, 6)
            if plan.nothingExpected {
                quietLine
            } else if plan.isComplete && !showsRecorded {
                closure
            } else {
                rows
            }
            ContinuityStrip(days: week, summary: weekSummary)
                .padding(.top, 14)
        }
        .onChange(of: plan.isComplete) { _, complete in
            guard complete else { return }
            showsRecorded = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayPlan")
    }

    // MARK: Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                PlanActionRow(
                    occurrence: occurrence,
                    index: index,
                    showsUndo: undoableID == occurrence.id,
                    onComplete: { complete(occurrence) },
                    onUndo: { undo(occurrence) },
                    onSkip: { onSkip(occurrence) },
                    onPause: { onPause(occurrence) },
                    onOpenDetail: { onOpenDetail(occurrence) }
                )
                if index < plan.occurrences.count - 1 {
                    Divider().overlay(Clinical.hairline)
                }
            }
        }
    }

    private func complete(_ occurrence: PlanAdherence.Occurrence) {
        onComplete(occurrence)
        undoableID = occurrence.id
        undoTimer?.cancel()
        undoTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { undoableID = nil }
        }
    }

    private func undo(_ occurrence: PlanAdherence.Occurrence) {
        undoTimer?.cancel()
        undoableID = nil
        onUndo(occurrence)
    }

    // MARK: Closure and quiet day

    private var closure: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Clinical.body(16))
                    .foregroundStyle(Clinical.sage)
                    .accessibilityHidden(true)
                Text(TodayPlanCopy.closureTitle)
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
            }
            Text(TodayPlanCopy.closureBody)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsRecorded = true }
            } label: {
                Text("\(TodayPlanCopy.recordedLine(plan.settledCount)) · Show")
                    .font(Clinical.body(12, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityIdentifier("planClosureShow")
        }
        .padding(.vertical, 8)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planClosure")
    }

    private var quietLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TodayPlanCopy.quietTitle)
                .font(Clinical.body(15, weight: .medium))
                .foregroundStyle(Clinical.ink)
            Text(TodayPlanCopy.quietBody)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let onOpenPlan {
                Button(TodayPlanCopy.viewPlan, action: onOpenPlan)
                    .font(Clinical.body(12, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planQuiet")
    }
}

// MARK: - Row

private struct PlanActionRow: View {
    let occurrence: PlanAdherence.Occurrence
    let index: Int
    let showsUndo: Bool
    let onComplete: () -> Void
    let onUndo: () -> Void
    let onSkip: () -> Void
    let onPause: () -> Void
    let onOpenDetail: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @State private var wash = false
    @State private var inkTrigger = false

    private var name: String {
        occurrence.treatment.name.isEmpty ? occurrence.treatment.treatmentClass.title : occurrence.treatment.name
    }

    private var classSubtitle: String? {
        let cls = occurrence.treatment.treatmentClass.title
        return name.localizedCaseInsensitiveContains(cls) ? nil : cls
    }

    private var slotTime: String? {
        PlanAdherence.slotDate(occurrence.slot, on: occurrence.day, calendar: calendar)
            .map { $0.formatted(date: .omitted, time: .shortened) }
    }

    private var timeLabel: String {
        switch occurrence.state {
        case .completed:
            return occurrence.completedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        case .skipped:
            return TodayPlanCopy.skippedLabel
        case .due:
            return slotTime.map { "Due \($0)" } ?? "Today"
        case .upcoming:
            return slotTime ?? "Today"
        case .missed, .notExpected:
            return ""
        }
    }

    private var circleValue: String {
        switch occurrence.state {
        case .completed: return "Completed at \(timeLabel)"
        case .skipped: return TodayPlanCopy.skippedLabel
        default: return "Not yet"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            circle
            Button(action: onOpenDetail) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(Clinical.body(14, weight: occurrence.isSettled ? .regular : .medium))
                            .foregroundStyle(occurrence.isSettled ? Clinical.secondary : Clinical.ink)
                            .completionInkUnderline(trigger: $inkTrigger)
                        if let classSubtitle {
                            Text(classSubtitle)
                                .font(Clinical.caption(11.5))
                                .foregroundStyle(Clinical.tertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    if occurrence.state == .completed && showsUndo {
                        Button(TodayPlanCopy.undo, action: onUndo)
                            .font(Clinical.body(12, weight: .medium))
                            .foregroundStyle(Clinical.tertiary)
                            .buttonStyle(.plain)
                            .minimumHitTarget()
                            .accessibilityIdentifier("planRowUndo.\(index)")
                    } else {
                        Text(timeLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Clinical.secondary)
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(timeLabel)")
            .accessibilityHint("Opens this treatment")
        }
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Clinical.sage.opacity(wash ? 0.14 : 0))
                .padding(.horizontal, -8)
        }
        .contextMenu {
            if occurrence.isSettled {
                Button(TodayPlanCopy.undo, systemImage: "arrow.uturn.backward", action: onUndo)
            }
            if occurrence.isOpen {
                Button("Skip today", systemImage: "forward.end", action: onSkip)
            }
            Button("Pause treatment", systemImage: "pause.circle", action: onPause)
            Button("Details", systemImage: "info.circle", action: onOpenDetail)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planRow.\(index)")
    }

    private var fill: Color {
        switch occurrence.state {
        case .completed: return Clinical.sage
        case .due: return Clinical.accent.opacity(0.06)
        default: return .clear
        }
    }

    private var stroke: Color {
        switch occurrence.state {
        case .completed: return Clinical.sage
        case .due: return Clinical.accent.opacity(0.5)
        case .skipped: return Clinical.tertiary.opacity(0.5)
        default: return Clinical.hairline
        }
    }

    private var circle: some View {
        Button {
            guard occurrence.isOpen else { return }
            complete()
        } label: {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(stroke, lineWidth: 1.5)
                if occurrence.state == .completed {
                    Image(systemName: "checkmark")
                        .font(Clinical.body(10, weight: .bold))
                        .foregroundStyle(Clinical.surface)
                }
                if occurrence.state == .skipped {
                    Capsule().fill(Clinical.tertiary).frame(width: 8, height: 1.5)
                }
            }
            .frame(width: 22, height: 22)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel(occurrence.isOpen ? "Mark \(name) complete" : name)
        .accessibilityValue(circleValue)
        .accessibilityHint(occurrence.isOpen ? "Records this action as done" : "Use Undo to change it")
        .accessibilityIdentifier("planRowComplete.\(index)")
    }

    private func complete() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onComplete()
        inkTrigger = true
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.18)) { wash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeIn(duration: 0.4)) { wash = false }
        }
    }
}

// MARK: - Continuity strip

/// Seven small day capsules for the current week: a sage check for a day whose planned actions
/// were all recorded, a copper dot for a partial day, a neutral dash when nothing was expected,
/// an outline for today and the days ahead, and a muted dot for a missed day — never red.
struct ContinuityStrip: View {
    let days: [PlanAdherence.DayState]
    let summary: PlanAdherence.Consistency?

    @Environment(\.calendar) private var calendar

    private var summaryLine: String {
        summary.map { TodayPlanCopy.weekLine(completed: $0.completed, expected: $0.expected) }
            ?? TodayPlanCopy.weekEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: TodayPlanCopy.weekEyebrow, color: Clinical.tertiary)
                Spacer(minLength: 8)
                Text(summaryLine)
                    .font(Clinical.caption(11.5))
                    .foregroundStyle(Clinical.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 0) {
                ForEach(days) { day in
                    VStack(spacing: 5) {
                        Text(initial(day.day))
                            .font(Clinical.caption(10))
                            .foregroundStyle(Clinical.tertiary)
                        DayCapsule(mark: day.mark)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(day))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("continuityStrip")
    }

    private func initial(_ day: Date) -> String {
        String(day.formatted(.dateTime.weekday(.abbreviated)).prefix(1)).uppercased()
    }

    private func label(_ day: PlanAdherence.DayState) -> String {
        let name = day.day.formatted(.dateTime.weekday(.wide))
        switch day.mark {
        case .complete: return "\(name), all planned actions recorded"
        case .partial: return "\(name), \(day.completed) of \(day.expected) recorded"
        case .missed: return "\(name), planned actions not recorded"
        case .notExpected: return "\(name), nothing planned"
        case .today: return "\(name), today, \(day.completed) of \(day.expected) so far"
        case .upcoming: return "\(name), ahead"
        }
    }
}

private struct DayCapsule: View {
    let mark: PlanAdherence.DayMark

    var body: some View {
        ZStack {
            switch mark {
            case .complete:
                Circle().fill(Clinical.sage)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Clinical.surface)
            case .partial:
                Circle().strokeBorder(Clinical.accent.opacity(0.5), lineWidth: 1)
                Circle().fill(Clinical.accent).frame(width: 6, height: 6)
            case .missed:
                Circle().strokeBorder(Clinical.hairline, lineWidth: 1)
                Circle().fill(Clinical.tertiary.opacity(0.55)).frame(width: 6, height: 6)
            case .notExpected:
                Capsule().fill(Clinical.hairline).frame(width: 8, height: 1.5)
            case .today:
                Circle().strokeBorder(Clinical.accent, lineWidth: 1.5)
            case .upcoming:
                Circle().strokeBorder(Clinical.hairline, lineWidth: 1)
            }
        }
        .frame(width: 18, height: 18)
    }
}
```

- [ ] **Step 4: Build, then run the copy test**

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error:'
```

Expected: no output. If `Clinical.hairline` does not exist under that name, use the token the hero's chip already uses for its stroke (`TodayTiles.swift`, the `sameAsYesterday` chip's `.strokeBorder`), and say so in the report. Then `utest TodayPlanCopyTests` → `✔ Test run with 2 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

Message:

```
TodayPlanSection: one-tap rows, Undo, Skip and Pause, week strip, closure

Rows carry a 44pt completion circle that fills sage, a five-second inline
Undo and a long-press menu for Undo, Skip today, Pause and Details. A
seven-day strip marks complete, partial, missed (muted, never red),
nothing-planned, today and ahead. When every occurrence is settled the
list folds into one closure line. Copy pinned as record-keeping.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git checkout -- "<scheme>"`, `git add "Hair Compass AI 5/Feature/TodayPlanSection.swift" "Hair Compass AI 5Tests/TodayPlanCopyTests.swift"`, `git commit -F`.

---

### Task 3: Wire Today, retire the ledger's routine rows, add the QA flag and the UI test

**Files:**
- Modify: `Hair Compass AI 5/Service/PersistenceRepositories.swift:89-109` (`MissedDoseRepository`)
- Modify: `Hair Compass AI 5/Feature/TodayView.swift` (`:23-31` queries, `:45-125` computed state, `:127-215` body, sheets/dialogs after the body, `isLogged`/`toggle` helpers near `:558-574`)
- Modify: `Hair Compass AI 5/Feature/TodayTiles.swift` (`TodayTileGrid` `:480-620`, `RoutineLedgerRow` `:856-924`)
- Modify: `Hair Compass AI 5/Model/Seed.swift:145-160`
- Modify: `Hair Compass AI 5/App/RootView.swift:287-298`
- Modify: `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift`

**Interfaces:**
- Consumes: `PlanAdherence` (Task 1), `TodayPlanSection`/`TodayPlanCopy` (Task 2), `DoseRepository.log/delete(treatment:day:slot:)` (`PersistenceRepositories.swift:53-70`), `MissedDoseRepository.record(treatment:day:slot:reason:)` (`:89-109`), `MissedDoseReason.allCases`/`.title`, `TreatmentDetailSheet(treatment:)` (`Feature/TreatmentDetailSheet.swift:7-10`), `Seed.ensureNoTodayEntry` pattern (`Seed.swift:145-160`), the `HC_NOTODAY` call site in `RootView.swift:287-298`.
- Produces: `MissedDoseRepository.delete(treatment:day:slot:) -> Bool`; DEBUG launch argument `HC_PLANOPEN`; `Seed.ensureNoDosesToday(context:calendar:now:)`; `TodayTileGrid` without routine parameters.

- [ ] **Step 1: Write the failing UI test**

Append inside the `Hair_Compass_AI_5UITests` class:

```swift
    /// A plan action is one tap and one Undo: with today's doses cleared, the first row's circle
    /// records it, the inline Undo returns it, and the closure line stays away while rows are open.
    @MainActor
    func testPlanRowCompletesAndUndoes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_PLANOPEN"]
        app.launch()

        let circle = app.buttons["planRowComplete.0"]
        XCTAssertTrue(circle.waitForExistence(timeout: 10), "today's plan must list an open action")
        XCTAssertEqual(circle.value as? String, "Not yet")
        XCTAssertFalse(app.otherElements["planClosure"].exists, "the closure line waits for every row")

        circle.tap()
        let undo = app.buttons["planRowUndo.0"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4), "a completed row offers Undo")
        XCTAssertTrue((circle.value as? String)?.hasPrefix("Completed") == true)

        undo.tap()
        XCTAssertTrue(circle.waitForExistence(timeout: 4))
        XCTAssertEqual(circle.value as? String, "Not yet")
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests/Hair_Compass_AI_5UITests/testPlanRowCompletesAndUndoes" 2>&1 | grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" | tail -4
```

Expected: `failed` on "today's plan must list an open action".

- [ ] **Step 3: `MissedDoseRepository.delete`**

In `Hair Compass AI 5/Service/PersistenceRepositories.swift`, inside `MissedDoseRepository` after `record(...)`:

```swift
    /// Removes today's (or `day`'s) skip record for one slot — the Undo of a skip.
    @discardableResult
    func delete(treatment: Treatment, day: Date = .now, slot: String) throws -> Bool {
        let bounds = HairAnalytics.dayBounds(for: day, calendar: calendar)
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        let records = try context.fetch(FetchDescriptor<MissedDoseRecord>(predicate: #Predicate {
            $0.date >= lower && $0.date < upper && $0.slot == slot
        }))
        guard let existing = records.first(where: { $0.treatment?.persistentModelID == treatment.persistentModelID }) else {
            return false
        }
        context.delete(existing)
        return true
    }
```

- [ ] **Step 4: The QA flag**

In `Hair Compass AI 5/Model/Seed.swift`, inside the existing `#if DEBUG` block after `ensureNoTodayEntry`:

```swift
    /// `HC_PLANOPEN`: removes every dose logged today so Today's plan starts fully open — the
    /// demo seed logs most of today's doses, which leaves nothing for a completion test to tap.
    /// Entries, photos and missed-dose records are left alone.
    static func ensureNoDosesToday(context: ModelContext, calendar: Calendar = .current, now: Date = .now) {
        let bounds = HairAnalytics.dayBounds(for: now, calendar: calendar)
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        let descriptor = FetchDescriptor<TreatmentDose>(predicate: #Predicate { $0.loggedAt >= lower && $0.loggedAt < upper })
        for dose in (try? context.fetch(descriptor)) ?? [] { context.delete(dose) }
        try? context.save()
    }
```

In `Hair Compass AI 5/App/RootView.swift`, directly after the `HC_NOTODAY` call (`Seed.ensureNoTodayEntry(context:)` inside the DEBUG launch task, around `:291-298`), add:

```swift
            if ProcessInfo.processInfo.arguments.contains("HC_PLANOPEN") {
                Seed.ensureNoDosesToday(context: context)
            }
```

(Use whatever the surrounding lines call the context variable.)

- [ ] **Step 5: Retire the routine rows from the ledger**

In `Hair Compass AI 5/Feature/TodayTiles.swift`, `TodayTileGrid`:
- Delete the stored properties `medsDone`, `medsTotal`, `routineSteps`, `isSlotLogged`, `onToggleSlot`, `onOpenPlan` and their doc comments.
- In `visibleRows`, delete the `medsRow` fallback line (`if medsTotal > 0 && routineSteps.isEmpty { add(medsRow) }`) and the routine block (`if !routineSteps.isEmpty { add(routineHeaderRow) … }`). The trigger row and the backfill footnote stay.
- Delete `routineHeaderRow`, `medsRemainingLabel`, `routineStepRow(_:slot:)`, and `medsRow` (search the file for `private var medsRow`), and the whole `private struct RoutineLedgerRow`.
- If `MiniTrace` or anything else in the file referenced a deleted symbol, keep the referenced symbol and note it in the report.

- [ ] **Step 6: Wire TodayView**

In `Hair Compass AI 5/Feature/TodayView.swift`:

(a) Queries (`:23-31`): add `@Query private var missedDoses: [MissedDoseRecord]`.

(b) State: add
```swift
    @State private var skipCandidate: PlanAdherence.Occurrence?
    @State private var pauseCandidate: PlanAdherence.Occurrence?
    @State private var detailTreatment: Treatment?
```

(c) Computed state (`:45-125`): delete `activeDaily`, `dueCareProducts`, `dailySlots`, `medsDone`; add

```swift
    /// Today's plan, the week strip and the week-so-far count, all from one engine.
    private var todayPlan: PlanAdherence.TodayPlan {
        PlanAdherence.today(treatments: treatments, doses: doses, missed: missedDoses, now: .now, calendar: calendar)
    }
    private var weekStates: [PlanAdherence.DayState] {
        PlanAdherence.week(treatments: treatments, doses: doses, missed: missedDoses, now: .now, calendar: calendar)
    }
    private var weekSummary: PlanAdherence.Consistency? {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return nil }
        return PlanAdherence.consistency(treatments: treatments, doses: doses, missed: missedDoses,
                                         from: start, through: today, now: .now, calendar: calendar)
    }
    private var medsDone: Int { todayPlan.completedCount }
    private var medsTotal: Int { todayPlan.occurrences.count }
```

`compassScore` keeps `medsDone: medsDone, medsTotal: medsTotal`.

(d) Body (`:127-215`): inside the `VStack(alignment: .leading, spacing: 16)`, before `CompassRingsCard`, insert

```swift
                    TodayPlanSection(
                        plan: todayPlan,
                        week: weekStates,
                        weekSummary: weekSummary,
                        onComplete: { occurrence in
                            _ = try? DoseRepository(context: context).log(treatment: occurrence.treatment, slot: occurrence.slot)
                        },
                        onUndo: { occurrence in
                            switch occurrence.state {
                            case .completed:
                                _ = try? DoseRepository(context: context).delete(treatment: occurrence.treatment, slot: occurrence.slot)
                            case .skipped:
                                _ = try? MissedDoseRepository(context: context).delete(treatment: occurrence.treatment, slot: occurrence.slot)
                            default:
                                break
                            }
                        },
                        onSkip: { skipCandidate = $0 },
                        onPause: { pauseCandidate = $0 },
                        onOpenDetail: { detailTreatment = $0.treatment },
                        onOpenPlan: onOpenPlan
                    )
                    .staggeredEntrance(index: 1)
```

and change the rings card to `.staggeredEntrance(index: 2)`. Update the `CompassRingsCard(... medsTotal: dailySlots.count ...)` argument to `medsTotal: medsTotal`. Remove the `medsDone:`, `medsTotal:`, `routineSteps:`, `isSlotLogged:`, `onToggleSlot:` and `onOpenPlan:` arguments from the `TodayTileGrid(...)` call.

(e) Dialogs and sheet — add after the existing `.sheet` modifiers on the body's outer view:

```swift
        .sheet(item: $detailTreatment) { TreatmentDetailSheet(treatment: $0) }
        .confirmationDialog(TodayPlanCopy.skipTitle, isPresented: Binding(
            get: { skipCandidate != nil }, set: { if !$0 { skipCandidate = nil } }
        ), titleVisibility: .visible) {
            ForEach(MissedDoseReason.allCases) { reason in
                Button(reason.title) { recordSkip(reason) }
            }
            Button("Cancel", role: .cancel) { skipCandidate = nil }
        } message: {
            Text(TodayPlanCopy.skipMessage)
        }
        .confirmationDialog(TodayPlanCopy.pauseTitle(pauseCandidate?.treatment.name ?? ""), isPresented: Binding(
            get: { pauseCandidate != nil }, set: { if !$0 { pauseCandidate = nil } }
        ), titleVisibility: .visible) {
            Button(TodayPlanCopy.pauseAction) { pauseTreatment() }
            Button("Cancel", role: .cancel) { pauseCandidate = nil }
        } message: {
            Text(TodayPlanCopy.pauseMessage)
        }
```

and the two helpers next to the other private functions:

```swift
    private func recordSkip(_ reason: MissedDoseReason) {
        guard let candidate = skipCandidate else { return }
        _ = try? MissedDoseRepository(context: context).record(
            treatment: candidate.treatment, slot: candidate.slot, reason: reason
        )
        skipCandidate = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Records the person's own decision and its date — never advises it. Resuming lives on the
    /// Plan tab's treatment card ("Reactivate"), which clears the end date again.
    private func pauseTreatment() {
        guard let candidate = pauseCandidate else { return }
        candidate.treatment.isActive = false
        candidate.treatment.endDate = .now
        pauseCandidate = nil
    }
```

(f) Delete the now-unused `isLogged(_:slot:)` and `toggle(_:slot:currentlyDone:)` helpers (`:558-574` region) if nothing else in the file uses them; `MissedDoseReason` needs `Identifiable` for the `ForEach` — `CareView` already iterates it the same way, so it is.

- [ ] **Step 7: Run the UI test, then the suites**

Run the single UI test (Step 2 command). Expected: `passed`. Then the full UI target (`-only-testing:"Hair Compass AI 5UITests"`, `-parallel-testing-enabled NO`) and the full unit target; both `TEST SUCCEEDED`. If an existing UI test looked for the ledger's routine rows, update it to the plan section's identifiers and say so in the report.

- [ ] **Step 8: See it**

```bash
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app"
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_SEED_DEMO HC_NORITUAL HC_PLANOPEN
python3 -c 'import time; time.sleep(3)'
xcrun simctl io booted screenshot "$DD/../g1-plan-open.png"
xcrun simctl terminate booted harib.Hair-Compass-AI-5
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_SEED_DEMO HC_NORITUAL
python3 -c 'import time; time.sleep(3)'
xcrun simctl io booted screenshot "$DD/../g1-plan-closed.png"
```

Open both screenshots. Expected: the first shows "TODAY'S PLAN" with three rows (08:00 minoxidil due, 21:00 finasteride and minoxidil ahead) and the week strip; the second shows the closure line with the sage check and "3 actions recorded · Show" (or the demo's count for the weekday), no routine rows further down the ledger.

- [ ] **Step 9: Commit**

Message:

```
Today owns the plan: one-tap rows replace the ledger's routine lines

TodayView folds treatments, doses and skip records through PlanAdherence
and renders TodayPlanSection above the rings; the ledger keeps its
signals and loses the routine rows it duplicated. Skip asks for a reason
through the same dialog Plan uses, Pause records the decision and its
date, Details opens the treatment sheet. HC_PLANOPEN clears today's
doses for QA; the UI test completes a row and undoes it.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git checkout -- "<scheme>"`; `git add` the six modified files; `git commit -F`.

---

### Task 4: Land sub-project G1

Controller task: whole-branch review, fix wave, fast-forward `feat/agent-profile-memory`, push, merge `rebuild/clinical-minimal` forward, push, leave the simulator on the new build.

---

## Self-review notes

- Spec §6.1 states: upcoming/due/completed/skipped/missed/not-expected — `OccurrenceState`; denominator exclusions — `expectedSlots` + `consistency(occurrences:)`; as-needed never scored — `hasSchedule`; no catch-up dosing — no copy mentions doses at all. §6.2 Today rows with one tap target, long press for Skip/Pause/Edit/Undo — `PlanActionRow`; seven capsules — `ContinuityStrip`. §3 completed-day state — `closure`, success haptic once on the transition, no XP/confetti. §6.4 recovery — missed is muted, never red; Undo corrects a forgotten log; pause reasons via `MissedDoseReason`. §7.3 motion — sage wash inside the row, Reduce Motion drops it. §7.6 — 44pt targets, labels, values.
- Deviation: the spec's "Edit time" lives behind "Details" (the existing treatment sheet) rather than an inline time editor; G3 revisits the Plan tab.
- Deviation: the thirty-day per-treatment view and the evidence ribbon are G2/G3; G1 ships the engine they read.
- The Compass Score keeps its inputs (`medsDone`/`medsTotal`) from the engine so the rings and the widget agree with the plan section until G2 demotes the rings.
