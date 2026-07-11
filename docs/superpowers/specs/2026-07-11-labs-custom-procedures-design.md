# Lab proposals + custom AI item + procedure appointments — Design (2026-07-11)

Three features on a shared data-model foundation. Honest-monetization and record-keeping-not-
diagnosis stances (see BLUEPRINT §1) govern all three.

## Foundation (orchestrator, committed before the tracks) — schema additions

Lightweight-migration-safe (every new attribute has an inline default; the new model is
registered in the container):
- **New `@Model ProcedureAppointment`** in `Model/Models.swift`:
  `typeRaw: String`, `date: Date`, `location: String = ""`, `isCompleted: Bool = false`,
  `completedAt: Date? = nil`, `note: String = ""`, `createdAt: Date = .now`, + computed
  `type: ProcedureType` accessor. Register `ProcedureAppointment.self` in
  `App/HairCompassApp.swift`'s `Schema([...])`.
- **`enum ProcedureType`** in `Model/Enums.swift`: `prp, microneedling, transplant, lllt,
  mesotherapy, other` with `title`, SF `symbol`, and `art` (maps to the existing imagesets
  `procedure-prp` / `procedure-microneedling` / `procedure-hair-transplant` /
  `procedure-low-level-laser`; mesotherapy/other reuse a generic).
- **`Treatment` gains** `ingredientPhotoPath: String = ""` and `aiIngredientSummary: String = ""`
  (inline defaults; init updated). Used by Track B.

Build + launch (fresh store) to confirm no migration crash, then commit as the foundation.

## Track A — Lab deficiency → proposal (supplements or clinician)

When a lab value is entered and it's out of range, immediately present a **proposal card** and
persist it in Labs. Honest and evidence-gated: a *lab-confirmed* deficiency is exactly when a
supplement suggestion is legitimate (the existing `deficiencyGated` flag), and hormonal/medical
findings go to a clinician, never OTC.

- **`Model/LabProposal.swift`** (pure, tested): `LabProposal.for(_ result: LabResult) ->
  LabProposal?`. Uses `HairAnalytics.flag(for:test:)`. Rules:
  - `ferritin` **below** → `.both`: suggest an iron supplement **with a strong clinician caution**
    (iron overload is harmful — "only supplement iron with a clinician's confirmation").
  - `vitaminD` **below** → `.supplement`: vitamin D3 product.
  - `vitaminB12` **below** → `.supplement`: B12 product.
  - `tsh` / `freeT4` out of range → `.clinician`: thyroid is medical management, no supplement.
  - any test **above** range → `.clinician` (high ferritin/B12 warrant a doctor, not a sale).
  - in range → `nil` (no card).
  `LabProposal { kind: .supplement/.clinician/.both, deficiency: String (honest one-liner),
  productIDs: [String], clinicianNote: String? }`. Never invents; only maps known tests.
- **`Model/ScienceProduct.swift`**: add three **deficiency-gated** products — `iron`
  ("Iron (ferritin support)"), `vitamind` ("Vitamin D3"), `b12` ("Vitamin B12") —
  `deficiencyGated: true`, appropriate evidence tier, maker-funding disclosure honest. Add a
  `relevantTest: LabTest?` field so LabProposal maps test→product cleanly.
- **`Feature/LabProposalCard.swift`** (new): renders a proposal — the deficiency line, the
  recommended product rows (tier badge + "View on {retailer}" via `AffiliateStore`, hidden
  until a link is configured, standing disclosure), and/or a copper "Talk to a clinician" note
  for medical findings. Framed as record-keeping, never diagnosis.
- **`Feature/AddLabSheet.swift`**: on `save()`, if `LabProposal.for(result) != nil`, present the
  card (a `.sheet(item:)` after dismiss, so it pops up right after adding the value).
- **`Feature/LabsView.swift`**: surface a compact deficiency banner/card for the latest
  out-of-range result, tappable to the full proposal — so it persists, not just a one-shot pop.
