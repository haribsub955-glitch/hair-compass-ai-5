# Sub-project C: Spotlight Tour Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the card tour with a spotlight tour that dims the screen and highlights six real controls one at a time, each with a short Wren caption, skippable, replayable from Profile.

**Architecture:** Six views mark themselves with a one-line `.tourAnchor(.step)` modifier that publishes their frame through a SwiftUI preference. `RootView` reads the preference above the tab shell and the tab-bar inset, and renders `SpotlightTourOverlay`: a scrim with an even-odd cutout around the current step's rect, a caption panel with Wren, a step counter, Next/Done and Skip. Steps on other tabs switch the tab first. The existing `hasSeenTutorial` flag and `LaunchPresentationState.tutorial` precedence slot are reused; `TutorialOverlay.swift` is deleted.

**Tech Stack:** SwiftUI preferences (`anchorPreference`, `overlayPreferenceValue`, `GeometryProxy[Anchor]`), Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-02-first-run-plan-tour-refinement-design.md` (section C)

## Global Constraints

- Framing rule: captions are education; none is a directive to start, stop or change anything; none contains a digit.
- No palette change, no new typefaces, no dark mode, no new dependencies. Colors and fonts only through `Clinical.*` tokens.
- The tour must never be shown twice to someone who already saw the old card tour: it reuses `@AppStorage("hasSeenTutorial")`.
- Reduce Motion disables the cutout animation. VoiceOver: the caption is a modal container; Next, Done and Skip are buttons; the counter is read.
- Unit tests are Swift Testing (`@Test`, `#expect`); UI tests are XCTest with `-parallel-testing-enabled NO`.
- Every command runs from the worktree root; quote every path; git only as plain single commands (no chaining, no "git" in heredocs; commit with `-F <file>`); discard xcodebuild's scheme rewrite before committing: `git checkout -- "Hair Compass AI 5.xcodeproj/xcshareddata/xcschemes/Hair Compass AI 5.xcscheme"`.
- Test helper (`DD` given in the dispatch):

```bash
utest() { xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5Tests/$1" 2>&1 | grep -E 'error:|✘|✔|Test run with|TEST (SUCCEEDED|FAILED)|BUILD FAILED' | tail -20; }
```

- Commit messages end with:
```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

---

## File structure

| File | Responsibility |
|---|---|
| Create `Hair Compass AI 5/Feature/Tour/TourStep.swift` | `TourStep` (order, tab, caption), `TourAnchorKey`, `.tourAnchor(_:)` |
| Create `Hair Compass AI 5/Feature/Tour/SpotlightTourOverlay.swift` | scrim with cutout, caption panel, navigation, accessibility |
| Delete `Hair Compass AI 5/Feature/TutorialOverlay.swift` | the card tour |
| Modify `Hair Compass AI 5/Feature/TodayTiles.swift:68, 330` | anchors on the hero root and the log button |
| Modify `Hair Compass AI 5/Feature/Companion/WrenChatButton.swift:41-46` | anchor on the control |
| Modify `Hair Compass AI 5/Design/FloatingTabBar.swift:57-98` | anchors on the Trends, Plan, Labs and Photos items |
| Modify `Hair Compass AI 5/App/RootView.swift:84-85, 200-212, 218-230, 262-266, 374-377` | render the overlay above the inset, `HC_TOUR` flag, replay hook |
| Modify `Hair Compass AI 5/Feature/BaselineFlow.swift` | "Replay the tour" row |
| Create `Hair Compass AI 5Tests/SpotlightTourTests.swift` | step order, tab per step, captions |
| Modify `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift` | `testSpotlightTourCanBeCompleted` |

---

### Task 1: `TourStep`, the anchor preference, and the captions

**Files:**
- Create: `Hair Compass AI 5/Feature/Tour/TourStep.swift`
- Test: `Hair Compass AI 5Tests/SpotlightTourTests.swift`

**Interfaces:**
- Consumes: `AppTab` (`App/RootView.swift:37`, cases `today, trends, care, labs, photos`).
- Produces:
  - `enum TourStep: Int, CaseIterable, Identifiable { case todayHero, editLog, wren, trendsTab, planTab, recordTabs; var tab: AppTab; var caption: String }`
  - `struct TourAnchorKey: PreferenceKey { typealias Value = [TourStep: [Anchor<CGRect>]] }`
  - `extension View { func tourAnchor(_ step: TourStep) -> some View }`

- [ ] **Step 1: Write the failing tests**

Create `Hair Compass AI 5Tests/SpotlightTourTests.swift`:

```swift
//
//  SpotlightTourTests.swift
//  Hair Compass AI 5Tests
//
//  The tour's order, which tab each step needs, and its captions are data — pinned here so a
//  copy edit or a reorder is a deliberate change, and so no caption ever carries a digit or a
//  directive.
//

