# Sub-project G2: Calm Horizon + Deterministic Daily Grounding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Today answers the spec's four questions in order — where am I in the plan (a Calm Horizon header), what should I remember today (one deterministic Daily Grounding card with a single action and a closure line), what is the one action due (the plan section from G1), when is the next meaningful review (an evidence ribbon) — and the card tour is gone.

**Architecture:** Three pure models feed the page: `EvidencePhase` (day number, phase label, next review from the plan's anchor), `PhotoCadence` (next comparable photo, monthly), and `GroundingCards` (the spec's selection hierarchy over a `GroundingInput` snapshot, producing a `GroundingCard` value with headline, body, anchor, one action, closure and a reason). `TodayView` builds the input from its queries and the G1 engine, renders `CalmHorizonHeader`, `GroundingCardView`, `TodayPlanSection`, `EvidenceRibbon`, then the record scene and the demoted rings. The card is a function of state, so it is stable for the day and changes only when the record changes. The server-generated card (spec §4.5) is G5; this plan is the deterministic fallback the spec requires either way.

**Tech Stack:** SwiftUI, SwiftData (queries only), Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-03-daily-grounding-adherence-design.md` — §3 (Today order, completed-day state), §4.1–4.4, 4.6, 4.8 (card jobs, anatomy, categories, hierarchy, examples), §7 (appearance, motion, Wren's role, accessibility), §8 (remove score hero, XP, tour), §9 (safety and trust), §10 (deterministic fallback), §14 (acceptance).

## Global Constraints

- Framing rule: record-keeping and education, never diagnosis; no directive copy ("you should", "you must", "start taking"); no exclamation marks; never "you are anxious" or any inferred emotion; a card may say what the record shows, never what it means for the hair.
- Every card has: an eyebrow, a headline of at most 10 words, a body of at most 55 words, at most one primary action, a closure sentence, and a reason for "Why this?". Safety outranks everything; the hierarchy is §4.6 with the controller's placements below.
- No palette/typeface/dark-mode change, no new dependencies, `Clinical.*` tokens only. The card is `ClinicalCard` (22pt radius, warm surface, the existing shadow); the headline is `Clinical.headline` (serif); the card's action is an outlined chip in the grammar of the "Same as yesterday" chip — never a second filled copper button on Today; Wren is a small static avatar (`CompanionView(moment:variant: .avatar, size:)`), never a large mascot on this card.
- No SwiftData schema change. New persisted state is UserDefaults only: `grounding.enabled` (Bool, default true).
- Motion: card entrance is a one-shot opacity + 4–6 pt settle (the existing `staggeredEntrance`); no pulsing, no countdowns. Reduce Motion keeps every end state.
- Accessibility: the card is a container whose headline is a header; actions are buttons with labels; decorative Wren is hidden; 44 pt targets.
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
| Create `Hair Compass AI 5/Model/EvidencePhase.swift` | anchor, day number, week, phase label, next review |
| Create `Hair Compass AI 5/Model/PhotoCadence.swift` | monthly comparable-photo cadence |
| Create `Hair Compass AI 5/Model/GroundingCards.swift` | `GroundingCard`, `GroundingInput`, `GroundingSignals`, `GroundingCards.select` |
| Create `Hair Compass AI 5Tests/EvidencePhaseTests.swift`, `PhotoCadenceTests.swift`, `GroundingCardsTests.swift` | the three models' rules and the copy rule |
| Create `Hair Compass AI 5/Feature/CalmHorizonHeader.swift` | greeting, day/phase eyebrow, horizon path with Wren, review line |
| Create `Hair Compass AI 5/Feature/GroundingCardView.swift` | the card, its action chip, "Why this?" |
| Create `Hair Compass AI 5/Feature/EvidenceRibbon.swift` | four evidence lines |
| Modify `Hair Compass AI 5/Feature/TodayView.swift` | input assembly, page order, actions, `grounding.enabled` |
| Modify `Hair Compass AI 5/Feature/TodayTiles.swift` (`ConditionsHero`) | `showsHeader` flag |
| Modify `Hair Compass AI 5/Feature/BaselineFlow.swift` | "Daily grounding" toggle |
| Modify `Hair Compass AI 5/App/RootView.swift`, `App/LaunchPresentationState.swift`, delete `Feature/TutorialOverlay.swift`, modify `Hair Compass AI 5Tests/LaunchPresentationStateTests.swift`, `EraseAndStartOverTests.swift` (if it names the tutorial), `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift` | the tour's removal |

---

### Task 1: `EvidencePhase` and `PhotoCadence`

**Files:**
- Create: `Hair Compass AI 5/Model/EvidencePhase.swift`, `Hair Compass AI 5/Model/PhotoCadence.swift`
- Test: `Hair Compass AI 5Tests/EvidencePhaseTests.swift`, `Hair Compass AI 5Tests/PhotoCadenceTests.swift`

**Interfaces:**
- Consumes: `Treatment` (`isActive`, `slots`, `startDate`, `name`), `DailyEntry.date`, `PhotoRecord.createdAt`, `HairAnalytics.weeksElapsed(since:now:calendar:)` (`Model/Analytics.swift:60`), `ProgressReport.isMilestone(week:)` / `nextMilestone(after:)` (`Model/ProgressReport.swift:127-136`).
- Produces:
  - `struct EvidencePhase: Equatable { enum Anchor: Equatable { case treatment(name: String), record }; let anchor: Anchor; let start: Date; let dayNumber: Int; let week: Int; let label: String; let nextReviewWeek: Int; let nextReviewDate: Date; let daysToReview: Int; var isMilestoneWeek: Bool; var daysIntoWeek: Int; static func current(treatments:entries:now:calendar:) -> EvidencePhase?; static func label(forWeek:) -> String }`
  - `enum PhotoCadence { static let intervalDays = 28; enum Status: Equatable { case noBaseline, due(daysOverdue: Int), upcoming(daysUntil: Int) }; static func status(photos:now:calendar:) -> Status; static func hasPhoto(withinDays:photos:now:calendar:) -> Bool }`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/EvidencePhaseTests.swift`:

