# The Evidence-Honest Tracking App — Blueprint

A complete, domain-agnostic playbook for building the *kind* of app this repository is,
for any problem that isn't hair. It documents the principles, the architecture, the design
system, the engagement science, the AI approach, the monetization, and — most importantly —
the **thinking processes** behind each decision, so the same app can be rebuilt for skin,
sleep, migraine, gut health, fertility, chronic-pain, fitness recovery, mood, or any
longitudinal self-tracking domain.

Read it top to bottom once; then use §14 (the porting playbook) as a working checklist.

> Throughout, replace the hair vocabulary with your domain's:
> **primary signal** (hair: daily shedding) · **secondary signals** (scalp flaking/itch,
> oiliness) · **interventions** (minoxidil, finasteride, rosemary oil) · **objective signals**
> (HealthKit sleep/HRV/weight) · **artifacts** (progress photos, lab results) · **events**
> (telogen-effluvium triggers). The abstractions are what port; the nouns are what change.

---

## 0. The one-sentence thesis

**Build a calm, beautiful, scientifically honest instrument that helps a person track a
long-arc condition they can't fully control — rewarding the effort of tracking (never the
outcome), grounding every claim in graded evidence, and turning consistent logging into
understanding, not anxiety.**

Every principle below descends from that sentence. When a decision is unclear, return to it.

---

## 1. First principles (the non-negotiable throughline)

These are the invariants. They appear in the models, the copy, the paywall, the gamification,
and the AI. Violating one is a bug even if it compiles.

1. **Honest uncertainty is the product's identity.** The condition is multi-causal and slow.
   Never imply certainty you don't have. Every tracked variable carries an **evidence tier**
   (strong / moderate / weak / context-only), shown in the UI. Myths are *named and excluded*
   in-app, not silently omitted — the honesty has to be *visible*.
2. **Reward effort, never outcomes.** The user does not control the outcome day to day.
   Gamify *logging, dosing, photographing, showing up* — never "your number went down."
   Rewarding an outcome the user can't control is both cruel and, per the digital-health
   ethics literature, a dark pattern. A bad week must cost zero points.
3. **The free tier is the actual product.** Core tracking is never paywalled. Monetize the
   *depth* layer (AI, analysis, convenience), not the loop. If premium pressure dents free
   retention, soften — the free base feeds everything.
4. **Record-keeping, not diagnosis.** The app never diagnoses, never prescribes, always
   defers to a clinician. This framing is load-bearing in AI prompts, treatment guidance,
   and prescription confirmation flows. Preserve it verbatim.
5. **No dark patterns.** No fake urgency, no countdown timers, no pre-checked upsells, no
   guilt copy, no hidden "skip", no selling data. The honest path is always visible and equal
   in weight.
6. **Deterministic core, thin reactive shell.** All math and logic is pure, injected with
   `now`/`calendar`, unit-tested, and replayable byte-for-byte. The UI is a thin projection of
   it. AI is *grounded* by this core and may never invent numbers.
7. **Privacy is a feature, not a cost.** Health data and media never leave the device without
   explicit consent; identifiers and raw pixels never enter an AI payload. Say so; it's an edge.

---

## 2. Domain modeling — the method that makes it credible

This is the part most trackers get wrong. The credibility comes from a **research pass** that
produces a graded catalog, done *before* any UI.

### 2.1 Do the evidence pass first
Before building, run a rigorous literature review of your domain and produce a `TrackingSpec`
document (`docs/TrackingSpec.md`) that lists, for every candidate variable:
- what it is, and how it's captured (auto vs manual),
- its **evidence tier** for a real link to the outcome,
- a one-line "why this matters" grounded in a citation,
- and, critically, the **excluded myths** — popular variables with *no* credible signal, which
  you will name in-app and refuse to track.

In this app that pass produced: strong (family history, a validated 16-point scalp scale,
traction/heat/chemical, smoking), moderate (shedding, sleep, body weight), weak/observation
(oiliness, alcohol, diet), context-only (stress, HRV), and named myths (water intake, dietary
caffeine, exercise-as-cause). The *shape* is what ports.

