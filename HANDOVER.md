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

Five tabs: **Today · Guide · Trends · Plan · Photos** (the tab enum case for Plan is still `care`,
and Guide's is still `shop` — it is the affiliate-link surface, but it presents as guidance, not a
storefront, by owner ruling 2026-08-21).
Labs no longer has its own tab — Task 9 of the monetization plan merged it into Plan (both are Pro,
both are clinical records); Guide (`ShopView` — the decide-what's-worth-it surface, still where
the affiliate links live) took the freed slot and is
deliberately kept outside the Pro wall. A Home Screen widget mirrors today's state.

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
| `HC_TAB <today\|shop\|trends\|care\|photos>` | Opens on that tab |
| `HC_LEARN` | Opens the Learn sheet on launch |
| `HC_SCROLL_PRODUCTS` | Scrolls Guide to the science-products section |
| `HC_COMPARE` / `HC_EXPORT` | Opens the Compare / Export sheet from Trends |
| `HC_AI_STATUS <available\|notEnabled\|modelNotReady\|deviceNotEligible>` | Forces what `ProAvailability.current` reports, which drives the paywall's Apple Intelligence notice on the two AI features. It does **not** affect the purchase buttons — those are unconditional (`ProAvailability.showsPurchaseButtons`). An iOS 26 Simulator on an Apple Intelligence Mac reports `.available`, so without this the unavailable states can only be seen on physically ineligible hardware. |
| `HC_TIER <free\|taster\|pro>` | Forces the resolved entitlement tier (`Entitlements.forcedTier`). A fresh install stamps `firstLaunchAt` and is therefore a **taster for three days**, so this is the only way to see the free tier — `LockedHistoryCard`, the three gated tabs (Trends, Plan, Photos), the suppressed widget snapshot — without waiting out the clock. DEBUG only: the flag is compiled out of release builds, so an App Review build cannot use it — review notes must not offer it (see §10). |

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

### Redesign v2 (2026-07-03, incorporated)
A layout-level polish pass from an external design handoff (preserved in
[docs/design-handoff-v2/](docs/design-handoff-v2/) — README with per-file snippets + an interactive
HTML prototype). Same tokens, no new dependencies. Four screen upgrades, all shipped:
- **Today** — the greeting sits *inside* a full-bleed hero (gradient-faded to canvas), profile button
  + streak chip float over it; the daily-log stats and today's routine share one card; the old
  standalone readout + baseline cards are gone (consolidated into Plan/profile).
- **Plan** — the coach card shows a copper **progress ring** instead of a bar.
- **Labs** — each result reads as a **reference-range gauge** (value dot on a 0→high axis with the
  healthy band shaded).
- **Photos** — an inline **drag-to-compare** before/after slider replaced the two-thumbnail card
  (and the separate full-screen `PhotoCompareView`, now removed).

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
- **Guide** [Feature/ShopView.swift](Hair%20Compass%20AI%205/Feature/ShopView.swift) — helps decide what's worth buying and which procedure to consider; still the affiliate-link surface, deliberately outside the Pro wall: **What the evidence supports for you** (→ `RecommenderView`), **In-clinic options** (→ `InClinicOptionsView`, a full card in the first screenful — it was a lone button below the whole catalogue, where nobody saw it), **Science-backed options** (→ `ScienceProductsView` + `ManageLinksSheet`). Used to live inside Plan; Task 9 (monetization hard wall) split it out since an affiliate link earns nothing from a free user who can't reach it.
- **Plan** [Feature/CareView.swift](Hair%20Compass%20AI%205/Feature/CareView.swift) — **Coach** card + **milestones**, **Today's routine** (grouped, check-off, per-step guidance), **Reminders** toggle, 24-week gate, treatment cards, ledger rows for Procedures/Progress check-in/Life events/**Labs** (→ `LabsView`, its own `.proGated(.labs)`). Add via [Feature/AddTreatmentSheet.swift](Hair%20Compass%20AI%205/Feature/AddTreatmentSheet.swift). Labs no longer has its own tab — reached from a row here instead (Task 9).
- **Labs** [Feature/LabsView.swift](Hair%20Compass%20AI%205/Feature/LabsView.swift) — bloodwork with reference-range flags; add via `AddLabSheet`. Opened from a row inside Plan, not its own tab.
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
| Affiliate links | UserDefaults `affiliate.link.<id>` | In-app **Guide → Science-backed options → Manage links** (Task 9 moved this out of Plan, which is now Pro-gated) |
| Privacy / support URLs | `AppInfo` in [Model/AppInfo.swift](Hair%20Compass%20AI%205/Model/AppInfo.swift) | Fill the two placeholder strings before submission (docs site) |
| Capabilities already configured | `.entitlements` + `INFOPLIST_KEY_*` | HealthKit entitlement + Health/Camera/Photo usage strings are present |