```swift
//
//  EvidencePhaseTests.swift
//  Hair Compass AI 5Tests
//
//  Where the person is in the plan, as data: the anchor (earliest active daily treatment, else
//  the first entry), the day and week, the phase word, and the next review on the 4/12/24-week
//  clock the progress report already keeps.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct EvidencePhaseTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        return c
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9))! }
    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now)! }

    @Test func anchorsOnTheEarliestActiveDailyTreatment() throws {
        let later = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                              scheduleTimes: "21:00", startDate: daysAgo(10), isActive: true)
        let earlier = Treatment(name: "Minoxidil", treatmentClass: .minoxidil, dose: "1 mL",
                                scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        let paused = Treatment(name: "Old", treatmentClass: .minoxidil, dose: "",
                               scheduleTimes: "08:00", startDate: daysAgo(200), isActive: false)
        let phase = try #require(EvidencePhase.current(treatments: [later, earlier, paused], entries: [],
                                                       now: now, calendar: calendar))
        #expect(phase.anchor == .treatment(name: "Minoxidil"))
        #expect(phase.dayNumber == 34)
        #expect(phase.week == 4)
        #expect(phase.label == "Early evidence")
        #expect(phase.nextReviewWeek == 12)
        #expect(phase.daysToReview == 84 - 33)
        #expect(phase.isMilestoneWeek)
    }

    @Test func fallsBackToTheFirstEntry() throws {
        let entries = [DailyEntry(date: daysAgo(2)), DailyEntry(date: daysAgo(9))]
        let phase = try #require(EvidencePhase.current(treatments: [], entries: entries, now: now, calendar: calendar))
        #expect(phase.anchor == .record)
        #expect(phase.dayNumber == 10)
        #expect(phase.week == 1)
        #expect(phase.label == "Building the baseline")
        #expect(phase.nextReviewWeek == 4)
        #expect(!phase.isMilestoneWeek)
    }

    @Test func nothingToAnchorOnIsNil() {
        #expect(EvidencePhase.current(treatments: [], entries: [], now: now, calendar: calendar) == nil)
    }

    @Test func labelsFollowTheReviewClock() {
        #expect(EvidencePhase.label(forWeek: 0) == "Building the baseline")
        #expect(EvidencePhase.label(forWeek: 3) == "Building the baseline")
        #expect(EvidencePhase.label(forWeek: 4) == "Early evidence")
        #expect(EvidencePhase.label(forWeek: 11) == "Early evidence")
        #expect(EvidencePhase.label(forWeek: 12) == "Assessment")
        #expect(EvidencePhase.label(forWeek: 23) == "Assessment")
        #expect(EvidencePhase.label(forWeek: 24) == "Review-ready")
        #expect(EvidencePhase.label(forWeek: 40) == "Review-ready")
    }

    @Test func daysIntoWeekCountsFromTheWeekBoundary() throws {
        let t = Treatment(name: "M", treatmentClass: .minoxidil, dose: "", scheduleTimes: "08:00",
                          startDate: daysAgo(28), isActive: true)
        let phase = try #require(EvidencePhase.current(treatments: [t], entries: [], now: now, calendar: calendar))
        #expect(phase.week == 4 && phase.daysIntoWeek == 0)
    }
}
```

Create `Hair Compass AI 5Tests/PhotoCadenceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `utest EvidencePhaseTests` then `utest PhotoCadenceTests`. Expected: build failures — the types do not exist.

- [ ] **Step 3: Write the two models**

Create `Hair Compass AI 5/Model/EvidencePhase.swift`:

```swift
//
//  EvidencePhase.swift
//  Hair Compass AI 5
//
//  Where the person is in the plan, as data. The anchor is the earliest active daily treatment
//  (the same rule ProgressReport uses), else the first entry in the record. The review clock is
//  ProgressReport's: weeks 4, 12, 24, then every 12. Nothing here judges the hair — it only
//  says how far along the record is and when the next honest read is due.
//

import Foundation

struct EvidencePhase: Equatable {
    enum Anchor: Equatable {
        case treatment(name: String)
        case record
    }

    let anchor: Anchor
    /// Start of the anchor's calendar day.
    let start: Date
    /// 1 on the start day.
    let dayNumber: Int
    let week: Int
    let label: String
    let nextReviewWeek: Int
    let nextReviewDate: Date
    let daysToReview: Int

    var isMilestoneWeek: Bool { ProgressReport.isMilestone(week: week) }
    /// 0 on the first day of the current week, 6 on the last.
    var daysIntoWeek: Int { (dayNumber - 1) - week * 7 }

    static func label(forWeek week: Int) -> String {
        switch week {
        case ..<4: return "Building the baseline"
        case 4..<12: return "Early evidence"
        case 12..<24: return "Assessment"
        default: return "Review-ready"
        }
    }

    static func current(
        treatments: [Treatment],
        entries: [DailyEntry],
        now: Date,
        calendar: Calendar
    ) -> EvidencePhase? {
        let primary = treatments
            .filter { $0.isActive && !$0.slots.isEmpty }
            .min { $0.startDate < $1.startDate }
        let anchor: Anchor
        let startDate: Date
        if let primary {
            anchor = .treatment(name: primary.name.isEmpty ? primary.treatmentClass.title : primary.name)
            startDate = primary.startDate
        } else if let first = entries.map(\.date).min() {
            anchor = .record
            startDate = first
        } else {
            return nil
        }
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        let days = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
        let week = days / 7
        let nextWeek = ProgressReport.nextMilestone(after: week)
        let nextDate = calendar.date(byAdding: .day, value: nextWeek * 7, to: start) ?? today
        let daysToReview = max(0, calendar.dateComponents([.day], from: today, to: nextDate).day ?? 0)
        return EvidencePhase(
            anchor: anchor, start: start, dayNumber: days + 1, week: week,
            label: label(forWeek: week), nextReviewWeek: nextWeek,
            nextReviewDate: nextDate, daysToReview: daysToReview
        )
    }
}
```

Create `Hair Compass AI 5/Model/PhotoCadence.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run both suites. Expected: `✔ Test run with 5 tests in 1 suite passed` and `✔ Test run with 4 tests in 1 suite passed`. If `DailyEntry(date:)` is not an initializer, use `DailyEntry()` and set `.date` — check `Models.swift:91-140` — and note it in the report.

- [ ] **Step 5: Commit**

```
EvidencePhase and PhotoCadence: where the record stands, when the next photo is due

The plan's anchor (earliest active daily treatment, else the first
entry), day and week, a phase word on the 4/12/24-week review clock, and
a monthly comparable-photo cadence that never asks earlier.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

---

### Task 2: `GroundingCards` — the deterministic card and its hierarchy

**Files:**
- Create: `Hair Compass AI 5/Model/GroundingCards.swift`
- Test: `Hair Compass AI 5Tests/GroundingCardsTests.swift`

**Interfaces:**
- Consumes: `ClinicianReviewFlag` (`Model/ClinicianReviewFlags.swift:7-13`: `id`, `title`, `detail`), `PlanAdherence.TodayPlan` / `.Occurrence` / `.Consistency` (G1), `EvidencePhase`, `PhotoCadence.Status` (Task 1), `DailyEntry.shed.rawValue`.
- Produces:
  - `struct GroundingCard: Equatable { enum Kind: String { case safety, grounding, continuation, preparation, closure, recovery, celebration, education, quiet }; enum Action: Equatable { case completePlanItem(id: String, label: String), logCheckIn, openPhotos, openPlan, prepareVisit, none }; let kind: Kind; let eyebrow: String; let headline: String; let body: String; let evidenceAnchor: String?; let primary: Action; let closure: String; let reason: String }`
  - `struct GroundingInput { var flags: [ClinicianReviewFlag]; var plan: PlanAdherence.TodayPlan; var missedYesterday: Int; var phase: EvidencePhase?; var photo: PhotoCadence.Status; var photoWithinTwoWeeks: Bool; var consistency30: PlanAdherence.Consistency?; var sheddingAboveUsual: Bool; var loggedToday: Bool }`
  - `enum GroundingSignals { static func sheddingAboveUsual(entries:now:calendar:) -> Bool; static func missedYesterday(treatments:doses:missed:now:calendar:) -> Int }`
  - `enum GroundingCards { static func select(_ input: GroundingInput) -> GroundingCard; static func daysWord(_ n: Int) -> String }`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/GroundingCardsTests.swift`:

