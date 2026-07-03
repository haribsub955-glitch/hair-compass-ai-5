# Hair Compass AI 5 — Handover

A single document to pick up the project cold: what it is, how it's designed and built, every
feature and where its code lives, and what's left before shipping. Companion docs:
[docs/DesignSystem.md](docs/DesignSystem.md) (design tokens), [docs/TrackingSpec.md](docs/TrackingSpec.md)
(evidence basis), [docs/superpowers/specs/2026-07-02-tracking-intelligence-design.md](docs/superpowers/specs/2026-07-02-tracking-intelligence-design.md)
(the tracking/intelligence design spec), and [CLAUDE.md](CLAUDE.md) (repo conventions).

---

## 1. What it is

A native iOS app (SwiftUI + SwiftData, iOS 26.2, Swift 5) for tracking and understanding hair/scalp
health. Its guiding stance — the thing that must never be diluted:

> **A documentation and education instrument, not a diagnosis engine.** Every signal carries an
> honest evidence tier, myths are named and excluded rather than silently dropped, AI explains
> deterministic findings but never invents numbers, and treatment-efficacy is gated behind the
> 24-week clinical-trial window. Where money is involved (affiliate products), the evidence rating
> is shown and never bent.

Five tabs: **Today · Trends · Plan · Labs · Photos** (the tab enum case is still `care`; its title
is "Plan"). A Home Screen widget mirrors today's state.

---

## 2. Build, run, test

Xcode project (no SPM/CocoaPods — Apple frameworks only). Scheme **`Hair Compass AI 5`**. Paths
contain spaces — always quote.

```bash
# Build
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
# Test (Swift Testing framework, not XCTest)
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Bundle id `harib.Hair-Compass-AI-5`; App Group `group.harib.Hair-Compass-AI-5`; subscription group
`21442176`. **Targets:** the app, the `Hair Compass CheckIn Widget` extension, the unit test bundle
(Swift Testing), and a UI test bundle (XCUITest).

**Adding/removing `.swift` files needs no pbxproj edits** — the project uses
`PBXFileSystemSynchronizedRootGroup`, so files on disk auto-join the target. Capabilities and
Info.plist keys are the exception (they're real project config — see §9).

### Debug launch arguments (DEBUG builds only)
| Arg | Effect |
|---|---|
| `HC_SEED_DEMO` | Seeds ~120 days of demo data (profile, entries, doses, labs, a trigger, weekly health snapshots) |
| `HC_TAB <today\|trends\|care\|labs\|photos>` | Opens on that tab |
| `HC_LEARN` | Opens the Learn sheet on launch |
| `HC_SCROLL_PRODUCTS` | Scrolls Plan to the science-products section |
| `HC_COMPARE` / `HC_EXPORT` | Opens the Compare / Export sheet from Trends |

Example: `xcrun simctl launch <SIM> harib.Hair-Compass-AI-5 HC_SEED_DEMO HC_TAB care`

---

## 3. Design system (incorporated)

Source of truth for tokens is [Design/Clinical.swift](Hair%20Compass%20AI%205/Design/Clinical.swift);
[docs/DesignSystem.md](docs/DesignSystem.md) is the written spec (keep both in sync). Direction:
**warm & premium** — a premium wellness/skincare feel, warm and tactile, unmistakably about hair.
(History: the app went pearl/serif → a rejected "clinical-minimal" white/blue rebuild → this warm
identity. The `Clinical` enum name is kept for continuity; the *content* is warm, not clinical.) A
Google Stitch pass independently regenerated this exact system ("Botanical Heritage"), confirming it.

**Palette** (`Clinical.*`):

| Token | Hex | Use |
|---|---|---|
| canvas | `#FBF6EF` | screen background (warm ivory) |
| surface | `#FEFCF9` | cards |
| ink | `#2B211A` | primary text (espresso, not black) |
| secondary | `#7A6B5D` | supporting text |
| tertiary | `#A69687` | captions, chart ticks |
| hairline | `#EDE1D3` | borders |
| accent | `#B1592E` | copper — CTAs, active states, selected segments |
| gold | `#C9A15A` | antique gold — highlights |
| sage | `#8A9D7B` | botanical green — matches the artwork |
| positive/warning/critical | `#5C7A52` / `#B98B2E` / `#A6432E` | flags only |

**Type:** serif headlines (`Clinical.headline`), SF monospaced uppercase tracked eyebrows
(`Clinical.eyebrow`), SF body with tabular figures for numbers (`Clinical.number`).
**Shape/elevation:** 22pt-radius warm-white cards with a diffuse warm-espresso shadow
(`Clinical.cardShadow`); primary buttons are solid copper with a soft glow.
**Evidence colors:** `Clinical.tierColor(_:)` for tracked-variable tiers and `Clinical.productColor(_:)`
for product tiers — confidence recedes into muted tones so nothing overclaims.