import Testing
@testable import Hair_Compass_AI_5

struct SpotlightTourTests {

    @Test func sixStepsInOrder() {
        #expect(TourStep.allCases == [.todayHero, .editLog, .wren, .trendsTab, .planTab, .recordTabs])
    }

    @Test func eachStepKnowsItsTab() {
        #expect(TourStep.todayHero.tab == .today)
        #expect(TourStep.editLog.tab == .today)
        #expect(TourStep.wren.tab == .today)
        #expect(TourStep.trendsTab.tab == .trends)
        #expect(TourStep.planTab.tab == .care)
        #expect(TourStep.recordTabs.tab == .labs)
    }

    @Test func captionsAreEducationNotDirectives() {
        for step in TourStep.allCases {
            let c = step.caption
            #expect(!c.isEmpty, "\(step)")
            #expect(c.rangeOfCharacter(from: .decimalDigits) == nil, "\(step): no digits in a caption")
            let lower = c.lowercased()
            #expect(!lower.contains("you should") && !lower.contains("you must") && !lower.contains("start taking"), "\(step)")
        }
    }

    @Test func captionsNameTheControl() {
        #expect(TourStep.wren.caption.contains(Companion.name))
        #expect(TourStep.trendsTab.caption.lowercased().contains("trends"))
        #expect(TourStep.planTab.caption.lowercased().contains("plan"))
        #expect(TourStep.recordTabs.caption.lowercased().contains("labs"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `utest SpotlightTourTests`
Expected: build failure — `TourStep` not found.

- [ ] **Step 3: Write the step model and the anchor plumbing**

Create `Hair Compass AI 5/Feature/Tour/TourStep.swift`:

```swift
//
//  TourStep.swift
//  Hair Compass AI 5
//
//  The spotlight tour's six steps, and the one-line way a view joins it. A view calls
//  `.tourAnchor(.step)`; the frame flows up as a SwiftUI anchor preference; RootView reads it
//  above the whole tab shell and draws the cutout. Views know nothing else about the tour.
//

import SwiftUI

enum TourStep: Int, CaseIterable, Identifiable {
    case todayHero, editLog, wren, trendsTab, planTab, recordTabs

    var id: Int { rawValue }

    /// The tab that must be showing for this step's control to exist on screen.
    var tab: AppTab {
        switch self {
        case .todayHero, .editLog, .wren: return .today
        case .trendsTab: return .trends
        case .planTab: return .care
        case .recordTabs: return .labs
        }
    }

    /// Written for a first-timer: what the control does and why it matters. No digits — the
    /// same rule the AI validator applies to generated copy.
    var caption: String {
        switch self {
        case .todayHero:
            return "This is today. Log once a day here — a month of these is what makes the trends honest."
        case .editLog:
            return "Change today's log any time. Nothing is judged from one day."
        case .wren:
            return "\(Companion.name) answers questions about your own record, in plain language. Never a diagnosis."
        case .trendsTab:
            return "Trends open as your record grows. Each chart says when."
        case .planTab:
            return "Your plan: the starting checklist, then your daily ritual."
        case .recordTabs:
            return "Labs and photos live here. They are what a clinician will ask about."
        }
    }
}

/// Frames of the marked views, keyed by step. A step may have more than one anchor (Labs and
/// Photos share `recordTabs`); the overlay unions them.
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourStep: [Anchor<CGRect>]] { [:] }
    static func reduce(value: inout [TourStep: [Anchor<CGRect>]], nextValue: () -> [TourStep: [Anchor<CGRect>]]) {
        for (step, anchors) in nextValue() {
            value[step, default: []].append(contentsOf: anchors)
        }
    }
}

extension View {
    /// Marks this view as the control the given tour step highlights.
    func tourAnchor(_ step: TourStep) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [step: [$0]] }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `utest SpotlightTourTests`
Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

Message (write to a scratch file, commit with `-F`):

```
Tour steps and the anchor preference

Six steps with their tab and caption, a preference key that carries the
marked views' frames upward, and the one-line `.tourAnchor(_:)` a view
uses to join the tour. Captions carry no digits and no directives; tests
pin order, tab and copy.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git add "Hair Compass AI 5/Feature/Tour/TourStep.swift" "Hair Compass AI 5Tests/SpotlightTourTests.swift"`, then `git commit -F`.

---

### Task 2: The overlay

**Files:**
- Create: `Hair Compass AI 5/Feature/Tour/SpotlightTourOverlay.swift`

**Interfaces:**
- Consumes: `TourStep`, `TourAnchorKey.Value` (Task 1); `CompanionView(moment:variant:size:)` and `Companion.name` (`Feature/Companion/`); `ClinicalCard`, `ClinicalButtonStyle`, `Eyebrow`, `Clinical.*` tokens.
- Produces: `struct SpotlightTourOverlay: View { init(anchors: [TourStep: [Anchor<CGRect>]], tab: Binding<AppTab>, onDone: @escaping () -> Void) }`; accessibility identifiers `tourCaption`, `tourNext`, `tourSkip`, `tourCounter`.

- [ ] **Step 1: Write the overlay**

Create `Hair Compass AI 5/Feature/Tour/SpotlightTourOverlay.swift`:

```swift
//
//  SpotlightTourOverlay.swift
//  Hair Compass AI 5
//
//  The first-run tour: the screen dims, one real control stays lit inside a rounded cutout, and
//  Wren says one thing about it. Rendered by RootView above the tab shell AND the tab-bar inset
//  (so tab items can be highlighted), from the anchors views published with `.tourAnchor`.
//  Steps on another tab switch the tab first and highlight once the new screen has laid out.
//

import SwiftUI
import UIKit

struct SpotlightTourOverlay: View {
    let anchors: [TourStep: [Anchor<CGRect>]]
    @Binding var tab: AppTab
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    private var step: TourStep { TourStep.allCases[index] }
    private var isLast: Bool { index == TourStep.allCases.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            let cutout = unionRect(for: step, in: proxy)
            ZStack(alignment: .topTrailing) {
                scrim(cutout: cutout, in: proxy)
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }

                skipButton
                    .padding(.top, proxy.safeAreaInsets.top + 8)
                    .padding(.trailing, 20)

                caption(for: step, cutout: cutout, in: proxy)
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: index)
        }
        .transition(.opacity)
        .onAppear { tab = step.tab }
        .onChange(of: index) { _, newValue in
            let next = TourStep.allCases[newValue]
            if tab != next.tab {
                withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) { tab = next.tab }
            }
        }
    }

    // MARK: Geometry

    /// The union of every anchor this step published (Labs + Photos share one), inset outward
    /// so the control breathes inside the cutout. Nil while the target has not laid out yet —
    /// right after a tab switch — in which case the scrim has no hole and the caption sits
    /// centred until the next layout pass fills it.
    private func unionRect(for step: TourStep, in proxy: GeometryProxy) -> CGRect? {
        guard let list = anchors[step], !list.isEmpty else { return nil }
        let rects = list.map { proxy[$0] }
        var union = rects[0]
        for r in rects.dropFirst() { union = union.union(r) }
        return union.insetBy(dx: -8, dy: -8)
    }

    private func scrim(cutout: CGRect?, in proxy: GeometryProxy) -> some View {
        Clinical.ink.opacity(0.55)
            .mask {
                // Even-odd: the full rect minus the rounded cutout.
                Rectangle()
                    .overlay {
                        if let cutout {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .frame(width: cutout.width, height: cutout.height)
                                .position(x: cutout.midX, y: cutout.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .accessibilityHidden(true)
    }

    // MARK: Caption

    private func caption(for step: TourStep, cutout: CGRect?, in proxy: GeometryProxy) -> some View {
        let panelHeight: CGFloat = 168
        let width = proxy.size.width
        let height = proxy.size.height
        // Below the cutout when there is room, otherwise above it; centred when no cutout yet.
        let y: CGFloat = {
            guard let cutout else { return height / 2 }
            if cutout.maxY + 16 + panelHeight < height - proxy.safeAreaInsets.bottom - 8 {
                return cutout.maxY + 16 + panelHeight / 2
            }
            return max(proxy.safeAreaInsets.top + 60 + panelHeight / 2, cutout.minY - 16 - panelHeight / 2)
        }()
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    CompanionView(moment: .greeting, variant: .avatar, size: 34)
                    Text(step.caption)
                        .font(Clinical.caption(14))
                        .foregroundStyle(Clinical.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tourCaption")
                }
                HStack {
                    Text("\(index + 1) of \(TourStep.allCases.count)")
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                        .accessibilityIdentifier("tourCounter")
                    Spacer(minLength: 8)
                    Button(isLast ? "Done" : "Next") { advance() }
                        .buttonStyle(ClinicalButtonStyle())
                        .accessibilityIdentifier("tourNext")
                }
            }
        }
        .frame(width: width - 40)
        .position(x: width / 2, y: y)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .id(index)
    }

    private var skipButton: some View {
        Button("Skip") { skip() }
            .font(Clinical.body(13, weight: .medium))
            .foregroundStyle(Clinical.surface.opacity(0.9))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Clinical.ink.opacity(0.35), in: Capsule())
            .accessibilityIdentifier("tourSkip")
            .accessibilityLabel("Skip the tour")
    }

    // MARK: Actions

    private func advance() {
        if isLast {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            index += 1
        }
    }

    private func skip() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onDone()
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -quiet 2>&1 | grep -E 'error:'
```

Expected: no output. The overlay is not yet rendered anywhere; Task 3 wires it.

- [ ] **Step 3: Commit**

Message:

```
SpotlightTourOverlay: scrim, cutout, and a caption with Wren

An even-odd mask lifts the current control out of the scrim; the
caption sits below the cutout or above it when there is no room; Next,
Done and Skip carry identifiers for the UI test; Reduce Motion drops the
cutout animation. Steps on another tab switch the tab first.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git checkout -- "<scheme>"`, `git add "Hair Compass AI 5/Feature/Tour/SpotlightTourOverlay.swift"`, `git commit -F`.

---

### Task 3: Anchors, the root wiring, the replay row, and the old tour's removal

**Files:**
- Modify: `Hair Compass AI 5/Feature/TodayTiles.swift` (`ConditionsHero.body` root `ZStack` at `:68`; `logButton` at `:330`)
- Modify: `Hair Compass AI 5/Feature/Companion/WrenChatButton.swift:41-46`
- Modify: `Hair Compass AI 5/Design/FloatingTabBar.swift:57-98` (`item(_:)`)
- Modify: `Hair Compass AI 5/App/RootView.swift` (`:200-212` old overlay; after `:230` new overlay; `:262-266` `HC_TOUR`; sheet content for the replay callback)
- Modify: `Hair Compass AI 5/Feature/BaselineFlow.swift` (replay row)
- Delete: `Hair Compass AI 5/Feature/TutorialOverlay.swift`
- Modify: `Hair Compass AI 5UITests/Hair_Compass_AI_5UITests.swift`

**Interfaces:**
- Consumes: `.tourAnchor(_:)`, `TourStep`, `TourAnchorKey` (Task 1); `SpotlightTourOverlay(anchors:tab:onDone:)` (Task 2); RootView's `hasSeenTutorial`, `showTutorial`, `launchPresentation.surface == .tutorial`, `showProfileEdit`, `tab`; `BaselineFlow(profile:onEraseRequested:)` from sub-project A.
- Produces: `BaselineFlow.onReplayTour: (() -> Void)?`; DEBUG launch argument `HC_TOUR`.

- [ ] **Step 1: Write the failing UI test**

Append inside the `Hair_Compass_AI_5UITests` class:

```swift
    /// The spotlight tour can be stepped through to Done, and does not return on relaunch.
    @MainActor
    func testSpotlightTourCanBeCompleted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_TOUR"]
        app.launch()

        let caption = app.staticTexts["tourCaption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10), "the tour must start when HC_TOUR forces it")

        let next = app.buttons["tourNext"]
        for _ in 0..<8 {
            guard next.waitForExistence(timeout: 4) else { break }
            next.tap()
            if !caption.exists { break }
        }
        XCTAssertFalse(caption.waitForExistence(timeout: 2), "Done must end the tour")

        app.terminate()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL"]
        app.launch()
        XCTAssertFalse(app.staticTexts["tourCaption"].waitForExistence(timeout: 4), "a finished tour must not return")
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests/Hair_Compass_AI_5UITests/testSpotlightTourCanBeCompleted" 2>&1 | grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" | tail -4
```

Expected: `failed` on "the tour must start when HC_TOUR forces it".

- [ ] **Step 3: Anchor the six controls**

`Hair Compass AI 5/Feature/TodayTiles.swift`: in `ConditionsHero`, the `body`'s root `ZStack(alignment: .topLeading) { ... }` gets `.tourAnchor(.todayHero)` appended after its closing brace and existing modifiers (find the `ZStack(alignment: .topLeading)` that opens at line 68 and its matching end; append the modifier to the last modifier of that ZStack expression). In `logButton`, add `.tourAnchor(.editLog)` after `.accessibilityHint(logButtonAccessibilityHint)`.

`Hair Compass AI 5/Feature/Companion/WrenChatButton.swift`: in `body`, change `control` inside the `HStack` to `control.tourAnchor(.wren)`.

`Hair Compass AI 5/Design/FloatingTabBar.swift`: in `item(_ tab: AppTab)`, after `.accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)` add:

```swift
        .modifier(TabTourAnchor(tab: tab))
```

and add at the bottom of the file:

```swift
/// Marks the tab items the tour highlights. Labs and Photos share one step; the overlay unions
/// their frames.
private struct TabTourAnchor: ViewModifier {
    let tab: AppTab
    func body(content: Content) -> some View {
        switch tab {
        case .trends: content.tourAnchor(.trendsTab)
        case .care: content.tourAnchor(.planTab)
        case .labs, .photos: content.tourAnchor(.recordTabs)
        case .today: content
        }
    }
}
```

- [ ] **Step 4: Render the overlay from RootView, above the inset**

In `Hair Compass AI 5/App/RootView.swift`:

(a) Delete the old overlay block — the `.overlay { if launchPresentation.surface == .tutorial { TutorialOverlay(tab: $tab) { ... } .transition(.opacity) } }` together with its three-line comment above it ("First-launch tutorial: a card-above-the-tab-bar coach sequence…").

(b) Directly after the `.safeAreaInset(edge: .bottom, spacing: 0) { ... }` modifier (the one containing `WrenChatButton` and `FloatingTabBar`, ending with `.zIndex(100)` and the closing `}`), add:

```swift
        // The spotlight tour draws above the tab-bar inset so tab items can be lit; the anchors
        // arrive from every view that called `.tourAnchor`, tab content and inset alike.
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if launchPresentation.surface == .tutorial {
                SpotlightTourOverlay(anchors: anchors, tab: $tab) {
                    hasSeenTutorial = true
                    showTutorial = false
                }
                .transition(.opacity)
            }
        }