```swift
//
//  GroundingCardsTests.swift
//  Hair Compass AI 5Tests
//
//  The card is a pure function of the record: the hierarchy (safety first, quiet last), the one
//  action, the closure, the reason — and the copy rule every card must pass.
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct GroundingCardsTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Muscat")!
        c.firstWeekday = 2
        return c
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 9, minute: 30))! }
    private func daysAgo(_ n: Int, hour: Int = 12) -> Date {
        let d = calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: d)!
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
            SideEffectLog.self, MissedDoseRecord.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func plan(open: Bool, in context: ModelContext) -> (PlanAdherence.TodayPlan, Treatment) {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        context.insert(t)
        var doses: [TreatmentDose] = []
        if !open {
            doses = [TreatmentDose(treatment: t, loggedAt: daysAgo(0, hour: 8), slot: "08:00"),
                     TreatmentDose(treatment: t, loggedAt: daysAgo(0, hour: 9), slot: "21:00")]
            doses.forEach { context.insert($0) }
        }
        return (PlanAdherence.today(treatments: [t], doses: doses, missed: [], now: now, calendar: calendar), t)
    }

    private func phase(daysAgo n: Int) -> EvidencePhase {
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "", scheduleTimes: "08:00",
                          startDate: daysAgo(n), isActive: true)
        return EvidencePhase.current(treatments: [t], entries: [], now: now, calendar: calendar)!
    }

    private func input(
        flags: [ClinicianReviewFlag] = [],
        plan: PlanAdherence.TodayPlan,
        missedYesterday: Int = 0,
        phase: EvidencePhase? = nil,
        photo: PhotoCadence.Status = .upcoming(daysUntil: 12),
        photoWithinTwoWeeks: Bool = true,
        consistency30: PlanAdherence.Consistency? = PlanAdherence.Consistency(completed: 26, expected: 30),
        sheddingAboveUsual: Bool = false,
        loggedToday: Bool = true
    ) -> GroundingInput {
        GroundingInput(flags: flags, plan: plan, missedYesterday: missedYesterday, phase: phase ?? self.phase(daysAgo: 33),
                       photo: photo, photoWithinTwoWeeks: photoWithinTwoWeeks, consistency30: consistency30,
                       sheddingAboveUsual: sheddingAboveUsual, loggedToday: loggedToday)
    }

    // MARK: Hierarchy

    @Test func safetyOutranksEverything() throws {
        let context = try makeContext()
        let (open, _) = plan(open: true, in: context)
        let flag = ClinicianReviewFlag(id: "scalpPain", title: "Scalp pain reported", detail: "Scalp pain was reported in a monthly check-in — persistent pain can be a sign of scarring alopecia, worth a prompt review.")
        let card = GroundingCards.select(input(flags: [flag], plan: open, sheddingAboveUsual: true))
        #expect(card.kind == .safety)
        #expect(card.headline == "Scalp pain reported")
        #expect(card.body == flag.detail)
        #expect(card.primary == .prepareVisit)
    }

    @Test func higherSheddingGroundsBeforeTheDueAction() throws {
        let context = try makeContext()
        let (open, t) = plan(open: true, in: context)
        let card = GroundingCards.select(input(plan: open, sheddingAboveUsual: true))
        #expect(card.kind == .grounding)
        #expect(card.headline == "One observation is not a trend")
        if case .completePlanItem(let id, let label) = card.primary {
            #expect(id == open.occurrences[0].id)
            #expect(label.contains(t.name))
        } else {
            Issue.record("the due action stays the one thing to do")
        }
    }

    @Test func dueActionBecomesContinuation() throws {
        let context = try makeContext()
        let (open, _) = plan(open: true, in: context)
        let card = GroundingCards.select(input(plan: open))
        #expect(card.kind == .continuation)
        if case .completePlanItem = card.primary {} else { Issue.record("continuation carries the due item") }
        #expect(card.evidenceAnchor == "Next review in 51 days")
        #expect(card.closure == "No photo is needed today.")
    }

    @Test func photoDueNowIsPreparation() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done, photo: .due(daysOverdue: 3)))
        #expect(card.kind == .preparation)
        #expect(card.primary == .openPhotos)
        #expect(card.headline == "A comparable photo is due")
    }

    @Test func missingBaselineIsAnInvitationNotAnOverdueTask() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done, photo: .noBaseline))
        #expect(card.kind == .preparation)
        #expect(card.headline == "A baseline photo anchors everything")
        #expect(card.closure == "Whenever you are ready — it does not have to be today.")
    }

    @Test func reviewWithinAWeekIsPreparation() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done, phase: phase(daysAgo: 80), photoWithinTwoWeeks: false))
        #expect(card.kind == .preparation)
        #expect(card.headline == "Your week 12 review is approaching")
        #expect(card.primary == .openPhotos)
    }

    @Test func completedPlanClosesTheDay() throws {
        let context = try makeContext()
        let (done, _) = plan(open: false, in: context)
        let card = GroundingCards.select(input(plan: done))
        #expect(card.kind == .closure)
        #expect(card.headline == "Your plan is complete for today")
        #expect(card.primary == .none)
        #expect(card.closure == "Nothing else needs to be checked today.")
    }

    @Test func missedYesterdayWithNothingDueYetIsRecovery() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(33), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, missedYesterday: 1))
        #expect(card.kind == .recovery)
        #expect(card.headline == "Today is a clean place to restart")
        #expect(card.body.contains("26 of 30"))
        #expect(!card.body.lowercased().contains("double"))
    }

    @Test func milestoneWeekIsRecognisedOnItsFirstTwoDays() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(29), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 29)))
        #expect(card.kind == .celebration)
        #expect(card.headline == "Four weeks of evidence, stored")
        let later = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 31)))
        #expect(later.kind != .celebration)
    }

    @Test func earlyWeeksTeachTheHorizon() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(8), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 8), loggedToday: false))
        #expect(card.kind == .education)
        #expect(card.headline == "You are building the baseline")
        #expect(card.primary == .logCheckIn)
    }

    @Test func quietDayGivesPermissionToClose() throws {
        let context = try makeContext()
        let evening = Treatment(name: "Finasteride", treatmentClass: .finasteride, dose: "1 mg",
                                scheduleTimes: "21:00", startDate: daysAgo(60), isActive: true)
        context.insert(evening)
        let upcomingOnly = PlanAdherence.today(treatments: [evening], doses: [], missed: [], now: now, calendar: calendar)
        let card = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 60)))
        #expect(card.kind == .quiet)
        #expect(card.primary == .none)
        #expect(card.closure == "You can close the app.")
        let unlogged = GroundingCards.select(input(plan: upcomingOnly, phase: phase(daysAgo: 60), loggedToday: false))
        #expect(unlogged.primary == .logCheckIn)
    }

    // MARK: Copy rule

    @Test func everyCardKeepsTheFramingRule() throws {
        let context = try makeContext()
        let (open, _) = plan(open: true, in: context)
        let (done, _) = plan(open: false, in: context)
        let flag = ClinicianReviewFlag(id: "heavyShed", title: "Heavy shedding most days", detail: "Shedding was logged Heavy on 8 of the last 14 days.")
        let cards = [
            GroundingCards.select(input(flags: [flag], plan: open)),
            GroundingCards.select(input(plan: open, sheddingAboveUsual: true)),
            GroundingCards.select(input(plan: open)),
            GroundingCards.select(input(plan: done, photo: .due(daysOverdue: 0))),
            GroundingCards.select(input(plan: done, photo: .noBaseline)),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 80), photoWithinTwoWeeks: false)),
            GroundingCards.select(input(plan: done)),
            GroundingCards.select(input(plan: open, missedYesterday: 2)),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 28))),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 5), loggedToday: false)),
            GroundingCards.select(input(plan: done, phase: phase(daysAgo: 60)))
        ]
        let banned = ["diagnos", "cure", "you have", "prescrib", "you should", "you must", "start taking",
                      "anxious", "worried about", "failed", "poor", "getting worse", "!"]
        for card in cards {
            #expect(card.headline.split(separator: " ").count <= 10, card.headline)
            #expect(card.body.split(separator: " ").count <= 55, card.body)
            #expect(!card.closure.isEmpty && !card.reason.isEmpty, card.headline)
            for text in [card.headline, card.body, card.closure, card.reason, card.evidenceAnchor ?? ""] {
                let lower = text.lowercased()
                for word in banned { #expect(!lower.contains(word), "\(card.kind): \(text) contains \(word)") }
            }
        }
    }

    @Test func daysWordReadsNaturally() {
        #expect(GroundingCards.daysWord(0) == "today")
        #expect(GroundingCards.daysWord(1) == "tomorrow")
        #expect(GroundingCards.daysWord(8) == "in 8 days")
    }

    // MARK: Signals

    @Test func sheddingAboveUsualNeedsARangeToBeAbove() {
        var entries: [DailyEntry] = []
        for n in 2...7 {
            let e = DailyEntry()
            e.date = daysAgo(n)
            e.shed = .normal
            entries.append(e)
        }
        let yesterday = DailyEntry()
        yesterday.date = daysAgo(1)
        yesterday.shed = .heavy
        #expect(GroundingSignals.sheddingAboveUsual(entries: entries + [yesterday], now: now, calendar: calendar))
        yesterday.shed = .normal
        #expect(!GroundingSignals.sheddingAboveUsual(entries: entries + [yesterday], now: now, calendar: calendar))
        #expect(!GroundingSignals.sheddingAboveUsual(entries: [yesterday], now: now, calendar: calendar))
    }

    @Test func missedYesterdayCountsMissedAndSkipped() throws {
        let context = try makeContext()
        let t = Treatment(name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
                          scheduleTimes: "08:00,21:00", startDate: daysAgo(33), isActive: true)
        context.insert(t)
        let skip = MissedDoseRecord(treatment: t, date: daysAgo(1), slot: "08:00", reason: .forgot)
        context.insert(skip)
        #expect(GroundingSignals.missedYesterday(treatments: [t], doses: [], missed: [skip], now: now, calendar: calendar) == 2)
        let dose = TreatmentDose(treatment: t, loggedAt: daysAgo(1, hour: 21), slot: "21:00")
        context.insert(dose)
        #expect(GroundingSignals.missedYesterday(treatments: [t], doses: [dose], missed: [skip], now: now, calendar: calendar) == 1)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `utest GroundingCardsTests`. Expected: build failure — `GroundingCards` not found.

- [ ] **Step 3: Write the model**

Create `Hair Compass AI 5/Model/GroundingCards.swift`:

```swift
//
//  GroundingCards.swift
//  Hair Compass AI 5
//
//  The deterministic Daily Grounding card (spec §4, §10). One card per state, chosen by the
//  spec's hierarchy — safety, then a real shedding observation, then the action that is due,
//  then a photo or review that is approaching, then closure, recovery, a milestone, the early
//  horizon, and finally a quiet day. Every card acknowledges, anchors in the record, points at
//  one action at most, and closes by saying what needs no attention. Pure: the same record
//  produces the same card all day; it changes only when the record does. The server-generated
//  card (spec §4.5) arrives later and falls back to this one.
//

