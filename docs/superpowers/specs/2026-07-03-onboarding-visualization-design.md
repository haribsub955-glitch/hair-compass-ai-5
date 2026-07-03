# Hair Compass — Cinematic Onboarding (physics-driven)

An impressive, multi-screen first-run that *demonstrates* rather than asks. Each question is its own
screen with a live, physics-driven visualization that reacts to the answer. It writes the same
`Profile` fields as today's `BaselineFlow`, in the warm gouache design language.

Status: design (2026-07-03). Fork decisions pending user confirmation (tech backbone; replace vs augment).

---

## Design principles
- **Show, don't ask.** Every screen answers a question *and* teaches something through motion.
- **The answer drives the physics.** Choosing "heavy shedding" makes more hairs fall — the input is the simulation parameter, not a separate illustration.
- **One idea per screen**, full-bleed, calm pacing, a single primary interaction.
- **Warm gouache, not neon.** Strands are copper/ink on ivory; motion is graceful (sub-gravity, air-drag flutter), never frantic. It should feel premium and editorial, like the brand art in motion.
- **Accessible.** Respect `accessibilityReduceMotion` — every animated screen has a tasteful static fallback (the existing brand art or a still frame).

## Architecture
- `Feature/Onboarding/OnboardingFlow.swift` — a paged container (`TabView(.page)` or a custom step controller) driving an `OnboardingStep` enum; a progress "compass fills" indicator; forward/back; writes to the bound `Profile` at the end (or per step).
- `Feature/Onboarding/Physics/` — reusable simulation primitives (see Physics engine below) + one `…Scene` view per animated screen.
- Replaces the plain `BaselineFlow` **as the first-run experience**; `BaselineFlow` stays as the editable profile sheet (from the Today profile button). Same `Profile` writes, so nothing downstream changes.

## Physics engine (shared)
One tiny, deterministic 2D integrator so every screen speaks the same language:
- **Driver:** `TimelineView(.animation)` → `Canvas`. Each frame computes `dt` from the timeline date; a `Simulation` value type steps particles and the `Canvas` draws them. 60 fps for tens–low-hundreds of particles.
- **Particle:** `position`, `velocity`, `angle`, `angularVelocity`, `length`, `width`, `opacity`, `phase`, `age/lifetime`.
- **Forces (composable per screen):**
  - Gravity `v.y += g·dt` (g ≈ 900–1300 pt/s² — sub-real for grace).
  - Air drag `v *= (1 − drag·dt)` (drag ≈ 0.6–1.2) → hairs flutter, not plummet.
  - Sway/curl `v.x += sin(t·ω + phase)·A·dt` (+ optional smooth curl-noise field) → leaf-like drift.
  - Tumble `angle += angularVel·dt`, `angularVel` nudged toward `k·v.x` → a drifting hair rotates as it falls, then damps to point downward.
  - Spring-to-target `a = kₛ(target − pos) − c·v` (for the finale convergence).
- **Emitter:** spawn from a region at `spawnRate` (per-second), each with jittered length/phase; despawn off-frame with an opacity fade near the bottom.
- **Strand rendering (the "wow"):** each hair is a **2–3 point Verlet chain** rendered as a tapered `Path` (quadratic curve), so it *bends* as it falls and drifts — reads unmistakably as a real hair, not a line. Distance constraints keep segment lengths; gravity + drag act on the tip.
- **Recommended backbone:** SwiftUI `Canvas` + `TimelineView`. SpriteKit is the alternative only if we later want thousands of particles / a built-in solver — the flagship falling-hair could drop into an `SKEmitterNode`. Recommendation: **hybrid — Canvas everywhere, keep SpriteKit as an upgrade path for the one flagship screen if we want density.**

---

## Step 1 — The questions (and the order)
Nine steps: a welcome, seven that map to `Profile`, and a finale. (`baselineStage` is optional, folded into the concern/stage screen.)

