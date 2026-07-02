# Hair Compass AI 5 — Tracking & Intelligence Design

**Status:** Approved design (2026-07-02). Combined spec covering five subsystems, to be built in phases.
**Branch:** `rebuild/clinical-minimal` (current warm & premium visual identity).
**Supersedes nothing** — extends the evidence-based tracking already in [docs/TrackingSpec.md](../../TrackingSpec.md).

## Guiding principle (unchanged)

The app is a **documentation instrument, not a diagnosis engine.** Every tracked variable
carries an honest evidence tier; myths are named and excluded, not silently dropped. The AI
layer explains and prioritizes deterministic findings — it never invents numbers, and it never
diagnoses. Treatment-efficacy talk is gated behind the 24-week outcome window.

---

## Scope: five subsystems, one combined spec

1. **Measurement layer** — expand the tracked-variable catalog and classify each as auto-fetched vs manual (user steps 1, 2, 5).
2. **HealthKit auto-fetch** — pluggable signal source, HealthKit first (step 4).
3. **Guided uniform camera** — overlay + ghost + compare (step 3).
4. **AI expert (hybrid)** — deterministic insight → on-device → opt-in cloud (step 6).
5. **UX clarity pass** — iterate over every entry surface (step 7).

Build order (phased implementation plan): 1 → 2 → 3 → 4 → 5.

### Decisions locked with the user (2026-07-02)

- **Wearables:** HealthKit-only, with a pluggable `SignalSource` protocol so a direct Whoop connector can be added later without touching the rest.
- **AI:** Hybrid — on-device Apple Foundation Models for daily insight, opt-in cloud "deep analysis" per request.
- **Cloud model:** Claude **Fable 5** (`claude-fable-5`) via the Messages API — the most capable model, chosen for best-quality analysis. Swift has no official Anthropic SDK, so the call is raw HTTPS. Fable specifics: thinking is always on (omit the `thinking` param — sending `disabled`/`budget_tokens`/`temperature` returns 400); check `stop_reason == "refusal"` before reading content; include a server-side fallback to `claude-opus-4-8` (beta header `server-side-fallback-2026-06-01`).
- **Oiliness:** included because the user asked for it, but labeled an **observation** (WEAK tier), not a risk driver.
- **Excluded myths are named in-app** so users trust the app's honesty.

---

## Subsystem 1 — Measurement layer

### Evidence pass (2026-07-02, targeted verification of the new candidates)

Existing spec already covers, and we do **not** re-derive: family history, smoking, poor sleep→progression,
stress (context), seborrheic-dermatitis flaking/redness/itch, ferritin/TSH/freeT4/vitaminD/B12 labs,
the 24-week treatment gate. Existing spec already rejected: zinc/Cu:Zn, blanket biotin, hair-diameter-diversity.

New candidates, tiered:

| Variable | Tier | Capture | In-app framing |
|---|---|---|---|
| Body weight / BMI | MODERATE (MetS↔AGA OR 3.46; rapid loss→TE) | **Auto (HealthKit)** | Risk/context; rapid-loss triggers a TE note |
| Crash diet / low-protein episode | MODERATE (reversible TE trigger, ~2–3 mo lag) | Manual (episodic `TriggerEvent`) | Timing context |
| Tight styling / heat / chemical | STRONG for traction | Manual (baseline habit + flare) | Preventable cause |
| Diet quality (veg-forward) | WEAK–MOD (protective for AGA) | Manual (periodic) | Supportive, hedged |
| Sleep hours | MODERATE (progression) | **Auto (HealthKit)**, manual quality fallback | Timed vs progression |
| Alcohol (drinks) | WEAK (pooled OR ns) | Manual | "possible modest association, not proven" |
| HRV / resting HR | INSUFFICIENT direct → stress proxy | Auto (HealthKit) | **stress proxy only**, never a hair predictor |
| Scalp oiliness (0–3) | WEAK (DHT downstream correlate) | Manual | **observation**, not a risk driver |
| Sun/UV to scalp | WEAK | (guidance, not a metric) | scalp-protection tip |

**Excluded by name** in an "Explicitly not tracked" note: water intake (myth), dietary caffeine (myth; topical ≠ dietary),
physical exercise as a hair-loss risk factor (no credible causal evidence).

