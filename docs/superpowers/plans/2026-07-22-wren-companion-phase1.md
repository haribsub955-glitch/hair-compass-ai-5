# Wren Companion — Phase 1 (Foundation & Identity) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the already-shipped on-device AI a name and face — **Wren**, a soft warm-brown guide-bird — and make Wren the recurring character across the app's "soft" moments (chat, onboarding welcome, empty state, celebration), without touching the AI's scope/honesty guardrails.

**Architecture:** One self-contained companion unit — a pure `Companion` model (moment → pose asset + optional copy) and a decorative `CompanionView` that reuses the existing `LivingArtwork` breathing treatment — plus a set of `wren-*` gouache assets. Everything else is small, surgical edits at existing sites (`HairChatSheet`, the three chat entry points, `CheckInCelebration`, `OnboardingFlow`). No new capability; the chat's model contract is unchanged.

**Tech Stack:** SwiftUI, SwiftData (unaffected), Swift Testing (`import Testing`, `@Test`, `#expect`), Xcode project with file-system-synchronized groups (new files auto-compile), Asset Catalog.

## Global Constraints

- **Deployment target:** iOS 26.2. Scheme: `Hair Compass AI 5`.
- **Tests:** Swift Testing only (`@Test`/`#expect`, `@testable import Hair_Compass_AI_5`). No XCTest.
- **New files auto-compile:** the app root `Hair Compass AI 5/` and test root `Hair Compass AI 5Tests/` are `PBXFileSystemSynchronizedRootGroup`s. Creating a file under them adds it to the target automatically — no `project.pbxproj` edits.
- **Palette:** use `Clinical` design tokens only (`Clinical.ink`, `.accent`, `.hairline`, `.secondary`, `.tertiary`, `.surface`, `.gold`, `.sage`). Never hardcode colors.
- **Motion:** all Wren motion goes through `LivingArtwork` / `MotionTimeline` (already Reduce-Motion-safe and off-screen-paused). Never add a raw always-on animation.
- **Accessibility:** Wren art is decorative — always `.allowsHitTesting(false)` + `.accessibilityHidden(true)`. Spoken labels live on the surrounding interactive controls.
- **Sacred:** do **not** modify `Service/HairChatService.swift` (scope/honesty prompt, on-device-only path). Wren is presentation only.
- **Name:** the companion's user-visible name is exactly `"Wren"` (use `Companion.name`, never a string literal at call sites).
- **Verification commands** (pick a simulator that exists via `xcrun simctl list devices`; iPhone 16 Pro assumed):
  - Build: `xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
  - Full tests: `xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`

---

## Task 1: `Companion` model (pure, TDD)

**Files:**
- Create: `Hair Compass AI 5/Feature/Companion/Companion.swift`
- Test: `Hair Compass AI 5Tests/CompanionTests.swift`

**Interfaces:**
- Produces:
  - `enum CompanionMoment: CaseIterable { case resting, greeting, listening, thinking, searching, celebrating }`
  - `enum CompanionArt` with `static let` asset-name strings: `resting`, `greeting`, `listening`, `thinking`, `searching`, `celebrating`, `avatar` (values `"wren-resting"` … `"wren-avatar"`).
  - `enum Companion { static let name: String; static func pose(for: CompanionMoment) -> String; static func line(for: CompanionMoment) -> String? }`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/CompanionTests.swift`:

