# Engagement Rings + Habit Plan + Audit Fixes — Design (2026-07-11)

Grounded in `docs/research/2026-07-11-engagement-science.md` (cited briefing), the backend
audit, and the UX audit (both run 2026-07-11, findings embedded below). Ethical frame the
research validates: reward **effort only** (never shedding/outcomes), transparent mechanics,
one capped supportive notification, streak repair instead of streak anxiety. This is also
already the codebase's hard rule (Gamification.swift).

## 1. Compass Rings — the Apple-Fitness-style daily score (user's centerpiece ask)

**Model** (`Model/CompassScore.swift`, pure + tested):
- Inputs per day: `hasLoggedToday: Bool`, `medsDone: Int`, `medsTotal: Int`,
  `hasPhotoThisWeek: Bool`.
- Rings: **Log** (copper `Clinical.accent`) = 1 or 0; **Care** (sage `Clinical.sage`) =
  `medsDone/medsTotal`, `nil` when `medsTotal == 0` (no schedule — rendered as faint dotted
  track, excluded from score); **Lens** (antique gold `Clinical.gold`) = 1 if a photo exists
  in the current calendar week else 0.
- **Score 0–100**: weights Log 50 / Care 30 / Lens 20; an unavailable ring's weight is
  redistributed proportionally across the available ones; rounded to Int.
- All inputs are 100% user-controllable effort. Shedding/scalp values NEVER touch the score.

**View** (`Feature/CompassRings.swift`):
- `CompassRingsView(score: CompassScore, size: CGFloat)` — three concentric rings, rounded
  caps, 270°-max sweep like Apple (full circle), spring fill on value change, one-shot
  closure moment per ring (brief glow + `UINotificationFeedbackGenerator.success`) when a
  ring crosses 1.0 while visible; center shows the big score number (`Clinical.number`) over
  "TODAY" eyebrow. Reduce Motion: values jump, no glow.
- `CompassRingsCard` for Today: rings (≈120pt) left; right column: "Compass Score" eyebrow,
  score line, one identity-toned status line (e.g. "You showed up today." / "Two rings to
  go — the check-in takes 20 seconds."), legend rows (dot + LOG/CARE/LENS + state). Tapping
  the card opens the log sheet. Placed between hero and tile grid on Today.

## 2. Habit mechanics (research top-8, scoped to this round)

- **Streak Shield** (Duolingo-validated freeze): deterministic, replayable, no stored state —
  `HairAnalytics.shieldedStreak(entryDates:now:calendar:) -> (streak: Int, shieldsHeld: Int)`.
  Rules: every 7 consecutive logged days earns 1 shield, max 2 held; a single-day gap
  consumes a shield (if held) and the streak continues through it; a ≥2-day gap breaks the
  streak. Existing `loggingStreak` stays untouched (XP math unchanged — shields protect the
  *displayed* streak, never mint XP). Hero streak chip shows a small shield icon + count
  when > 0; `CheckInReward.streak` switches to the shielded streak so celebrations match.
- **Evening check-in reminder** (implementation intention + 1/day cap): a user-chosen time
  (default 20:30) in the Plan tab's reminder section, OFF until the user turns it on.
  Schedules the next 3 days' non-repeating reminders, skipping today when today is already
  logged; re-planned whenever reminders reschedule. Copy is invitation-toned, streak-aware
  when streak ≥ 3 ("Day {n+1} is a 20-second check-in away."), never guilt.
- **Identity copy**: celebration + rings status lines say "you're someone who shows up",
  never outcome claims.
- **Endowed progress**: onboarding already seeds day one — the rings card's first-day copy
  acknowledges it ("Day 1 is already on the board — you logged it during setup.").
- Deferred (needs infra, out of scope): social/leagues layer.

## 3. Backend fixes (audit findings, ranked)

1. `CameraCaptureService.capture()` re-entrancy: second shutter tap overwrites the stored
   continuation → first caller hangs forever and photos cross wires. Guard
   `captureContinuation == nil` (return nil on re-entry).
2. `HealthKitService.upsertToday` predicate unbounded above (`date >= start` only) →
   restored future-dated snapshots get today's readings written into them. Add the
   upper bound (`< start of tomorrow`).
3. `HealthKitService.refreshSnapshot` dead ternary → `snapshot.hasAnyValue ? snapshot : nil`.
4. RootView `widgetFingerprint` misses same-day edits (counts only) → widget shows stale
   severity after editing today's entry. Include latest entry's content (shedRaw + scalp
   fields) and active-treatment fingerprint in the id string.
5. `NotificationService.reschedule()` re-entrancy: add an in-flight coalescing guard
   (single pending Task; latest call wins).
6. `PurchaseService.monthlyEquivalentDisplay` integer division for week/day periods →
   correct proportional math (weeks×7 or days, / 30.44 for months), still unreachable today.

## 4. UX fixes (audit top-10, all in scope)

1. `Eyebrow` default color → `Clinical.secondary`; `Clinical.tertiary` darkened to ≥4.5:1
   on canvas (~`#8A7A6B` region — verify with a contrast computation in the PR) and kept for
   decorative/non-text use.
2. Dynamic Type step 1: `Clinical.headline/number/eyebrow` route their sizes through
   `UIFontMetrics(forTextStyle:).scaledValue(for:)` (headline→.title2, number→.body,
   eyebrow→.caption2) so system text size finally affects the app; identity at default size.
3. `GuidedCaptureView`: accessibility labels on the four camera controls.
4. `CareView` routine-step info button: ≥44pt contentShape + label.
5. `TreatmentDetailSheet` side-effect delete button: label + ≥32pt shape.
6. `LearnView` card flip honors Reduce Motion (opacity cross-fade fallback).
7. Onboarding step 5: raise live falling-hair density at low/mid intensity (HairPhysics
   spawn math) so the scene never reads as empty/broken.
8. Onboarding step 10 (habits): add the `onboard-habits` gouache vignette to fill the dead
   lower half (art above the toggles, StressStrandView stays).
9. Trends zero/thin-data state: `trends-journey-empty` compass-trail art in the empty/
   forming cards.
10. `ExportSheet`: `export-seal` art under the two cards.
11. Shared `.trailingFade()` modifier (LinearGradient mask) applied to the horizontal chip
    scrollers in LearnView, PhotosView, GuidedCaptureView.

Assets (already generated with Higgsfield nano_banana, committed as imagesets):
`trends-journey-empty`, `onboard-habits`, `export-seal`.

## Non-goals this round
Widget rings, social features, Duolingo-style leagues, paywall changes, any new @Model
fields (everything is derived — no schema migration risk).

## Execution
Four Sonnet tracks, disjoint files, frozen contracts (see plan). Fable integrates, builds,
tests, simulator-verifies, commits.
