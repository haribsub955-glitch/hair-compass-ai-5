# Progress check-in — the questions a dermatologist asks — Design (2026-07-11)

Between visits, a hair specialist asks a patient a specific set of *response* questions —
"are you seeing new baby hairs since starting minoxidil?", "is your scalp showing through
less?", "any scalp pain?". These are slow-moving, patient-observable signals that don't belong
in the daily log. This feature captures them in a periodic **Progress check-in** and puts the
answers where the clinician looks: the **clinician export** and the **AI context**.

## 1. The questions (clinically grounded, patient-observable, honest)

Six questions, each a real between-visit dermatology question, phrased plainly. Stored on a new
`ProgressCheckIn` (dated, ~monthly). Answers are self-report *context*, never measurement or
diagnosis — the app's standing stance.

1. **New regrowth (baby hairs)** — *the flagship.* "Any new fine 'baby' hairs at your hairline,
   part, or crown?" → **None · A few · Clearly visible · Lots** (`RegrowthLevel`, 0–3). The
   earliest patient-observable sign that a medication/procedure is working (vellus→terminal
   conversion, ~2–4 months in).
2. **Density** — "Compared to last time, does your scalp show through…" → **More · About the
   same · Less** (`ProgressTrend`; *better* = less scalp visible).
3. **Shedding (self-assessed trend)** — "Your shedding lately is…" → **More · Same · Less**.
   Complements the objective daily shed with the patient's own read.
4. **Hairline / part** — "Your hairline or part is…" → **Receding/widening · Stable ·
   Filling in**.
5. **Scalp symptoms (a genuine red flag)** — "Any scalp pain, burning, or sore/tender spots?" →
   **No · Yes** (+ optional note). Persistent scalp pain/tenderness with hair loss can signal a
   scarring alopecia (lichen planopilaris, frontal fibrosing) that needs prompt dermatology —
   so a *Yes* surfaces an honest "worth mentioning to your dermatologist soon" note (not a
   diagnosis). This is the safety-relevant question a doctor most wants answered.
6. **Overall** — "Overall, your hair feels…" → **Worse · Stable · Better** (`ProgressTrend`).

The check-in header contextualizes with the plan — "You've been on {treatment} for {N} weeks"
and any recent procedure — so the regrowth/shedding answers are read against *what the user is
doing* ("after a medication or a procedure"), exactly the clinician's framing.

## 2. Where they live

- **Capture:** a **Progress check-in card in the Plan tab** (Care) — the treatment-response
  home — showing the last check-in date and a "New check-in" button, flagged "Due" when it's
  been ≥ 30 days. A short, low-frequency **monthly reminder** (beautiful, low-text, reusing
  `NotificationArt`) nudges it — no increase to the daily cadence.
- **The answers surface where the clinician + AI read them:**
  - **`ExportService.clinicianSummary`** gains a "Progress check-ins (self-reported)" section
    listing the most recent 1–3 check-ins in plain lines, plus the scalp-pain red-flag line
    when present. `dataJSON` includes them too.
  - **`AIContext`** gains a `progressCheckIns` section so the daily insight / deep analysis /
    chat can reference regrowth and trajectory ("you reported new baby hairs at week 14 —
    consistent with an early minoxidil response; keep going, and confirm with your clinician").

## 3. Foundation (orchestrator first, migration-safe, committed before tracks)

- **`enum RegrowthLevel: Int`** (`none/few/visible/lots`) + **`enum ProgressTrend: Int`**
  (`worse/same/better`, where `better` is always the good direction) in `Model/Enums.swift`,
  each with `title` and a context-labelled helper for the four trend questions.
- **`@Model ProgressCheckIn`** in `Model/Models.swift`: `date`, `regrowthRaw`, `densityRaw`,
  `sheddingRaw`, `hairlineRaw`, `overallRaw` (Ints), `scalpPain: Bool`, `scalpPainNote: String`,
  `note: String`, `createdAt` — all inline defaults; computed enum accessors + a
  `clinicianSummary() -> [String]` helper producing the export lines. Registered in the
  container `Schema`. Launch-verified on the existing store.

## 4. Tracks

- **Track A — capture:** `Feature/ProgressCheckInSheet.swift` (the six-question form, Clinical
  idiom, chip/scrubber answers, the scalp-pain red-flag note on save), a Progress-check-in card
  in `Feature/CareView.swift` (last date + "Due" + "New check-in"), and a monthly reminder in
  `Service/NotificationService.swift`.
- **Track B — surface:** `Service/ExportService.swift` (+ `Feature/ExportSheet.swift` to pass a
  `@Query` of check-ins) and `Model/AIContextBuilder.swift` (a `progressCheckIns` section).

## Honesty guardrails
Answers are self-reported context, never diagnosis. The scalp-pain red flag is a safety nudge
to see a clinician, not a diagnosis. The AI may reference the answers but never claim a
treatment "worked" — it stays "consistent with… confirm with your clinician."

## Tests
- `ProgressCheckInTests`: the `clinicianSummary()` lines for a filled check-in (regrowth,
  each trend's contextual wording, the red-flag line when `scalpPain`), and no red-flag line
  when false. Foundation launch-verified.

## Execution
Orchestrator: foundation (model/enums/schema) + launch check + commit. Then two Sonnet tracks
(A capture, B surface) over disjoint files. Orchestrator integrates, builds, tests, launches,
commits.
