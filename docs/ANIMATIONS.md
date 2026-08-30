# Animations — the Lottie catalogue and where motion belongs

2026-08-21. The owner asked for more animation, pointing at the
[diffusionstudio/lottie](https://github.com/diffusionstudio/lottie) text-to-Lottie skill.
This file is the candidate map that came out of auditing every surface, what shipped from it,
and the rules that keep motion from becoming clutter.

## The two laws

1. **The gouache is off-limits.** Wren's poses, the onboarding covers, the teaching plates,
   ClarityContrast — all hand-painted raster art. Lottie is vector; a vector redraw of any of it
   would sit inside the app like a sticker on a painting. Those surfaces already move the right
   amount via `LivingArtwork` (drift + breath). **No Lottie ever replaces or imitates painted
   art.**
2. **Motion is punctuation, not furniture.** Everything here is either a *waiting state* (loops
   while real work happens) or a *flourish* (plays once at a moment of completion). If a
   candidate is neither, it's decoration for its own sake — cut. Reduce Motion: loops hold
   their first frame, one-shots vanish (`ClinicalLottie` enforces this; nothing renders raw
   `LottieView`).

## Shipped

| File (`Resources/Animations/`) | Where | Kind | What it is |
|---|---|---|---|
| `wren-thinking.json` | `HairChatSheet.thinkingRow` | loop | Three copper dots, a wave of attention travelling left→right with a quiet beat — the sentence's animated ellipsis while on-device generation runs. |
| `compass-analyzing.json` | `DeepAnalysisSheet` run button | loop | A compass needle seeking its bearing (swing, overshoot, settle, re-seek) — replaces the stock `ProgressView`, the sheet's one off-palette element. Tinted `Clinical.surface` at this call site via `ClinicalLottie(tint:)`. |
| `celebration-burst.json` | `CheckInCelebration` | one-shot | Nine brand-token petals lift out from behind Wren and fade in under a second; then `LeafFallBackdrop`'s ambient drift is all that remains. The staged *entrance* is the one thing the hash-seeded Canvas flecks cannot do — they have no beginning. |

All three are **code-authored Bodymovin JSON** — no After Effects, no export step. The
generator (`gen_lottie.py`, session scratch; recreate freely) emits keyframes directly and the
suite proves the contract: `LottieAssetTests` decodes every shipped JSON on the exact runtime
that ships, checks loops are ≥1.5 s (a shorter loop reads as a tic) and one-shots ≤2 s (longer
upstages the copy).

## Runtime

`lottie-ios` (Airbnb, SPM, pinned `upToNextMajor 4.5.0`) — **the repo's first third-party
dependency**, a deliberate owner-directed exception to the Apple-frameworks-only convention.
It renders bundled JSON offline; no network, no data, App Privacy stays *Data Not Collected*.
All playback goes through `Design/ClinicalLottie.swift` (Reduce Motion, hit-testing,
accessibility, tinting — the house rules live there once).

## Candidates not yet built — ready to author

Ordered by value. Each prompt is written for the text-to-lottie skill's conventions
(transparent background, restraint defaults, purposeful easing, brand palette:
copper `#B1592E`, gold `#C9A15A`, sage `#8A9D7B`, ink `#2B211A`, surface `#FEFCF9`).

1. **Ritual completion flourish** — `RitualView.completeRitual()` is haptic-only today; the
   cover just dismisses. One-shot, ~1 s: *"A single copper hair-strand line draws itself
   across the frame left to right with a calligraphic ease (fast attack, long settle), then
   fades. 320×120, transparent, one stroke, no chrome."* Wire it as a brief overlay between
   `success.notificationOccurred` and dismiss.
2. **Export/report ready** — `ExportSheet` completion is instant text. One-shot: *"A minimal
   document sheet outline draws on (stroke-reveal), a copper checkmark strokes in at its
   corner with a small overshoot, everything holds 300 ms then fades. 200×200, transparent."*
3. **Badge unlock shine** — `newBadgeChip` / ConsistencyCard celebrations. One-shot: *"A
   narrow specular highlight sweeps once across a horizontal gold capsule, 25°, 600 ms,
   ease-in-out; nothing else moves. 280×64, transparent."* Overlay on the existing chip, not a
   replacement.
4. **HealthKit / photo import wait** — anywhere `ProgressView` still appears on-palette-less
   (`grep -rn "ProgressView(" | grep -v tint`). Reuse `compass-analyzing` before authoring
   anything new — one waiting mark app-wide is a feature, not a shortage.
5. **Streak milestone (7/30/90)** — one-shot in the celebration sheet only on milestone days:
   *"A laurel of 5+5 sage leaves grows outward symmetrically from the bottom centre
   (stroke-reveal, staggered 40 ms), holds, fades. 240×140, transparent."* Gate it to
   milestones so ordinary days keep the quieter burst.

**Explicitly rejected:** animating Wren herself (law 1); chart draw-ons in Trends (Swift
Charts owns those; two animation systems in one chart fights); tab-bar icon animations
(`symbolEffect` bounce already there — a second system would double-speak); onboarding page
transitions (parallax is the motion language there); the compass ring (its trim animation
*is* the feature; see `CompassRingView`'s anti-scold note).

## Authoring pipeline (repeatable)

1. Write keyframes in a small Python generator (or by hand) → minified Bodymovin JSON into
   `Hair Compass AI 5/Resources/Animations/` (synchronized group: dropping the file in ships
   it).
2. Add the name to `LottieAssetTests.shipped` with its loop contract.
3. Render it in the simulator behind a reachable flag (`HC_CELEBRATE`, `HC_CHAT`…) and
   screenshot — the simulator **is** this project's Skottie player; verify frame 0, a
   midpoint, and the final frame the way the skill's own checklist demands.
4. Reduce Motion pass: Settings → Accessibility → Motion in the sim, confirm loops freeze
   and one-shots vanish.
