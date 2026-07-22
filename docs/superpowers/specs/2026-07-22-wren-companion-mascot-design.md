# Wren — Companion Mascot & AI Identity

**Date:** 2026-07-22
**Status:** Design approved (character direction), spec under review
**Author:** brainstormed with Claude Code

---

## 1. Summary

Introduce **Wren**, a soft warm-brown guide-bird mascot painted in the app's existing
gouache style, who becomes the **name and face of the on-device AI that already ships**
(`HairChatService` / `HairChatSheet`) and a recurring character across the app's "soft"
moments.

One character serves four goals at once:

1. **Warmer, less clinical** — a patient companion softens a data-forward app.
2. **Memorable identity** — an ownable character, not just a copper accent.
3. **Surface the AI** — the chat exists but is undiscovered; Wren gives it a name, a face,
   and a home ("Ask Wren").
4. **Marketing / store** — a hero character for App Store screenshots and onboarding.

The end-state target is a "full companion" present across the app. It ships in **phases**;
this spec defines **Phase 1 (Foundation & Identity)** in full and outlines Phases 2–3 as
follow-on specs.

## 2. Current state (what already exists)

- **On-device AI chat, already shipped.** `Service/HairChatService.swift` runs an
  Apple-Intelligence (FoundationModels) chat, grounded in the canonical `AIContext` JSON,
  scoped to hair science + the user's own record, streaming token-by-token, on-device only
  (no cloud, no key, no consent). Opened today from three places: `Feature/TodayView.swift`,
  `Feature/CompareView.swift`, `Feature/DeepAnalysisSheet.swift`.
  It currently has **no identity** — it presents as "Assistant" / "Thinking" with a generic
  `sparkles` SF Symbol (`Feature/HairChatSheet.swift`). This is *why* it feels undiscovered.
- **A mature brand-art system.** `Design/Clinical.swift` defines the `Clinical` design tokens
  (warm ivory canvas `#FBF6EF`, copper accent `#B1592E`, sage `#8A9D7B`, antique gold
  `#C9A15A`, espresso ink `#2B211A`, serif headlines) and a `BrandArt` vocabulary of painterly
  gouache assets, plus three "unboxed" treatments tuned for restraint: `CornerSprig`,
  `StrandDivider`, and `LivingArtwork` (art that slowly "breathes", Reduce-Motion-safe and
  off-screen-paused via `MotionTimeline`).
- **The compass metaphor.** The app is *Hair Compass*: `Model/CompassScore.swift`,
  `Feature/CompassRings.swift` (three effort rings — Log/copper, Care/sage, Lens/gold).
- **No mascot today.**

## 3. The character

- **Name:** **Wren.** A wren *is* a small brown songbird, so the name and the look are the
  same object — no name/appearance mismatch. Short, warm, unpretentious; pairs with "Ask Wren."
- **Look:** small, plump, soft warm-brown wren; a delicate copper-tipped crest feather (ties
  to `Clinical.accent`); calm kind eyes. Sophisticated painterly gouache in the app's existing
  style. **Not** cartoonish, not googly-eyed — a serious, minimalist brand character.
- **Personality:** a **patient wayfinder**. The app's own rule — a treatment can't be judged
  before 24 weeks — makes patience the correct register. Wren is a steady companion for a slow
  journey, never a hype-creature.
- **Voice = the AI's voice.** The chat becomes **Wren**. Warm, precise, honest; the same
  register the prompt already sets.

## 4. Principles & guardrails (non-negotiable)

- **Wren is skin, not new capability.** The scope/honesty rules in
  `HairChatService.swift` `HairChatPrompt.system(...)` — hair topics only, record-keeping not
  diagnosis, never invent numbers, never name an un-stated condition, on-device only, no cloud
  fallback — stay **100% intact**. Phase 1 changes name/face/presentation, never the model
  contract or guardrails.
- **The anti-clutter law.** Full-character Wren appears **only in "soft" moments** (onboarding,
  empty states, celebrations, the chat). On data-dense analytical screens (Trends charts, Labs
  tables) Wren is **at most a small avatar on an entry point** — never a character sitting on
  the user's data. This is what keeps "mascot everywhere" from denting the clinical
  minimalism.
- **Reuse motion infra.** All Wren motion routes through `LivingArtwork` / `MotionTimeline`
  (Reduce Motion → static representative frame; off-screen / inactive → paused). No new
  always-animating character.
- **Accessibility.** Decorative poses are `accessibilityHidden`. Interactive avatars (chat
  entry points) carry real spoken labels.
- **Honesty stays visible.** The "record-keeping, not diagnosis / not medical advice" line
  stays on the chat surface, so a friendly bird never makes the app read as a toy that
  diagnoses.

## 5. Architecture — four small, isolated units

### 5.1 `Feature/Companion/Companion.swift` — the model (pure, testable)
The single home of Wren's personality. Maps a **moment** to a **pose asset** and an optional
**line of copy**. No SwiftUI, no state — a pure function, mirroring how `HairChatPrompt`
centralizes the chat's scope and how `HairInsightCalculator` centralizes analytics.

