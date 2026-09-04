# Living Clinical UI Integration

Date: 2026-09-04

## Intent

Bring the strongest ideas from the Herbarium Journey, Living Compass, focused Labs/Plan/Trends, and subtle Wren concepts into the shipping SwiftUI app without replacing its trusted information architecture or clinical logic.

The concepts are direction, not production assets. The app continues to use the existing gouache asset catalog, `Clinical` tokens, SwiftData record, and current navigation.

## Guardrails

- Presentation layer only: no model schema, persistence, analytics, subscription, consent, prompt, safety-screen, or server-contract changes.
- Preserve the five tabs and all current destinations, gates, sheets, destructive confirmations, exports, and accessibility labels.
- Preserve evidence thresholds, range calculations, clinician framing, treatment timing, and the non-diagnostic language already in the app.
- Preserve Trends' animation-free data transaction; chart marks must never slide when a range changes.
- Reuse `Clinical` colors, type, spacing, warm paper surfaces, and existing brand art. Do not ship generated concept screenshots as UI assets.
- Keep art subordinate to evidence: one header wash, one teaching plate when empty, and quiet edge accents.
- Every repeating motion must pause off-screen/inactive and become static with Reduce Motion.
- Check compact widths and accessibility text sizes before calling the migration complete.

## Change slices

### 1. Shared visual vocabulary

Add small reusable evidence components for status and progress. They must accept semantic text and tint from the calling feature; they do not calculate or interpret health data.

Rollback: remove the new design file and replace its call sites with the pre-existing local layout.

### 2. Wren presence

Keep the existing six semantic moments. Give each moment a restrained motion profile—breathing, a very small head inclination, or still attention—and map celebration to a folded-wing pose. No bounce, confetti, open-beak performance, or outcome claim.

Rollback: restore `CompanionView` to static/generic `LivingArtwork`; the chat service and conversation record are untouched.

### 3. Plan

Add one compact evidence-horizon card near the top when a real `EvidencePhase` exists. It reports the existing week, phase label, next review date, and progress to that review. The existing routine, evidence path, progress report, and treatment cards remain authoritative.

Rollback: remove the card; no stored state is introduced.

### 4. Labs

Add a returning-user summary above the existing continuous ledger, place the ledger on one contained paper surface, and make latest status text explicit without changing ranges or proposal rules. Keep the generic-range and diagnostic-context footnotes.

Rollback: unwrap the ledger and remove the summary/status presentation; lab records and calculations are unchanged.

### 5. Trends

Refine the existing current-read surface into the Living Compass visual language and add a compact evidence-horizon cue when the treatment clock exists. Do not change focus selection, minimum evidence counts, chart construction, or current-read evaluation.

Rollback: restore the prior `currentReadCard`; no stored state is introduced.

## Verification

1. Build the app and widget for an installed iOS simulator.
2. Run companion, evidence-phase, lab analytics, and trajectory tests, then the full unit-test target if those pass.
3. Exercise populated and empty Labs; Plan with and without a daily treatment; sparse and established Trends; all Wren states.
4. Repeat visual checks with Reduce Motion, an accessibility text size, and a compact iPhone width.
5. Review the final diff to confirm that only presentation files, focused tests, and this change note moved.

## Deferred intentionally

- New navigation or tab consolidation.
- New clinical recommendations or automated interpretation.
- New Wren image assets or generative art in the production bundle.
- Server-agent wiring, attachment controls, or paid-feature changes.
- Onboarding and export internals (Today and Photos were subsequently authorized below).

## Expanded integration — owner-requested second pass

The owner reviewed the conservative first slice in the simulator and explicitly asked for most
of the proposed UI/UX across the app, not only Wren. This supersedes the first-pass preference
for a continuous Labs ledger and minimal additions to existing layouts.

### Scope now implemented

- **Today / Ceramic Horizon:** a time-based circular horizon with the actual review clock,
  botanical edges, a tactile daily-plan surface, and a two-column evidence dashboard. The
  existing conditions scene and its log/copy/drag actions remain below the plan.