import Foundation

struct GroundingCard: Equatable {
    enum Kind: String {
        case safety, grounding, continuation, preparation, closure, recovery, celebration, education, quiet
    }

    enum Action: Equatable {
        case completePlanItem(id: String, label: String)
        case logCheckIn
        case openPhotos
        case openPlan
        case prepareVisit
        case none
    }

    let kind: Kind
    let eyebrow: String
    let headline: String
    let body: String
    let evidenceAnchor: String?
    let primary: Action
    let closure: String
    /// Shown behind "Why this?": the one fact in the record that selected this card.
    let reason: String
}

struct GroundingInput {
    var flags: [ClinicianReviewFlag]
    var plan: PlanAdherence.TodayPlan
    var missedYesterday: Int
    var phase: EvidencePhase?
    var photo: PhotoCadence.Status
    var photoWithinTwoWeeks: Bool
    var consistency30: PlanAdherence.Consistency?
    var sheddingAboveUsual: Bool
    var loggedToday: Bool
}

enum GroundingSignals {
    /// True when yesterday's shed band is strictly above every one of the (up to six) entries
    /// before it, and at least three such entries exist — a conservative "above your usual
    /// range", never a trend claim.
    static func sheddingAboveUsual(entries: [DailyEntry], now: Date, calendar: Calendar) -> Bool {
        guard let yesterdayDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return false }
        let bounds = HairAnalytics.dayBounds(for: yesterdayDay, calendar: calendar)
        let sorted = entries.sorted { $0.date < $1.date }
        guard let yesterday = sorted.last(where: { bounds.contains($0.date) }) else { return false }
        let prior = sorted.filter { $0.date < bounds.lowerBound }.suffix(6)
        guard prior.count >= 3 else { return false }
        let usualMax = prior.map { $0.shed.rawValue }.max() ?? 0
        return yesterday.shed.rawValue > usualMax
    }

    /// Yesterday's occurrences that were missed or skipped — the recovery card's trigger.
    static func missedYesterday(
        treatments: [Treatment], doses: [TreatmentDose], missed: [MissedDoseRecord],
        now: Date, calendar: Calendar
    ) -> Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return 0 }
        return treatments
            .flatMap {
                PlanAdherence.occurrences(treatment: $0, doses: doses, missed: missed,
                                          from: yesterday, through: yesterday, now: now, calendar: calendar)
            }
            .filter { $0.state == .missed || $0.state == .skipped }
            .count
    }
}

enum GroundingCards {

    static func daysWord(_ n: Int) -> String {
        switch n {
        case ...0: return "today"
        case 1: return "tomorrow"
        default: return "in \(n) days"
        }
    }

    private static func reviewAnchor(_ phase: EvidencePhase?) -> String? {
        guard let phase else { return nil }
        return phase.daysToReview == 0 ? "Review due today" : "Next review in \(phase.daysToReview) days"
    }

    private static func photoClosure(_ photo: PhotoCadence.Status) -> String {
        switch photo {
        case .noBaseline: return "A baseline photo can wait for a day with good light."
        case .due: return "A comparable photo is due when you have a moment."
        case .upcoming(let days): return days <= 3 ? "Your next comparable photo is \(daysWord(days))." : "No photo is needed today."
        }
    }

    private static func dueAction(_ plan: PlanAdherence.TodayPlan, loggedToday: Bool) -> GroundingCard.Action {
        if let next = plan.nextOpen {
            let name = next.treatment.name.isEmpty ? next.treatment.treatmentClass.title : next.treatment.name
            return .completePlanItem(id: next.id, label: "Mark \(name) complete")
        }
        return loggedToday ? .none : .logCheckIn
    }

