# Sub-project E: Fresh-Eyes Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four gaps the fresh-eyes verdict found: a one-tap "Same as yesterday" log on Today, a one-time reminder nudge after the first log, a Compass Score that explains itself, and the "echo window" jargon gone from user-facing copy.

**Architecture:** Two pure decision/data helpers (`YesterdayCopy`, `ReminderNudge`) carry the logic and the tests; `TodayView` owns the state and the writes through the existing `DailyEntryRepository`; `ConditionsHero` gains one optional callback and one chip; `CompassRingsCard`'s existing expanded detail gains the explanation line, driven by weights lifted into `CompassScore` so the copy cannot drift from the model.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-03-fresh-eyes-verdict.md`

## Global Constraints

- Framing rule: record-keeping and education, never diagnosis; no directive copy.
- No palette/typeface/dark-mode change, no new dependencies, `Clinical.*` tokens only; secondary chips are outlined, never a second filled button beside the log button.
- A copied entry is a full entry: streaks, Compass Score and the widget treat it like any log. `note` is never copied.
- The nudge shows once per device, only after a saved log, only while the evening check-in reminder is off; either button retires it forever. It never asks for notification permission before the person taps "Turn on".
- The score explanation's weights come from `CompassScore` itself (50 / 30 / 20; care only when something is scheduled).
- Unit tests are Swift Testing; UI tests XCTest with `-parallel-testing-enabled NO`; git as plain single commands in the worktree session; commit with `-F`; discard the scheme rewrite before committing: `git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"`.
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
| Create `Hair Compass AI 5/Model/YesterdayCopy.swift` | which fields a "same as yesterday" log copies, and when the chip may show |
| Create `Hair Compass AI 5/Model/ReminderNudge.swift` | the one-time nudge decision |
| Modify `Hair Compass AI 5/Model/CompassScore.swift` | weights lifted into named constants; explanation copy |
| Modify `Hair Compass AI 5/Feature/TodayTiles.swift` (`ConditionsHero`) | `onCopyYesterday` callback and the chip |
| Modify `Hair Compass AI 5/Feature/TodayView.swift` | performs the copy; hosts the nudge card |
| Modify `Hair Compass AI 5/Feature/CompassRings.swift` (`CompassRingsCard`) | explanation line in the expanded detail |
| Modify `Hair Compass AI 5/Feature/JourneyChart.swift:84-85`, `Feature/LifeEventsSheet.swift:71,140` | copy |
| Create `Hair Compass AI 5Tests/YesterdayCopyTests.swift`, `ReminderNudgeTests.swift`, `CompassScoreExplanationTests.swift` | tests |
| Modify `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift` | `testSameAsYesterdayLogsToday` |

---

### Task 1: `YesterdayCopy` and the "Same as yesterday" chip

**Files:**
- Create: `Hair Compass AI 5/Model/YesterdayCopy.swift`
- Modify: `Hair Compass AI 5/Feature/TodayTiles.swift` (`ConditionsHero`: new `var onCopyYesterday: (() -> Void)? = nil` beside `onLog`; `controlsRow`)
- Modify: `Hair Compass AI 5/Feature/TodayView.swift` (the `ConditionsHero(...)` call around line 112; a new `copyYesterday()` func)
- Test: `Hair Compass AI 5Tests/YesterdayCopyTests.swift`; UI test in `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift`

