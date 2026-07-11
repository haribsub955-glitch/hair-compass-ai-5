# Lab proposals + custom AI item + procedures — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lab-deficiency proposals (sell supplements or route to a clinician), a custom plan item with AI ingredient analysis, and procedure appointments with reminders + check-in logging.

**Architecture:** The schema foundation is ALREADY committed (`ProcedureAppointment` model, `ProcedureType` enum, `Treatment.ingredientPhotoPath`/`.aiIngredientSummary`, registered in the container, launch-verified). Three parallel Sonnet tracks over disjoint files build on it. Spec: `docs/superpowers/specs/2026-07-11-labs-custom-procedures-design.md`. Constraints: Clinical tokens, honesty rules (record-keeping-not-diagnosis; supplements only for lab-confirmed deficiencies + maker disclosure; medical → clinician), **agents do not run xcodebuild/git**, Swift Testing, quote paths. No cross-track shared symbols (all model/enum/schema changes are already done).

---

### Task A: Lab deficiency → proposal

**Files (owns exclusively):** Create `Hair Compass AI 5/Model/LabProposal.swift`, `Hair Compass AI 5/Feature/LabProposalCard.swift`, `Hair Compass AI 5Tests/LabProposalTests.swift`; Modify `Hair Compass AI 5/Model/ScienceProduct.swift`, `Hair Compass AI 5/Feature/AddLabSheet.swift`, `Hair Compass AI 5/Feature/LabsView.swift`.

- [ ] **A1: Deficiency-gated products.** In `ScienceProduct.swift`, add a `relevantTest: LabTest?` field (default nil) to the struct + its `.init`s (existing products pass nil), and append three `deficiencyGated: true` products with `relevantTest` set: `iron` ("Iron (ferritin support)", `.oral`, evidence tier `.moderate`, `relevantTest: .ferritin`, `industryFunded: false`), `vitamind` ("Vitamin D3", `.oral`, `.moderate`, `.vitaminD`), `b12` ("Vitamin B12", `.oral`, `.limited`, `.vitaminB12`). Read the `ScienceProduct` struct + `ProductEvidence` first to match the exact field list/order.

- [ ] **A2: LabProposal (pure + tested).** Create `LabProposal.swift`:
  ```swift
  import Foundation

  struct LabProposal: Equatable {
      enum Kind: Equatable { case supplement, clinician, both }
      let kind: Kind
      let deficiency: String        // honest one-liner, e.g. "Ferritin is below the hair-relevant range."
      let productIDs: [String]      // ScienceProduct ids to offer (may be empty for .clinician)
      let clinicianNote: String?    // non-nil for .clinician / .both

      /// nil when the value is in range (no card).
      static func `for`(_ result: LabResult, calendar: Calendar = .current) -> LabProposal? {
          let flag = HairAnalytics.flag(for: result.value, test: result.test)
          switch (result.test, flag) {
          case (.ferritin, .low):
              return .init(kind: .both, deficiency: "Ferritin is below the range often cited for hair.",
                  productIDs: ["iron"],
                  clinicianNote: "Iron only helps if you're genuinely low — and too much iron is harmful. Confirm with a clinician before supplementing.")
          case (.vitaminD, .low):
              return .init(kind: .supplement, deficiency: "Vitamin D is below range.", productIDs: ["vitamind"], clinicianNote: nil)
          case (.vitaminB12, .low):
              return .init(kind: .supplement, deficiency: "Vitamin B12 is below range.", productIDs: ["b12"], clinicianNote: nil)
          case (.tsh, _), (.freeT4, _) where flag != .normal:
              return .init(kind: .clinician, deficiency: "Thyroid result is out of range.", productIDs: [],
                  clinicianNote: "Thyroid changes are a treatable shedding driver, but they need a clinician — not a supplement.")
          case (_, .high):
              return .init(kind: .clinician, deficiency: "\(result.test.title) is above range.", productIDs: [],
                  clinicianNote: "An above-range result is worth reviewing with a clinician.")
          default:
              return nil
          }
      }
  }
  ```
  (Fix the `where` placement so thyroid low/high both → clinician and thyroid-normal → nil; verify the switch is exhaustive and compiles. Use `LabResult.flag` if simpler than recomputing.)