**Reusable components in Clinical.swift:** `ClinicalCard`, `Eyebrow`, `ScreenHeader`, `StatBlock`,
`ClinicalSegmented`, `ClinicalButtonStyle`, `PipStepper`, `ProgressBar`, `TierBadge`, `ProductBadge`,
`WhyDisclosure`, `VariableSectionHeader`, and the `clinicalScreen()` modifier.

**Imagery (`BrandArt`):** one painterly gouache style (terracotta/cream/sage/gold, botanical sprigs +
hair strands + compass rose), generated with `nano_banana_pro` (Higgsfield MCP). Assets: `hero-today`,
`hero-baseline`, `hero-photos-empty`, `AppIcon`, and the Learn card art `learn-{basics,conditions,
treatments,supplements,myths,dailycare}`. **App-icon gotcha:** generated icon art can bake in its own
rounded corners; prompt for "full-bleed square, sharp 90° corners" and verify corner pixels.

---

## 4. Architecture

SwiftData is the single source of truth. [App/HairCompassApp.swift](Hair%20Compass%20AI%205/App/HairCompassApp.swift)
builds one `ModelContainer` over all `@Model` types; on a store-open failure it deletes the on-disk
store + sidecars and recreates (in-memory as last resort) rather than crashing. It also seeds the
Claude API key from the environment (`AIConfig.seedKeyIfProvided`).
[App/RootView.swift](Hair%20Compass%20AI%205/App/RootView.swift) owns the flat `FloatingTabBar`,
injects the observable services as environment values, drives first-run onboarding, and publishes the
widget snapshot on data change.

### Data model — [Model/Models.swift](Hair%20Compass%20AI%205/Model/Models.swift)
Raw values stored as primitives, bridged to domain enums (in [Model/Enums.swift](Hair%20Compass%20AI%205/Model/Enums.swift))
via computed accessors, so a case-label change never breaks the schema. **Every stored attribute has
an inline default** — mandatory attributes without a property-level default cause a lightweight-migration
launch crash (learned the hard way).

| `@Model` | Purpose | Notable fields |
|---|---|---|
| `Profile` | Baseline (captured once, editable) | condition, sex, familyHistory, baselineStage, hasOnboarded, `wearsTightStyles`/`usesHeat`/`usesChemicalTreatments` (traction), `hasTractionRisk` |
| `DailyEntry` | Daily self-report | shed, flaking/erythema/itch (→ 16-pt scalp scale), sleepQuality, stress, cigarettes, `alcoholDrinks`, `oiliness`, note |
| `Treatment` / `TreatmentDose` | Regimen + adherence | class, dose, scheduleTimes→`slots`, startDate; doses log per slot |
| `LabResult` | Bloodwork | test, value, `flag` (vs reference range) |
| `PhotoRecord` | Progress photos | region + capture-condition metadata (lighting/distance/parting/wet) |
| `HealthSnapshot` | Daily HealthKit cache | sleepHours, hrvSDNN, restingHR, bodyMassKg, bmi, dietaryProteinG (all optional) |
| `TriggerEvent` | Episodic TE triggers | type (crashDiet/illness/…), date, note; `weeksElapsed()` |

### Pure/deterministic logic (unit-tested, no SwiftData/UI)
- [Model/Analytics.swift](Hair%20Compass%20AI%205/Model/Analytics.swift) `HairAnalytics` — scalp 16-pt scale, lab flags, 24-week outcome gate, adherence, rolling average, direction, streak, `rapidWeightLossPercent`, baseline risk notes.
- [Model/TreatmentGuide.swift](Hair%20Compass%20AI%205/Model/TreatmentGuide.swift) — application guidance, `RoutinePlanner` (Morning/Evening/Periodic grouping), `AdherenceCoach`, `Milestones`.
- [Model/ChartMetric.swift](Hair%20Compass%20AI%205/Model/ChartMetric.swift) — metric catalog + `ChartMath` (normalize, `pairWithLag`, honest `association`).
- [Model/LearnLibrary.swift](Hair%20Compass%20AI%205/Model/LearnLibrary.swift), [Model/ScienceProduct.swift](Hair%20Compass%20AI%205/Model/ScienceProduct.swift), [Model/TreatmentRecommender.swift](Hair%20Compass%20AI%205/Model/TreatmentRecommender.swift) — curated evidence-tiered catalogs.

