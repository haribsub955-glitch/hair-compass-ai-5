# Widget Rebuild — Design (2026-07-11)

Rebuild the home-screen widget: recent status at a glance, one tap into the log flow, and
the app's Clinical language (ivory, copper, serif, hairlines, compass rings). The current
widget is a plain text card whose `haircompass://today` URL is never handled by the app.

## Deep link routing (the missing piece)

- URLs: `haircompass://log` (open Today + present the log sheet) and `haircompass://today`
  (open Today tab only).
- New `App/DeepLinkRouter.swift`: `@MainActor @Observable final class DeepLinkRouter`
  with `var openLogRequested = false`. RootView owns one, injects via `.environment`,
  and adds `.onOpenURL` — always `tab = .today`; for host == "log" also
  `router.openLogRequested = true`, but only when `!showOnboarding` (never fight the
  onboarding cover; the lock window sits above everything regardless — no special-casing).
- TodayView reads `@Environment(DeepLinkRouter.self)` and, when `openLogRequested` flips
  true, sets `showLog = true` and resets the flag (consume-once).

## Snapshot v2 (duplicated struct, both targets, new key `clinicalSnapshot.v2`)

```swift
struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let hasLoggedToday: Bool
    let score: Int          // Compass score 0–100 (CompassScore)
    let ringLog: Double     // 0…1
    let ringCare: Double?   // nil = no plan scheduled today
    let ringLens: Double    // 0…1
    let shedLabel: String   // latest entry's shed band ("Elevated"), "" if none
    let scalpLabel: String  // "Scalp mild", "" if none
    let streakDays: Int     // shielded streak
    let shieldsHeld: Int
    let dueTitles: [String] // remaining routine steps today
}
```

`WidgetSnapshotBuilder.build` gains `photos: [PhotoRecord]` (for the Lens ring's
photo-this-week bit) and computes score/rings via `CompassScore`, streak via
`HairAnalytics.shieldedStreak`. RootView adds a `PhotoRecord` @Query, passes it through,
and folds a photo-week bit into `widgetFingerprint`. New key means stale v1 data simply
falls back to placeholder until the app's first write — no migration.

## Widget design (complete visual rebuild, Clinical language)

Shared palette constants mirroring Clinical (canvas #FBF6EF, surface #FEFCF9, ink, secondary
#7A6B5D-region, tertiary #7C6D5F, copper #B1592E, sage, gold #C9A15A, hairline) — a
`WidgetPalette` enum in the widget file (widget target doesn't compile Clinical.swift).

- **systemSmall** — eyebrow "COMPASS" (10pt mono-tracked, secondary) + flame streak chip
  (copper, shield.fill + count in sage when shields > 0); centered mini rings (~64pt,
  copper/sage/gold, same 50/30/20 semantics, dotted care track when nil) with the score
  inside (serif semibold 20); bottom line: `hasLoggedToday ? "\(shedLabel) · \(scalpLabel)"
  (12pt secondary) : "Tap to log today" (12pt semibold copper)`. `widgetURL` →
  `haircompass://log`.
- **systemMedium** — left: rings 78pt + score; right column: serif headline (20pt, ink):
  "Log today's check-in" when not logged, else "Logged — nice." / routine-aware line;
  severity line (12pt secondary); streak + shields chip row; up to 2 `dueTitles` rows
  (copper open-circle glyph + 12pt medium ink, mirrors the app's checklist rows) separated
  by a hairline divider. Same `widgetURL`.
- **accessoryCircular** — `Gauge(value: score/100)` `.gaugeStyle(.accessoryCircularCapacity)`
  with "\(score)" center; `AccessoryWidgetBackground()`.
- **accessoryRectangular** — "Hair Compass" caption, status line ("Log today" / shed·scalp),
  flame + streak. System tint handles color.
- Placeholder/no-data: invitation copy ("Your compass is ready — tap to log day one"),
  rings at 0 with dotted tracks, never an error state.
- Container: `containerBackground(canvas, for: .widget)`; serif via
  `.font(.system(size:, design: .serif))`. All text 2-line max, `minimumScaleFactor(0.8)`
  on the headline.

`configurationDisplayName("Compass")`, description "Your rings, streak, and a one-tap
check-in." Kind string unchanged (`HairCompassCheckInWidget`) so existing placements
survive.

## Tests

Extend/add builder tests (app target): logged-today + photo-this-week → ringLog=1,
ringLens=1, score matches `CompassScore`; no-treatments → ringCare nil and dueTitles empty;
due-titles content for a 2-slot treatment with 1 dose logged; shielded streak passthrough.

## Verification (orchestrator)

Build app + widget targets; unit tests; install; `xcrun simctl openurl` with
`haircompass://log` → screenshot proves the log sheet opens from a cold tap; read the app
group's UserDefaults plist to confirm the v2 snapshot payload was written. Widget visual
itself can't be screenshotted headlessly (no simctl API to place widgets) — verified by
code review; the user can long-press the home screen to add "Compass" and see it live.

## Non-goals

Interactive AppIntent buttons (log-from-widget without opening the app), lock-screen
complications beyond the two accessories, StandBy tuning, widget configuration intents.
