# Visual AI Insights — design spec

**Date:** 2026-07-04 · **Status:** approved plan, not yet built
**Problem:** every AI outcome in the app is a paragraph of text. The daily insight on Today is a
`String`; the cloud deep analysis returns a `String`. Text is slow to scan, can't show direction,
and reads the same whether things are fine or need attention. The ask: represent AI outcomes
visually, in **two densities — a short glanceable version and an expanded version**.

---

## 1. The core move: structure first, prose second

Both AI paths stop returning free text and start returning one shared, versioned struct. Prose
becomes one *field* of the result instead of the whole result.

```swift
/// The single insight shape every producer emits and every view renders.
/// Produced identically by: RuleBasedInsight (deterministic), on-device Foundation Models,
/// and Fable cloud deep-analysis — so the UI never cares who wrote it.
struct StructuredInsight: Codable, Sendable {
    var version: Int = 1
    let status: Status                 // the one-glance verdict
    let headline: String               // ≤ 90 chars, plain language, non-diagnostic
    let factors: [Factor]              // 2–5, each renders as a visual chip/row
    let watch: [String]                // 0–3 short "worth watching" lines (expanded only)
    let detail: String                 // the full prose paragraph (expanded only)
    let source: Source                 // rules / onDevice / cloud — always shown
    let generatedAt: Date

    enum Status: String, Codable { case steady, encouraging, watch }
    // steady = sage · encouraging = gold · watch = warning. Never a "bad/alarm" state:
    // the app describes data, it does not judge scalps. `watch` is the strongest allowed.

    struct Factor: Codable, Sendable, Identifiable {
        let id: String                 // metric id from the TrackedVariable/ChartMetric catalog
        let title: String              // "Shedding", "Sleep", "Adherence"
        let direction: Direction       // improving / flat / rising — arrows, tinted by *desirability*
        let weight: Weight             // primary (big chip) / context (small chip)
        let note: String?              // ≤ 40 chars, e.g. "7-day trend", "vs last month"
        enum Direction: String, Codable { case improving, flat, rising }
        enum Weight: String, Codable { case primary, context }
    }
    enum Source: String, Codable { case rules, onDevice, cloud }
}
```

**Why `factors` reference catalog metric ids:** the expanded view can then draw each factor's real
sparkline from local data (`ChartMath.rollingMean`, exactly like the Compare/Journey charts) —
the AI *selects and orders* what matters; the numbers on screen always come from the store, never
from the model. An LLM can therefore never invent a chart.

### Producers
- **RuleBasedInsight** (exists): trivially refactored — it already computes trends; it now fills
  the struct directly. This is the guaranteed-non-empty fallback, and the schema's reference
  implementation.
- **On-device Foundation Models** (exists): prompt gains a JSON-schema instruction +
  `JSONDecoder` with one retry; on any decode failure → rules result (marked `source: .rules`).
- **Cloud deep analysis (Fable)** (exists): same schema, plus a photo section (below). The
  Messages API call keeps its current shape — only the prompt and parsing change.

### Deep analysis extends the same idea per photo region

```swift
struct PhotoAssessment: Codable, Sendable, Identifiable {
    let id: String                     // PhotoRegion rawValue
    let observation: String            // ≤ 120 chars, descriptive-only
    let comparedToLast: Direction?     // nil when no prior photo of that region
}
```
Rendered as a card per region: the actual photo thumbnail + observation + direction glyph.
Framing stays record-keeping-not-diagnosis (existing consent + footer copy unchanged).

---

## 2. The two densities

### Short — lives inside the Today insight card (replaces the paragraph)
Glanceable in under 3 seconds, no scrolling:
```
┌ TODAY'S INSIGHT ──────────────────── on-device ┐
│ ● steady        (status dot + word, sage)      │
│ "Shedding keeps easing; week 20 of 24."        │  ← headline, serif, 1–2 lines max
│ [↓ Shedding] [→ Scalp] [↑ Sleep]               │  ← factor chips: arrow + title
│                             Expand ›           │
└────────────────────────────────────────────────┘
```
- Status dot pulses gently once on appear (respects Reduce Motion).
- Factor chip arrows are tinted by **desirability**, not raw direction (shedding ↓ = sage;
  stress ↑ = warning) — a small per-metric `desirableDirection` table in the catalog decides.
- The old full paragraph is gone from the card; `headline` carries it.

### Expanded — a sheet (`InsightDetailSheet`), opened from "Expand ›"
Reuses existing visual vocabulary — nothing new to invent:
1. **Header**: status word + headline (serif), source + generatedAt line, "record-keeping, not
   diagnosis" footnote.
2. **Factor rows** (one `ClinicalCard` each): title, direction glyph, note — and a 60pt sparkline
   of that metric's last 30 days drawn from local data (JourneyChart-lite, exactly the
   ProgressReportSheet mini-chart component — extract it into `Design/` for reuse).
3. **Watch list**: the 0–3 `watch` lines as quiet bullet rows (`Clinical.tertiary` icons).
4. **Full prose**: `detail` as the closing paragraph, for people who want the words.
5. For **deep analysis**: the `PhotoAssessment` cards between (2) and (3).

---

## 3. Honesty guardrails (non-negotiable, test-asserted like the report's)
- `status` has no negative case; `watch` is the ceiling. Copy rules from ProgressReport apply
  ("never *it's working* / *stop taking*") — assert on the rules producer + prompt instructions.
- Charts/numbers only ever come from local data keyed by metric id (the model picks, never plots).
- `source` is always visible in both densities (existing cpu/seal iconography).
- Decode failure of any AI output silently falls back to rules — the card never shows an error
  state for a model problem.

## 4. Build plan (one PR-sized chunk each)
1. `Model/StructuredInsight.swift` + refactor RuleBasedInsight to emit it. Unit tests: schema
   round-trip, desirability tinting table, guardrail phrasing, decode-failure fallback.
2. On-device + cloud producers adopt the schema (prompt + parse + retry). Test with recorded
   fixture JSON.
3. `ShortInsightView` in the Today card + `InsightDetailSheet` (+ extract the mini-sparkline
   component from ProgressReportSheet). `HC_INSIGHT` debug flag opens the sheet.
4. DeepAnalysisSheet adopts PhotoAssessment cards.

Estimated as 3–4 subagent chunks, each build+screenshot-verified before commit.
