# First run, starter plan, spotlight tour, and design refinement

**Date:** 2026-09-02
**Branch base:** `feat/agent-profile-memory` @ 60fa2d9 (1.1 build 5 + cloud engine)
**Status:** approved in brainstorming; awaiting spec review

## Why

The owner's brief, in six items, after a first pass on the 1.1 build:

1. Every user must go through onboarding on first use.
2. When there is not enough data for a trend, show a shaded graph with a label saying when it opens.
3. Give a tour once onboarding finishes.
4. Give the person a plan after onboarding: the tests to ask for, the applications and the procedures.
5. On the Plan tab, improve the ritual copy and add checklists for the person to enter their medications and lab values.
6. Improve the interface; it feels bold and too much like a default AI product design.

The code survey changed two of these. Onboarding already cannot be dismissed on a fresh install (`OnboardingFlow.onDismiss` is nil on first run; the paywall's only exit is "Continue free", which advances). The owner had tested on a device that already held a profile. A five-page card tour already fires after onboarding (`TutorialOverlay`). The owner chose, item by item:

- keep the cream, copper and serif; calm the hierarchy and add illustrations in the existing gouache style;
- replace the card tour with a spotlight tour on real controls;
- deliver the starter plan as an onboarding finale preview plus a checklist section on the Plan tab, with setup steps and personalised items in one merged list;
- add an "erase and start over" action in Profile so the first-run path can be exercised on a device that has data.

## Framing rule (unchanged, load-bearing)

Record-keeping and education, never diagnosis. Every new surface that names a lab, treatment or procedure says "worth asking your clinician about" or "what the evidence supports", carries the existing disclaimer, and never tells the person to start, stop or change anything.

## Sequencing

Four sub-projects, each built, tested, run in the simulator, and landed on `feat/agent-profile-memory` (then merged to `rebuild/clinical-minimal`) before the next starts:

| # | Sub-project | Contents |
|---|---|---|
| A | Quick wins | Trends chart placeholders; Profile "erase and start over" |
| B | Starter plan | `StarterPlan` engine and lab table; onboarding finale; Plan-tab checklist; ritual copy |
| C | Spotlight tour | anchors, overlay, captions, replay; delete `TutorialOverlay` |
| D | Design refinement | type and weight tokens, per-tab rhythm pass, eight new illustrations |

Illustration generation (part of D) may start in parallel with A–C since it produces assets only; wiring happens in D.

## Non-goals

- No palette change, no new typefaces, no dark mode.
- No new dependencies.
- No change to monetization, the 3-day access window, or any data threshold.
- No change to what onboarding asks; only the finale (step 14) changes.
- No change to the cloud/on-device AI engines.

---

## A. Quick wins

### A1. `ChartPlaceholder`

One shared view replaces every "not enough data" state on the Trends tab.

**Appearance.** A soft illustrative curve, drawn with `Clinical.hairline` and `Clinical.accentSoft`, at low opacity (about 0.35), filled under the line with a vertical wash. No axis numbers, no legend. It reads as a chart that is not open yet, not as an empty box. Over it, centred, one pill label in `Clinical.surface` with a hairline border: primary line "Opens after N daily logs", secondary line "k of N". Below the chart, the existing eyebrow style is kept for the section title.

**API.**

```swift
struct ChartPlaceholder: View {
    enum Unit { case dailyLogs, days, pairedDays, readings }
    let required: Int      // the section's own threshold
    let have: Int          // progress toward it, clamped to 0...required
    let unit: Unit
    var height: CGFloat = 132
}
```

`ChartPlaceholder.Copy.label(required:have:unit:)` is a pure function returning the two strings, so it is unit-testable: "Opens after 7 days" / "2 of 7"; "Opens after 2 daily logs" / "1 of 2"; "Opens after 8 paired days" / "0 of 8"; "Opens after 2 readings" / "1 of 2". Singular forms when `required == 1` (not used today, but the function must not print "1 daily logs").

**Adoption.** Thresholds do not change; each site passes its own rule and progress:

| Site | Rule (existing) | `required` / `unit` | `have` |
|---|---|---|---|
| `TrendsView.emptyState` (scalp and adherence rows) | `windowEntries.count < 2` | 2 / dailyLogs | `windowEntries.count` |
| `JourneyChart.thinDataPlaceholder` | `shedPoints.count < 2` | 2 / dailyLogs | `shedPoints.count` |
| `CompareView` locked state | `readyThreshold = 7` overlapping days | 7 / days | overlapping days |
| Lifestyle association (`ChartMath.association`, `minPairs: 8`) | fewer than 8 pairs | 8 / pairedDays | pair count |
| `BodySignalsDashboard` per metric | fewer than 2 readings in window | 2 / readings | readings |

Compare keeps its "Your real graph unlocks after 7 days" meaning but moves onto the shared component so wording and drawing match everywhere. The trajectory annotation at the top of Trends stays text. `trends-journey-empty` stops being used by the Trends empty state; if nothing else uses it, remove the asset and its `BrandArt` reference in the same change.

**Tests.** `ChartPlaceholderTests`: label copy for each unit, clamping of `have`, singular form. Existing Trends tests stay green.

### A2. Profile: erase and start over

A destructive row at the bottom of the Profile (Baseline) screen: "Erase everything and start over". Tapping it shows a confirmation alert:

> Erase all records on this iPhone and start from the beginning? Export a backup first if you want to keep them. Your subscription is not affected.

Buttons: "Export first" (opens the existing export sheet), "Erase", "Cancel".

**Erase does:** delete every SwiftData object of every model in the container; delete stored photos through `PhotoStore`; clear the app's `UserDefaults` domain except the keys listed below; cancel pending notifications; write an empty widget snapshot through `WidgetBridge`; then present onboarding by the normal path (`profile == nil` → `RootView` shows onboarding as it does on a fresh install).

**Erase also clears** the cloud-AI consent, so a fresh start asks again, which is the honest default.

**Erase keeps:** the Keychain `AccessWindow` (1.1 rule: nothing restarts the 3-day window) and StoreKit entitlement state (Apple-managed).

**Tests.** `EraseAndStartOverTests`: after erase, every model type has zero objects, `hasSeenTutorial` is false, `AccessWindow` start date is unchanged, and the onboarding presentation condition is true.

---

## B. Starter plan and the Plan tab

### B1. `StarterPlan` engine (`Model/StarterPlan.swift`)

Pure, stateless. Input is the profile and a snapshot of the record; output is an ordered list of items in four groups. Done-ness is derived from the record so it cannot drift.

```swift
struct StarterPlan {
    struct Snapshot {              // built by the caller from SwiftData
        var profile: Profile
        var labTests: Set<LabTest>          // tests that have at least one result
        var treatmentClasses: Set<TreatmentClass>
        var hasBaselinePhoto: Bool
        var remindersEnabled: Bool
        var loggedToday: Bool
        var dismissed: Set<String>          // item ids the person marked "Not for me"
    }
    enum Group: CaseIterable { case askClinician, evidenceOptions, inClinic, setUp }
    enum Kind {
        case lab(LabTest)
        case treatment(RecommendedOption)
        case procedure(ProcedureType)      // the app's existing procedure enum in Model/ProcedureGuide.swift, whatever its name is there
        case setup(SetupStep)
    }
    enum SetupStep: String, CaseIterable { case logToday, addTreatments, enterLabs, baselinePhoto, reminders }
    struct Item: Identifiable, Equatable {
        let id: String            // stable: "lab.ferritin", "treatment.minoxidil", "procedure.prp", "setup.logToday"
        let group: Group
        let kind: Kind
        let title: String
        let why: String           // one line
        let caution: String?      // pregnancy caution where applicable
        let isDone: Bool
        let isDismissed: Bool
    }
    static func items(for snapshot: Snapshot) -> [Item]
    static func isComplete(_ items: [Item]) -> Bool   // every item done or dismissed
}
```

**Lab table** (`LabSuggestion.tests(condition:sex:pregnancy:)`), reviewed for the record-keeping framing; a clinician review of the table is a release checklist item, not a code gate:

| Condition | Sex | Labs, in order |
|---|---|---|
| telogenEffluvium | any | ferritin, TSH, vitamin D, B12, hemoglobin, zinc |
| unsure | any | ferritin, TSH, vitamin D, B12, hemoglobin |
| androgenetic | female | ferritin, TSH, vitamin D, total testosterone, DHEA-S |
| androgenetic | male, other | ferritin, vitamin D |
| alopeciaAreata | any | TSH, free T4, vitamin D, B12 |
| traction | any | none |
| seborrheicDermatitis | any | none |

Pregnancy status `pregnant`, `breastfeeding` or `tryingToConceive`: ferritin and TSH are added if absent and moved to the front, and each lab item carries the existing pregnancy caution line. Each lab item's `why` is one sentence in plain language, for example ferritin: "Low iron stores are a common, fixable reason for shedding."

**Treatments.** `TreatmentRecommender.options(condition:sex:)`, keep tiers `.strong` and `.moderate`, take the first three. `title` is the option name, `why` is its `summary`, `caution` is its `caution`. Done when a treatment of that class exists in the plan; dismissed by id.

**Procedures** (`ProcedureSuggestion.kinds(condition:)`):

| Condition | Procedures |
|---|---|
| androgenetic | PRP, low-level laser, microneedling, transplant consultation |
| alopeciaAreata, traction, unsure | consultation |
| telogenEffluvium, seborrheicDermatitis | none |

`why` comes from `ProcedureGuide.shortExpectation(for:)`. Done when a procedure of that kind is recorded; otherwise only dismissible.

**Setup steps**, always present, in this order: log today (done when `loggedToday`), add your medications and treatments (done when any treatment exists), enter your lab values (done when any lab result exists), take a baseline photo (done when `hasBaselinePhoto`), turn on reminders (done when `remindersEnabled`).

**Order within the list:** setUp first, then askClinician, evidenceOptions, inClinic. Done items sink to the end of their group; dismissed items are excluded.

**Persistence.** Only `dismissed` is stored: `@AppStorage("starterPlan.dismissed")` as a JSON array of ids. Everything else is recomputed on each body evaluation.

### B2. Onboarding finale: "Your starting plan"

Step 14 (`OnboardingFlow` finale) renders the plan as a read-only preview: a short header with a new illustration (D), then the four groups with their items as plain rows (title and why, no check circles), the recommender disclaimer, and one button "Open my plan". The button calls the existing `finish()` and lands on the Plan tab with the checklist at the top. `finish()` also arms the tour (C). Nothing on this step writes to the record.

The finale uses the same `StarterPlan.items(for:)` as the tab, with a snapshot built from the freshly seeded profile and day-one entry, so the two can never disagree; a test asserts the ids match.

### B3. Plan tab: "Set up your plan"

A new first section in `CareView`, above `routineSection` / `planRitualPlate`, shown while `!StarterPlan.isComplete(items)`.

- Header: eyebrow "Set up your plan", title "Your starting plan", one-line intro, and the D illustration (a soft moment, so full Wren is allowed).
- Rows, grouped with the four group eyebrows. Each row: check circle (empty, or filled with the accent when done), title, `why` in caption, chevron. Done rows show the circle filled and the title in secondary tone.
- Tap opens the right surface: `AddLabSheet(initialTest:)`, `AddTreatmentSheet(initialClass:)`, `ProcedureDetailSheet` for the procedure kind, `GuidedCaptureView`, the reminders sheet, or `LogSheet`.
- Swipe or long-press → "Not for me" adds the id to the dismissed list. A small "Undo" text button in the section footer restores the most recent dismissal until the next launch.
- When the list becomes complete, the section shows a one-line closer "Starting plan done — your ritual takes it from here" once, then disappears on the next launch.

**Ritual copy.** `planRitualPlate` (empty routine) becomes:

> **Your ritual**
> Each treatment you add becomes a daily step here, so a month of tracking can be compared with the next. Start with the checklist above; the ritual is what makes the record honest.

`routineSection` eyebrows stay (Morning, Evening, Periodic).

**Tests.** `StarterPlanTests`: lab table per condition and sex, pregnancy reordering and caution, procedure table, setup done-derivation for each step, dismissal exclusion, ordering (done to end), `isComplete`, finale and tab id parity.

---

## C. Spotlight tour

### C1. Anchors

```swift
enum TourStep: Int, CaseIterable { case todayHero, editLog, wren, trendsTab, planTab, recordTabs }
extension TourStep { var tab: AppTab { ... } }   // which tab must be showing
```

A preference key `TourAnchorKey: [TourStep: Anchor<CGRect>]` and a modifier `.tourAnchor(_ step: TourStep)` that attaches `anchorPreference(key:value:)`. Six call sites: the shedding hero and Edit log button in Today, `WrenChatButton`, and the Trends, Plan and Labs tab items in `FloatingTabBar` (Labs and Photos are one step; the cutout spans both items).

### C2. Overlay

`SpotlightTourOverlay` is rendered by `RootView` through `overlayPreferenceValue(TourAnchorKey.self)`, above the tab shell and below sheets.

- Scrim: `Clinical.ink` at 0.55 with an even-odd mask that cuts out the current anchor's rect, inset by −8 points, corner radius 18. The cutout animates between steps with `.easeInOut(0.35)`; Reduce Motion disables the animation.
- Caption: a `ClinicalCard`-styled panel placed below the cutout, or above it when there is no room, containing `CompanionView(.avatar)`, the caption text, a step counter "2 of 6", and a Next / Done button. A quiet "Skip" text button sits at the top trailing edge.
- Steps whose `tab` differs from the current tab set the tab first, then advance after the next layout pass.
- Tapping the scrim advances; tapping inside the cutout also advances (the control itself is not activated during the tour).
- VoiceOver: the caption is a container with `accessibilityAddTraits(.isModal)`; Next, Done and Skip are buttons; the counter is read.

### C3. Captions

| Step | Caption |
|---|---|
| todayHero | "This is today. Log once a day here — a month of these is what makes the trends honest." |
| editLog | "Change today's log any time. Nothing is judged from one day." |
| wren | "Wren answers questions about your own record, in plain language. Never a diagnosis." |
| trendsTab | "Trends open as your record grows. Each chart says when." |
| planTab | "Your plan: the starting checklist, then your daily ritual." |
| recordTabs | "Labs and photos live here. They are what a clinician will ask about." |

### C4. Lifecycle

- Starts once, after the finale's "Open my plan", replacing `TutorialOverlay` (file deleted, its `LaunchPresentationState.tutorial` precedence slot reused).
- Reuses `@AppStorage("hasSeenTutorial")`; anyone who saw the old tour does not get the new one.
- Profile: "Replay the tour" row next to "Replay the walkthrough". Replay sets the flag false and returns to Today.
- The erase action (A2) clears the flag.
- Skip and Done both set the flag true.

**Tests.** `SpotlightTourTests`: step order, tab per step, caption non-empty and free of digits (so the AI validator style rule holds for copy too). UI test `testSpotlightTourFollowsOnboarding`: finish onboarding with `HC_ONBOARD`, assert `tourCaption` exists, tap Next through to Done, relaunch, assert absent.

---

## D. Design refinement and illustrations

### D1. Tokens (`Design/Clinical.swift`)

| Token | Now | After |
|---|---|---|
| `headline(size, weight:)` default weight | `.bold` | `.semibold` |
| `eyebrow` weight / colour / tracking | semibold / `secondary` / 1.4 | medium / `tertiary` / 1.2 |
| Filled button label weight | semibold | medium |
| Filled button vertical padding | current | −2 pt |
| `ClinicalCard` ambient shadow | 7% r16 y6 | 5% r14 y5 |
| `ClinicalCard` contact shadow | 10% r2 y1 | 8% r2 y1 |
| Compass ring stroke | current | −1 pt |

### D2. Display scale

Call sites are remapped, not the function: 50 → 40 (Today hero), 44 → 36, 34 → 30, 30 → 26, 28 → 26, 26 → 24. Sizes 22 and below are unchanged. A `TypeScaleTests` snapshot lists every `Clinical.headline(` size in the app sources and fails if any exceeds 40.

### D3. Rhythm pass

One pass per tab (Today, Trends, Plan, Labs, Photos), plus the three new surfaces: section spacing on an 8-point grid; at most one eyebrow per section; one focal element per screen (the hero on Today, the journey on Trends, the checklist or ritual on Plan, the newest result on Labs, the latest photo on Photos); secondary actions outlined rather than filled. Before-and-after screenshots of every tab from the simulator go in the pull request.

### D4. Illustrations

Generated with the saved recipe (memory: `hair-compass-gemini-image-pipeline`): `gemini-3-pro-image`, gouache, "no heavy outline — forms described by pigment and tone", isolated on flat white, flood-fill cutout with the tight second pass at tolerance 10, alpha feathered 0.5 px, checked on the cream canvas and a dark ground in one contact sheet. Wren poses pass `wren-greeting.png` back as the reference image.

| Asset | Surface | Subject |
|---|---|---|
| `art-starting-plan` | onboarding finale header | a compass resting on three small paper cards, sprig beside |
| `art-plan-checklist` | Plan "Set up your plan" header | Wren perched on a folded checklist card |
| `art-compare-locked` | Compare locked state | two strands drawn side by side, one still faint |
| `art-learn` | Learn header wash | an open field guide with a pressed leaf |
| `art-in-clinic` | in-clinic options header | a clinic chair with a small potted plant |
| `art-labs-empty` | Labs empty state | a single vial and a dropper on paper |
| `art-photos-empty` | Photos empty state | a camera beside a strand and a comb |
| `wren-pointing` | tour captions | Wren turned to the side, wing raised toward the left |

Each is wired through a `BrandArt` constant and rendered on its surface so `BrandArtCoverageTests` keeps it in use. Sizes: 1024 px on the long edge, PNG with alpha, 1x/2x/3x scale set generated from the same source.

---

## Testing summary

- Swift Testing unit suites: `ChartPlaceholderTests`, `EraseAndStartOverTests`, `StarterPlanTests`, `SpotlightTourTests`, `TypeScaleTests`, plus the existing 479 stay green.
- UI tests: `testSpotlightTourFollowsOnboarding`; the existing 8 stay green.
- Simulator run after each sub-project: onboarding through to the finale, the checklist on Plan, the tour, the placeholders on a fresh install, and the erase action returning to onboarding with the access window intact.

## Landing

Each sub-project is one pull request-sized commit series on `feat/agent-profile-memory`, tests green, merged forward to `rebuild/clinical-minimal`. Marketing version stays 1.1; the build number advances when the owner uploads.
