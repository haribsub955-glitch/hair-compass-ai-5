# Faster launch rituals + textured haptics — Design (2026-07-11)

Two independent changes.

## 1. Faster launch rituals (replace comb + massage)

**Why they feel wrong now:** `CombRitual` and `MassageRitual` are laborious drag-to-completion
mini-games — you must comb every one of 5 strands until average smoothness > 0.94, or rub in
circles until a progress ring fills. That's slow and fiddly on a launch screen. The fix is not
to polish the combing; it's to make the launch moment a **fast, auto-playing flourish** that
completes on its own in ~1 second (a tap only accelerates it), the way premium apps do a launch
beat — not a chore.

Keep the `RitualKind` cases (`comb/massage/serum/knot`) and the concrete type names
(`CombRitual`, `MassageRitual`) unchanged, so `RitualKind.make`, the coordinator's no-repeat
persistence (`lastRitualKind` rawValue), and the `HC_RITUAL_KIND` debug arg all keep working.
Only each struct's internals + `title`/`hint` change. Both still emit `beats` for the host's
light impact and set `isComplete` after their short duration; RitualView is untouched.

- **`CombRitual` → an automatic single "smoothing pass"** (title "Smooth", hint "One clean
  pass — you're set."). Five wavy strands auto-straighten as a soft copper→gold light bar
  sweeps top→bottom **once** over ~0.9 s; a light sparkle trail follows the bar; each strand
  emits one beat as the bar passes it. `isComplete` when the sweep finishes (elapsed ≥ ~1.0 s).
  A touch anywhere advances the sweep faster (elapsed += extra), so it stays interactive but
  never *requires* interaction. Reuse the existing strand-drawing (quad-curve locks, 3-stroke
  render) but drive smoothness from the sweep's y-position, not from finger proximity.
- **`MassageRitual` → an automatic "settle" pulse** (title "Breathe", hint "A moment, then
  we begin."). Three concentric copper rings pulse outward from center on a ~0.33 s cadence
  (total ~1.0 s), each with a soft radial glow; one beat per ring. A gentle scalp-dot field
  ripples outward with each pulse. `isComplete` at elapsed ≥ ~1.05 s. A touch spawns one extra
  ripple at the touch point (bonus, not required).

Both are elapsed-driven (a `time` accumulator in `step`), so they can't stall. Reduce Motion:
the existing RitualView path draws a single static frame and offers a "Done" button — the new
`draw` must render a sensible static frame at `time == 0` (strands mid-tone, one ring), which
it already will.

## 2. Textured CoreHaptics that mimics the feeling

Today the shedding dial and scrubbers fire a flat `UISelectionFeedbackGenerator` tick on every
band change. Replace that with **CoreHaptics** patterns whose intensity/sharpness *mean*
something — so heavier shedding literally feels heavier under the thumb.

**`Service/Haptics.swift`** — `@MainActor final class Haptics` singleton wrapping
`CHHapticEngine`:
- Capability-gated: if `CHHapticEngine.capabilitiesForHardware().supportsHaptics` is false
  (all simulators, older devices), every method falls back to `UIImpactFeedbackGenerator` /
  `UISelectionFeedbackGenerator` so behavior degrades cleanly and nothing crashes.
- Engine created lazily, `try engine.start()`, with `resetHandler`/`stoppedHandler` that
  restart it (backgrounding stops the engine).
- API:
  - `bandTick(fraction: Double)` — a single transient "strand pluck". intensity =
    `0.35 + 0.55 * fraction`, sharpness = `0.25 + 0.65 * fraction`. Higher band → firmer,
    crisper pluck. Fallback: `UIImpactFeedbackGenerator(style: fraction > 0.66 ? .heavy :
    fraction > 0.33 ? .medium : .light)`.
  - `detentTick()` — a very short, low transient (intensity 0.3, sharpness 0.5) for scrubber
    tick crossings. Fallback: `UISelectionFeedbackGenerator().selectionChanged()`.
  - `startTexture()` / `updateTexture(intensity: Double)` / `stopTexture()` — a continuous
    granular drag texture (a long `.hapticContinuous` event played via
    `makeAdvancedPlayer`; `updateTexture` sends a `CHHapticDynamicParameter`
    `.hapticIntensityControl`; stop stops it). Used only by the two shedding dials while a drag
    is in progress, so running fingers down the "shedding" feels granular. Fallback: no-op
    (transient ticks still fire on band change).
  - `success()` — completion notification. Fallback: `UINotificationFeedbackGenerator`.

**Wiring:**
- `SheddingDial` (OnboardingComponents.swift) and `ShedDialField` (Controls): on drag-begin
  `Haptics.shared.startTexture()`; while dragging, on band change `bandTick(fraction: band /
  (count-1))` and `updateTexture(intensity: currentFraction)`; on drag-end `stopTexture()`.
- `LivingGauge` (Controls): replace the two `selectionChanged()` calls with
  `bandTick(fraction: Double(newBand) / Double(bandCount - 1))`.
- `MetricScrubber`, `CountScrubber` (Controls): replace `selectionChanged()` with
  `detentTick()`.
- Leave `DateStripPicker`, `CapturePreviewChips` on their current feedback (not "hair" texture
  surfaces).

Haptics are NOT gated by Reduce Motion (that governs animation); they remain on.

## Verification honesty
The iOS **Simulator has no haptics** (`supportsHaptics == false`), so the texture can't be
felt in the sim — only the fallback code path runs. Haptics are verified by build + code review
+ the graceful-fallback guarantee; the real texture is felt on a device. The two rituals ARE
screenshot-verifiable (`HC_RITUAL_KIND comb` / `massage`).

## Non-goals
No new ritual kinds, no changes to knot/serum, no haptics on non-scrubber controls, no
Core Haptics AHAP files (patterns built in code).

## Execution
Two Sonnet tracks (disjoint files): A rituals (CombRitual.swift, MassageRitual.swift), B
haptics (new Service/Haptics.swift + 4 control files + SheddingDial). Fable integrates,
builds, screenshots the two rituals, commits.