```swift
//
//  CompanionTests.swift
//  Hair Compass AI 5Tests
//
//  The Wren companion's personality is a pure mapping (moment -> pose asset + optional copy).
//  This is the only unit-tested part of the companion feature; the views are verified by build.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct CompanionTests {

    @Test func nameIsWren() {
        #expect(Companion.name == "Wren")
    }

    @Test func everyMomentMapsToANonEmptyWrenPose() {
        for moment in CompanionMoment.allCases {
            let pose = Companion.pose(for: moment)
            #expect(pose.hasPrefix("wren-"))
            #expect(!pose.isEmpty)
        }
    }

    @Test func poseMappingIsExact() {
        #expect(Companion.pose(for: .resting) == CompanionArt.resting)
        #expect(Companion.pose(for: .greeting) == CompanionArt.greeting)
        #expect(Companion.pose(for: .listening) == CompanionArt.listening)
        #expect(Companion.pose(for: .thinking) == CompanionArt.thinking)
        #expect(Companion.pose(for: .searching) == CompanionArt.searching)
        #expect(Companion.pose(for: .celebrating) == CompanionArt.celebrating)
    }

    @Test func warmMomentsCarryCopyAmbientMomentsDoNot() {
        #expect(Companion.line(for: .greeting)?.isEmpty == false)
        #expect(Companion.line(for: .searching)?.isEmpty == false)
        #expect(Companion.line(for: .celebrating)?.isEmpty == false)
        #expect(Companion.line(for: .resting) == nil)
        #expect(Companion.line(for: .listening) == nil)
        #expect(Companion.line(for: .thinking) == nil)
    }

    @Test func copyNeverSoundsDiagnostic() {
        let banned = ["diagnos", "cure", "you have", "condition", "prescrib"]
        for moment in CompanionMoment.allCases {
            guard let line = Companion.line(for: moment)?.lowercased() else { continue }
            for word in banned {
                #expect(!line.contains(word), "Companion copy must not sound diagnostic: \(line)")
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Hair Compass AI 5Tests/CompanionTests"`
Expected: FAIL — compile error `cannot find 'Companion' in scope` / `cannot find 'CompanionMoment' in scope` (the type does not exist yet).

- [ ] **Step 3: Write the model**

Create `Hair Compass AI 5/Feature/Companion/Companion.swift`:

```swift
import Foundation

/// Asset-catalog names for Wren's gouache poses. One consistent painterly style; transparent
/// backgrounds so poses bleed like `brand-sprig`. See the plan's "Asset Generation" appendix
/// for the art brief. Kept beside the model (not in BrandArt) so the companion is one isolated unit.
enum CompanionArt {
    static let resting     = "wren-resting"
    static let greeting    = "wren-greeting"
    static let listening   = "wren-listening"
    static let thinking    = "wren-thinking"
    static let searching   = "wren-searching"
    static let celebrating = "wren-celebrate"
    static let avatar      = "wren-avatar"
}

/// The contexts Wren can appear in. Drives which pose renders and which line (if any) she says.
enum CompanionMoment: CaseIterable {
    case resting       // ambient / default presence
    case greeting      // onboarding welcome, chat empty state
    case listening     // chat: waiting for / reading the person
    case thinking      // chat: generating a reply
    case searching     // empty states (replaces a flat empty icon)
    case celebrating   // milestone / streak celebration
}

/// Wren — the name and personality of the on-device AI. This is the single home of the
/// companion's voice: a pure mapping, no SwiftUI, no state, fully unit-tested (mirrors how
/// `HairChatPrompt` centralizes the chat's scope and `HairInsightCalculator` centralizes stats).
///
/// Wren is *presentation*, never capability: the chat's model contract and guardrails live in
/// `HairChatService` and are untouched. Copy here stays warm, patient, and non-diagnostic.
enum Companion {
    static let name = "Wren"

    /// The pose asset for a moment.
    static func pose(for moment: CompanionMoment) -> String {
        switch moment {
        case .resting:     return CompanionArt.resting
        case .greeting:    return CompanionArt.greeting
        case .listening:   return CompanionArt.listening
        case .thinking:    return CompanionArt.thinking
        case .searching:   return CompanionArt.searching
        case .celebrating: return CompanionArt.celebrating
        }
    }

    /// Wren's line for a moment, or `nil` for ambient moments that should stay silent.
    static func line(for moment: CompanionMoment) -> String? {
        switch moment {
        case .greeting:
            return "I'm Wren. I'll help you read what your hair is telling you — a little at a time."
        case .searching:
            return "Nothing here yet. Add something and I'll help you see what changes."
        case .celebrating:
            return "You showed up. That consistency is the part that actually moves hair."
        case .resting, .listening, .thinking:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Hair Compass AI 5Tests/CompanionTests"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add "Hair Compass AI 5/Feature/Companion/Companion.swift" "Hair Compass AI 5Tests/CompanionTests.swift"
git commit -m "Add Wren companion model (moment -> pose + copy), unit-tested"
```

