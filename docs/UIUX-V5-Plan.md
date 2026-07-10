# Hair Compass — UI/UX V5 Plan

V5 should make the app feel less like a set of tracking forms and more like a calm, living record
of change. The interface must communicate status emotionally without exaggerating medical meaning.

## Product outcomes

1. A user understands today's status and next action within five seconds.
2. Logging feels visual and tactile, while every saved value remains explicit and accessible.
3. Motion explains magnitude, continuity, or cause-and-effect; decorative motion stays quiet.
4. Longitudinal evidence remains more prominent than illustration or gamification.
5. Every important flow works with Reduce Motion, VoiceOver, large text, and low-power constraints.

## Priority map

| Priority | Surface | Improvement | Success signal |
|---|---|---|---|
| P0 | Daily log | Semantic animated portraits for shedding, scalp, sleep, and stress | Each band is visually distinguishable without reading the label |
| P0 | Daily log | Compact journey header and live pre-save check-in portrait | The long sheet has clear structure and an understandable summary |
| P0 | Today | Carry the saved shedding portrait and emotional status language into the hero | The state chosen in logging is recognizably reflected after save |
| P0 | Motion system | Shared 60/30/15 fps scheduling, off-screen pause, Reduce Motion frames | No uncontrolled `TimelineView(.animation)` remains |
| P1 | Today | Stronger action hierarchy: one primary action, contextual secondary actions | Users can identify the next useful action immediately |
| P1 | Trends | Progressive disclosure for trend, treatment, trigger, and confidence context | The chart answers “what changed?” before showing detail |
| P1 | Plan | Make completion, refill, tolerance, and milestone state more glanceable | Routine state is readable without opening treatment detail |
| P1 | Labs | Preserve reference-range context while reducing visual density | Flag, value, date, and range scan in that order |
| P1 | Photos | Guided region capture, matched-condition guidance, and clearer empty state | Starting a comparable series takes one obvious action |
| P1 | Sheets/forms | Fix field contrast, disabled-state clarity, keyboard flow, and navigation color | Text and prompts remain readable in every sheet state |
| P2 | Onboarding | Reuse the same semantic motion language as daily logging | The onboarding answer behaves like the later log control |
| P2 | Celebration | Make reward motion feel earned and brief, not game-like or blocking | Celebration reinforces continuity and dismisses cleanly |
| P2 | Empty/error states | Give every empty state one explanation and one next action | No dead-end card or generic placeholder remains |

## Phase 1 — Daily logging

### Structure

- Add a compact “daily portrait” header that previews the path: hair, scalp, context.
- Keep all values in one scrollable sheet, but group them into visually distinct chapters.
- Add a live check-in portrait before save summarizing shedding, scalp score, sleep, and stress.
- Keep the optional note and final save action after the portrait.

### Semantic motion

- **Shedding:** occasional individual strands at minimal; steady flow at normal; grouped events and
  a growing resting collection at elevated/heavy.
- **Flaking:** frequency and clump size rise with the selected band.
- **Redness:** the field warms and breathes more strongly as redness rises.
- **Itch:** prickle ripples become more frequent and harder to ignore.
- **Oiliness:** sheen strength and sweep become more pronounced.
- **Sleep:** the wave settles, moon grows, and stars appear as quality improves.
- **Stress:** the trace becomes faster, hotter, and more irregular as stress rises.

### Interaction

- Crossfade status language at band boundaries.
- Spring magnitude bars into the selected band.
- Use one selection haptic per categorical boundary, never per drag pixel.
- Keep a static representative frame under Reduce Motion.
- Clearly state that shedding scenes are categorical portraits, not measured hair counts.

## Phase 2 — Today

- Preserve a single full-width conditions hero.
- Reflect the saved shedding scene exactly as selected in the log.
- Add a short, non-alarming reflection such as “Steady turnover” or “A heavier day.”
- Keep one primary action: log today or edit log.
- Move secondary education and profile actions away from the primary decision area.
- Animate data changes with a short crossfade/settle; never replay the whole screen on return.

## Phase 3 — Trends

- Lead with trajectory and direction before correlations or raw daily points.
- Pair each trend with plain-language confidence/context (“7-day smoothed,” “limited data,” etc.).
- Keep treatment and trigger markers aligned on the same time domain.
- Reveal raw observations, comparisons, and exports progressively.
- Use motion only when the selected time window or metric changes.

## Phase 4 — Plan, Labs, and Photos

### Plan

- Keep the V2 ritual artwork as a quiet coach-card layer.
- Promote today’s incomplete task and relevant refill/tolerance state.
- Animate completion locally and update progress without moving the entire page.

### Labs

- Keep the contextual lab artwork behind the disclaimer card.
- Establish consistent scan order: test → value → flag → date → reference range.
- Use color plus text and position; never color alone.

### Photos

- Keep the matched-capture artwork as the empty-state teaching visual.
- Make the selected region and capture action persistent.
- Show framing, lighting, distance, and parting guidance before capture.
- Carry the last comparable image as an optional ghost overlay.

## Phase 5 — System-wide polish

- Standardize sheet navigation color, form prompts, disabled states, and keyboard behavior.
- Use the same card radius, border, shadow, spacing, and press response across features.
- Keep tab transitions short and spatially consistent.
- Reuse existing botanical/medallion assets where they add orientation or reward meaning.
- Give empty, loading, permission, offline, and error states dedicated copy and recovery actions.

## Phase 6 — Accessibility and verification

- Test Reduce Motion, VoiceOver adjustable controls, Dynamic Type, contrast, and 44-point targets.
- Verify procedural motion pauses off-screen and when the scene is inactive.
- Build the app and run the Swift Testing unit target.
- Capture simulator states for Today, all four shedding bands, scalp extremes, Plan, Labs, Photos,
  celebration, and add/edit sheets.
- Compare consecutive active frames to confirm motion advances; compare Reduce Motion frames to
  confirm they remain static.

## V5 acceptance criteria

- All four shedding bands differ in density, rhythm, grouping, warmth, resting collection, label,
  and accessible value.
- The log has an orienting header and a live summary before save.
- Today reflects the same semantic scene selected during logging.
- No important text becomes unreadable during sheet presentation or disabled states.
- No decorative artwork competes with data, input, or the primary action.
- Build and unit tests pass with no new warnings attributable to V5.