### 2.2 Encode the evidence in the type system
- `EvidenceTier { strong, moderate, weak, context }` with display strings.
- `CaptureMode { auto, manual }` with badges ("Auto from Health" / "Manual").
- A single **tracked-variable catalog** (`TrackedVariable.catalog`): `id, title, tier,
  capture, why` — the *one source of truth* the UI reads to render a label, a tier badge, a
  capture badge, and a "why this matters" line. Add a variable in one place.
- An **excluded-myth enum** (`ExcludedMyth`) with `title` + `reason`, rendered in a card so the
  app's restraint is legible.

### 2.3 Validated instruments beat invented scales
Where your domain has a validated clinical instrument (this app uses a 16-point
seborrheic-dermatitis severity score), implement it exactly and cite it. Don't invent a scale
when a validated one exists — it's the difference between a toy and an instrument.

---

## 3. Architecture

**Stack:** SwiftUI + SwiftData (iOS), Apple frameworks only, no third-party SDKs. Xcode
"synchronized folder groups" so new files auto-join their target (no project-file surgery).
Swift 5 mode to keep `@Observable`/AVFoundation/`@Model` friction low.

### 3.1 SwiftData is the single source of truth
One `ModelContainer` over all `@Model` types, persisted on disk, shared with extensions via an
**App Group**. On store-open failure, delete the store sidecars and recreate rather than
fall back to in-memory (a stale schema from an older version must not strand the user). Every
stored attribute has an inline default so lightweight migration never crashes.

### 3.2 The generalized model set
This app's nine `@Model`s map to a reusable spine. Rename the nouns; keep the roles:

| Role (port this) | Hair instance | Notes |
|---|---|---|
| **Profile / baseline** | `Profile` | condition, baseline stage, risk factors, onboarding flag |
| **Daily entry** (primary + secondary signals) | `DailyEntry` | one per day; the core loop's artifact |
| **Intervention** | `Treatment` | the thing the user *does* about it; has a schedule |
| **Intervention event** (adherence) | `TreatmentDose` | one logged use; powers adherence math |
| **Tolerability log** | `SideEffectLog` | why people quit an intervention |
| **Objective measurement** | `LabResult` | a dated value with a reference range + flag |
| **Media artifact** | `PhotoRecord` | path on disk, not bytes in the DB; standardization metadata |
| **External-signal cache** | `HealthSnapshot` | daily cache of platform-health metrics; all optional |
| **Dated context event** | `TriggerEvent` | events whose *effect lags* by weeks |

Store media as a **path** (`PhotoStore` saves JPEGs to disk); the model holds the path.
Store enum values as **raw primitives** with computed accessors to the domain enum, so a label
rename never breaks the schema.

### 3.3 File organization (mirror it)
```
App/        entry point, RootView (tab host), deep-link router, container setup
Design/     the design system (tokens, tab bar) — one file owns the visual language
Model/      @Models + PURE logic (analytics, scores, projections, catalogs, seed)
Service/    side-effecting singletons (@MainActor @Observable): health, notifications,
            purchases, AI, camera, backup, export, photo store, widget bridge, haptics
Feature/    one file per screen/sheet as `private struct ...: View`; Controls/ = reusable
            tactile inputs; Onboarding/, Ritual/ = self-contained subsystems
```
Rule: **pure logic in `Model/`, side effects in `Service/`, thin views in `Feature/`.** A view
should be a projection; if it holds domain math, that math belongs in `Model/` behind a test.

---

## 4. The deterministic analytics core

The heart. A set of **pure enums/structs** with static functions, `now`/`calendar` injected,
no `Date.now` inside, exhaustively unit-tested (Swift Testing). Examples to port:
- **Streaks** with day-boundary and DST correctness (`loggingStreak`, and a Duolingo-style
  `shieldedStreak` that grants grace days).