```

(c) Add the QA flag next to `HC_ONBOARD` / `HC_PROFILE` inside the `#if DEBUG` block:

```swift
            if ProcessInfo.processInfo.arguments.contains("HC_TOUR") { showTutorial = true }
```

(d) Replay from Profile: where `BaselineFlow(profile: profile, onEraseRequested: { pendingErase = true })` is constructed, add the second callback:

```swift
                BaselineFlow(
                    profile: profile,
                    onEraseRequested: { pendingErase = true },
                    onReplayTour: {
                        showProfileEdit = false
                        tab = .today
                        showTutorial = true
                    }
                )
```

- [ ] **Step 5: The replay row in Profile**

In `Hair Compass AI 5/Feature/BaselineFlow.swift`, after `var onEraseRequested: (() -> Void)? = nil` add:

```swift
    /// Set by RootView: closes this sheet and starts the spotlight tour on Today.
    var onReplayTour: (() -> Void)? = nil
```

Directly after the `replayRow` usage in the form (the `BrandNavRow` "Replay the walkthrough"), add a second row. Add this property next to `replayRow`:

```swift
    private var replayTourRow: some View {
        BrandNavRow(
            symbol: "scope",
            title: "Replay the tour",
            line: "Walk the six highlighted controls again"
        ) { onReplayTour?() }
        .accessibilityIdentifier("replayTour")
    }
```