### Services — `@MainActor @Observable`, injected via environment
| Service | Role |
|---|---|
| `PhotoStore` | Saves JPEGs to Documents; `PhotoRecord` holds the path, not bytes |
| `HealthKitService` (+ `SignalSource` protocol) | Reads the evidence-defensible HealthKit types into a daily `HealthSnapshot`. Pluggable — a Whoop source can conform later |
| `CameraCaptureService` | AVFoundation session for guided capture (falls back to picker if no camera) |
| `InsightEngine` | `RuleBasedInsight` (deterministic facts) → on-device Apple Foundation Models → rule-based fallback |
| `CloudAnalysisService` (+ `AIConfig`) | Opt-in cloud "deep analysis" via Claude **Fable 5** (`claude-fable-5`, server-side fallback to `claude-opus-4-8`), raw HTTPS, vision, refusal handling |
| `NotificationService` | Local reminders: routine slot times, evening log nudge, monthly photo prompt |
| `AffiliateStore` | Per-product affiliate links in UserDefaults (nothing in the repo) |
| `ExportService` | Clinician text summary + full JSON data export |
| `WidgetBridge` (+ `WidgetSnapshotBuilder`) | Writes the App-Group snapshot the widget reads |

---

## 5. Feature map (screen → what it does → key files)

- **Today** [Feature/TodayView.swift](Hair%20Compass%20AI%205/Feature/TodayView.swift) — greeting + hero, daily-log card, **AI insight** card (on-device/rule-based, "Deep analysis with photos" → `DeepAnalysisSheet`), today's treatments, a **Learn** flash-card carousel (→ `LearnView`), readout, status. Logging via [Feature/LogSheet.swift](Hair%20Compass%20AI%205/Feature/LogSheet.swift).
- **Trends** [Feature/TrendsView.swift](Hair%20Compass%20AI%205/Feature/TrendsView.swift) — range picker, **Lifestyle signals** (HealthKit connect/metrics, rapid-weight-loss + traction + trigger notes), shedding/scalp/adherence charts, **Compare** entry (→ `CompareView`), **Export** button (→ `ExportSheet`), "Explicitly not tracked" honesty card.
- **Plan** [Feature/CareView.swift](Hair%20Compass%20AI%205/Feature/CareView.swift) — **Coach** card + **milestones**, **Today's routine** (grouped, check-off, per-step guidance), **What the evidence supports for you** (→ `RecommenderView`), **Reminders** toggle, 24-week gate, treatment cards, **Science-backed options** (→ `ScienceProductsView` + `ManageLinksSheet`). Add via [Feature/AddTreatmentSheet.swift](Hair%20Compass%20AI%205/Feature/AddTreatmentSheet.swift).
- **Labs** [Feature/LabsView.swift](Hair%20Compass%20AI%205/Feature/LabsView.swift) — bloodwork with reference-range flags; add via `AddLabSheet`.
- **Photos** [Feature/PhotosView.swift](Hair%20Compass%20AI%205/Feature/PhotosView.swift) — per-region series, **guided capture** (→ `GuidedCaptureView`: live overlay + ghost of last shot + condition pre-fill), before/after **slider** (→ `PhotoCompareView`).
- **Baseline/profile** [Feature/BaselineFlow.swift](Hair%20Compass%20AI%205/Feature/BaselineFlow.swift) — one-time setup (condition, sex, family history, hair-care habits) + About/legal footer.
- **Learn** [Feature/LearnView.swift](Hair%20Compass%20AI%205/Feature/LearnView.swift) — tap-to-flip evidence cards in six categories; myths render a MYTH badge.
- **Widget** [Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift](Hair%20Compass%20CheckIn%20Widget/HairCompassCheckInWidget.swift) — streak, today's remaining steps, latest readout; warm palette (mirror `Clinical` hexes; the widget target can't import the app's `Clinical`).

---

## 6. Evidence basis (why each thing is or isn't in the app)

Anchored to [docs/TrackingSpec.md](docs/TrackingSpec.md) (a 106-agent deep-research run) plus two
targeted evidence passes (tracked variables; supplements). The rules the whole product enforces:

- **Tracked variables** carry tiers (`EvidenceTier` in Enums.swift, catalog `TrackedVariable`). Strong: family history, smoking, traction, scalp SD scale. Moderate: sleep→progression, body weight, crash-diet TE trigger. Weak/context/observation: oiliness, alcohol, HRV-as-stress-proxy. **Named-and-excluded myths** (`ExcludedMyth`): water intake, dietary caffeine, exercise-as-risk. Also rejected upstream: blanket biotin, multivitamins, zinc/Cu:Zn.
- **Supplements** (`ScienceProduct`, `ProductEvidence`): no supplement beats minoxidil/finasteride. Moderate: rosemary oil (≈ minoxidil 2% in one RCT), ketoconazole, saw palmetto. Limited/early below that. Deficiency-gated: iron, vitamin D. The catalog **cannot contain a myth** (biotin/gummies/collagen/zinc/niacinamide are excluded; they appear only as Learn myth cards).
- **Treatment recommender** (`TreatmentRecommender`): ranks by pattern (condition + sex), always clinician-noted, never a prescription/dose. Male AGA → minoxidil+finasteride first; female → topical minoxidil; alopecia areata → specialist.
- **24-week gate:** treatment efficacy is never judged before week 24 anywhere in the app.
- **AI grounding:** the LLM only explains/prioritizes numbers `HairAnalytics` computed; it never generates them, and always carries the not-diagnosis framing.