**Interfaces:**
- Consumes: `DailyEntry` stored fields `shedRaw, flaking, erythema, itch, sleepQuality, stress, cigarettes, alcoholDrinks, oiliness, washedHair, note` (`Model/Models.swift:91-140`); `DailyEntryRepository(context:).upsert(day:updateExisting:update:)` (`Service/PersistenceRepositories.swift:14`); `TodayView.entries` (`@Query`, newest first) and `todayEntry` (`:37`); `UINotificationFeedbackGenerator`.
- Produces: `enum YesterdayCopy { static func canOffer(todayLogged: Bool, yesterday: DailyEntry?) -> Bool; static func apply(from yesterday: DailyEntry, to today: DailyEntry); static func yesterdayEntry(in entries: [DailyEntry], now: Date = .now, calendar: Calendar = .current) -> DailyEntry? }`; `ConditionsHero.onCopyYesterday`; accessibility identifier `sameAsYesterday`.

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/YesterdayCopyTests.swift`:

```swift
//
//  YesterdayCopyTests.swift
//  Hair Compass AI 5Tests
//
//  "Same as yesterday" is a full log made in one tap. It copies every self-reported value and
//  nothing personal, offers itself only when it can be honest (yesterday exists, today doesn't),
//  and finds "yesterday" by calendar day, not by the newest entry.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct YesterdayCopyTests {

    private func entry(daysAgo: Int, calendar: Calendar = .current, now: Date = .now) -> DailyEntry {
        let e = DailyEntry()
        e.date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return e
    }

    @Test func offersOnlyWhenTodayIsEmptyAndYesterdayExists() {
        #expect(YesterdayCopy.canOffer(todayLogged: false, yesterday: entry(daysAgo: 1)))
        #expect(!YesterdayCopy.canOffer(todayLogged: true, yesterday: entry(daysAgo: 1)))
        #expect(!YesterdayCopy.canOffer(todayLogged: false, yesterday: nil))
    }

    @Test func copiesEverySelfReportedValueAndNoNote() {
        let y = DailyEntry()
        y.shedRaw = ShedLevel.elevated.rawValue
        y.flaking = 2; y.erythema = 1; y.itch = 3
        y.sleepQuality = 4; y.stress = 2
        y.cigarettes = 3; y.alcoholDrinks = 1; y.oiliness = 2
        y.washedHair = true
        y.note = "private"
        let t = DailyEntry()
        YesterdayCopy.apply(from: y, to: t)
        #expect(t.shedRaw == ShedLevel.elevated.rawValue)
        #expect(t.flaking == 2 && t.erythema == 1 && t.itch == 3)
        #expect(t.sleepQuality == 4 && t.stress == 2)
        #expect(t.cigarettes == 3 && t.alcoholDrinks == 1 && t.oiliness == 2)
        #expect(t.washedHair == true)
        #expect(t.note.isEmpty, "a note is personal and never copied")
    }

    @Test func yesterdayIsFoundByCalendarDayNotRecency() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 9))!
        let twoDaysAgo = entry(daysAgo: 2, calendar: cal, now: now)
        let yesterday = entry(daysAgo: 1, calendar: cal, now: now)
        // Newest first, as TodayView's query delivers them; today absent.
        #expect(YesterdayCopy.yesterdayEntry(in: [yesterday, twoDaysAgo], now: now, calendar: cal) === yesterday)
        #expect(YesterdayCopy.yesterdayEntry(in: [twoDaysAgo], now: now, calendar: cal) == nil)
        #expect(YesterdayCopy.yesterdayEntry(in: [], now: now, calendar: cal) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `utest YesterdayCopyTests` → build failure, `YesterdayCopy` not found.

- [ ] **Step 3: Write the helper**

Create `Hair Compass AI 5/Model/YesterdayCopy.swift`:

```swift
//
//  YesterdayCopy.swift
//  Hair Compass AI 5
//
//  One tap on a quiet day: today's log becomes a copy of yesterday's self-reported values.
//  Pure rules here — what may be offered, what is copied, which entry counts as yesterday — so
//  TodayView only performs the write.
//

import Foundation

enum YesterdayCopy {
    /// Offer the chip only when it is honest: nothing logged today, and a real yesterday to copy.
    static func canOffer(todayLogged: Bool, yesterday: DailyEntry?) -> Bool {
        !todayLogged && yesterday != nil
    }

    /// Every self-reported value; never the note, never the date.
    static func apply(from yesterday: DailyEntry, to today: DailyEntry) {
        today.shedRaw = yesterday.shedRaw
        today.flaking = yesterday.flaking
        today.erythema = yesterday.erythema
        today.itch = yesterday.itch
        today.sleepQuality = yesterday.sleepQuality
        today.stress = yesterday.stress
        today.cigarettes = yesterday.cigarettes
        today.alcoholDrinks = yesterday.alcoholDrinks
        today.oiliness = yesterday.oiliness
        today.washedHair = yesterday.washedHair
    }

    /// The entry dated on the calendar day before `now`, whatever order the list arrives in.
    static func yesterdayEntry(in entries: [DailyEntry], now: Date = .now, calendar: Calendar = .current) -> DailyEntry? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return entries.first { calendar.isDate($0.date, inSameDayAs: yesterday) }
    }
}
```

- [ ] **Step 4: Run to verify pass** — `utest YesterdayCopyTests` → 3 passed.

- [ ] **Step 5: The chip in the hero**

In `Hair Compass AI 5/Feature/TodayTiles.swift`, `ConditionsHero`: next to `let onLog: () -> Void` (find it in the property list) add:

```swift
    /// Present only when today is empty and yesterday exists — the one-tap quiet-day log.
    var onCopyYesterday: (() -> Void)? = nil
```

Replace `private var controlsRow: some View { logButton }` with:

```swift
    private var controlsRow: some View {
        HStack(spacing: 10) {
            logButton
            if let onCopyYesterday, !hasLoggedToday {
                Button(action: onCopyYesterday) {
                    Label("Same as yesterday", systemImage: "arrow.uturn.backward")
                        .font(Clinical.body(12, weight: .medium))
                        .foregroundStyle(Clinical.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Clinical.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
                }
                .buttonStyle(.clinicalPressable)
                .accessibilityIdentifier("sameAsYesterday")
                .accessibilityHint("Logs today with yesterday's values; you can edit afterwards")
            }
        }
    }
```

- [ ] **Step 6: The write in TodayView**

In `Hair Compass AI 5/Feature/TodayView.swift`, pass the callback where `ConditionsHero(` is constructed, directly after `onLog: { showLog = true },`:

```swift
                    onCopyYesterday: YesterdayCopy.canOffer(
                        todayLogged: todayEntry != nil,
                        yesterday: YesterdayCopy.yesterdayEntry(in: entries)
                    ) ? { copyYesterday() } : nil,
```

Add the function next to the other private funcs:

```swift
    /// One tap, one full entry: today becomes a copy of yesterday's self-reported values. The
    /// hero flips to "Edit log" the moment the write lands, so a wrong tap is a one-tap fix.
    private func copyYesterday() {
        guard let yesterday = YesterdayCopy.yesterdayEntry(in: entries) else { return }
        do {
            try DailyEntryRepository(context: context).upsert(day: .now, updateExisting: false) { today in
                YesterdayCopy.apply(from: yesterday, to: today)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // The next tap on "Log today" reaches the same store through the sheet.
        }
    }
```

If `TodayView` does not import `UIKit`, add `import UIKit` at the top (the file already uses `UINotificationFeedbackGenerator` in the celebration path — check with a grep and follow what is there).

- [ ] **Step 7: The UI test**

Append inside the `Hair_Compass_AI_5UITests` class:

```swift
    /// A quiet day is one tap: with yesterday logged and today empty, "Same as yesterday" exists
    /// and turns into "Edit log" once tapped.
    @MainActor
    func testSameAsYesterdayLogsToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_NOTODAY"]
        app.launch()
        let chip = app.buttons["sameAsYesterday"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "today is empty and yesterday exists — the chip must show")
        chip.tap()
        XCTAssertTrue(app.buttons["Edit log"].waitForExistence(timeout: 6), "one tap must produce today's log")
        XCTAssertFalse(chip.exists, "the chip retires once today is logged")
    }
```

`HC_NOTODAY` is a new DEBUG launch argument: in `Seed.demo(context:profiles:entries:)` (`Model/Seed.swift:13`), skip creating today's entry when `ProcessInfo.processInfo.arguments.contains("HC_NOTODAY")` — find where the demo loop creates the entry for offset 0 (today) and guard it. Document the flag in `CLAUDE.md`'s DEBUG flags line.

- [ ] **Step 8: Run** — `utest YesterdayCopyTests`, the UI test alone, then the full unit and UI targets. Discard the scheme rewrite. Commit (message: "Today: a quiet day is one tap — Same as yesterday").

---

### Task 2: The one-time reminder nudge

**Files:**
- Create: `Hair Compass AI 5/Model/ReminderNudge.swift`
- Modify: `Hair Compass AI 5/Feature/TodayView.swift`
- Test: `Hair Compass AI 5Tests/ReminderNudgeTests.swift`

**Interfaces:**
- Consumes: `@AppStorage("eveningCheckInEnabled")` (the evening check-in reminder flag, `App/RootView.swift:94`, `Feature/CareView.swift:65`); `NotificationService.requestAuthorizationIfNeeded() async -> Bool` (`Service/NotificationService.swift:157`); RootView's `.task` keyed on `eveningCheckInPlanKey` re-plans the reminder whenever the flag changes, so TodayView only flips the flag.
- Produces: `enum ReminderNudge { static let shownKey = "reminders.nudgeShown"; static func shouldShow(hasLoggedToday: Bool, eveningReminderOn: Bool, alreadyShown: Bool) -> Bool }`; identifiers `reminderNudge`, `reminderNudgeOn`, `reminderNudgeNotNow`.

- [ ] **Step 1: Failing test**