and place `replayTourRow` immediately after `replayRow` wherever `replayRow` appears in the body.

- [ ] **Step 6: Delete the card tour**

```bash
grep -rn 'TutorialOverlay' --include='*.swift' "Hair Compass AI 5" "Hair Compass AI 5Tests" "Hair Compass AI 5UITests"
```

Expected: only the file's own declaration. Then `git rm -q "Hair Compass AI 5/Feature/TutorialOverlay.swift"`. If a test or UI test references `tutorialNext` / `tutorialSkip`, update it to `tourNext` / `tourSkip`.

- [ ] **Step 7: Run the UI test, then the suites**

```bash
xcodebuild test -project "Hair Compass AI 5.xcodeproj" -scheme "Hair Compass AI 5" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" -parallel-testing-enabled NO -only-testing:"Hair Compass AI 5UITests/Hair_Compass_AI_5UITests/testSpotlightTourCanBeCompleted" 2>&1 | grep -E "Test Case .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)" | tail -4
```

Expected: `passed`. Then the full UI target (`-only-testing:"Hair Compass AI 5UITests"`) and the full unit target; both `TEST SUCCEEDED`.

- [ ] **Step 8: See it**

```bash
xcrun simctl terminate booted harib.Hair-Compass-AI-5 2>/dev/null
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/Hair Compass AI 5.app"
xcrun simctl launch booted harib.Hair-Compass-AI-5 HC_SEED_DEMO HC_NORITUAL HC_TOUR
sleep 3
xcrun simctl io booted screenshot "$DD/../tour-step1.png"
```