- **Rolling means / smoothing** so trends read as shape, not noise.
- **Adherence** over a schedule; and **trailing-N-day usage** to turn spiky on/off logs into a
  smooth intensity line (`TreatmentAdherence.dailyAverage`).
- **Reference-range flags** (`below/in/above`) for objective measurements.
- **Direction / trajectory** over a window with explicit thin-data language.
- **Honest association** (Compare): pair a primary signal with a secondary one at a chosen
  **lag** (effect follows cause by weeks), and return only a **sign-and-clarity verdict**
  (`together / opposite / unclear / insufficient`) gated behind a minimum overlap — **never a
  coefficient, never a causal claim.** The phrasing is always "a pattern you're noticing, not
  proof."
- A **composite effort score** built *only* from controllable inputs (§7.2).

Because it's pure, two builds over the same history are byte-identical — which is what makes AI
grounding, prompt caching, and tests trustworthy.

---

## 5. The design system

The look is a deliberate anti-template: **warm, premium, editorial, hand-made** — not clinical
blue, not flat Material. One file (`Design/Clinical.swift`) owns the entire language.

### 5.1 Tokens (define once, never hardcode)
- **Palette:** ivory/cream canvas, a single signature accent (copper), sage + antique-gold
  supporting tones, espresso ink, warm taupe secondaries, hairline separators. Warm, low
  chroma, high legibility. Pick *one* signature accent for your domain and commit.
- **Type:** serif display headlines (`.serif` design), mono-tracked eyebrows (all-caps labels),
  tabular numerals for data. Route sizes through `UIFontMetrics` for Dynamic Type.
- **Depth:** soft warm shadows (contact + ambient) + a 0.5pt top catchlight, not hairline-only
  flatness. A reusable `Card` with this depth; all call sites free.
- **Accessibility is a token concern:** verify text tokens pass WCAG AA (this app's `tertiary`
  was darkened to 4.64:1 after an audit). Honor Reduce Motion everywhere.

### 5.2 Motion & the "living" surfaces
- A one-shot **staggered entrance** (rise + fade) for cards; a spring-driven floating tab bar
  with a matched-geometry active pill.
- **`MotionTimeline` + `Canvas`** procedural animation for domain motifs (falling strands,
  flakes, oil sheen, sleep wave, a stress seismograph). Every motif has a **static
  representative frame** under Reduce Motion.
- **"The input *is* the preview."** The flagship interaction pattern: a drag control whose live
  animation *is* the thing being measured. Dragging the shedding dial makes hair fall behind
  your finger; the `LivingGauge` shell (preview panel + tinted drag track + band labels) is
  written once and every 0–3 / 1–5 field reuses it. Port this: your primary log input should
  *feel* like the thing it records.
- **Texture haptics that mean something** (`Haptics` via CoreHaptics): a heavier band gives a
  firmer, sharper "pluck"; dragging plays a continuous granular texture scaled to the value.
  Capability-gated with `UIFeedbackGenerator` fallbacks. Feedback should encode magnitude.

### 5.3 Generated brand art (the imagery layer)
A recurring lesson from this app: **when a design "doesn't feel like" the product's domain, the
fix is real imagery, not new color tokens.** Generate a consistent set of gouache/editorial
illustrations (this repo uses Higgsfield `nano_banana`) in one house style for: hero banners,
empty states, onboarding vignettes, the paywall banner, procedure/education cards, and — for a
media-progress domain — a **realistic reference sequence** (here: a 4-frame scalp-regrowth
timelapse generated by using the first frame as a consistency reference for the rest). Keep the
style locked (palette, paper grain, negative space) across every asset.

### 5.4 Empty states are first-class
Every zero-data screen gives a *next action* and warm art, never bare chrome. The first session
must communicate the core loop within five seconds.

---

## 6. Onboarding — demonstrate, don't interrogate

A cinematic first run that *teaches something true* about the domain while it collects the
baseline. Principles:
- **Auto-focus the first text field**; let return advance. Remove every avoidable tap.
- **Each question demonstrates a fact.** The shedding dial *is* the falling-hair simulation;
  the sex step shows the staging-scale illustration; habits animate their effect on a strand.
  Your onboarding should make the user feel *understood*, not surveyed.
