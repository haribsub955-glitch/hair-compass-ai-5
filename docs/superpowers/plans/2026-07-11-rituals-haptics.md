# Faster rituals + textured haptics — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two slow drag-to-complete launch rituals (comb, massage) with fast auto-playing flourishes, and give the shedding dial + scrubbers CoreHaptics texture that mimics the physical feeling.

**Architecture:** Two parallel Sonnet tracks, disjoint files. Spec: `docs/superpowers/specs/2026-07-11-rituals-haptics-design.md`. Same global constraints (Clinical tokens, Reduce Motion, **agents do not run xcodebuild / git**, quote paths). No cross-track shared symbols.

---

### Task A: Fast auto-playing rituals

**Files (owns exclusively):** Modify `Hair Compass AI 5/Feature/Ritual/CombRitual.swift`, `Hair Compass AI 5/Feature/Ritual/MassageRitual.swift`.

Keep `struct CombRitual: Ritual` / `struct MassageRitual: Ritual` with `let kind: RitualKind = .comb` / `.massage` (unchanged) so `RitualKind.make`, the coordinator's persistence, and `HC_RITUAL_KIND` keep working. Only internals + `title`/`hint` change. Read `Feature/Ritual/Ritual.swift` and `Feature/Ritual/RitualView.swift` first (do NOT edit them) to honor the `Ritual` protocol (`handle`/`step`/`draw`/`isComplete`) and how `beats`/`isComplete` drive the host.