```
enum CompanionMoment {
    case resting          // default / ambient presence
    case greeting         // onboarding welcome
    case listening        // chat: waiting for / reading the user
    case thinking         // chat: generating a reply (replaces the "Thinking" dots' role)
    case searching        // empty states (replaces flat empty icons)
    case celebrating      // milestone / streak celebration
}

enum Companion {
    static func pose(for moment: CompanionMoment) -> String   // -> CompanionArt asset name
    static func line(for moment: CompanionMoment) -> String?  // optional Wren copy
}
```

Voice lines are short, warm, patient, and never diagnostic. Draft set (final copy in
implementation):
- greeting: "I'm Wren. I'll help you read what your hair is telling you — one day at a time."
- searching (photos): "Nothing here yet. When you add a photo, I'll help you see the change."
- celebrating: "A week of showing up. That consistency is the part that actually moves hair."

### 5.2 `Feature/Companion/CompanionView.swift` — the view
Renders a `CompanionMoment` as Wren. Two variants:
- **Full pose** (hero moments): uses `LivingArtwork` so Wren "breathes"; Reduce-Motion-safe,
  off-screen-paused.
- **`.avatar`** (entry points, chat header): a small, static, circular-cropped Wren.

Depends only on `Companion` + the art assets; callers pass a moment and a size/variant.

### 5.3 Art assets — `CompanionArt` (beside `BrandArt` in `Design/Clinical.swift`)
A new `wren-*` imageset group in `Assets.xcassets`, transparent-background gouache (like
`brand-sprig`), one consistent style. Phase-1 poses:
- `wren-resting`, `wren-greeting`, `wren-listening`, `wren-thinking`, `wren-searching`,
  `wren-celebrate`, and `wren-avatar` (small crop).

Generated in the app's gouache style (nano-banana, once its model string is refreshed, or
Higgsfield). Style contract: strict `Clinical` palette; copper-tipped crest; no rounded-corner
baked-in backgrounds (see the project's app-icon corner gotcha); transparent where the art
bleeds.

### 5.4 AI reface — edits confined to `Feature/HairChatSheet.swift`
- Header: Wren `.avatar` + "Wren" + the existing honesty subtitle. Remove the generic
  `sparkles` treatment.
- The "Thinking" state uses Wren's `thinking` pose in place of / alongside the pulsing dots.
- User-facing entry copy ("Ask AI" chips at the three call sites) becomes "Ask Wren."
- **`Service/HairChatService.swift` logic is untouched** — same on-device path, same scope.

## 6. Wren presence map (Phase 1)

| Location | Moment | Variant | File |
|---|---|---|---|
| Onboarding welcome | greeting | full pose | `Feature/Onboarding/OnboardingFlow.swift` |
| "Ask Wren" home on Today | resting | avatar | `Feature/TodayView.swift` |
| Chat header | listening | avatar | `Feature/HairChatSheet.swift` |
| Chat generating | thinking | full/inline | `Feature/HairChatSheet.swift` |
| Empty states (e.g. Photos) | searching | full pose | empty-state views |
| Milestone celebration | celebrating | full pose | `Feature/CheckInCelebration.swift` |
| Trends / Labs (data-dense) | — | none / avatar only | (anti-clutter law) |

## 7. Phase plan

- **Phase 1 — Foundation & Identity (this spec):** the four units (§5), the presence map
  (§6), the art set, and tests (§8). Establishes the character and finally surfaces the AI.
- **Phase 2 — Reactions & reach (own spec):** Wren reacts to context (tilts at new data,
  flutters on a milestone); `Service/NotificationArt.swift` gains a Wren variant; additional
  placements.
- **Phase 3 — Living companion (own spec):** Wren's mood/fullness tracks the **Compass Score**
  (Wren visibly thrives as the user stays consistent — the mascot *becomes* the progress);
  widget (`Hair Compass CheckIn Widget`) and launch presence
  (`App/LaunchPresentationState.swift`).

## 8. Testing

Swift Testing (`@Test` / `#expect`) in `Hair Compass AI 5Tests`, over the pure `Companion`
mapping — exactly like `HairInsightCalculator` / `HairChatPrompt` are tested today:
- every `CompanionMoment` maps to a non-empty, existing pose asset name;
- moments that must carry copy return non-empty lines; ambient moments may return `nil`;
- copy contains no diagnostic phrasing (guard test).

No view-layer unit tests (consistent with the codebase).

## 9. Marketing (goal 4)

Phase 1's `wren-greeting` / `wren-celebrate` poses double as App Store screenshot heroes and
the onboarding welcome. A dedicated marketing composition set can be a small Phase-1 tail task
or its own follow-up.

## 10. Decisions & open items

- **Name:** Wren (chosen).
- **Anti-clutter law:** adopted (§4) — pending final user confirmation.
- **Art pipeline:** blocked this session (nano-banana stale model; Higgsfield expired). Not a
  design blocker; art is produced during implementation. Concept preview available once either
  generator is restored.
- **Non-goals (Phase 1):** no change to AI capability/scope; no cloud; no rigged/Lottie
  character; no Wren on data-dense analytical screens as a full character.
