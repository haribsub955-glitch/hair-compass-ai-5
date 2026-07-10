# Engagement Rings + Habit Plan + Audit Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Compass Rings daily score, the streak-shield + evening-reminder habit mechanics, all six backend-audit fixes, and the UX-audit top fixes with the three new gouache assets.

**Architecture:** Four parallel Sonnet tracks with disjoint file ownership. Spec: `docs/superpowers/specs/2026-07-11-engagement-rings-design.md`. Research: `docs/research/2026-07-11-engagement-science.md`. Same global constraints as the two prior plans in this folder: Clinical tokens only, Reduce Motion everywhere, effort-only rewards (NEVER shedding/outcomes in any score/copy), **agents do not run xcodebuild and do not git commit**, Swift Testing for tests, quote all paths.

Assets already in Assets.xcassets: `trends-journey-empty`, `onboard-habits`, `export-seal`.

**Cross-track frozen contracts:**
1. `HairAnalytics.shieldedStreak(entryDates: [Date], now: Date = .now, calendar: Calendar = .current) -> (streak: Int, shieldsHeld: Int)` — produced by Track B in `Model/Analytics.swift`; consumed by Track A in TodayView.
2. `ConditionsHero` gains `shields: Int = 0` (WITH default, so call sites compile regardless of order) — produced by Track B in `Feature/TodayTiles.swift`; Track A passes it from TodayView.
3. Nothing else crosses tracks.

---

### Task A: Compass Rings

**Files (owns exclusively):** Create `Hair Compass AI 5/Model/CompassScore.swift`, `Hair Compass AI 5/Feature/CompassRings.swift`, `Hair Compass AI 5Tests/CompassScoreTests.swift`; Modify `Hair Compass AI 5/Feature/TodayView.swift`.

- [ ] **A1: CompassScore (pure).**

```swift
import Foundation

/// The daily effort score behind the Compass Rings. Built ONLY from controllable inputs —
/// check-in logged, doses done, weekly photo. Shedding/scalp severity never touch it
/// (rewarding outcomes users can't control backfires; see docs/research/2026-07-11).
struct CompassScore: Equatable {
    /// 1 when today's check-in exists.
    let log: Double
    /// Fraction of today's scheduled doses logged; nil when nothing is scheduled today.
    let care: Double?
    /// 1 when a progress photo exists in the current calendar week.
    let lens: Double

    init(hasLoggedToday: Bool, medsDone: Int, medsTotal: Int, hasPhotoThisWeek: Bool) {
        log = hasLoggedToday ? 1 : 0
        care = medsTotal > 0 ? Double(min(medsDone, medsTotal)) / Double(medsTotal) : nil
        lens = hasPhotoThisWeek ? 1 : 0
    }

    /// 0–100. Weights Log 50 / Care 30 / Lens 20; an unavailable ring's weight is
    /// redistributed proportionally across the rings that exist.
    var score: Int {
        var pairs: [(value: Double, weight: Double)] = [(log, 50), (lens, 20)]
        if let care { pairs.append((care, 30)) }
        let totalWeight = pairs.reduce(0) { $0 + $1.weight }
        let weighted = pairs.reduce(0) { $0 + $1.value * $1.weight }
        return Int((weighted / totalWeight * 100).rounded())
    }

    var allClosed: Bool { log >= 1 && lens >= 1 && (care ?? 1) >= 1 }
}
```