---

## Task 2: Wren art assets + `CompanionView`

**Files:**
- Create: `Hair Compass AI 5/Assets.xcassets/wren-resting.imageset/` (+ `greeting`, `listening`, `thinking`, `searching`, `celebrate`, `avatar`) — each with `Contents.json` + a placeholder PNG.
- Create: `Hair Compass AI 5/Feature/Companion/CompanionView.swift`

**Interfaces:**
- Consumes: `Companion.pose(for:)`, `CompanionMoment`, `Clinical.hairline` (Task 1 + existing `LivingArtwork`).
- Produces: `struct CompanionView: View { init(moment: CompanionMoment, variant: Variant = .pose, size: CGFloat = 80); enum Variant { case pose, avatar } }`

- [ ] **Step 1: Create the seven imagesets with a placeholder PNG**

Run this from the repo root (seeds a 1×1 transparent PNG so the build has no missing-asset warnings; real art swapped in later per the appendix):

```bash
cd "Hair Compass AI 5/Assets.xcassets"
B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
for name in resting greeting listening thinking searching celebrate avatar; do
  dir="wren-$name.imageset"
  mkdir -p "$dir"
  printf '%s' "$B64" | base64 --decode > "$dir/wren-$name.png"
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "wren-$name.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
done
cd - >/dev/null
ls "Hair Compass AI 5/Assets.xcassets" | grep wren
```
Expected: lists `wren-avatar.imageset` … `wren-thinking.imageset` (7 entries).

- [ ] **Step 2: Create `CompanionView`**

Create `Hair Compass AI 5/Feature/Companion/CompanionView.swift`:

```swift
import SwiftUI

/// Renders the Wren companion for a moment. Purely decorative: never intercepts touches and is
/// invisible to accessibility — spoken labels live on the surrounding controls. Two variants:
///
/// - `.pose`  — a full illustration that slowly "breathes" via the shared `LivingArtwork`
///   treatment (Reduce-Motion-safe, off-screen-paused). Used in hero/soft moments.
/// - `.avatar` — a small, static, circular-cropped Wren for entry points and the chat header.
struct CompanionView: View {
    enum Variant { case pose, avatar }

    let moment: CompanionMoment
    var variant: Variant = .pose
    var size: CGFloat = 80

    var body: some View {
        content
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .pose:
            LivingArtwork(art: Companion.pose(for: moment), contentMode: .fit)
                .frame(width: size, height: size)
        case .avatar:
            Image(Companion.pose(for: moment))
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: `** BUILD SUCCEEDED **`, no "unassigned image" / missing-asset warnings for `wren-*`.

- [ ] **Step 4: Commit**

```bash
git add "Hair Compass AI 5/Assets.xcassets" "Hair Compass AI 5/Feature/Companion/CompanionView.swift"
git commit -m "Add Wren art assets (placeholder) + CompanionView (pose/avatar)"
```

---

## Task 3: Reface the AI chat as Wren (`HairChatSheet`)

**Files:**
- Modify: `Hair Compass AI 5/Feature/HairChatSheet.swift`

**Interfaces:**
- Consumes: `CompanionView`, `CompanionMoment`, `Companion.name`, `Companion.line(for:)` (Tasks 1–2).
- Note: `HairChatService.swift` is **not** touched.

- [ ] **Step 1: (No property change in this task)**

The header below stops rendering the per-entry `title`; the entry-specific `eyebrow` becomes Wren's subtitle. **Leave the `title` stored property in place for now** — removing it would break the two callers that still pass `title:`, and this task must stay independently buildable. Task 4 removes the property together with those arguments.

- [ ] **Step 2: Replace the `header` computed property**

Replace the entire `private var header` (currently lines 59–83) with:
```swift
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CompanionView(moment: .listening, variant: .avatar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(Companion.name)
                    .font(Clinical.headline(22))
                    .foregroundStyle(Clinical.ink)
                Text(eyebrow)
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(Clinical.secondary)
                    .frame(width: 30, height: 30)
                    .background(Clinical.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Close chat")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
```

- [ ] **Step 3: Replace the empty-state art with Wren + a greeting line**

In `private var emptyState` (currently lines 208–238), replace the leading `Image(BrandArt.sprig)…` block (lines 210–216) with a Wren pose and her greeting line. The new opening of the outer `VStack` becomes:
```swift
        VStack(alignment: .leading, spacing: 14) {
            CompanionView(moment: .listening, variant: .pose, size: 84)
            if let hello = Companion.line(for: .greeting) {
                Text(hello)
                    .font(Clinical.body(14, weight: .medium))
                    .foregroundStyle(Clinical.ink)
            }
            Text("Answers stay about hair science and your own data. Not medical advice.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
```
Leave the rest of `emptyState` (the `ForEach` of starters and the trailing padding) unchanged.

- [ ] **Step 4: Replace `thinkingRow` with Wren, and delete `ThinkingDots`**

Replace the entire `private var thinkingRow` (currently lines 182–197) with:
```swift
    private var thinkingRow: some View {
        HStack(spacing: 8) {
            CompanionView(moment: .thinking, variant: .pose, size: 30)
            Text("\(Companion.name) is thinking")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.tertiary)
        }
        .transition(.opacity)
        .accessibilityLabel("\(Companion.name) is thinking")
    }
```
Then delete the now-unused `private struct ThinkingDots` (currently lines 328–350) at the bottom of the file.

- [ ] **Step 5: Point the unavailable notice at a resting Wren**

In `private var unavailableNotice` (currently lines 293–322), replace the `Image(systemName: "sparkles")…` block (lines 297–301) with:
```swift
            CompanionView(moment: .resting, variant: .avatar, size: 56)
```
Leave the "On-device AI unavailable" text, `status.message`, and Settings button unchanged.

- [ ] **Step 6: Rename the "Assistant" accessibility labels to Wren**

- In `bubble(_:)` (line 154): change
  `.accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.text)")`
  to
  `.accessibilityLabel("\(isUser ? "You" : Companion.name): \(message.text)")`
- In `streamingBubble(_:)` (line 179): change
  `.accessibilityLabel("Assistant is typing: \(text)")`
  to
  `.accessibilityLabel("\(Companion.name) is typing: \(text)")`

- [ ] **Step 7: Build to verify**

Run: `xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: `** BUILD SUCCEEDED **`. (The `title` property is still present and still passed by both callers, so nothing breaks; it is removed in Task 4.)

- [ ] **Step 8: Commit**

```bash
git add "Hair Compass AI 5/Feature/HairChatSheet.swift"
git commit -m "Reface AI chat as Wren: header, empty state, thinking, unavailable, a11y"
```

---

## Task 4: Entry-point copy → "Ask Wren", and the Today avatar'd home

**Files:**
- Modify: `Hair Compass AI 5/Feature/TodayView.swift` (button + a11y + drop `title:` arg)
- Modify: `Hair Compass AI 5/Feature/CompareView.swift` (label + a11y)
- Modify: `Hair Compass AI 5/Feature/DeepAnalysisSheet.swift` (drop `title:` arg)

**Interfaces:**
- Consumes: `CompanionView`, `CompanionMoment` (Task 2). No new symbols produced.

- [ ] **Step 1: HairChatSheet — remove the now-unused `title` property**

In `HairChatSheet.swift`, delete these two lines (currently lines 21–22):
```swift
    /// Header title — defaults to the original Compare-sheet copy.
    var title: String = "Explain this chart"
```
(Nothing renders it after Task 3. The two callers that pass `title:` are fixed in Steps 2 and 5 of this task, so the build stays green at the end of this task.)

- [ ] **Step 2: Today — drop the `title:` argument**

In `TodayView.swift` (the `showChat` sheet, currently line 240), replace:
```swift
                eyebrow: "Ask about your record", title: "Ask AI",
```
with:
```swift
                eyebrow: "Ask about your record",
```

- [ ] **Step 3: Today — make the "Ask AI" affordance the Wren home**

In `TodayView.swift` `insightFootnote` (currently lines 358–366), replace:
```swift
                    HStack(spacing: 2) {
                        Text("Ask AI")
                        Image(systemName: "chevron.right").font(Clinical.body(8, weight: .semibold))
                    }
                    .font(Clinical.body(11, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.clinicalPressable)
                .accessibilityLabel("Ask AI about your tracking record")
```
with:
```swift
                    HStack(spacing: 4) {
                        CompanionView(moment: .resting, variant: .avatar, size: 16)
                        Text("Ask Wren")
                        Image(systemName: "chevron.right").font(Clinical.body(8, weight: .semibold))
                    }
                    .font(Clinical.body(11, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.clinicalPressable)
                .accessibilityLabel("Ask Wren about your tracking record")
```

- [ ] **Step 4: Compare — rename the chip and its a11y label**

In `CompareView.swift`:
- Line 388: change `Label("Ask AI about this", systemImage: "bubble.left.and.text.bubble.right")`
  to `Label("Ask Wren about this", systemImage: "bubble.left.and.text.bubble.right")`
- Line 396: change `.accessibilityLabel("Ask AI about this comparison")`
  to `.accessibilityLabel("Ask Wren about this comparison")`

- [ ] **Step 5: Deep analysis — drop the `title:` argument**

In `DeepAnalysisSheet.swift` (the `HairChatSheet(` call, currently line 48), replace:
```swift
                eyebrow: "Ask about your record", title: "Ask a follow-up",
```
with:
```swift
                eyebrow: "Ask about your record",
```
(Leave the `"Ask a follow-up question"` chip label as-is — it is already Wren-agnostic and reads naturally.)

- [ ] **Step 6: Build to verify (this is the gate for Tasks 3–4)**

Run: `xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: `** BUILD SUCCEEDED **` with no unused-argument or missing-argument errors.

- [ ] **Step 7: Commit**

```bash
git add "Hair Compass AI 5/Feature/HairChatSheet.swift" "Hair Compass AI 5/Feature/TodayView.swift" "Hair Compass AI 5/Feature/CompareView.swift" "Hair Compass AI 5/Feature/DeepAnalysisSheet.swift"
git commit -m "Rename chat entry points to 'Ask Wren' + Wren avatar on Today home"
```

---

## Task 5: Soft-moment placements (celebration + onboarding welcome)

**Files:**
- Modify: `Hair Compass AI 5/Feature/CheckInCelebration.swift`
- Modify: `Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift`

**Interfaces:**
- Consumes: `CompanionView`, `CompanionArt.celebrating`, `Companion.name` (Tasks 1–2).

- [ ] **Step 1: Celebration — Wren takes the medallion's place**

In `CheckInCelebration.swift`, replace the celebration artwork (currently lines 26–33):
```swift
                LivingArtwork(
                    art: BrandArt.medallion,
                    contentMode: .fit,
                    travel: 2,
                    zoom: 0.025,
                    phase: 0.8
                )
                .frame(width: 72, height: 72)
```
with (same tuned-calm motion params, Wren's celebrate pose):
```swift
                LivingArtwork(
                    art: CompanionArt.celebrating,
                    contentMode: .fit,
                    travel: 2,
                    zoom: 0.025,
                    phase: 0.8
                )
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
```

- [ ] **Step 2: Onboarding welcome — Wren introduces herself**

In `OnboardingFlow.swift` `welcome` (currently lines 243–248), replace:
```swift
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Welcome")
                Text("Let's set your\ncompass").font(Clinical.headline(34)).foregroundStyle(Clinical.ink)
                Text("A few questions — each one shows you something true about hair. It takes about a minute.")
                    .font(Clinical.caption(15)).foregroundStyle(Clinical.secondary)
            }
```
with:
```swift
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    CompanionView(moment: .greeting, variant: .avatar, size: 40)
                    Eyebrow(text: "Meet \(Companion.name)")
                }
                Text("Let's set your\ncompass").font(Clinical.headline(34)).foregroundStyle(Clinical.ink)
                Text("I'm \(Companion.name), your hair-tracking companion. A few questions first — each one shows you something true about hair. About a minute.")
                    .font(Clinical.caption(15)).foregroundStyle(Clinical.secondary)
            }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add "Hair Compass AI 5/Feature/CheckInCelebration.swift" "Hair Compass AI 5/Feature/Onboarding/OnboardingFlow.swift"
git commit -m "Place Wren in celebration + onboarding welcome (soft moments)"
```

---

## Task 6: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: all tests pass, including `CompanionTests` (5) and the pre-existing suites (no regressions from the reface).

- [ ] **Step 2: Manual smoke check in the simulator (optional but recommended)**

Launch the app; confirm: the chat header shows the Wren avatar + "Wren"; the empty state shows Wren's greeting; onboarding welcome reads "Meet Wren"; a check-in celebration shows Wren. (Wren is an invisible 1×1 placeholder until the appendix art swap — verify layout/copy, not the illustration.)

- [ ] **Step 3: Commit (only if the smoke check required any tweak)**

```bash
git add -A && git commit -m "Wren Phase 1: full-suite green"
```

---

## Appendix — Asset Generation (deferred art swap)

The wiring ships with an invisible 1×1 placeholder for each `wren-*` asset so the build is green.
Swapping in the real art is a **pure asset replacement — no code changes.**

**When to do it:** once an image generator is restored (nano-banana's Gemini model string refreshed, or the Higgsfield connector re-authorized — both were down at plan time).

**How:** generate each pose, export a transparent-background PNG, and overwrite the file at
`Hair Compass AI 5/Assets.xcassets/wren-<name>.imageset/wren-<name>.png` (keep the filename; optionally add `@2x`/`@3x` and fill the empty scale slots in `Contents.json`).

**Art brief (one consistent style across all poses):**
- **Subject:** a small, plump, soft warm-brown wren with a delicate copper-tipped crest, calm kind eyes. Sophisticated painterly **gouache**, soft brush texture. Not cartoonish, not googly-eyed.
- **Palette (strict):** warm ivory `#FBF6EF`, espresso `#2B211A`, copper accent `#B1592E`, sage `#8A9D7B`, antique gold `#C9A15A`. Transparent background.
- **No baked-in rounded-corner backgrounds** (see the project's app-icon corner gotcha) — the art must be the bird on transparency.
- **Poses:** `wren-resting` (perched, calm), `wren-greeting` (one wing lifted in hello), `wren-listening` (attentive, head level), `wren-thinking` (head tilted), `wren-searching` (looking around/peering), `wren-celebrate` (wings up, joyful-but-restrained), `wren-avatar` (tight head-and-shoulders crop that reads at 16–56 pt).

---

## Spec Coverage (self-review)

| Spec item | Task |
|---|---|
| `Companion` pure model (moment → pose + copy), tested | Task 1 |
| `CompanionView` reusing `LivingArtwork`, pose/avatar variants | Task 2 |
| `wren-*` gouache assets + `CompanionArt` | Task 2 (+ Appendix for real art) |
| AI reface confined to `HairChatSheet`; header name+avatar; thinking pose; a11y → Wren | Task 3 |
| `HairChatService` untouched | (guaranteed — no task modifies it) |
| "Ask Wren" copy at 3 entry points; Today avatar'd home | Task 4 |
| Celebration placement | Task 5 |
| Onboarding welcome greeting | Task 5 |
| Empty-state searching/greeting placement | Task 3 (chat empty state) |
| Reduce-Motion-safe, off-screen-paused motion | Task 2 (via `LivingArtwork`) |
| Decorative art `accessibilityHidden` + `allowsHitTesting(false)` | Task 2 (`CompanionView`) |
| Anti-clutter law (no Wren on Trends/Labs data) | Honored — no task adds Wren to those screens |
| Swift Testing over the mapping | Task 1 |

**Out of scope (later specs, per spec §7):** Phase 2 reactions + notification art; Phase 3 Compass-Score-driven mood, widget, launch. The empty-state anchor `hero-photos-empty` (Photos) is intentionally left to Phase 2's broader empty-state pass — Phase 1's empty-state placement is the chat's own empty state, which is the one on the AI surface.