- **Plain language, clinical term demoted.** Lead with "smooth round patches"; put "alopecia
  areata" underneath as a caption. Simplicity is the headline; rigor is the footnote.
- **Reuse the log's inputs.** Scalp-feel and stress/sleep use the same `LivingGauge` scrubbers
  as the daily log, so onboarding and logging share one grammar.
- **Ask the questions that make later features work.** Collect the inputs your paywall
  projection and personalization need (risk factors, recent trigger events, severity).
- **Endowed progress.** Seed day-one data from the answers so the streak/score is already
  partly filled ("Day 1 is already on the board — you logged it during setup"). Proven to lift
  completion.
- **End on an honest projection + offer** (§9), then a **first-launch tutorial** that switches
  the live tabs underneath as it narrates the loop, then a **permissions ask** (platform
  health) framed by benefit with an equal "Not now."

Keep onboarding's writes identical to the editable baseline flow (one seeding helper, pure and
tested), so re-editing the profile can't diverge from first-run.

---

## 7. Engagement — the science, applied honestly

Ground engagement in the literature (this repo's `docs/research/…-engagement-science.md` is a
cited briefing: Fogg B=MAP, the Hook model, goal-gradient/endowed-progress, Zeigarnik/closure,
loss-aversion streaks, implementation intentions, identity-based habits, SDT). The mechanics:

### 7.1 The daily-score ring (Apple-Fitness idiom, honestly)
2–3 concentric rings + a 0–100 center score, a **hard daily reset**, and a **closure
celebration** (glow + haptic) when a ring closes. This exploits the Zeigarnik/closure effect
that makes Apple's rings work. **Non-negotiable:** every ring is built from a *controllable
effort* input (logged today / doses done / weekly artifact captured) — the outcome signal
**never** touches the score. Weight and redistribute when a ring is unavailable.

### 7.2 Effort-only gamification
An XP engine and level ladder where **every point derives from the tracking process** — logging,
dosing, photographing, measurements, streaks, time milestones. Nothing is ever awarded for the
outcome improving or removed when it worsens. Pure and replayable (only "seen achievements"
persists, for "new since last look"). Surface XP + a level-progress ring on the home screen.

### 7.3 Streaks with grace, not anxiety
Streak-anxiety drives churn. Implement a **shield/freeze**: earn a grace day every N consecutive
logs (cap 2); a single missed day spends a shield and the streak survives; a longer gap resets.
Deterministic from history, no stored state. Loss aversion, without the cruelty.

### 7.4 Identity copy, not outcome copy
Celebration and status lines say "you're someone who shows up for your [domain]" — never "your
number improved." Identity-based habits are more durable and stay honest about what the user
controls.

### 7.5 Launch rituals (optional delight)
Short (~1s) **auto-playing** brand moments on some app opens (this app: a comb "Smooth" sweep, a
"Breathe" pulse). Show them on a **fixed cadence** (every Nth open, not every open, not random),
never on first launch, always skippable, always Reduce-Motion-safe. Delight, never friction.

### 7.6 Notifications: capped, user-timed, invitational
One evening reminder at a **user-chosen** time, **≤1/day**, skipped on days already logged,
invitation-toned ("Ready for tonight's check-in?"), never guilt. The retention cliff past
~1/day is real; respect it.

---

## 8. The AI layer — hybrid, grounded, honest

### 8.1 Shape
- **On-device first** (Apple Foundation Models) for the daily insight; **opt-in cloud** (a
  frontier model via raw URLSession, no SDK) for deep, multi-source analysis and chat.
  Deterministic rule-based fallback when neither is available.
- **A single versioned context object** (`AIContext`, `schemaVersion`) is the *only* thing any
  AI feature consumes — one machine-readable JSON shape over *all* the models: profile facts,
  the daily series with pre-computed trend stats, interventions (with adherence + tolerability),
  **objective measurements/labs**, dated events, external signals, and media *metadata*. Build
  it purely (`now` injected, `.sortedKeys` encoding) so it's test-stable and cacheable.