- [ ] **A2: Tests** (`CompassScoreTests.swift`, Swift Testing, `@testable import Hair_Compass_AI_5`): all-done = 100; nothing = 0; log-only with no schedule = `round(50/70*100)` = 71; care nil when medsTotal == 0 and non-nil otherwise; medsDone > medsTotal clamps to 1.0; `allClosed` true only when every available ring is 1.
- [ ] **A3: CompassRingsView.** Three concentric rings (outer Log copper `Clinical.accent`, middle Care sage `Clinical.sage`, inner Lens antique gold `Clinical.gold`), stroke ≈ size/9 rounded caps, tracks in the ring color at 0.15 opacity; `care == nil` renders its track as a dotted hairline (`StrokeStyle(dash:)`, `Clinical.hairline`) with no fill. Spring fill `.spring(response: 0.7, dampingFraction: 0.8)` on value change. Closure moment: keep the previous `CompassScore` in `@State`; when a ring crosses from <1 to ≥1, run a one-shot glow (ring-colored shadow radius pulse, ~0.9 s) + `UINotificationFeedbackGenerator().notificationOccurred(.success)`; when `allClosed` flips true, glow all three. Reduce Motion: no springs, no glow, values jump (haptic stays). Center: score number in `Clinical.number(28)` over `Eyebrow(text: "Today")`. `.accessibilityElement(children: .ignore)` + label "Compass score {score} of 100" + value describing each ring's state.
- [ ] **A4: CompassRingsCard.** `ClinicalCard`: rings (120 pt) left; right column: `Eyebrow("Compass score")`, status line (identity-toned, 14 pt ink — exact copy: all closed → "All rings closed. You showed up today."; log missing → "The check-in takes 20 seconds — it closes the copper ring."; log done + others open → "Logged. {N} ring(s) to go."; brand-new day-one user (score>0 via seeded entry) → "Day 1 is already on the board — you logged it during setup."), then three legend rows (8 pt dot in ring color + LOG / CARE / LENS eyebrow + trailing state: "Logged"/"Not yet", "2 of 3", "This week ✓"/"Not this week", care row reads "No plan yet" when nil). Whole card is a Button → `onLog` (same action as hero's log button), `.buttonStyle(.plain)`, accessibility hint "Opens today's check-in".
- [ ] **A5: TodayView wiring.** Insert `CompassRingsCard` between the hero and `TodayTileGrid` (staggered index 1; bump later indices by one). Compute: `hasPhotoThisWeek = photos.contains { calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .weekOfYear) }`; reuse existing `todayEntry != nil`, `medsDone`, `dailySlots.count`. Also (contract 1+2): change the hero call to `streak: shieldedInfo.streak` and add `shields: shieldedInfo.shieldsHeld` where `private var shieldedInfo: (streak: Int, shieldsHeld: Int) { HairAnalytics.shieldedStreak(entryDates: entries.map(\.date)) }` — replacing the current `HairAnalytics.loggingStreak` use for the DISPLAYED streak only.

### Task B: Streak shield + evening reminder + identity copy

**Files (owns exclusively):** Modify `Hair Compass AI 5/Model/Analytics.swift`, `Hair Compass AI 5/Model/CheckInReward.swift`, `Hair Compass AI 5/Feature/TodayTiles.swift`, `Hair Compass AI 5/Feature/CheckInCelebration.swift`, `Hair Compass AI 5/Service/NotificationService.swift`, `Hair Compass AI 5/Feature/CareView.swift`; Create `Hair Compass AI 5Tests/StreakShieldTests.swift`.

- [ ] **B1: shieldedStreak** in Analytics.swift next to `loggingStreak` (which stays untouched — XP math must not change):

```swift
/// Displayed streak with Duolingo-style shields: every 7 consecutive logged days earns one
/// shield (max 2 held); a single-day gap consumes a shield and the run continues through
/// it; a gap of 2+ days breaks the run. Deterministic and replayable from history — no
/// stored state. Shields protect the DISPLAYED streak only; XP never mints from them.
static func shieldedStreak(
    entryDates: [Date], now: Date = .now, calendar: Calendar = .current
) -> (streak: Int, shieldsHeld: Int)
```

Implementation: walk unique start-of-days ascending; maintain `run`, `shields` (earn at each multiple of 7 consecutive REAL logged days, cap 2); on a 1-day gap: if `shields > 0` spend one and continue the run (the gap day does NOT increment `run`); on a ≥2-day gap reset `run = 0` and `shields = 0`. After the walk, the streak is current only if the last covered day is today or yesterday (mirror `loggingStreak`'s recency rule — read it first); otherwise 0 (shields report what's held regardless).
- [ ] **B2: Tests** (`StreakShieldTests.swift`): 7 straight days → (7, 1); 7 days + skip 1 + log next → streak continues (9 covered days → streak 9, shields 0); two separate 1-day gaps with only one shield → second gap breaks; 14 straight → shields 2 (cap); ≥2-day gap → (fresh run, 0); no entries → (0, 0); entries only up to 3 days ago → streak 0.
- [ ] **B3: Hero chip.** `ConditionsHero` gains `shields: Int = 0`; when `shields > 0` the streak chip appends a small `shield.fill` (10 pt, `Clinical.sage`) + count. Accessibility label mentions "{n} streak shields held".
- [ ] **B4: CheckInReward** builds its `streak` from `HairAnalytics.shieldedStreak(...).streak` instead of `loggingStreak` (read `CheckInReward.swift:70-85` first; XP fields unchanged).
- [ ] **B5: Identity copy** in CheckInCelebration: the congratulatory line becomes effort/identity framed — e.g. headline stays, subline "You're someone who shows up for your hair — day \(reward.streak)." Never mention shedding/severity in celebration copy (verify none exists).
- [ ] **B6: Evening check-in reminder.** In NotificationService: (1) add the coalescing re-entrancy guard for `reschedule()` (audit #5): keep a `private var rescheduleTask: Task<Void, Never>?`; `reschedule()` cancels the previous task and runs the remove+add sequence inside one new task, checking `Task.isCancelled` between remove and add. (2) New API `func planEveningCheckIn(enabled: Bool, time: DateComponents, hasLoggedToday: Bool, streak: Int)`: removes pending ids prefixed `eveningCheckIn.`, and when enabled schedules non-repeating reminders for the next 3 days at `time` (skip day 0 when `hasLoggedToday`), ids `eveningCheckIn.<n>`. Copy: streak ≥ 3 → "Day \(streak + 1) is a 20-second check-in away." else "Ready for tonight's check-in? 20 seconds keeps your chart honest." — invitation tone, never guilt, ≤1/day by construction.
- [ ] **B7: CareView.** In the reminders section: "Evening check-in" toggle + `DatePicker(.hourAndMinute)` (default 20:30), persisted via `@AppStorage("eveningCheckInEnabled")` / `@AppStorage("eveningCheckInMinutes")` (minutes-since-midnight Int). Call `planEveningCheckIn` from the existing notification-reschedule `.task` (add an entries `@Query` if the view lacks one for `hasLoggedToday`/streak). ALSO fix the audit item: the routine-step info (ⓘ) button gets `.frame(width: 44, height: 44).contentShape(Rectangle())` + `.accessibilityLabel("About this step")`.

### Task C: Backend fixes (audit #1, #2, #3, #4, #6)

**Files (owns exclusively):** Modify `Hair Compass AI 5/Service/CameraCaptureService.swift`, `Hair Compass AI 5/Service/HealthKitService.swift`, `Hair Compass AI 5/App/RootView.swift`, `Hair Compass AI 5/Service/PurchaseService.swift`.

- [ ] **C1:** CameraCaptureService.capture(): `guard captureContinuation == nil else { return nil }` before storing; also nil-out the stored continuation in the delegate BEFORE resuming (read lines 55-80 first and keep the delegate flow intact).
- [ ] **C2:** HealthKitService.upsertToday: bound the predicate to `[start, startOfTomorrow)` (`calendar.date(byAdding: .day, value: 1, to: start)`).
- [ ] **C3:** `return snapshot.hasAnyValue ? snapshot : nil`.
- [ ] **C4:** RootView.widgetFingerprint: append the newest entry's content — `entries.first.map { "\($0.shedRaw)-\($0.flaking)-\($0.erythema)-\($0.itch)" } ?? "none"` — and the active-treatment fingerprint `treatments.filter(\.isActive).count` so same-day edits and deactivations refresh the widget.
- [ ] **C5:** PurchaseService week/day monthly-equivalent math: `case .week: months = Double(period.value) * 7 / 30.44`, `case .day: months = Double(period.value) / 30.44`, guard `months > 0`, keep output formatting unchanged (switch `months` to Double throughout that helper).

### Task D: UX fixes + art wiring (audit top-10)

**Files (owns exclusively):** Modify `Hair Compass AI 5/Design/Clinical.swift`, `Hair Compass AI 5/Feature/GuidedCaptureView.swift`, `Hair Compass AI 5/Feature/TreatmentDetailSheet.swift`, `Hair Compass AI 5/Feature/LearnView.swift`, `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift` (steps 5 & 10 only), `Hair Compass AI 5/Feature/Onboarding/HairPhysics.swift`, `Hair Compass AI 5/Feature/TrendsView.swift`, `Hair Compass AI 5/Feature/PhotosView.swift`, `Hair Compass AI 5/Feature/ExportSheet.swift`.

- [ ] **D1: Contrast.** In Clinical.swift: change `Eyebrow`'s default color to `Clinical.secondary`; darken `tertiary` to pass 4.5:1 on `canvas` — compute programmatically (python3: relative luminance per WCAG; canvas is #FBF6EF) and pick the closest hue-preserving darker value (start trying around #8A796A and darken until ≥4.5). Put the final hex + measured ratio in a code comment.
- [ ] **D2: Dynamic Type step 1.** Route the three type helpers through `UIFontMetrics`: `headline(_ s:)` → `Font.system(size: UIFontMetrics(forTextStyle: .title2).scaledValue(for: s), weight: …, design: .serif)` (match existing weight/design exactly — read the helpers first), `number` → `.body` metrics, `eyebrow` → `.caption2` metrics. Verify default-size output is IDENTICAL (scaledValue is identity at the default content size).
- [ ] **D3:** GuidedCaptureView: `.accessibilityLabel` on shutter ("Take photo"), library ("Choose from library"), flip ("Switch camera"), and the guide toggle if present.
- [ ] **D4:** TreatmentDetailSheet side-effect delete: `.frame(minWidth: 32, minHeight: 32).contentShape(Rectangle())` + `.accessibilityLabel("Delete this entry")`.
- [ ] **D5:** LearnView flip honors Reduce Motion: `@Environment(\.accessibilityReduceMotion)`; when reduced, swap faces with `.opacity` transition instead of `rotation3DEffect` animation.
- [ ] **D6:** HairPhysics spawn density: raise the low-intensity floor so ~15+ strands are alive at intensity 0.34 (read the spawn math at lines ~20-40; scale the spawn rate curve, keep the top end unchanged; respect the existing Reduce Motion static path).
- [ ] **D7:** Onboarding habits step: `Image("onboard-habits")` (scaledToFit, maxHeight 150, rounded 18, hairline border) between `head(...)` and `StressStrandView`, shrinking the dead Spacer.
- [ ] **D8:** TrendsView zero/thin-data: in the empty/forming state cards, show `Image("trends-journey-empty")` (scaledToFit, maxHeight 140, rounded corners) above the copy, replacing the bare SF-symbol circle where present.
- [ ] **D9:** ExportSheet: `Image("export-seal")` (scaledToFit, maxHeight 150) centered below the two share cards, `.accessibilityHidden(true)`.
- [ ] **D10:** Shared `.trailingFade(width: CGFloat = 24)` View modifier in Clinical.swift (LinearGradient mask, clear at trailing edge) applied to the horizontal chip ScrollViews in LearnView, PhotosView.regionPicker, GuidedCaptureView.regionChips.

### Task E (orchestrator): integrate, build, test, verify, commit
- [ ] Build; unit tests; screenshots: Today (rings card + shield chip), Trends empty (fresh install), onboarding steps 5/10, ExportSheet, Learn; verify contrast change didn't break any tinted surface; commit per track.