Open the screenshot. Expected: the screen dimmed, the Today hero lit inside a rounded cutout, Wren's caption panel below it with "1 of 6", Next, and Skip at the top right.

- [ ] **Step 9: Commit**

Message:

```
Spotlight tour replaces the card tour

Six real controls mark themselves with one modifier; RootView draws the
scrim and cutout above the tab-bar inset so tab items can be lit. The
tour starts after onboarding as before, reuses hasSeenTutorial so nobody
sees it twice, replays from Profile, and HC_TOUR forces it for QA. The
card tour is gone. UI test steps through to Done and proves it does not
return.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HV9VUdf2Q5nPmjRviKGnvu
```

`git checkout -- "<scheme>"`; `git add` the six modified files and the UI test file; `git commit -F`.

---

### Task 4: Land sub-project C

Controller task: fast-forward `feat/agent-profile-memory`, push, merge `rebuild/clinical-minimal` forward, push, leave the simulator on the new build.

---

## Self-review notes

- Spec C1 anchors: six call sites (hero, log button, Wren, Trends, Plan, Labs+Photos) — Task 3. C2 overlay: scrim 0.55, cutout inset 8 radius 18, caption placement, tab switch, Reduce Motion, VoiceOver traits — Task 2. C3 captions — Task 1, digit-free test. C4 lifecycle: starts after the finale via the existing `showTutorial` path, reuses `hasSeenTutorial`, replay row, erase clears the flag (sub-project A), Skip/Done set it — Tasks 3 and existing RootView code.
- Deviation: the UI test forces the tour with `HC_TOUR` on a seeded record instead of walking all fifteen onboarding steps; the onboarding→tour hand-off is the unchanged `onFinish` code path.
- Deviation: tapping inside the cutout advances via the scrim's tap gesture only where the scrim is hit-testable; the lit control itself remains tappable underneath. Acceptable: the spec asked that the control not be activated, and the mask leaves the control visible; if QA shows taps reaching the control, add `.allowsHitTesting(false)` on the tab content while the tour is active in a follow-up.