### 8.2 The hard rules (port verbatim)
- **The model never invents numbers.** All arithmetic is done by the deterministic core and
  handed to the model as facts; the model only *phrases* them.
- **No identifiers, no raw media.** No name in the payload; photos are metadata only (count,
  regions, dates) — pixels never enter a text payload. The cloud photo analysis sends images
  only behind an explicit one-time consent gate (revocable).
- **Record-keeping, not diagnosis** is in the system prompt; off-topic queries get a one-line
  redirect; scope is hard-limited to the domain + the user's JSON.
- **Read from *all* sources, uniformly.** Ensure every AI surface (daily insight, deep analysis,
  chat) builds from the same organized context — including the objective measurements (labs).
  A lighter daily-insight context must still carry the same sources, or it will "forget" data
  the deep path knows.

---

## 9. Monetization

### 9.1 The honest paywall
Presented at the end of onboarding as **"your plan."** A scientifically grounded projection
where the **only** quantitative curve is a *published* clinical average for the user's profile
(everyone else gets qualitative milestones), every chart labeled **"Illustrative — published
averages, not a prediction of your results,"** the post-price always visible, **"Continue free"**
equal in weight and directly under the buy buttons, restore-purchases present, and **no**
timers/scarcity/fake discounts. Purchase buttons render only when real products load — never a
placeholder price.

### 9.2 The stack (StoreKit 2)
- **Subscription** (monthly + annual, annual anchored ~50% off) gating the *depth* layer: AI
  chat, AI deep analysis, advanced compare, longer media history, coaching, backup/sync.
- **Free trial** as an Apple introductory offer, **eligibility-gated** (one per subscription
  group per Apple ID) — never show a trial CTA to an ineligible user.
- Consider a **lifetime unlock** (non-consumable) for the subscription-averse segment.
- **Affiliate commerce** as low-friction secondary revenue: an evidence-tiered product catalog
  with maker-funding disclosure, tier badges, deficiency-gating ("test first"), and links hidden
  until configured. Monetizes free users without a paywall and reinforces the science stance.
- **Referral to clinicians/telehealth** (the export hand-off) is the biggest upside for
  high-WTP domains, but the most regulated — scope carefully; keep it a referral, never advice.
- **Never** sell data or run ad networks.

`PurchaseService` is a `@MainActor @Observable` StoreKit-2 wrapper (`Transaction.updates`
listener, `currentEntitlements` → `hasPro`); a `ProGate` view wraps premium content with the
same honest offer. A local `.storekit` config exercises it in the simulator.

---

## 10. Data capture subsystems

- **Guided media capture** (`GuidedCaptureView` + `CameraCaptureService`): AVFoundation live
  preview with a per-region overlay, a ghost of the last shot, same-condition pre-fill, and
  standardization metadata (lighting/distance/parting) — because comparability is the whole
  point of progress media. Guard the capture continuation against double-taps.
- **Media journey/timelapse** (`JourneyPlayerView`): aggregate N same-condition artifacts into
  a scrubbable, play/pause progression; seed the empty state with a generated realistic example
  clearly badged as an example.
- **External health signals** (`HealthKitService` behind a `SignalSource` protocol so other
  sources are pluggable): read *only* the evidence-defensible metrics for your domain, cache a
  daily snapshot (all values optional; "not available" is first-class), and degrade honestly
  when permission is off (a "Connect" CTA, never a broken chart).
- **Objective measurements** (`LabsView` + `LabResult`): dated values with validated reference
  ranges rendered as range gauges with in/below/above flags — context, never diagnosis.
- **Interventions & adherence** (`CareView`, `TreatmentGuide`, `RxGate`): per-class application
  guidance, schedule + reminders + refill tracking, a coach, milestone windows, and a friendly
  "usually prescription-only — we assume a clinician prescribed it" confirmation (reassurance,
  never gatekeeping).