---

## 10. Open items before App Store submission

Items 3 and 4 of the old list are gone — AI is fully on-device now (no cloud, no key to provision)
and both AI sheets sit behind `ProGate`, which reads the resolved tier from `Entitlements`
(free · taster · pro) rather than a `hasPro` boolean. They are 2 of the 12 gated features.

### In this repo

1. **Privacy policy + support URLs** — `AppInfo.privacyPolicyURLString` / `.supportURLString` still
   point at a GitHub Pages site that has never resolved (the repo is private and Pages was never
   enabled). `SubmissionReadinessTests` fails until they point somewhere real; see
   [docs/README.md](docs/README.md). This is a hard blocker: App Store Connect requires a resolving
   privacy policy URL, and `PaywallLegal` renders the link on the paywall itself (Guideline 3.1.2).

### In App Store Connect (nothing in the repo can verify these)

2. **App record + App ID capabilities** — bundle id `harib.Hair-Compass-AI-5`, with HealthKit and
   App Group `group.harib.Hair-Compass-AI-5` enabled on the identifier, or the entitlements won't
   sign.
3. **Subscriptions** — create both products in group `21442176` and get them to *Ready to Submit*:
   localized display name (≤30 chars), description (≤45 chars), price, and an IAP review screenshot.
   `HairCompass.storekit` is a local simulator fixture only; it configures nothing on Apple's side.
   Keep the ASC descriptions matching the in-app claim — **twelve features are gated**, the full
   `ProFeature.allCases` table in [Feature/Entitlements.swift](Hair%20Compass%20AI%205/Feature/Entitlements.swift):
   history, trends, compare, journey, photos, labs, procedures, treatments, reports, body signals,
   Ask Wren and Deep analysis. Trends is `.proGated(.trends)`, so do **not** describe it as free.
   Only the last two need Apple Intelligence; the other ten run on any supported iPhone, which is
   why the purchase buttons are unconditional. Free keeps: unlimited daily check-ins, today's own
   values, the streak count, the Guide tab, Learn, and export.
4. **Paid Apps agreement + banking/tax** signed, or products never load and the paywall shows
   `StoreUnavailableView` to every reviewer.
5. **App Privacy questionnaire** → *Data Not Collected*, matching both `PrivacyInfo.xcprivacy`
   files and the fact that the app makes no network requests at all.
6. **Age rating**, description, keywords, support URL, and screenshots — taken on a real device.
7. **App Review notes** — say that no account is needed, and that two of the twelve Pro features
   (Ask Wren, Deep analysis) require Apple Intelligence, naming a device that has it. A reviewer on
   ineligible hardware sees **live purchase buttons plus an honest notice** naming those two
   features — the subscription sells on every iPhone because the other ten run everywhere (see
   `ProAvailability.canRun` / `.showsPurchaseButtons`). Do **not** offer `HC_TIER free` in the
   notes: the flag is `#if DEBUG` and compiled out of the build App Review actually runs. What a
   reviewer really sees is the fresh install's three-day taster with everything unlocked — say
   that, and describe the wall (`LockedHistoryCard` + the three gated tabs) in words or attach a
   screenshot if the free tier matters to the review.

### Before the archive

8. **TestFlight on a physical device.** HealthKit, Face ID, the widget, Live Activities and
   Foundation Models are all things the Simulator cannot prove.

There are no half-built features pending — only the items above.

---

## 11. Gotchas worth knowing

- **SwiftData migration:** new mandatory attributes need inline defaults, or the store fails to open and the app deletes+recreates it (data loss). Add defaults.
- **Stale store crash:** an old on-disk store from a previous schema can crash on launch; the container recovery handles it, but to force-clear a sim, delete the store files under the device's data container.
- **Widget target is separate:** it can't import the app's `Clinical` — colors are re-declared in the widget file (keep the hexes in sync). App-side `WidgetBridge` needs `import SwiftData` (it touches `persistentModelID`).
- **Foundation Models availability is not what this doc used to claim.** An iOS 26 Simulator on an Apple Intelligence Mac reports `.available` and really runs the model; it's non-Apple-Intelligence *hardware* (below iPhone 15 Pro), Apple Intelligence switched off, or a model still downloading that report unavailable. The rule-based insight is still the always-there path — keep it good — but don't assume the Simulator exercises the unavailable branches. Use `HC_AI_STATUS` to force them.
- **Charts:** overlaying multiple `LineMark` groups without `series:` merges them into one line — always pass `series:` / `foregroundStyle(by:)`.