| # | Screen | Writes to Profile |
|---|---|---|
| 0 | Welcome | — |
| 1 | Your name | `name` |
| 2 | Biological sex | `sex` |
| 3 | Age | `ageBand` |
| 4 | What are you noticing? (condition) | `condition` |
| 5 | How much are you shedding? | seeds first `DailyEntry.shed` |
| 6 | Does it run in your family? | `familyHistory` |
| 7 | Hair-care habits | `wearsTightStyles`/`usesHeat`/`usesChemicalTreatments` |
| 8 | Pattern stage (optional) | `baselineStage` |
| 9 | Finale — your compass | commit `hasOnboarded` |

---

## Step 2 & 3 — Per-screen visualization, interaction, and physics

### 0 · Welcome
- **Visual:** the brand hero gouache art, but the strands gently **sway** (Verlet chains anchored at the root, driven by a slow curl-noise wind) and a few motes drift up. Title fades in.
- **Interaction:** a single "Begin" that sends a ripple through the field.
- **Physics:** anchored Verlet strands; wind = low-frequency sinusoid + curl noise on the tips; no gravity emission.

### 1 · Your name
- **Visual:** a calm field; as the user types, each character **condenses from drifting motes** into the letter (particles spring-to-target onto glyph outlines).
- **Interaction:** text field; live particle assembly per keystroke; haptic tick.
- **Physics:** spring-to-target (`kₛ, c`) with per-particle targets sampled along the typed text's `Path`.

### 2 · Biological sex → staging scale
- **Visual:** two elegant gouache silhouettes (crown + part-line). Selecting one **morphs** a hair-pattern overlay onto it — a Norwood crown whorl vs a Ludwig central-part — and a small caption reveals the staging scale used.
- **Interaction:** tap to select; the unpicked silhouette recedes/desaturates.
- **Physics:** light — `Shape` `animatableData` cross-morph of the part/whorl path + a particle settle; no full sim.

### 3 · Age
- **Visual:** a horizontal **"hair timeline"** — a band of strands; dragging the age dial ages the field (density/color subtly shift younger→older) so the choice feels consequential without implying doom.
- **Interaction:** a draggable dial/slider snapping to bands (Under 25 … 56+); continuous haptic.
- **Physics:** a density field parameter (see density model below) bound live to the dial; strands re-tinted via an eased interpolation.

### 4 · What are you noticing? (the centerpiece)
- **Visual:** a stylized scalp/head. Each option triggers a **distinct animated demonstration** on it:
  - **Diffuse shedding** → the flagship **falling-hair emitter** (strands detach from the scalp and flutter down with gravity + drag + sway + tumble).
  - **Crown thinning** → a whorl at the crown **sparsifies** (density field thins in a circle; strands fade + shrink).
  - **Receding hairline** → the hairline `Shape` **animates backward** into an M via `animatableData`; strands above fade.
  - **Patches (areata)** → circular clearings **fade in** with a soft edge.
  - **Flaky / itchy scalp** → small **flakes drift** off + a gentle redness pulse (opacity breathing).
  - **Not sure** → the whole field breathes slowly; "we'll help you find the pattern."
- **Interaction:** tap an option → that demonstration plays and stays looping while selected; switching options cross-fades demonstrations.
- **Physics:**
  - Shedding = the emitter + Verlet-chain strands (flagship).
  - Thinning/patches = **density field**: N strands placed by jittered-grid / Poisson-disc, each with a root position; a per-strand `alive` probability driven by a spatial mask (radial for crown, circular for patches) animated 0→target; strands fade/shrink on death.
  - Hairline = animatable `Path` control points morphing full→receded.

### 5 · How much are you shedding? (the interactive "wow")
- **Visual:** the **same falling-hair simulation**, now the whole screen — and a **dial the user drags from Minimal → Heavy directly controls the fall rate in real time.** Drag up and the scalp releases a light drizzle; drag to Heavy and it's a graceful downpour. A live count/label ("a few strands" … "clumps").
- **Interaction:** vertical drag on the dial → `spawnRate` binds live; continuous haptic scaled to intensity; the four `ShedLevel` bands snap.
- **Physics:** `spawnRate` mapped `minimal 0.5/s → heavy ~12/s`; strand `A` (sway) and `g` nudge up slightly with intensity so "heavy" also *feels* heavier. This is the screen that most sells the app — the input literally is the simulation.