```swift
//
//  ReminderNudgeTests.swift
//  Hair Compass AI 5Tests
//
//  One card, once, at the moment it matters: after the first saved log, while reminders are off.
//

import Testing
@testable import Hair_Compass_AI_5

struct ReminderNudgeTests {
    @Test func showsOnlyAfterALogWhileRemindersAreOffAndNeverTwice() {
        #expect(ReminderNudge.shouldShow(hasLoggedToday: true, eveningReminderOn: false, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: false, eveningReminderOn: false, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: true, eveningReminderOn: true, alreadyShown: false))
        #expect(!ReminderNudge.shouldShow(hasLoggedToday: true, eveningReminderOn: false, alreadyShown: true))
    }

    @Test func storageKeyIsStable() {
        #expect(ReminderNudge.shownKey == "reminders.nudgeShown")
    }
}
```

- [ ] **Step 2: Run to fail**, then create `Hair Compass AI 5/Model/ReminderNudge.swift`:

```swift
//
//  ReminderNudge.swift
//  Hair Compass AI 5
//
//  Reminders default to off, and a tracking app lives or dies in its first week. This is the
//  one moment the app asks: right after the first saved log, once, with a real "not now".
//

import Foundation

enum ReminderNudge {
    static let shownKey = "reminders.nudgeShown"

    static func shouldShow(hasLoggedToday: Bool, eveningReminderOn: Bool, alreadyShown: Bool) -> Bool {
        hasLoggedToday && !eveningReminderOn && !alreadyShown
    }
}
```

- [ ] **Step 3: The card in TodayView**

Add to `TodayView`'s properties:

```swift
    @Environment(NotificationService.self) private var notifications
    @AppStorage("eveningCheckInEnabled") private var eveningCheckInEnabled = false
    @AppStorage(ReminderNudge.shownKey) private var reminderNudgeShown = false
```