- [ ] **A3: LabProposalCard.** Create `Feature/LabProposalCard.swift`: `LabProposalCard(proposal: LabProposal)` rendering a `ClinicalCard` — an eyebrow "What this may mean", the `deficiency` line (ink), then for supplements the `productIDs` mapped to `ScienceProduct[id]` rows (name + `TierBadge` + a "View on {retailer}" button via `AffiliateStore` only when a link is configured, plus the standing maker/affiliate disclosure), and for `.clinician`/`.both` a copper "Talk to a clinician" note (`clinicianNote`). Footer: "Record-keeping, not medical advice." Read `ScienceProductsView.swift` for the existing product-row + disclosure + `AffiliateStore` idiom and reuse it.

- [ ] **A4: AddLabSheet pop-up.** In `AddLabSheet.save()`: build the `LabResult`, insert it, and if `LabProposal.for(result) != nil`, stash it and present `LabProposalCard` — use `@State private var proposal: LabProposal?` (make `LabProposal` carry an `Identifiable` id, or wrap it) and `.sheet(item:)`; since `save()` also dismisses, present the proposal from the parent via a returned value OR keep the sheet on AddLabSheet and dismiss after the user closes the proposal. Simplest: don't auto-dismiss on save when there's a proposal — show the card as a sheet over AddLabSheet, and dismiss AddLabSheet when the card closes.

- [ ] **A5: LabsView surface.** In `LabsView`, compute the most recent out-of-range `LabResult` with a proposal and show a compact deficiency banner above the list, tappable to present the full `LabProposalCard`. Persists the proposal beyond the one-shot pop-up.

- [ ] **A6: Tests.** `LabProposalTests` (Swift Testing, `@MainActor` for `LabResult` @Model): ferritin low → `.both` + `["iron"]` + non-nil clinicianNote; vitaminD low → `.supplement` + `["vitamind"]`; tsh out of range → `.clinician` + empty products; ferritin in range → nil; ferritin high → `.clinician`.

### Task B: Custom plan item + AI ingredient analysis

**Files (owns exclusively):** Modify `Hair Compass AI 5/Feature/AddTreatmentSheet.swift`, `Hair Compass AI 5/Feature/TreatmentDetailSheet.swift`, `Hair Compass AI 5/Service/CloudAnalysisService.swift`.

- [ ] **B1: AI ingredient method.** In `CloudAnalysisService.swift`, add:
  ```swift
  /// Identify a product from a photo of its ingredient label. Consent-gated (photo leaves the
  /// device). Returns a short summary, or nil on refusal/error. Record-keeping, not medical advice.
  func analyzeIngredients(image: UIImage) async -> String?
  ```
  Reuse the existing `request(...)` plumbing (Fable→Opus fallback, `AIConsent` guard, `downscaledJPEGBase64`), but with a focused prompt: "From this product's ingredient label, identify what it is and summarize its key active ingredients and their evidence tier for hair. Note if it's largely inactive or a marketing myth. Be brief. Record-keeping, not medical advice; do not diagnose." Read the current `analyze`/`request`/`prompt` to match style; keep the consent guard.