- [ ] **A1: CombRitual → automatic smoothing pass.** Rewrite as an elapsed-driven single top→bottom sweep:
  - `title = "Smooth"`, `hint = "One clean pass — you're set."`.
  - State: `time: CGFloat = 0`, `built: Bool`, the existing `locks` (reuse `build()`, `pointPosition`, `lockPath`, `lockAvg`, `Sparkle` — keep them), a `sweptStrandCount` counter, `sparkles`.
  - `duration ≈ 1.0` s. In `step(dt:size:)`: `time += dt`. Sweep y-fraction `sy = min(1, time / 0.9)` over the strand band [yTop, yBottom]. For each lock point whose y-fraction ≤ `sy`, set its smoothness `s = min(1, s + gain)` (fast, e.g. `+= 0.25`/frame) so strands straighten behind the bar. Spawn a few sparkles at the sweep bar's x-spread each frame while `sy < 1`. Emit one `beat` the frame a lock's average first crosses ~0.9 (reuse the reward logic → `beats += 1`). `handle(_:)`: any `.began/.moved` touch adds a small time boost (`time += 0.06`) to accelerate — no per-strand combing.
  - `isComplete`: `time >= 1.0` (not the old average threshold).
  - `draw`: keep the 3-stroke lock render; draw the copper→gold light bar as a soft horizontal blurred blob at the sweep y across the strand x-range while `sy < 1`; keep the sparkle render. Drop the comb-tool-follows-finger drawing (there's no finger now) — instead draw the sweep bar. Static frame at `time == 0` = wavy mid-tone strands (Reduce Motion path draws this once).

- [ ] **A2: MassageRitual → automatic settle pulse.** Rewrite as elapsed-driven concentric ring pulses:
  - `title = "Breathe"`, `hint = "A moment, then we begin."`.
  - State: `time: CGFloat = 0`, `rings: [Pulse]` where `Pulse { var start: CGFloat; var r: CGFloat }`, a `spawnedCount: Int`, plus an optional touch-ripple list, and a soft dot field (precomputed grid of scalp dots, or draw procedurally).
  - Spawn a pulse at `time == 0, 0.33, 0.66` (3 pulses); each expands `r` outward from center over ~0.6 s and fades; emit one `beat` per spawn. `duration ≈ 1.05` s. `handle(_:)` `.began/.moved`: append a ripple at the touch point (bonus).
  - `isComplete`: `time >= 1.05`.
  - `draw`: center-anchored expanding copper rings (stroke, fading with radius), a faint radial glow behind them, and a light dot field that nudges outward with the nearest pulse. Static frame at `time == 0` = one ring + glow.

Both: pure per-frame mutation via the protocol; no SwiftUI state. Keep everything `Clinical`-toned (accent/gold/canvas/ink). Do NOT run xcodebuild/git.

### Task B: CoreHaptics texture service + wiring

**Files (owns exclusively):** Create `Hair Compass AI 5/Service/Haptics.swift`; Modify `Hair Compass AI 5/Feature/Controls/ShedDialField.swift`, `Hair Compass AI 5/Feature/Controls/LivingGauge.swift`, `Hair Compass AI 5/Feature/Controls/MetricScrubber.swift`, `Hair Compass AI 5/Feature/Controls/CountScrubber.swift`, `Hair Compass AI 5/Feature/Onboarding/OnboardingComponents.swift`.

- [ ] **B1: Haptics service.** Create `Service/Haptics.swift`:

```swift
import CoreHaptics
import UIKit

/// Textured haptics that MEAN something — a heavier shedding band feels firmer than a light
/// one, and dragging the dial plays a continuous granular texture. Capability-gated: on any
/// device/simulator without CoreHaptics support, every call degrades to a UIFeedbackGenerator
/// (or a no-op for the continuous texture) so nothing crashes and the app still ticks.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private var texturePlayer: CHHapticAdvancedPatternPlayer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let selection = UISelectionFeedbackGenerator()
    private let notify = UINotificationFeedbackGenerator()

    private init() { prepareEngine() }

    private func prepareEngine() {
        guard supportsHaptics, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        engine?.stoppedHandler = { _ in }
        try? engine?.start()
    }

    /// A single "strand pluck" — intensity & sharpness rise with `fraction` (0…1), so a heavier
    /// band feels firmer. Fallback maps the fraction to an impact style.
    func bandTick(fraction: Double) {
        let f = min(1, max(0, fraction))
        guard supportsHaptics, let engine else {
            UIImpactFeedbackGenerator(style: f > 0.66 ? .heavy : f > 0.33 ? .medium : .light).impactOccurred()
            return
        }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: Float(0.35 + 0.55 * f)),
            .init(parameterID: .hapticSharpness, value: Float(0.25 + 0.65 * f))
        ], relativeTime: 0)
        play(event, on: engine)
    }

    /// A crisp low detent for scrubber tick crossings.
    func detentTick() {
        guard supportsHaptics, let engine else { selection.selectionChanged(); return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.3),
            .init(parameterID: .hapticSharpness, value: 0.5)
        ], relativeTime: 0)
        play(event, on: engine)
    }

    /// Begin a continuous granular texture (for a dial drag). No-op without CoreHaptics.
    func startTexture() {
        guard supportsHaptics, let engine else { return }
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.25),
            .init(parameterID: .hapticSharpness, value: 0.35)
        ], relativeTime: 0, duration: 30)
        texturePlayer = try? engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
        try? texturePlayer?.start(atTime: CHHapticTimeImmediate)
    }

    func updateTexture(intensity: Double) {
        guard supportsHaptics, let texturePlayer else { return }
        let p = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                         value: Float(0.15 + 0.5 * min(1, max(0, intensity))),
                                         relativeTime: 0)
        try? texturePlayer.sendParameters([p], atTime: CHHapticTimeImmediate)
    }

    func stopTexture() {
        try? texturePlayer?.stop(atTime: CHHapticTimeImmediate)
        texturePlayer = nil
    }

    func success() {
        guard supportsHaptics, let engine else { notify.notificationOccurred(.success); return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.8),
            .init(parameterID: .hapticSharpness, value: 0.6)
        ], relativeTime: 0)
        play(event, on: engine)
    }

    private func play(_ event: CHHapticEvent, on engine: CHHapticEngine) {
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
```

Verify every CoreHaptics symbol used (`CHHapticEngine.capabilitiesForHardware()`, `CHHapticEvent`, `CHHapticEventParameter` init shorthand `.init(parameterID:value:)`, `CHHapticPattern(events:parameters:)`, `makePlayer`/`makeAdvancedPlayer`, `CHHapticDynamicParameter`, `CHHapticTimeImmediate`) against the iOS 26.2 SDK `.swiftinterface` before finalizing; adjust if any signature differs.

- [ ] **B2: Shedding dials get texture.** In `SheddingDial` (OnboardingComponents.swift) and `ShedDialField` (Controls): read each first.
  - On the drag gesture `.onChanged`: on the FIRST change of a drag (track a `@State private var dragging = false`), call `Haptics.shared.startTexture()`; every change call `Haptics.shared.updateTexture(intensity: Double(intensity))`; and replace the existing `UISelectionFeedbackGenerator().selectionChanged()` (fired only when the band changes) with `Haptics.shared.bandTick(fraction: Double(SheddingDial.band(intensity)) / 3.0)` (SheddingDial) or the equivalent band/(count-1) for ShedDialField.
  - On `.onEnded`: `Haptics.shared.stopTexture()`, `dragging = false`.
  - SheddingDial's current gesture fires the tick on every change (not just band change) — preserve the band-change gating if present, else fire `bandTick` only when `SheddingDial.band` actually changes (add a small `@State private var lastBand`), matching the "tick per detent" feel.

- [ ] **B3: Gauges + scrubbers.** In `LivingGauge`: replace both `UISelectionFeedbackGenerator().selectionChanged()` calls with `Haptics.shared.bandTick(fraction: Double(newBand) / Double(max(1, bandCount - 1)))` (use the band it just moved to). In `MetricScrubber` and `CountScrubber`: replace `selectionChanged()` with `Haptics.shared.detentTick()`.

- [ ] **B4:** No unit test (haptics are hardware side effects). Build-only verification.

### Task C (orchestrator): integrate, build, verify, commit
- [ ] Build; run unit tests (should be unaffected); screenshot both new rituals (`HC_RITUAL_KIND comb`, `HC_RITUAL_KIND massage` — note they auto-play, so capture mid-animation); confirm haptics compile + take the fallback path on the simulator (no crash on the dial/scrubbers). Commit per track + spec/plan.