- **Education** (`LearnLibrary` + `LearnView`): a flash-card library where myth cards are
  labeled MYTH — the honesty stance as content.
- **Export** (`ExportService`): a plain-text clinician summary + a JSON backup, both from the
  same models, shareable. This is also the hook for the telehealth referral.

---

## 11. Widget & extensions

- Write a `Codable` **snapshot** into the shared App Group, then reload timelines. The struct is
  **duplicated** across app and widget targets — pin it with identical `CodingKeys` + a
  "KEEP IN SYNC" header + a round-trip test, since the widget target can't import the app's
  models.
- The widget shows *recent status at a glance* in the app's own visual language (the rings,
  streak, primary signal) and **deep-links straight into logging** (`widgetURL` →
  `scheme://log`, handled by a `DeepLinkRouter` that routes to the tab and presents the log
  sheet). A widget's job is one-tap re-entry.
- **App Group gotcha to check on day one:** the app target's `application-groups` entitlement
  must actually contain the group string, or `UserDefaults(suiteName:)` silently no-ops and the
  widget shows only placeholder data. (This exact bug bit this repo.)

---

## 12. Privacy & security

- **App lock** (Face ID) presented in its own `UIWindow` above the entire sheet/cover stack — a
  locked app must never show content, whatever was on screen.
- **AI consent** gate before any media leaves the device; revocable; enforced defensively inside
  the cloud service, not just the UI.
- **Versioned backup/restore** with base64 media and **natural-key merge** (restore never
  duplicates or deletes); CloudKit-ready schema.
- No third-party analytics SDK — local-only event logging via `os.Logger` + counts in
  `UserDefaults` if you need product metrics. No data brokerage, ever.

---

## 13. The build process (how this app is actually made)

The engineering method is part of the blueprint. It's what let this app move fast without
losing rigor.

1. **Brainstorm → Spec → Plan → Implement → Verify.** Every feature starts as a design spec in
   `docs/superpowers/specs/` and a task-decomposed plan in `docs/superpowers/plans/` with
   **frozen interface contracts** between work units.
2. **Research before building** where the domain warrants it (the evidence pass; the engagement
   science briefing) — cited, saved under `docs/research/`.
3. **Parallel implementation over disjoint files.** Decompose a feature into 2–4 tracks that own
   *non-overlapping* files, with the cross-track types frozen in the plan; implement them
   concurrently; integrate, build, and commit centrally. Interface drift is the only real risk —
   the frozen contracts prevent it.
4. **Pure core is TDD'd** with Swift Testing (`@Test`/`#expect`), not XCTest. Views are verified
   by **building + running in the simulator + screenshots**, driven by `#if DEBUG` launch
   arguments (`HC_TAB`, `HC_SEED_DEMO`, `HC_ONBOARD_STEP n`, `HC_RITUAL_KIND`, …) since GUI tap
   automation is unreliable — deterministic launch args are how you reach any screen headlessly.
5. **Verify before claiming done:** build green (app + every extension target), tests pass, and
   the actual screen screenshotted. Simulators have **no haptics** and can't place widgets — be
   honest about what's code-verified vs felt-on-device.
6. **Persist the non-obvious** in project memory/docs: build/run recipes, the stale-store crash
   fix, the App-Group gotcha, the Swift-Charts multi-series trap, the icon-corner check.

Recurring gotchas worth stating up front for a new build:
- SwiftData: give every stored attr an inline default (migration safety); a stale store from an
  old schema is a launch crash — clear the `.store*` sidecars.
- Swift Charts: `LineMark`s without an explicit `series:` merge into one line; leading Y-axis
  labels of varying width make charts "breathe" horizontally — pin the label width.
- Presented sheets/covers **don't inherit** the environment from where the modifier is *set* —
  re-inject services on the cover's content.
- SwiftUI `Canvas`/CoreGraphics is the right tool for the "living" motifs; back per-frame
  mutation with a reference box so it doesn't thrash SwiftUI state.

---

