# Progress check-in — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the between-visit questions a dermatologist asks (regrowth/baby hairs, density/shedding/hairline trend, scalp-pain red flag, overall) in a periodic Progress check-in, and surface the answers in the clinician export and the AI context.

**Architecture:** The schema foundation is ALREADY committed (`ProgressCheckIn` model, `RegrowthLevel`/`ProgressTrend` enums, container registration, launch-verified). Two parallel Sonnet tracks over disjoint files. Spec: `docs/superpowers/specs/2026-07-11-progress-checkin-design.md`. Constraints: Clinical tokens, honesty (self-report context, never diagnosis; scalp-pain is a safety nudge), **agents do not run xcodebuild/git**, Swift Testing, quote paths. No cross-track shared symbols (all model/enum/schema changes done).

Shared model API (already committed) both tracks read:
`ProgressCheckIn(date:regrowth:density:shedding:hairline:overall:scalpPain:scalpPainNote:note:)`; computed `regrowth: RegrowthLevel`, `density/shedding/hairline/overall: ProgressTrend`, `scalpPain: Bool`, `func clinicianSummary() -> [String]`; `RegrowthLevel.title`; `ProgressTrend.label(for: .density/.shedding/.hairline/.overall)` and `.clinicianPhrase(for:)`.

---

### Task A: Capture — sheet + Plan entry + reminder

**Files (owns exclusively):** Create `Hair Compass AI 5/Feature/ProgressCheckInSheet.swift`; Modify `Hair Compass AI 5/Feature/CareView.swift`, `Hair Compass AI 5/Service/NotificationService.swift`.

- [ ] **A1: ProgressCheckInSheet.** A `NavigationStack` form (match `AddProcedureSheet`/`LogSheet`/`AddLabSheet` Clinical idiom). `@Environment(\.modelContext)`, `@Environment(\.dismiss)`. Optional `existing: ProgressCheckIn?` (nil = new). `@State` for each answer. Six question sections:
  - Header line contextualizing with the plan when data is available — accept optional `treatmentContext: String?` (built by CareView from active treatments, e.g. "You've been on Minoxidil for 20 weeks") and show it under the title if non-nil.
  - **Regrowth:** a `BandChipRow`-style row of 4 chips from `RegrowthLevel.allCases.map(\.title)` bound to the `RegrowthLevel`. (Reuse the chip idiom from onboarding/`AddProcedureSheet`; if `BandChipRow` was removed, build a small inline 4-chip picker.)
  - **Density / Shedding / Hairline / Overall:** four 3-chip rows using `ProgressTrend.allCases.map { $0.label(for: .density) }` etc., bound to each `ProgressTrend`.
  - **Scalp symptoms:** a `Toggle` "Any scalp pain, burning, or tender spots?" → `scalpPain`; when on, a note `TextField` + an inline honest caption "Persistent scalp pain is worth mentioning to your dermatologist soon."
  - **Note:** free-text.
  - Save inserts a new `ProgressCheckIn(...)` (or mutates `existing`); a Cancel toolbar. On save with `scalpPain == true`, no diagnosis — just persist (the caption already nudged).
- [ ] **A2: CareView entry card.** Add `@Query(sort: \ProgressCheckIn.date, order: .reverse) private var checkIns: [ProgressCheckIn]` and a `progressCheckInCard`: an `Eyebrow("Progress check-in")`, the last check-in's date (or "Not done yet"), a "Due" chip when `checkIns.first == nil || checkIns.first!.date < 30 days ago`, and a "New check-in" button opening `ProgressCheckInSheet` (pass a `treatmentContext` built from the first active treatment: "You've been on {name} for {HairAnalytics.weeksElapsed} weeks"). Place it near the coach/procedures cards (read CareView first; use the next `staggeredEntrance` index without disturbing existing ones). Add a `HC_PROGRESSCHECKIN` debug arg to open the sheet.
- [ ] **A3: Monthly reminder.** In `NotificationService`, add `planProgressCheckInReminder(lastCheckIn: Date?)` — schedules ONE non-repeating reminder ~30 days after `lastCheckIn` (or 30 days from now if nil) at 10:00, id `progressCheckIn.0`, short copy ("Monthly progress check-in", "A minute on how it's going.") + `NotificationArt.attachment()`. Called from CareView's existing reschedule `.task` (pass `checkIns.first?.date`). Balanced: one low-frequency reminder, removes its own stale id first.
- [ ] **A4: Test.** No UI test; the model's `clinicianSummary()` is tested by Track B. (Skip.)

### Task B: Surface — clinician export + AI context

**Files (owns exclusively):** Modify `Hair Compass AI 5/Service/ExportService.swift`, `Hair Compass AI 5/Feature/ExportSheet.swift`, `Hair Compass AI 5/Model/AIContextBuilder.swift`; Create `Hair Compass AI 5Tests/ProgressCheckInTests.swift`.

- [ ] **B1: Clinician summary section.** In `ExportService.clinicianSummary(...)`, add a `progressCheckIns: [ProgressCheckIn]` parameter (place after `triggers`). After the existing sections, append a "PROGRESS CHECK-INS (self-reported)" section listing the most recent up-to-3 (sorted by date desc): for each, the date header + `checkIn.clinicianSummary()` lines (indented "• "). Skip the section when empty. Also add `progressCheckIns` to `dataJSON(...)` (a small `Codable` DTO with the raw answer fields + date) and to the `ExportBundle`.
- [ ] **B2: ExportSheet wiring.** In `ExportSheet`, add `@Query(sort: \ProgressCheckIn.date, order: .reverse) private var progressCheckIns: [ProgressCheckIn]` and pass it into both `clinicianSummary(...)` and `dataJSON(...)`. Read the file first for the exact call sites.
- [ ] **B3: AIContext section.** In `AIContextBuilder.swift`, add a `progressCheckIns` section to `AIContext` — a `[ProgressCheckInFacts]` (date + regrowth title + each trend's `clinicianPhrase` + scalpPain bool + note), built from a new `progressCheckIns: [ProgressCheckIn]` parameter on `AIContext.build(...)` (most recent ~6). Bump `schemaVersion`. Update all `AIContext.build` call sites (grep: `DeepAnalysisSheet`, `CompareView`, `TodayView`? — TodayView uses `InsightContext`, not AIContext; check) to pass `progressCheckIns` (each has or can add a `@Query`). If a call site lacks the data, pass `[]` and note it.
- [ ] **B4: Tests.** `ProgressCheckInTests` (Swift Testing, `@MainActor`): a filled `ProgressCheckIn(regrowth: .visible, density: .better, shedding: .better, hairline: .stable→.same, overall: .better, scalpPain: false)` → `clinicianSummary()` contains "New regrowth (baby hairs): Clearly visible", "Density: less scalp shows", and NO red-flag line; and with `scalpPain: true, scalpPainNote: "sore crown"` → a line containing "scalp pain/tenderness" and "sore crown".

### Task C (orchestrator): integrate, build, test, launch, screenshot, commit
- [ ] Build app + widget (0 warnings); run unit tests (incl. ProgressCheckInTests); launch fresh store (no crash); screenshot the Plan tab progress card + the check-in sheet (`HC_PROGRESSCHECKIN`); commit per track + plan.
