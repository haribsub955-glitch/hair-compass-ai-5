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