- **Plan / Herbarium Journey:** scheduled routines precede setup guidance; leaf seals and
  connecting stems mark morning/evening/periodic steps. Larger action cards expose Complete,
  logged Undo, Details, and the existing missed-dose path. The report sits after the routine.
- **Labs:** a permanent illustrated context header, separate test cards with large values,
  semantic emblems, saved-range bars, histories, notes, and existing proposal/deletion flows.
  Prepare for a visit opens the existing ExportSheet; it does not send anything automatically.
- **Trends / Living Compass:** the existing current read leads, charts gain a defined journal
  surface, review and evidence-clock tiles explain timing, and the sparse-state guidance is
  illustrated. A photo-led sparse state may show five or more existing daily shedding points
  as explicitly secondary context; it never satisfies or replaces the primary photo baseline.
- **Photos:** an illustrated repeatability guide, setup cues, an always-available camera
  header action, a framed empty state, and a larger capture card. Pairing/mismatch rules,
  private on-device capture, and deletion confirmation are unchanged.
- **Shared shell:** warm floating dock, selected-tab wash, tactile header controls, reusable
  emblems/action cards, and more visible but still restrained Wren journal notes.

### Change controls

All values still come from the existing model/analytics code. No schema, persistence, safety,
consent, server, subscription, or medical-threshold changes. No concepts' invented example data
or medical claims are copied. Five primary destinations and their accessibility IDs are retained.
No newly generated raster assets or dependencies. The existing dirty worktree is preserved.

Rollback is view-local: restore the changed presentation files and remove the new
`BotanicalSurfaces`, `TodayJournalHero`, and `WrenJournalNote` components. Do not restore unrelated
changes in those files wholesale. Unit and cross-screen UI checks cover the retained actions.

### Second-pass verification — 4 September 2026

- App and widget compile on the iPhone 17 Pro simulator, iOS 26.3.1.
- Focused regression run **passed 30/30**: 27 unit tests across companion motion, evidence phases, lab trends,
  and current progress reads; three UI tests cover all five destinations, routine completion
  and Undo, visit-summary presentation, and the Plan navigator.
  Final result bundle: `/tmp/hc-expanded-release-check.xcresult`.
- Saved captures reviewed for Today, Plan, Labs, Trends overview/chart, and Photos. The chart's
  final month label was corrected without changing the time domain or plotted values.
- Largest-accessibility-text checks cover Today, Plan, Labs, and Photos. Side illustrations
  yield to text; Plan jumps reflow to two columns. The dock keeps readable labels and exposes
  native large-content magnification instead of truncating destination names.
- Fixed a discovered accessibility-identifier collision on routine completion controls; UI
  coverage now exercises both directions of the action.
- An initial parallel run encountered disk exhaustion. No user data was deleted; verification
  was rerun serially with reduced diagnostic collection. The full suite and a separate compact
  simulator pass were not repeated, so the focused result is not a full-regression claim.

Keep the expanded presentation as one coherent Ceramic Horizon / Herbarium / Living Compass
edition. The mutually exclusive concept palettes are not separate user-selectable themes.

### Today follow-up — check-in first

The owner asked to raise daily checking in Today's hierarchy. A compact greeting now leads
directly into Daily check-in and the existing shedding scene, Log/Edit, and Same as yesterday
actions. The review circle, evidence dashboard, and effort rings move below the daily actions
and signal tiles. Reminder promotion no longer precedes logging.

The selected safety grounding card remains above check-in; non-safety notes remain below it.
Selection rules, consent, logging writes, copy semantics, and treatment actions are unchanged.
The existing Log/Edit and copy controls now have minimum 44-point hit targets. Added UI coverage
checks top-of-screen reachability, opening/cancelling the log, copying yesterday, and editing.

Follow-up validation: build succeeded and **32/32 focused tests passed** (27 unit, five UI),
including grounding explanation, routine Complete/Undo/Skip, and all-tab navigation. The routine
test now explicitly scrolls to its lower row before long-pressing it. Saved default-size captures
confirm both Log today and Edit log are reachable without scrolling on iPhone 17 Pro.
Result bundle: `/tmp/hc-today-checkin-final.xcresult`. This was not a full-regression run.