- [ ] **B2: AddTreatmentSheet ingredient photo.** Add an optional "Ingredients photo" section: a `PhotosPicker` (single image); on pick, load the `UIImage`, save via `PhotoStore.shared.save(...)` (read PhotoStore's save API), hold the resulting path in `@State`, and show the thumbnail. An "Analyze with AI" button — gated on `AIConsent.isGranted()` (present `AIConsentSheet` if not, like `DeepAnalysisSheet`/`TodayView`) — calls `CloudAnalysisService.analyzeIngredients` and stores the returned summary in `@State`. In `save()`, set the new `Treatment(ingredientPhotoPath:aiIngredientSummary:)` fields. The custom item is just the existing flow with the class picker free to be `.other`; don't remove existing behavior.

- [ ] **B3: TreatmentDetailSheet display.** When `treatment.ingredientPhotoPath` is non-empty, show the thumbnail (via `PhotoStore.shared.loadThumbnail`); when `aiIngredientSummary` is non-empty, show it under an "AI summary · not medical advice" caption. Read the sheet first to place it consistently.

- [ ] **B4:** No unit test (AI/photo side effects). Orchestrator build-verifies.

### Task C: Procedure appointments + check-in logging

**Files (owns exclusively):** Create `Hair Compass AI 5/Feature/ProceduresView.swift`, `Hair Compass AI 5/Feature/AddProcedureSheet.swift`, `Hair Compass AI 5/Feature/ProcedureDetailSheet.swift`; Modify `Hair Compass AI 5/Service/NotificationService.swift`, `Hair Compass AI 5/Feature/LogSheet.swift`, `Hair Compass AI 5/Feature/CareView.swift`.

- [ ] **C1: AddProcedureSheet.** `NavigationStack` form: `ProcedureType` picker (chips, like AddTreatmentSheet's class picker), a `DatePicker` (date+time), a location text field, a note field → `context.insert(ProcedureAppointment(type:date:location:note:))`. Cancel/Save toolbar. Match the Clinical form idiom of `AddTreatmentSheet`/`AddLabSheet`.

- [ ] **C2: ProcedureDetailSheet.** Shows one `ProcedureAppointment` (type art/symbol, date, location, note); a "Mark completed" button (sets `isCompleted = true`, `completedAt = .now`) shown when not completed; a Delete (destructive, `context.delete`); Done toolbar.

- [ ] **C3: ProceduresView.** `@Query(sort: \ProcedureAppointment.date)` → "Upcoming" (isUpcoming) and "Done" sections, rows → `ProcedureDetailSheet` via `.sheet(item:)`; an add button → `AddProcedureSheet`. Empty state with a next action. Clinical screen idiom.

- [ ] **C4: CareView entry.** Add a "Procedures" section/card to `CareView` (Plan tab) that opens `ProceduresView` (or embeds a compact upcoming list + "Add procedure"). Read CareView first to place it near the treatments/plan content without disturbing existing sections.

- [ ] **C5: Reminders.** In `NotificationService`, add `planProcedureReminders(_ items: [(id: String, title: String, date: Date)])` — remove pending `procedure.*` ids, then for each future item schedule ONE reminder ~1 day before at 10:00 (or the appointment time if within a day), ids `procedure.<n>`, short copy ("Upcoming: {title}", "Tomorrow at your clinic."), `NotificationArt.attachment()`. Call it from `CareView`'s existing notification-reschedule `.task` (add an appointments `@Query`), passing upcoming appointments. Respects the balanced cadence (one per appointment).

- [ ] **C6: Log a procedure.** In `LogSheet`, add a compact optional "Did a procedure today?" control near the bottom: if a `ProcedureAppointment` is dated today and not completed, offer "Mark {type} done"; else a small menu to log an ad-hoc `ProcedureAppointment(type:, date: today, isCompleted: true, completedAt: .now)`. Needs a `@Query` of appointments + `@Environment(\.modelContext)` (LogSheet already has context). Keep it minimal and out of the way; don't disturb the existing log flow/save.

- [ ] **C7:** No unit test (UI/side effects). Orchestrator build + launch verifies.

### Task D (orchestrator): integrate, build, test, launch, screenshot, commit
- [ ] Build app + widget; run unit tests (incl. LabProposalTests); launch on a fresh store (confirm no crash); screenshot the Plan/Care tab (procedures entry) and — if reachable via debug args — the lab proposal card and procedures list; commit per track + plan.