Folded rather than added as standalone trackers (redundant): vitamin-D behavior (covered by the lab),
plain dandruff/Malassezia (covered by seb-derm flaking), dietary iron (covered by ferritin).

### Data-model changes (`Model/Models.swift`, `Model/Enums.swift`)

- **Extend `DailyEntry`**: add `oiliness: Int = 0` (0–3), `alcoholDrinks: Int = 0`. Provide SwiftData property-level defaults (mandatory attrs need `= …` to avoid the lightweight-migration launch crash this project has hit before).
- **New `@Model HealthSnapshot`**: one row per day; fields `date`, `sleepHours: Double?`, `hrvSDNN: Double?`, `restingHR: Double?`, `bodyMassKg: Double?`, `bmi: Double?`, `dietaryProteinG: Double?`. Written by the sync service. All optionals so "not available" is first-class.
- **New `@Model TriggerEvent`**: episodic TE context. `typeRaw` (enum: crashDiet, illness, majorStress, childbirth, newMedication, other), `date`, `note`. New `TriggerType` enum in Enums.swift.
- **Extend `Profile`**: hair-care habit flags `wearsTightStyles: Bool`, `usesHeat: Bool`, `usesChemicalTreatments: Bool` (all `= false`), captured in `BaselineFlow`.
- **New evidence-tier vocabulary**: an `EvidenceTier` enum (strong/moderate/weak/insufficient) + a `TrackedVariable` catalog (title, tier, capture mode auto/manual, one-line "why") so the UX pass (subsystem 5) can render tiers and the "why this matters" affordance from one source of truth.

### Analytics changes (`Model/Analytics.swift`)

- `rapidWeightLoss(snapshots:) -> Bool` — flags a clinically meaningful drop over a trailing window; surfaces the ~2–3-month TE-trigger note.
- Keep all existing pure/deterministic helpers; new helpers stay pure and unit-tested (Swift Testing).

---

## Subsystem 2 — HealthKit auto-fetch (`Service/HealthKitService.swift`, new)

- Protocol `SignalSource` with `func refreshSnapshot(context:) async` and an authorization state. `HealthKitSource` is the first implementation; a `WhoopSource` can be added later without changing callers.
- `HealthKitService` (`@MainActor @Observable`): authorization state machine, reads only the evidence-defensible types — `sleepAnalysis`, `bodyMass`, `bodyMassIndex`, `heartRateVariabilitySDNN`, `restingHeartRate`, `dietaryProtein`, `mindfulSession`.
- On refresh, writes/updates today's `HealthSnapshot` in SwiftData (cache for Trends, the widget, offline, and the AI — never re-queried per view).
- **Build config (prerequisite):** add the HealthKit capability + entitlement and `NSHealthShareUsageDescription` to Info.plist. This is real Xcode project config, not just adding a `.swift` file — flag it in the plan.
- **Framing:** HRV/resting HR are surfaced as a stress proxy with explicit copy; body weight surfaces the rapid-loss trigger note.
- Graceful states: not-determined / denied / no-data all render honestly; the app is fully usable with HealthKit off (manual fallback for sleep quality, etc.).

---

## Subsystem 3 — Guided uniform camera (`Feature/GuidedCaptureView.swift`, `Service/CameraCaptureService.swift`, new)

Current [CapturePhotoSheet.swift](../../../Hair%20Compass%20AI%205/Feature/CapturePhotoSheet.swift) is a plain `PhotosPicker` + metadata dropdowns. Replace with live guided capture; keep picker import as a fallback.

- `CameraCaptureService` — AVFoundation session wrapper (`@MainActor @Observable`): preview layer, capture, permission state. Info.plist `NSCameraUsageDescription` required (build-config prerequisite).
- **Per-region alignment overlay**: frontal hairline frame, vertex crown circle, temple-L / temple-R markers, global frame (drawn in SwiftUI over the preview — precise and reliable, not generated art).
- **Ghost overlay**: last accepted photo of the same region at ~30% opacity, so the user matches head angle/crop. This is the single biggest lever for comparable longitudinal photos.
- **Condition pre-fill**: lighting / distance / parting / wet carried from the last shot of that region (existing `PhotoRecord` metadata fields), keeping comparisons same-condition.
- **Per-region coaching** copy ("part down the middle, arm's length, face a window") + optional **"full set" session** walking all five regions in order for a consistent monthly set.
- **Compare view** (`PhotosView`): same-region before/after slider.
- Storage unchanged: `PhotoStore` + `PhotoRecord` (region + condition metadata already present).