    static func select(_ input: GroundingInput) -> GroundingCard {
        let phase = input.phase
        let dayLine = phase.map { "Day \($0.dayNumber)" } ?? "Today"

        // 1. Safety: a clinician-review rule fired. No motivation, one care step.
        if let flag = input.flags.first {
            return GroundingCard(
                kind: .safety, eyebrow: "Worth a clinician's look",
                headline: flag.title, body: flag.detail, evidenceAnchor: nil,
                primary: .prepareVisit,
                closure: "This note replaces today's encouragement. Your plan continues unless your clinician says otherwise.",
                reason: "A pattern in your record met the clinician-review rule \"\(flag.id)\"."
            )
        }

        // 2. (An explicit concern from "I'm worried" arrives with sub-project G4.)

        // 3. Grounding: yesterday's shedding sat above the recent range.
        if input.sheddingAboveUsual {
            return GroundingCard(
                kind: .grounding, eyebrow: "Today's grounding",
                headline: "One observation is not a trend",
                body: "You recorded more shedding yesterday than in the days before it. Shedding varies between wash days, so Hair Compass waits for a repeated pattern before reading anything into it.",
                evidenceAnchor: reviewAnchor(phase),
                primary: dueAction(input.plan, loggedToday: input.loggedToday),
                closure: "You logged it. That is enough for today.",
                reason: "Yesterday's shedding band was above every entry in the six days before it."
            )
        }

        // 4. Continuation: an action is due now.
        if let next = input.plan.nextOpen, next.state == .due {
            let name = next.treatment.name.isEmpty ? next.treatment.treatmentClass.title : next.treatment.name
            return GroundingCard(
                kind: .continuation, eyebrow: "Today's grounding",
                headline: "One step today keeps the record honest",
                body: "\(dayLine) of your plan. Your next planned action is \(name). Consistent records are what make the next review readable.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .completePlanItem(id: next.id, label: "Mark \(name) complete"),
                closure: photoClosure(input.photo),
                reason: "\(name) is due and not yet recorded."
            )
        }

        // 5. Preparation: a comparable photo is due, a baseline is pending, or a review is close.
        switch input.photo {
        case .due(let overdue):
            return GroundingCard(
                kind: .preparation, eyebrow: "Coming up",
                headline: "A comparable photo is due",
                body: "It has been \(PhotoCadence.intervalDays + overdue) days since your last photo. Same light, same parting, same distance keeps the comparison fair.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .openPhotos,
                closure: "After that, nothing else is needed today.",
                reason: "Your last photo is \(PhotoCadence.intervalDays + overdue) days old; the cadence is every \(PhotoCadence.intervalDays) days."
            )
        case .noBaseline:
            return GroundingCard(
                kind: .preparation, eyebrow: "Coming up",
                headline: "A baseline photo anchors everything",
                body: "There is no baseline photo yet. One photo in good light, taken the same way each time, is what every later comparison is measured against.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .openPhotos,
                closure: "Whenever you are ready — it does not have to be today.",
                reason: "The record has no photo yet."
            )
        case .upcoming:
            break
        }
        if let phase, phase.daysToReview <= 7 {
            let headline = phase.nextReviewWeek == 4 ? "Your first review is approaching" : "Your week \(phase.nextReviewWeek) review is approaching"
            return GroundingCard(
                kind: .preparation, eyebrow: "Coming up",
                headline: headline,
                body: "You have collected \(phase.week) weeks of plan and shedding records. A comparable photo before the review completes the checkpoint.",
                evidenceAnchor: "Review \(daysWord(phase.daysToReview))",
                primary: input.photoWithinTwoWeeks ? .none : .openPhotos,
                closure: input.photoWithinTwoWeeks ? "Your recent photo already covers it. Nothing else is needed today." : "One photo this week is the whole preparation.",
                reason: "The week \(phase.nextReviewWeek) review is \(daysWord(phase.daysToReview))."
            )
        }

        // 6. Closure: every planned action today is recorded.
        if input.plan.isComplete {
            return GroundingCard(
                kind: .closure, eyebrow: "Today is done",
                headline: "Your plan is complete for today",
                body: "You showed up. Today is now part of the evidence you are building, and your next useful check is tomorrow.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .none,
                closure: "Nothing else needs to be checked today.",
                reason: "Every planned action today is recorded or skipped with a reason."
            )
        }

        // 7. Recovery: something was missed yesterday and today has not started yet.
        if input.missedYesterday > 0 {
            let rhythm = input.consistency30.map { "Over the last 30 days you completed \($0.completed) of \($0.expected) planned actions. " } ?? ""
            return GroundingCard(
                kind: .recovery, eyebrow: "Today's grounding",
                headline: "Today is a clean place to restart",
                body: "One missed action does not erase the record you have built. \(rhythm)Resume your normal plan today unless your clinician instructed otherwise.",
                evidenceAnchor: reviewAnchor(phase),
                primary: input.plan.nextOpen.map { .completePlanItem(id: $0.id, label: "Mark \($0.treatment.name.isEmpty ? $0.treatment.treatmentClass.title : $0.treatment.name) complete") } ?? .openPlan,
                closure: "Nothing needs catching up. Today's step is the only one that counts now.",
                reason: "\(input.missedYesterday) planned action\(input.missedYesterday == 1 ? " was" : "s were") not recorded yesterday."
            )
        }

        // 8. Recognition: a milestone week, on its first two days only.
        if let phase, phase.isMilestoneWeek, phase.daysIntoWeek <= 1 {
            let weeks: String
            switch phase.week {
            case 4: weeks = "Four"
            case 12: weeks = "Twelve"
            case 24: weeks = "Twenty-four"
            default: weeks = "\(phase.week)"
            }
            return GroundingCard(
                kind: .celebration, eyebrow: "Stored evidence",
                headline: "\(weeks) weeks of evidence, stored",
                body: "Your record now covers \(phase.week) weeks of plan and shedding entries. This is stored evidence, not a verdict on your hair — the review reads it.",
                evidenceAnchor: reviewAnchor(phase),
                primary: .openPlan,
                closure: "Nothing else is needed today.",
                reason: "Week \(phase.week) is a review milestone on the plan's clock."
            )
        }

        // 9. Education: too early to judge.
        if let phase, phase.week < 4 {
            return GroundingCard(
                kind: .education, eyebrow: "Today's grounding",
                headline: "You are building the baseline",
                body: "\(dayLine) of your plan. It is too early to judge visible change; consistent records make the first comparison at week four more reliable.",
                evidenceAnchor: reviewAnchor(phase),
                primary: input.loggedToday ? .none : .logCheckIn,
                closure: "No photo is needed today.",
                reason: "The plan is in its first four weeks."
            )
        }

        // 10. Quiet day.
        return GroundingCard(
            kind: .quiet, eyebrow: "Today's grounding",
            headline: "You are allowed to have a normal day",
            body: "No unusual pattern or plan action needs your attention right now. Hair Compass will say when something meaningful is due.",
            evidenceAnchor: reviewAnchor(phase),
            primary: input.loggedToday ? .none : .logCheckIn,
            closure: input.loggedToday ? "You can close the app." : "The check-in is the whole day.",
            reason: "Nothing in the record met an earlier rule today."
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `utest GroundingCardsTests`. Expected: `✔ Test run with 15 tests in 1 suite passed`. Two expectations depend on the fixture arithmetic: `dueActionBecomesContinuation` expects "Next review in 51 days" (day 34 of a treatment started 33 days ago → week 4 → next review week 12 → 84 − 33 = 51) and `reviewWithinAWeekIsPreparation` uses a treatment started 80 days ago (week 11, review at day 84 → 4 days away). If an assertion is off by one, the engine's day arithmetic — not the test — is wrong.

- [ ] **Step 5: Commit**

```
GroundingCards: the deterministic Daily Grounding card

Ten states in the spec's order — safety, higher shedding, the due
action, a photo or review coming up, closure, recovery, a milestone, the
early horizon, a quiet day — each with a headline under ten words, a
body under fifty-five, one action at most, a closure sentence and a
reason for "Why this?". Signals for shedding-above-usual and yesterday's
missed actions. Tests pin the hierarchy and the framing rule.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

---

### Task 3: The three views — header, card, ribbon

**Files:**
- Create: `Hair Compass AI 5/Feature/CalmHorizonHeader.swift`, `Hair Compass AI 5/Feature/GroundingCardView.swift`, `Hair Compass AI 5/Feature/EvidenceRibbon.swift`

**Interfaces:**
- Consumes: `EvidencePhase`, `PhotoCadence.Status`, `GroundingCard`, `PlanAdherence.Consistency`, `CompanionView(moment:variant:size:)` (`Feature/Companion/CompanionView.swift:9`), `CompanionMoment.resting`, `ClinicalCard`, `Eyebrow`, `Clinical.*`, `.clinicalPressable`, `.minimumHitTarget()`.
- Produces: `CalmHorizonHeader(greeting:phase:onOpenBaseline:)`, `GroundingCardView(card:onPrimary:)` with identifiers `groundingCard`, `groundingHeadline`, `groundingAction`, `groundingWhy`, `groundingReason`; `EvidenceRibbon(weekSummary:consistency30:photo:phase:)` with identifier `evidenceRibbon`.

- [ ] **Step 1: Write the header**

Create `Hair Compass AI 5/Feature/CalmHorizonHeader.swift`:

```swift
//
//  CalmHorizonHeader.swift
//  Hair Compass AI 5
//
//  Where the person is in the plan, drawn as a quiet path: Baseline — You are here — Review.
//  Wren sits on the current position instead of floating as an unrelated button. The answer is
//  ahead in time; the header says how far. Nothing here is a score.
//

import SwiftUI

struct CalmHorizonHeader: View {
    let greeting: String
    let phase: EvidencePhase?
    var onOpenBaseline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                        .font(Clinical.eyebrow(10)).tracking(1.4).foregroundStyle(Clinical.secondary)
                    Text(greeting).font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
                }
                Spacer()
                Button(action: onOpenBaseline) {
                    Image(systemName: "person.circle")
                        .font(Clinical.caption(22))
                        .foregroundStyle(Clinical.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile and settings")
            }
            if let phase {
                Text(phaseEyebrow(phase))
                    .font(Clinical.eyebrow(11)).tracking(1.4)
                    .foregroundStyle(Clinical.secondary)
                    .accessibilityAddTraits(.isHeader)
                horizon(phase)
                Text(reviewLine(phase))
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calmHorizon")
    }

    private func phaseEyebrow(_ phase: EvidencePhase) -> String {
        "Day \(phase.dayNumber) · \(phase.label)".uppercased()
    }

    private func reviewLine(_ phase: EvidencePhase) -> String {
        switch phase.daysToReview {
        case 0: return "Your next meaningful review is today."
        case 1: return "Your next meaningful review is tomorrow."
        default: return "Your next meaningful review is in \(phase.daysToReview) days."
        }
    }

    private func horizon(_ phase: EvidencePhase) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Rectangle().fill(Clinical.hairline).frame(height: 1)
                HStack {
                    Circle().fill(Clinical.sage).frame(width: 10, height: 10)
                    Spacer()
                    ZStack {
                        Circle().strokeBorder(Clinical.accent, lineWidth: 1.5).frame(width: 36, height: 36)
                        CompanionView(moment: .resting, variant: .avatar, size: 30)
                    }
                    Spacer()
                    Circle().strokeBorder(Clinical.hairline, lineWidth: 1.5)
                        .background(Circle().fill(Clinical.canvas))
                        .frame(width: 10, height: 10)
                }
            }
            HStack {
                Text("Baseline")
                Spacer()
                Text("You are here")
                Spacer()
                Text("Week \(phase.nextReviewWeek) review")
            }
            .font(Clinical.caption(10.5))
            .foregroundStyle(Clinical.tertiary)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Baseline behind you, you are here, week \(phase.nextReviewWeek) review ahead")
    }
}
```

- [ ] **Step 2: Write the card**

Create `Hair Compass AI 5/Feature/GroundingCardView.swift`:

```swift
//
//  GroundingCardView.swift
//  Hair Compass AI 5
//
//  The Daily Grounding card as a reassuring note, not a dashboard tile: eyebrow, a small Wren
//  avatar, a serif headline, two or three sentences, an optional anchor from the record, one
//  action rendered as an outlined chip (never a second filled button on Today), the closure
//  line, and "Why this?" which reveals the one fact that chose the card.
//

import SwiftUI

struct GroundingCardView: View {
    let card: GroundingCard
    var onPrimary: (GroundingCard.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsReason = false

    private var actionLabel: String? {
        switch card.primary {
        case .completePlanItem(_, let label): return label
        case .logCheckIn: return "Log today's check-in"
        case .openPhotos: return "Open photos"
        case .openPlan: return "See the evidence path"
        case .prepareVisit: return "Prepare your visit notes"
        case .none: return nil
        }
    }

    private var actionSymbol: String {
        switch card.primary {
        case .completePlanItem: return "circle"
        case .logCheckIn: return "square.and.pencil"
        case .openPhotos: return "camera"
        case .openPlan: return "point.topleft.down.curvedto.point.bottomright.up"
        case .prepareVisit: return "doc.text"
        case .none: return ""
        }
    }

    var body: some View {
        ClinicalCard(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CompanionView(moment: .resting, variant: .avatar, size: 28)
                    Eyebrow(text: card.eyebrow, color: card.kind == .safety ? Clinical.warning : Clinical.secondary)
                }
                Text(card.headline)
                    .font(Clinical.headline(22, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("groundingHeadline")
                Text(card.body)
                    .font(Clinical.body(14.5))
                    .foregroundStyle(Clinical.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if let anchor = card.evidenceAnchor {
                    Text(anchor)
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                        .monospacedDigit()
                }
                if let actionLabel {
                    Button { onPrimary(card.primary) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: actionSymbol).font(Clinical.body(12, weight: .medium))
                            Text(actionLabel).font(Clinical.body(13, weight: .medium))
                        }
                        .foregroundStyle(Clinical.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Clinical.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.clinicalPressable)
                    .minimumHitTarget()
                    .accessibilityIdentifier("groundingAction")
                }
                Text(card.closure)
                    .font(Clinical.caption(12.5))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(showsReason ? "Hide" : "Why this?") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsReason.toggle() }
                    }
                    .font(Clinical.body(12, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityIdentifier("groundingWhy")
                    Spacer(minLength: 0)
                }
                if showsReason {
                    Text(card.reason)
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        .accessibilityIdentifier("groundingReason")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("groundingCard")
    }
}
```

- [ ] **Step 3: Write the ribbon**

Create `Hair Compass AI 5/Feature/EvidenceRibbon.swift`:

```swift
//
//  EvidenceRibbon.swift
//  Hair Compass AI 5
//
//  Four quiet lines of supporting evidence — this week, the last thirty days, the next photo,
//  the next review. Numbers here are subordinate to the decision above them; none is a score.
//

import SwiftUI

struct EvidenceRibbon: View {
    let weekSummary: PlanAdherence.Consistency?
    let consistency30: PlanAdherence.Consistency?
    let photo: PhotoCadence.Status
    let phase: EvidencePhase?

    private var weekLine: String {
        weekSummary.map { "\($0.completed) of \($0.expected) planned actions" } ?? "No planned actions"
    }

    private var monthLine: String {
        consistency30.map { "\($0.percent)% · \($0.completed) of \($0.expected)" } ?? "Not enough planned actions yet"
    }

    private var photoLine: String {
        switch photo {
        case .noBaseline: return "Baseline pending"
        case .due: return "Due now"
        case .upcoming(let days): return days == 1 ? "Tomorrow" : "In \(days) days"
        }
    }

    private var reviewLine: String {
        guard let phase else { return "—" }
        switch phase.daysToReview {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(phase.daysToReview) days"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Your evidence")
            VStack(spacing: 0) {
                row("This week", weekLine)
                Divider().overlay(Clinical.hairline)
                row("Last 30 days", monthLine)
                Divider().overlay(Clinical.hairline)
                row("Next photo", photoLine)
                Divider().overlay(Clinical.hairline)
                row("Next review", reviewLine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evidenceRibbon")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Clinical.body(13, weight: .medium))
                .foregroundStyle(Clinical.ink)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error:'
```

Expected: no output. If `Clinical.canvas` or `Clinical.warning` is named differently, use the page-background token `.clinicalScreen()` relies on and the existing warning token from `Design/Clinical.swift:21-30`, and say so in the report.

- [ ] **Step 5: Commit**

```
Calm Horizon header, Daily Grounding card, evidence ribbon

A path from Baseline through Wren's position to the next review; the
card as a reassuring note with a serif headline, one outlined action,
a closure line and "Why this?"; four quiet lines of evidence. Rendering
only — Today wires them next.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

---

### Task 4: Today's new order, the grounding switch, and the tour's removal

**Files:**
- Modify: `Hair Compass AI 5/Feature/TodayView.swift` (header `:1-44`, computed state, body `:127-215`, sheets, `greeting` `:456`)
- Modify: `Hair Compass AI 5/Feature/TodayTiles.swift` (`ConditionsHero` `:18-70`, `content` `:217-235`)
- Modify: `Hair Compass AI 5/Feature/BaselineFlow.swift` (after `replayRow` in the form, `:55`)
- Modify: `Hair Compass AI 5/App/RootView.swift` (`:84-85`, `:110`, `:168`, `:234-248`, `:322-330`, `:422-426`, the `TodayView(...)` construction)
- Modify: `Hair Compass AI 5/App/LaunchPresentationState.swift`
- Delete: `Hair Compass AI 5/Feature/TutorialOverlay.swift`
- Modify: `Hair Compass AI 5Tests/LaunchPresentationStateTests.swift`, `Hair Compass AI 5Tests/EraseAndStartOverTests.swift` (only if it references the tutorial flag)
- Modify: `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–3, `TodayPlanSection` (G1), `ClinicianReviewFlags.evaluate(progressCheckIns:entries:triggers:sideEffects:now:calendar:)` (`Model/ClinicianReviewFlags.swift:37`), `DoseRepository.log`, `ExportSheet()` (`Feature/ExportSheet.swift:7`, presented as `TrendsView.swift:184` does).
- Produces: `TodayView.onOpenPhotos: (() -> Void)?`; `ConditionsHero.showsHeader: Bool = true`; `@AppStorage("grounding.enabled")`; no `.tutorial` surface.

- [ ] **Step 1: Write the failing UI test**

Append inside the `Hair_Compass_AI_5UITests` class:

```swift
    /// Today opens on the horizon and one grounding card; "Why this?" reveals the reason.
    @MainActor
    func testGroundingCardExplainsItself() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL"]
        app.launch()
        XCTAssertTrue(app.otherElements["calmHorizon"].waitForExistence(timeout: 10), "the horizon header leads the page")
        let card = app.otherElements["groundingCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 4), "one grounding card follows it")
        app.buttons["groundingWhy"].tap()
        XCTAssertTrue(app.staticTexts["groundingReason"].waitForExistence(timeout: 4), "Why this? shows the reason")
        XCTAssertFalse(app.buttons["tutorialSkip"].exists, "the card tour is gone")
    }
```

In `testOpenMyPlanLandsOnThePlanTab`, delete the two lines that wait for and tap `tutorialSkip` (and their comment).

- [ ] **Step 2: Run the new test to verify it fails**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests/Hair_Compass_AI_5UITests/testGroundingCardExplainsItself" 2>&1 | grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" | tail -4
```

Expected: `failed` on "the horizon header leads the page".

- [ ] **Step 3: The hero's header flag**

In `Hair Compass AI 5/Feature/TodayTiles.swift`, `ConditionsHero`: add `var showsHeader: Bool = true` after `let greeting: String`. In `content` (`:217-235`), wrap the date/greeting/profile `HStack(alignment: .top) { … }` in `if showsHeader { … }`. Nothing else in the hero changes.

- [ ] **Step 4: Today**

In `Hair Compass AI 5/Feature/TodayView.swift`:

(a) Properties: after `var onOpenPlan`, add `var onOpenPhotos: (() -> Void)? = nil`. Add `@AppStorage("grounding.enabled") private var groundingEnabled = true` and `@State private var showExport = false`. Add `@Query(sort: \MissedDoseRecord.date) private var missedDoses` only if G1 did not already add it.

(b) Computed state — add:

```swift
    private var evidencePhase: EvidencePhase? {
        EvidencePhase.current(treatments: treatments, entries: entries, now: .now, calendar: calendar)
    }
    private var photoStatus: PhotoCadence.Status {
        PhotoCadence.status(photos: photos, now: .now, calendar: calendar)
    }
    private var consistency30: PlanAdherence.Consistency? {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return nil }
        return PlanAdherence.consistency(treatments: treatments, doses: doses, missed: missedDoses,
                                         from: start, through: today, now: .now, calendar: calendar)
    }
    private var groundingCard: GroundingCard {
        GroundingCards.select(GroundingInput(
            flags: ClinicianReviewFlags.evaluate(
                progressCheckIns: progressCheckIns, entries: entries, triggers: triggers,
                sideEffects: sideEffectLogs, now: .now, calendar: calendar
            ),
            plan: todayPlan,
            missedYesterday: GroundingSignals.missedYesterday(
                treatments: treatments, doses: doses, missed: missedDoses, now: .now, calendar: calendar
            ),
            phase: evidencePhase,
            photo: photoStatus,
            photoWithinTwoWeeks: PhotoCadence.hasPhoto(withinDays: 14, photos: photos, now: .now, calendar: calendar),
            consistency30: consistency30,
            sheddingAboveUsual: GroundingSignals.sheddingAboveUsual(entries: entries, now: .now, calendar: calendar),
            loggedToday: todayEntry != nil
        ))
    }
```

(c) Body — the new order inside the `ScrollView`'s outer `VStack(alignment: .leading, spacing: 0)`:

```swift
                VStack(alignment: .leading, spacing: 16) {
                    CalmHorizonHeader(greeting: greeting, phase: evidencePhase, onOpenBaseline: onOpenBaseline)
                        .staggeredEntrance(index: 0)
                    if groundingEnabled {
                        GroundingCardView(card: groundingCard, onPrimary: performGroundingAction)
                            .staggeredEntrance(index: 1)
                    }
                    TodayPlanSection(/* unchanged G1 arguments */)
                        .staggeredEntrance(index: 2)
                    EvidenceRibbon(weekSummary: weekSummary, consistency30: consistency30,
                                   photo: photoStatus, phase: evidencePhase)
                        .staggeredEntrance(index: 3)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ConditionsHero(/* unchanged arguments */, showsHeader: false /* after greeting: */)
                    .staggeredEntrance(index: 4)
                    .padding(.top, 20)
                if showsReminderNudge { /* unchanged */ }
                VStack(alignment: .leading, spacing: 16) {
                    CompassRingsCard(/* unchanged */).staggeredEntrance(index: 5)
                    TodayTileGrid(/* unchanged */)
                    insightCard.staggeredEntrance(index: 9)
                    StrandDivider()
                    learnFootnote.staggeredEntrance(index: 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                PageCloser()
                statusCaption /* unchanged */
```

Pass `showsHeader: false` in the hero's memberwise order (directly after `greeting:`). The `.animation(.easeOut(duration: 0.25), value: showsReminderNudge)` stays on the container it is on today.

(d) The action:

```swift
    private func performGroundingAction(_ action: GroundingCard.Action) {
        switch action {
        case .completePlanItem(let id, _):
            guard let occurrence = todayPlan.occurrences.first(where: { $0.id == id }) else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            _ = try? DoseRepository(context: context).log(treatment: occurrence.treatment, slot: occurrence.slot)
        case .logCheckIn:
            showLog = true
        case .openPhotos:
            onOpenPhotos?()
        case .openPlan:
            onOpenPlan?()
        case .prepareVisit:
            showExport = true
        case .none:
            break
        }
    }
```

and `.sheet(isPresented: $showExport) { ExportSheet() }` next to the other sheets.

(e) Delete the `HC_CELEBRATE` block in `onAppear` and stop presenting the celebration: remove `pendingReward`, `celebrationReward`, `presentPendingReward()`, the `.sheet(item: $celebrationReward)` and the two `onDismiss: presentPendingReward` arguments (the log sheets keep `onSaved:` — pass `onSaved: { _ in }`). If `CheckInCelebration` is then referenced nowhere (grep `CheckInCelebration` across the app target), delete `Hair Compass AI 5/Feature/CheckInCelebration.swift`; if something else still uses it, leave it and say so.

- [ ] **Step 5: RootView and the tour**

In `Hair Compass AI 5/App/RootView.swift`:
- Pass the new callback where `TodayView(...)` is constructed: `onOpenPhotos: { tab = .photos }` (next to `onOpenPlan`).
- Delete `@AppStorage("hasSeenTutorial")` and `@State private var showTutorial` (`:84-85`), the `hasSeenTutorial: !showTutorial` reducer input (`:110`), the `hasSeenTutorial = false` line in the erase path (`:168`), the whole `.overlay { if launchPresentation.surface == .tutorial { … } }` block with its comment (`:234-248`), the tutorial trigger (`:328-330`: the `if !showOnboarding, profile?.hasOnboarded == true, !hasSeenTutorial, !forcingRitual { showTutorial = true }` and `forcingRitual` if it is now unused), `!showTutorial` from the ritual roll condition (`:338`) and from the foreground re-roll (`:518`), and `if !hasSeenTutorial { showTutorial = true }` in onboarding's `onFinish` (`:425`).
- In `Hair Compass AI 5/App/LaunchPresentationState.swift`: remove `case tutorial`, `var hasSeenTutorial`, and the `else if !input.hasSeenTutorial { surface = .tutorial }` branch. Update `Hair Compass AI 5Tests/LaunchPresentationStateTests.swift` to drop the tutorial input and any test that asserted `.tutorial` (keep the ordering tests for the remaining surfaces). If `EraseAndStartOverTests` names `hasSeenTutorial`, drop that assertion.
- `git rm -q "Hair Compass AI 5/Feature/TutorialOverlay.swift"`; then `grep -rn 'TutorialOverlay\|hasSeenTutorial\|tutorialSkip\|tutorialNext' --include='*.swift' "Hair Compass AI 5" "Hair Compass AI 5Tests" "Hair Compass AI 5UITests"` must print nothing.

- [ ] **Step 6: The grounding switch in Profile**

In `Hair Compass AI 5/Feature/BaselineFlow.swift`, add `@AppStorage("grounding.enabled") private var groundingEnabled = true` and, directly after `replayRow` in the form, a field:

```swift
                        field("Today") {
                            Toggle(isOn: $groundingEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Daily grounding note")
                                        .font(Clinical.body(14, weight: .medium))
                                        .foregroundStyle(Clinical.ink)
                                    Text("One calm note a day on Today. Your plan and reminders stay either way.")
                                        .font(Clinical.caption(12))
                                        .foregroundStyle(Clinical.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(Clinical.accent)
                            .accessibilityIdentifier("groundingToggle")
                        }
```

- [ ] **Step 7: Run the UI test, then the suites**

Run the single UI test (Step 2 command) → `passed`. Then the full UI target and the full unit target; both `TEST SUCCEEDED`. Any test that still referenced the tutorial or the celebration is updated, and named in the report.

- [ ] **Step 8: See it**

```bash
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app"
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_SEED_DEMO HC_NORITUAL
python3 -c 'import time; time.sleep(3)'
xcrun simctl io booted screenshot "$DD/../g2-today.png"
xcrun simctl terminate booted harib.Hair-Compass-AI-5
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_SEED_DEMO HC_NORITUAL HC_PLANOPEN
python3 -c 'import time; time.sleep(3)'
xcrun simctl io booted screenshot "$DD/../g2-today-open.png"
```

Open both. Expected: the page opens on the date, greeting, "DAY 141 · REVIEW-READY" (the demo's treatment started 140 days ago) or the demo's actual day, the horizon with Wren in the middle, then one card (closure on the first launch, continuation on the second), then TODAY'S PLAN, then YOUR EVIDENCE, then the shedding scene without its own greeting.

- [ ] **Step 9: Commit**

```
Today answers the four questions in order; the card tour is gone

Calm Horizon header, then one deterministic grounding card, then the
plan, then the evidence ribbon; the shedding scene and the rings follow
as the record's detail. The celebration sheet no longer interrupts a
log. Daily grounding can be switched off in Profile without touching
the plan. The card tour, its flag and its launch surface are removed —
teaching happens in place now.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

---

### Task 5: Land sub-project G2

Controller task: whole-branch review, fix wave, fast-forward `feat/agent-profile-memory`, push, merge `rebuild/clinical-minimal` forward, push, leave the simulator on the new build.

---

## Self-review notes

- Spec §3 order — Task 4's body. §3 completed-day state — closure card + G1's collapsed plan; no XP (celebration sheet removed), no confetti. §4.1 four jobs — every `GroundingCard` has body (acknowledge + anchor), one `primary`, `closure`. §4.2 anatomy — eyebrow, ≤10-word headline, ≤55-word body, anchor, one primary, "Why this?", small avatar. §4.3/4.6 — the ten states in `select`. §4.4 no inferred emotion — no copy names a feeling. §7.1 largest type is the headline (22pt serif) and the phase eyebrow, not a score; the shedding band word remains a state word in the demoted scene. §7.5 small avatar only. §8 — Compass Score demoted, XP celebration removed, tour removed, weekly photo no longer a score input in the card's world (the rings still count it until they retire). §9 — no affiliate, no fear; safety card carries no motivation. §10 — the deterministic card is the only card until G5. §14 — "Daily Grounding can be muted" → `grounding.enabled`; "Why this?" → `reason`.
- Deviation: "Helpful / Not for me" feedback and tone preferences (§4.7) are not built (spec marks feedback optional; tone is Phase 4).
- Deviation: the "I'm worried" secondary action arrives with G4; until then the card's only secondary is "Why this?".
- The demo record (treatment 140 days old, week 20) will usually show the closure or continuation card; `HC_NOTODAY` + a heavy yesterday would show grounding — not scripted here.