## 14. Porting playbook — build it for a new domain

A concrete, ordered checklist. Work top-down; each step has a real deliverable.

**Step 0 — Pick a domain with the right shape.** Best fit: a *longitudinal, multi-causal,
partly-uncontrollable* condition with a daily-loggable primary signal, some interventions,
objective measurements, and progress media. (Skin/acne, sleep, migraine, IBS/gut, mood/anxiety,
fertility cycles, chronic pain, tinnitus, allergy, post-injury recovery all fit.)

**Step 1 — Evidence pass → `TrackingSpec.md`.** Grade every candidate variable into
strong/moderate/weak/context; name the myths you'll exclude; find a validated instrument if one
exists. This is the credibility foundation — don't skip it.

**Step 2 — Fill the abstraction table.**

| Abstraction | Your domain |
|---|---|
| Primary signal (daily, 0–3 or 1–5) | e.g. migraine: *headache severity* |
| Secondary signals | aura, nausea, photophobia |
| Interventions (+ schedule) | triptans, preventives, magnesium |
| Objective measurements (+ ranges) | BP, sleep hours, cycle day |
| Media artifact (optional) | n/a — or food/skin photos in other domains |
| External signals (platform health) | sleep, HRV, menstrual data, weather/pressure |
| Dated context events (lagged) | menstruation, weather front, missed meal |
| Composite effort score inputs | logged today · took preventive · slept ≥7h |

**Step 3 — Model the spine** (§3.2): rename the nine `@Model` roles; keep the raw-value+enum
pattern and the on-disk-path for media.

**Step 4 — Build the pure core** (§4): streaks (+shields), rolling means, adherence, range
flags, trajectory, the honest lagged Compare, and the effort score. TDD it.

**Step 5 — Stand up the design system** (§5): pick one signature accent; generate the house-style
art set; build the `Card`, the `LivingGauge`, the tab bar, the tokens. Verify contrast + Dynamic
Type + Reduce Motion.

**Step 6 — The core loop:** Today (rings + score + primary-signal hero as a "living" input) →
the log sheet (LivingGauge scrubbers) → Trends (smoothed charts, pinned axes) → Compare.

**Step 7 — Onboarding** (§6): demonstrate-don't-ask, plain language, endowed-progress seeding,
projection paywall, tutorial, permissions.

**Step 8 — Engagement** (§7): effort-only rings + XP, shielded streaks, identity copy, capped
user-timed reminders, optional cadence-gated rituals.

**Step 9 — AI** (§8): the versioned context over *all* sources, on-device + consented cloud +
deterministic fallback, the hard honesty rules.

**Step 10 — Capture subsystems** (§10) your domain needs: guided media, external signals,
objective measurements, interventions/adherence, education, export.

**Step 11 — Monetization** (§9): honest paywall, StoreKit stack, eligibility-gated trial,
evidence-tiered affiliate, (optionally) telehealth referral.

**Step 12 — Widget + privacy + backup** (§11, §12).

**Step 13 — Verify** (§13): build every target, run the pure-core tests, screenshot every screen
via launch args, and be honest about device-only surfaces.

**Do-not-ship gate:** re-read §1. If any screen rewards an outcome, gates the core loop, implies
certainty, uses a dark pattern, ships a fabricated number to the model, or leaks an identifier —
it's not done, regardless of build status.

---

## 15. What makes this app *feel* different (the intangibles to preserve)

- It reads like an **instrument crafted by someone who respects both the science and the user**,
  not a growth-hacked funnel.
- The **honesty is visible** — evidence tiers, named myths, "a pattern, not proof," "illustrative,
  not a prediction." That candor is the trust, and the trust is the retention.
- The **effort, not the outcome, is celebrated** — which is kinder and, for an uncontrollable
  condition, the only defensible design.
- The **craft is total** — generated art in one house style, procedural "living" motifs, texture
  haptics, spring motion, warm depth — so it never reads as a template.

Build for a new domain by keeping those four intangibles and the seven first principles; swap
everything else.