---

## Subsystem 4 — AI expert, hybrid (`Service/InsightEngine.swift`, `Service/CloudAnalysisService.swift`, new)

**Anti-hallucination architecture (the core decision):** a deterministic `RuleBasedInsight` computes the
facts from `HairAnalytics` + recent `DailyEntry`/`HealthSnapshot`/`Treatment`. The LLM only explains and
prioritizes those facts in plain language. Numbers come from analytics, never from the model.

- `InsightEngine` protocol → three implementations:
  - `RuleBasedInsight` — always available; also the grounding input for the LLMs and the fallback.
  - `OnDeviceInsightEngine` — Apple **Foundation Models** (`import FoundationModels`, `SystemLanguageModel`/`LanguageModelSession`), iOS 26. Private, offline, free. Availability-guarded; falls back to rule-based on unsupported devices.
  - `CloudInsightEngine` (`CloudAnalysisService`) — opt-in, per-request "Deep analysis" (e.g. review progress photos). Raw HTTPS to the Claude Messages API (`claude-fable-5`, server-side fallback to `claude-opus-4-8`). Explicit off-device-data consent before each cloud send. API key from env/UserDefaults (mirrors the deleted OpenAI key pattern; no key in repo).
- **Guardrails baked into every prompt/output:** record-keeping/not-diagnosis framing; treatment-efficacy statements gated behind the 24-week rule; honest uncertainty; evidence tiers respected.
- **Surface:** an "Insight" card on `TodayView` (rule-based + on-device), and a clearly-labeled "Deep analysis" entry point (cloud, opt-in) in Photos or You.

**Note:** Swift is not an officially-supported Anthropic SDK language — the cloud call is `URLSession` against `/v1/messages` with `anthropic-version` + `x-api-key` headers, images as base64 `image` content blocks. On-device uses Apple's framework directly.

---

## Subsystem 5 — UX clarity pass (cross-cutting, last)

Iterate over every entry surface — `TodayView`, `LogSheet`, `CareView`, `LabsView`, `PhotosView`, `TrendsView`:

- Every tracked variable renders its **label + evidence-tier microcopy + a "why this matters" tap**, sourced from the `TrackedVariable` catalog (subsystem 1).
- **Auto vs manual badge** ("Auto from Health" vs manual) wherever a value can come from either.
- **Progressive disclosure** in the now-larger `LogSheet` (Shedding · Scalp signs incl. oiliness · Lifestyle · Wellbeing · Note) so it never becomes a wall.
- Proper **empty / loading / permission** states for HealthKit and AI.
- Keep the warm & premium visual system in `Design/Clinical.swift` (see [docs/DesignSystem.md](../../DesignSystem.md)); no new color tokens unless a surface genuinely needs one.

---

## Risks & prerequisites

- **Build config (must precede subsystems 2 & 3):** HealthKit capability + entitlement + `NSHealthShareUsageDescription`; `NSCameraUsageDescription`. These touch project settings, not just files.
- **Foundation Models availability** varies by device — the rule-based fallback must be solid and is the default when unavailable.
- **Cloud AI:** needs an API key + a clear consent flow; sends personal health data off-device only on explicit per-request opt-in. Ship the `refusal` stop-reason and error handling per the claude-api guidance.
- **SwiftData migration:** every new mandatory attribute needs a property-level default to avoid the known stale-store launch crash; the container recovery path already deletes sidecars on failure.
- **Widget snapshot** (`Service/WidgetBridge.swift`) is duplicated on both sides of the App Group — keep in sync if surfacing new fields.

## Testing

- New pure analytics helpers (`rapidWeightLoss`, any tier logic) covered with Swift Testing `@Test`/`#expect`.
- Build + launch verification in the iPhone 17 Pro simulator after each phase; screenshot each affected tab (`HC_TAB`, `HC_SEED_DEMO` debug args).
- Full suite (`xcodebuild test`) at the end of each phase.

## Explicitly out of scope

- Direct Whoop API integration (deferred; `SignalSource` leaves the seam).
- Trichoscopy/dermatoscope feature counting (bare phone camera can't; optional note field only).
- Any variable that failed verification (water, dietary caffeine, exercise-as-risk, zinc, biotin, hair-diameter-diversity).
