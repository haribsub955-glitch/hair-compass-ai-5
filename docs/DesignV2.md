# Hair Compass — Design V2

Design V2 evolves the warm-premium system without turning the app into an illustration gallery.
Data remains the product; artwork explains context, and motion shows state or continuity.

## Principles

1. **Data first.** Charts, ranges, completion, and photo evidence stay visually dominant.
2. **Illustrate a job.** New art must orient, teach, or reassure—not merely fill space.
3. **One living focal point.** A screen gets at most one animated narrative artwork.
4. **Motion has a budget.** Interactive physics run at 60 fps, ambient Canvas motifs at 30 fps,
   and slow raster drift at 15 fps.
5. **Motion yields to the user.** Procedural motion pauses off-screen and while the app is inactive;
   Reduce Motion renders a static representative frame.
6. **Medical humility.** Artwork and copy support record-keeping and context, never diagnosis.

## Screen review

| Surface | V2 decision | Reason |
|---|---|---|
| Today | Keep the falling-hair hero and live metric motifs; no new raster hero | Today is already the app's strongest data-to-motion expression |
| Trends | Keep the chart and consistency card dominant; use only the existing corner sprig | Decorative art would compete with longitudinal evidence |
| Plan | Add `v2-plan-ritual` behind the coach card | Gives the routine a distinctive, reassuring identity without adding another card |
| Labs | Add `v2-labs-context` behind a shorter context panel | Breaks up a dense results screen and makes the disclaimer easier to scan |
| Photos | Replace the generic mirror empty state with `v2-photo-capture` and a direct capture CTA | Teaches repeatable framing and gives the empty state a next action |
| Daily log | Turn each gauge into a semantic status portrait; add a four-band shedding scene with falling and resting strands | The animation is the input feedback, so density, rhythm, warmth, and accumulation must change with the answer |
| Celebration | Reuse the existing medallion with slow living motion | Adds a focal point without generating a duplicate reward asset |
| Onboarding | Preserve the established compass hero; move all procedural demos to shared scheduling | The narrative is already coherent; performance and consistency were the gap |
| Launch rituals | Preserve interaction design; move simulation and completion burst to shared 60 fps scheduling | Touch response matters here, but background/inactive work does not |
| Add treatment / lab | Fix explicit field foreground and cursor colors | System-inferred colors made entered values nearly invisible on warm surfaces |
| Guided capture | Force a light navigation toolbar | The no-camera fallback previously produced a white title on an ivory sheet |

## Motion system

`MotionTimeline` is the only display-driven scheduling path in Design V2.

- `interactive` — 60 fps: falling hair, launch rituals, touch-reactive strands, completion burst.
- `ambient` — 30 fps: metric motifs, leaf fall, density preview, small particle accents.
- `decorative` — 15 fps: subtle raster artwork drift and breath.

Every tier:

- pauses when its view falls below 2% scroll visibility;
- pauses while the scene is not active;
- becomes a static frame under Reduce Motion;
- uses modulo time for long-running trigonometric animation.

Tab changes use a 220 ms opacity + 0.985 scale settle. Reduce Motion uses a 120 ms opacity-only
transition. The floating selection pill remains the primary spatial continuity cue.

### Semantic status motion

Logging motion represents the selected condition instead of applying one generic flourish:

- Shedding moves from an occasional strand and a single resting curve to denser flow and a larger
  collected tangle. It remains a categorical portrait, never an implied hair count.
- Flaking changes fleck frequency and clump size; redness changes the field wash and breath;
  itch changes prickle frequency; oiliness changes sheen; sleep settles its wave; stress makes its
  trace faster and more irregular.
- Status copy crossfades at band boundaries, magnitude bars spring into the selected band, and the
  scalp composite carries a low-cost pulse whose strength follows the 0–16 score.
- The same shedding scene appears on Today after save, preserving continuity between the answer
  the user chose and the status the app reflects back.

## New assets

All three assets were generated with the built-in image-generation workflow using existing Hair
Compass art as style references, then downsampled for the asset catalog.

| Asset | Size | Prompt intent |
|---|---:|---|
| `v2-plan-ritual` | 1400×933 | Warm gouache routine still life; object cluster right; quiet copy space left |
| `v2-labs-context` | 1400×933 | Amber vials, magnifier, hair strand, and blank reference strip; non-diagnostic |
| `v2-photo-capture` | 1250×1250 | Phone-on-stand and mirror teaching repeatable, non-identifiable framing |

Shared constraints: warm ivory/copper/sage/gold palette, no embedded text, no logos, no watermark,
no diagnosis or prescription implication, and no photorealism.

## Verification checklist

- Main tabs render without tab-bar occlusion or chart compositing conflicts.
- Living art remains behind readable gradients at standard and large text sizes.
- Consecutive frames advance at each active cadence.
- Off-screen/inactive and Reduce Motion states do not schedule continuous work.
- Treatment and lab field content remains readable on warm surfaces.
- Capture title remains readable with and without an available camera.
- SwiftUI build and unit suite pass.