### 6 · Does it run in your family?
- **Visual:** a generative **strand-tree** — a central strand; choosing None / One parent / Both / Extended **grows branches** (each relative = a branch drawn by animated `trim` with a spring overshoot), and a **risk arc** fills to an evidence-grounded level (family history OR ~2.72; both-parents highest). Honest caption: "the single strongest measured risk factor — context, not a prediction."
- **Interaction:** segmented choice; branches grow/retract on change; the arc animates.
- **Physics:** spring-driven path `trim` growth (`kₛ, c`) + an animatable arc value; branch endpoints jittered for organic feel.

### 7 · Hair-care habits (three stressor demos)
- **Visual:** a single hero strand; each toggle animates a **real stressor** on it:
  - **Tight styles / tension** → a force pulls one end; the **Verlet chain goes taut**, then **frays/snaps at the follicle** (a few particles detach) → traction shown.
  - **Heat** → a **heat-shimmer** (vertical noise displacement on the strand's path) + desaturation + the strand **curls** (bend added); a faint rising haze.
  - **Chemical** → a **droplet falls** (gravity), lands, **spreads** (growing alpha), the strand **thins to nothing** (width→0) then recovers when toggled off.
- **Interaction:** three toggles; each plays its demo while on; combining them stacks effects.
- **Physics:** tension = Verlet distance-constraint chain with a break threshold; heat = Perlin/sine displacement of path points + color lerp; chemical = a gravity droplet + width decay curve.

### 8 · Pattern stage (optional)
- **Visual:** an interactive illustrated **Norwood (male) / Ludwig (female) scale** — a stepper that **morphs** the pattern on the head illustration through the stages; skippable.
- **Interaction:** a stage stepper (or "not sure / skip"); the illustration morphs between stages.
- **Physics:** light — `Shape` `animatableData` between stage silhouettes + a density thin as the stage advances.

### 9 · Finale — your compass
- **Visual:** every strand and mote from the journey **converges** and **assembles into the brand compass rose** — a satisfying swarm-into-place — then the **streak flame ignites** and "Your compass is set, {name}." A single "Start tracking."
- **Interaction:** tap to enter the app.
- **Physics:** spring-to-target attractor — each particle gets a target sampled along the compass-rose `Path`; damped springs pull them in and settle; a final settle-jitter dampens to zero.

---

## Density-field model (used by 3, 4, 8)
A reusable `DensityField`: root points placed once (jittered grid / Poisson-disc) over a region; each root grows a short Verlet strand. A `mask(point) → aliveProbability` (radial, circular, or hairline-band) is animated toward a target; strands cross-fade/shrink as their probability drops. Cheap, deterministic, and reused across the thinning/patch/hairline/stage screens.

## Data & integration
- Writes the same `Profile` fields → slots into the existing model with zero downstream change.
- Step 5 seeds the first `DailyEntry.shed` so day-one has data (and the Today insight has something to say).
- (Optional) add a `Profile.goal` later if we add a "your goal" screen; out of scope for v1.
- Debug arg `HC_ONBOARD` to jump straight into the flow for iteration/screenshots.

## Performance & accessibility
- Cap particle counts (~120 active); pause `TimelineView` when a screen is off-page; `Canvas` is GPU-backed.
- `accessibilityReduceMotion` → swap each sim for a still brand illustration + the same controls.
- Haptics via `UISelectionFeedbackGenerator` (selection), a continuous generator (dials), and `.success` (finale).

## Testing
- Unit-test the pure physics (`Simulation.step`, `DensityField.mask`, `spawnRate(for: ShedLevel)`, spring settle) with Swift Testing — deterministic given a fixed `dt` seed.
- Verify each screen builds + renders in the Simulator; screenshot the centerpiece screens.

## Build order (phased)
1. Physics engine + `Canvas`/`TimelineView` harness + Verlet strand + the falling-hair emitter (screens 4-shedding & 5) — the flagship, highest wow.
2. Density field (screens 3, 4-thinning/patches, 8) + hairline morph.
3. Stressor demos (7) + family tree (6).
4. Name particle-assembly (1), sex morph (2), welcome (0), finale convergence (9).
5. Flow container, progress, Profile write, reduce-motion fallbacks, haptics, tests.