---

## 7. AI (hybrid)

- **On-device** — Apple Foundation Models (`import FoundationModels`), availability-guarded, for the daily Today insight; falls back to the deterministic `RuleBasedInsight` when unavailable (e.g. the Simulator, or a non-Apple-Intelligence device).
- **Cloud (opt-in, per request)** — `CloudAnalysisService` calls Claude **Fable 5** over raw HTTPS (`/v1/messages`, `anthropic-version: 2023-06-01`, `x-api-key`, `anthropic-beta: server-side-fallback-2026-06-01`, `fallbacks: [{model: claude-opus-4-8}]`, no `thinking`/`temperature`, checks `stop_reason == "refusal"` before reading content). Sends deterministic facts + progress photos with explicit consent. Requires an API key (see §9); gated behind `DeepAnalysisSheet` consent.

---

## 8. Testing

Unit tests are **Swift Testing** (`import Testing`, `@Test`, `#expect`) in the app test bundle,
covering the pure logic: scalp scale, lab flags, 24-week gate, adherence, streak, rapid weight loss,
tracked-variable tiers, routine planner, adherence coach, milestones, Learn integrity, science
catalog (myth-free) + affiliate store, chart math (association/normalize/lag), recommender ranking,
widget snapshot. **37 tests, all passing.** Write new pure logic with tests; UI is verified by
building + launching + screenshotting in the Simulator.

> Note: the XCUITest runner has intermittently failed to *launch* after many rapid install cycles in
> one session — that's a Simulator flake, not a code failure; the unit bundle stays green. Boot the
> sim (`simctl boot`) if `simctl` reports "Shutdown".

---

## 9. Configuration & secrets (nothing sensitive is in the repo)

| Thing | Where | How to set |
|---|---|---|
| Claude API key (cloud deep analysis) | UserDefaults `claudeAPIKey`, seeded from env | Set `ANTHROPIC_API_KEY` in the scheme's run env (`AIConfig.seedKeyIfProvided`) |
| iHerb affiliate links | UserDefaults `affiliate.link.<id>` | In-app **Plan → Science-backed options → Manage links** |
| Privacy / support URLs | `AppInfo` in [Model/AppInfo.swift](Hair%20Compass%20AI%205/Model/AppInfo.swift) | Fill the two placeholder strings before submission (docs site) |
| Capabilities already configured | `.entitlements` + `INFOPLIST_KEY_*` | HealthKit entitlement + Health/Camera/Photo usage strings are present |

---

## 10. Open items before App Store submission (decisions, not code)

1. **Privacy policy + support URLs** — fill `AppInfo` (docs/ GitHub Pages site).
2. **App Privacy labels** — complete the questionnaire in App Store Connect (HealthKit read, photos, optional off-device cloud AI).
3. **Paywall decision** — the Fable cloud "deep analysis" costs per request. Decide free / subscription (`PurchaseManager` + subscription group `21442176` exist to build on) / one-off, then gate `DeepAnalysisSheet`.
4. **Cloud API key** provisioning for release (a shipped app can't read a scheme env var — decide on a proxy/backend or a user-provided key).
5. **Screenshot every tab on device** at release for the store listing.

Everything the user requested through 2026-07-03 is implemented (measurement layer, HealthKit,
guided camera, hybrid AI, Learn, Plan/coaching/reminders, science-backed affiliate products, the
Compare chart-builder, the treatment recommender, clinician + data export, the widget, and the
legal footer). There are no half-built features pending — only the business/config decisions above.

---

## 11. Gotchas worth knowing

- **SwiftData migration:** new mandatory attributes need inline defaults, or the store fails to open and the app deletes+recreates it (data loss). Add defaults.
- **Stale store crash:** an old on-disk store from a previous schema can crash on launch; the container recovery handles it, but to force-clear a sim, delete the store files under the device's data container.
- **Widget target is separate:** it can't import the app's `Clinical` — colors are re-declared in the widget file (keep the hexes in sync). App-side `WidgetBridge` needs `import SwiftData` (it touches `persistentModelID`).
- **Foundation Models** aren't available in the Simulator / on non-Apple-Intelligence devices — the rule-based insight is the always-there path; keep it good.
- **Charts:** overlaying multiple `LineMark` groups without `series:` merges them into one line — always pass `series:` / `foregroundStyle(by:)`.