(If `NotificationService` is not in TodayView's environment, check how `RootView` injects it — `.environment(notifications)` on the tab content — and confirm `TodayView` is inside that scope; it is, because `CareView` reads it the same way.)

Directly after the `ConditionsHero(...)` call (still inside the top-level `VStack`), add:

```swift
                if ReminderNudge.shouldShow(hasLoggedToday: todayEntry != nil,
                                            eveningReminderOn: eveningCheckInEnabled,
                                            alreadyShown: reminderNudgeShown) {
                    reminderNudgeCard
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
```

and the view:

```swift
    /// Asked once, after the first log, while reminders are off. Both buttons retire it.
    private var reminderNudgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Want a nudge tomorrow evening?")
                .font(Clinical.body(15, weight: .medium))
                .foregroundStyle(Clinical.ink)
            Text("One quiet reminder at your check-in time. You can change or switch it off on the Plan tab.")
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Turn on") {
                    reminderNudgeShown = true
                    Task {
                        let granted = await notifications.requestAuthorizationIfNeeded()
                        eveningCheckInEnabled = granted
                    }
                }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .accessibilityIdentifier("reminderNudgeOn")
                Button("Not now") { reminderNudgeShown = true }
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reminderNudgeNotNow")
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(Clinical.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(Clinical.hairline) }
        .accessibilityIdentifier("reminderNudge")
    }
```

- [ ] **Step 4: Run** — `utest ReminderNudgeTests` (2 passed), the full unit target, the UI target (a seeded launch shows the card once; existing tests must not be blocked by it — if `testLaunchRitualIsSkippable` or another test taps something the card now covers, add `HC_NORITUAL`-style guard: skip the nudge when `ProcessInfo.processInfo.arguments.contains("HC_NONUDGE")` under `#if DEBUG`, pass that flag in the affected tests, and document it). Commit ("Today: one reminder nudge, after the first log, once").

---

### Task 3: The Compass Score explains itself

**Files:**
- Modify: `Hair Compass AI 5/Model/CompassScore.swift`
- Modify: `Hair Compass AI 5/Feature/CompassRings.swift` (`CompassRingsCard`'s expanded detail)
- Test: `Hair Compass AI 5Tests/CompassScoreExplanationTests.swift`

**Interfaces:**
- Produces: `CompassScore.Weights { static let log = 50.0; static let care = 30.0; static let lens = 20.0 }` used by `score`; `CompassScore.explanation: String` (static).

- [ ] **Step 1: Failing test**

```swift
//
//  CompassScoreExplanationTests.swift
//  Hair Compass AI 5Tests
//
//  The score's explanation is generated from the same weights the score uses, so the words on
//  screen cannot drift from the arithmetic.
//

import Testing
@testable import Hair_Compass_AI_5

struct CompassScoreExplanationTests {
    @Test func explanationNamesEveryFactorAndItsWeight() {
        let text = CompassScore.explanation
        #expect(text.contains("check-in"))
        #expect(text.contains("doses"))
        #expect(text.contains("photo"))
        #expect(text.contains("\(Int(CompassScore.Weights.log))"))
        #expect(text.contains("\(Int(CompassScore.Weights.care))"))
        #expect(text.contains("\(Int(CompassScore.Weights.lens))"))
        #expect(text.lowercased().contains("never") && text.lowercased().contains("hair"), "it must say the score is not about hair health")
    }

    @Test func weightsStillProduceTheKnownScores() {
        #expect(CompassScore(hasLoggedToday: true, medsDone: 0, medsTotal: 0, hasPhotoThisWeek: false).score == 71)
        #expect(CompassScore(hasLoggedToday: true, medsDone: 2, medsTotal: 2, hasPhotoThisWeek: true).score == 100)
        #expect(CompassScore(hasLoggedToday: false, medsDone: 0, medsTotal: 2, hasPhotoThisWeek: false).score == 0)
    }
}
```

(71: log 50 of an available 70 when care is unavailable → 50/70 = 71.4 → 71. Confirm against the current `score` before changing anything; if the existing arithmetic gives a different value, keep the arithmetic and correct the expectation — the refactor must not change scores.)

- [ ] **Step 2: Lift the weights and add the copy** in `CompassScore.swift`:

```swift
    /// Log 50 / Care 30 / Lens 20. Named so the explanation shown to the person is generated
    /// from the same numbers the score uses.
    enum Weights {
        static let log = 50.0
        static let care = 30.0
        static let lens = 20.0
    }

    var score: Int {
        var pairs: [(value: Double, weight: Double)] = [(log, Weights.log), (lens, Weights.lens)]
        if let care { pairs.append((care, Weights.care)) }
        ...unchanged...
    }

    /// Shown under the rings when the detail is expanded. Consistency, never hair health.
    static var explanation: String {
        "Today's check-in counts \(Int(Weights.log)), your routine doses \(Int(Weights.care)) (only on days something is scheduled), and a photo this week \(Int(Weights.lens)). It resets every day and measures showing up — never your hair."
    }
```

- [ ] **Step 3: Show it** in `CompassRingsCard`: inside the expanded detail (the view revealed by `ringButton`'s toggle — locate the `expanded` branch), append below the per-ring ledger rows:

```swift
                Text(CompassScore.explanation)
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("compassScoreExplanation")
```

- [ ] **Step 4: Run** — `utest CompassScoreExplanationTests`, `utest CompassScoreTests`, the full unit target. Commit ("Compass Score: the rings say what they count").

---

### Task 4: Copy — "echo window"

**Files:**
- Modify: `Hair Compass AI 5/Feature/JourneyChart.swift:84-85`, `Hair Compass AI 5/Feature/LifeEventsSheet.swift:71,140`

- [ ] **Step 1:** In `JourneyChart.swift` change `Text(" — possible echo window")` to `Text(" — when a trigger's effect may show")`. In `LifeEventsSheet.swift:71` change the alert message to `"Its journey-chart marker and amber band go with it — this can't be undone."`; at `:140` change `"\(when) · echo window ~\(echoWindowLabel(event.date))"` to `"\(when) · effect may show ~\(echoWindowLabel(event.date))"`. Leave code comments and function names alone.
- [ ] **Step 2:** `grep -rn 'echo window' --include='*.swift' "Hair Compass AI 5"` must show only comments/doc lines, not `Text(`/string literals shown to users. Run the full unit target. Commit ("Trends and Life events: plain words for the amber band").

---

### Task 5: Land sub-project E

Controller task: fast-forward `feat/agent-profile-memory`, push, merge `rebuild/clinical-minimal` forward, push, leave the simulator on the new build.

---

## Self-review notes

- E1 → Task 1 (helper + chip + write + UI test with the new `HC_NOTODAY` seed flag); E2 → Task 2 (decision helper + card; permission asked only on "Turn on"); E3 → Task 3 (weights lifted, explanation generated, shown in the existing expanded detail rather than a new sheet — one fewer surface, same information); E4 → Task 4.
- Names consistent: `YesterdayCopy.canOffer/apply/yesterdayEntry`, `ConditionsHero.onCopyYesterday`, `ReminderNudge.shouldShow/shownKey`, `CompassScore.Weights`, `CompassScore.explanation`.