- **Notification:** in-app card + Labs surface only. No push for lab deficiencies (respects the
  ≤1/day balanced-notifications stance); note this is intentional.

## Track B — Custom plan item with AI ingredient analysis

Let a user add a custom item to their plan (a `Treatment`, class `.other`, their own name) and
attach a **photo of its ingredient label** so the AI can identify and summarize it.

- **`Feature/AddTreatmentSheet.swift`**: add an "Ingredients photo (optional)" affordance —
  a `PhotosPicker`; on pick, save the image via `PhotoStore` and set `ingredientPhotoPath`;
  an "Analyze with AI" button (behind the existing `AIConsent` gate) that runs the analysis and
  stores `aiIngredientSummary`. The custom-item path is just the existing add flow with class
  `.other`; keep the class picker.
- **`Service/CloudAnalysisService.swift`**: add `analyzeIngredients(image: UIImage) async ->
  String?` — sends the single ingredient photo to the cloud model (same Fable→Opus fallback,
  consent guard, downscaled base64) with a focused prompt: "From this product's ingredient
  label, identify what it is and summarize its key active ingredients and their evidence tier
  for hair; note if it's largely inactive or a myth. Record-keeping, not medical advice; do not
  diagnose." Returns a short summary. Reuses the existing request plumbing.
- **`Feature/TreatmentDetailSheet.swift`**: show the ingredient photo thumbnail +
  `aiIngredientSummary` (with the "AI summary · not medical advice" caption) when present.
- Consent: the photo leaves the device → the analyze button routes through `AIConsentSheet` if
  not yet granted (same pattern as `DeepAnalysisSheet`).

## Track C — Procedure appointments + check-in logging

Schedule procedures (PRP, microneedling, transplant, LLLT, …), get a pre-reminder, and mark
them done — from a detail view or from the daily check-in.

- **`Feature/AddProcedureSheet.swift`** (new): type picker (`ProcedureType`), date/time,
  location, note → inserts a `ProcedureAppointment`.
- **`Feature/ProceduresView.swift`** (new): "Upcoming" (future, not completed) and "Done"
  sections; each row → detail; an add button. Entered from a **Procedures section in
  `Feature/CareView.swift`** (the Plan tab).
- **`Feature/ProcedureDetailSheet.swift`** (new): shows the appointment; a "Mark completed"
  action (sets `isCompleted`, `completedAt`), and edit/delete.
- **`Service/NotificationService.swift`**: add `planProcedureReminders(_ appointments:
  [(id, type, date)])` — one reminder ~1 day before each upcoming, non-completed appointment
  (beautiful, low-text, brand image via `NotificationArt`, ids `procedure.<n>`). Called from
  `CareView`'s reschedule task with a `@Query` of appointments. Respects the balanced cadence.
- **`Feature/LogSheet.swift`**: a compact "Did a procedure today?" control — if there's a
  scheduled appointment dated today it offers to mark it completed; otherwise it logs an ad-hoc
  completed `ProcedureAppointment(date: today, isCompleted: true)`. Minimal, optional, at the
  bottom of the log.

## Honesty guardrails (all tracks)
- Supplement proposals only for lab-*confirmed* deficiencies, evidence-tiered, with the maker-
  funding disclosure and (for iron) a clinician caution; medical findings → clinician, never a
  sale. Affiliate links hidden until configured.
- The AI ingredient summary and all AI copy stay "record-keeping, not medical advice."
- No new push notifications beyond the procedure pre-reminder; lab proposals are in-app.

## Tests
- `LabProposalTests`: each test/flag → correct kind + product ids; in-range → nil; thyroid →
  clinician-only; iron-low → both with the caution.
- Foundation: app launches on a fresh store with the new schema (orchestrator, simulator).
- No test for the AI/notification side effects (verified by build + code review).

## Execution
Orchestrator does the schema foundation first (+ launch check + commit). Then three Sonnet
tracks over disjoint files: A labs, B custom-item AI, C procedures. Orchestrator integrates,
builds, tests, launches, commits.
