import SwiftUI

/// The three concentric rings of the Compass Score — an Apple-Fitness-style daily *effort*
/// readout. Outer **Log** (copper) closes on today's check-in; middle **Care** (sage) tracks
/// today's dose completion, or renders as a faint dotted hairline when nothing is scheduled;
/// inner **Lens** (antique gold) closes on a progress photo captured this calendar week. Every
/// ring reflects only effort the user directly controls — shedding/scalp severity never touch
/// it (see `CompassScore`).
enum CompassRingKind: CaseIterable, Hashable {
    case log, care, lens

    var color: Color {
        switch self {
        case .log: return Clinical.accent
        case .care: return Clinical.sage
        case .lens: return Clinical.gold
        }
    }
}

/// Draws the three rings and the center score. Reuses the app's established ring recipe
/// (`CoachProgressRing`/`XPProgressRing`/`MedsArcRing` in CareView.swift/TodayTiles.swift): a
/// faint track, a rounded-cap fill stroked from 12 o'clock, a spring on value change, and a
/// one-shot draw-in on first appearance. Adds a closure moment on top: when a ring first reaches
/// 1.0 it pulses a brief ring-colored glow and fires a success haptic.
struct CompassRingsView: View {
    let score: CompassScore
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Gates the initial 0 → value draw-in so the rings animate once on first appearance,
    /// instantly under Reduce Motion — same idiom as the other rings in this app.
    @State private var shown = false
    /// Held explicitly (rather than relying solely on `onChange`'s old-value parameter) so the
    /// very first appearance never reads as a "closure" — only a real change after the rings
    /// are already on screen can trigger the glow.
    @State private var previousScore: CompassScore?
    @State private var glowingRings: Set<CompassRingKind> = []

    private var strokeWidth: CGFloat { size / 9 }

    var body: some View {
        ZStack {
            ringLayer(.log, diameter: size, progress: score.log)
            ringLayer(.care, diameter: size * 0.7, progress: score.care)
            ringLayer(.lens, diameter: size * 0.4, progress: score.lens)

            VStack(spacing: 2) {
                Text("\(score.score)")
                    .font(Clinical.number(28))
                    .foregroundStyle(Clinical.ink)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: score.score)
                Eyebrow(text: "Today")
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard previousScore == nil else { return }
            previousScore = score
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) { shown = true }
            }
        }
        .onChange(of: score) { _, new in
            if let previousScore { handleClosure(from: previousScore, to: new) }
            previousScore = new
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compass score \(score.score) of 100")
        .accessibilityValue(ringsAccessibilityValue)
    }

    // MARK: - Ring drawing

    @ViewBuilder
    private func ringLayer(_ kind: CompassRingKind, diameter: CGFloat, progress: Double?) -> some View {
        let color = kind.color
        ZStack {
            if let progress {
                let clamped = shown ? max(0, min(1, progress)) : 0
                Circle().stroke(color.opacity(0.15), lineWidth: strokeWidth)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8), value: clamped)
            } else {
                // No plan today: a quiet dotted hairline, no fill — this ring is excluded from
                // the score entirely rather than reading as "0 of something".
                Circle()
                    .stroke(Clinical.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(
            color: color.opacity(glowingRings.contains(kind) ? 0.85 : 0),
            radius: glowingRings.contains(kind) ? 16 : 0
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: glowingRings.contains(kind))
    }

    // MARK: - Closure moment

    /// One-shot glow + success haptic when a ring first reaches 1.0 (or all three close at
    /// once). The haptic always fires; the visual pulse is skipped under Reduce Motion.
    private func handleClosure(from old: CompassScore, to new: CompassScore) {
        var crossed: Set<CompassRingKind> = []
        if !old.allClosed && new.allClosed {
            crossed = Set(CompassRingKind.allCases)
        } else {
            if old.log < 1 && new.log >= 1 { crossed.insert(.log) }
            if let oldCare = old.care, let newCare = new.care, oldCare < 1 && newCare >= 1 {
                crossed.insert(.care)
            }
            if old.lens < 1 && new.lens >= 1 { crossed.insert(.lens) }
        }
        guard !crossed.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard !reduceMotion else { return }
        glowingRings = crossed
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            glowingRings.subtract(crossed)
        }
    }

    // MARK: - Accessibility

    private var ringsAccessibilityValue: String {
        let logState = score.log >= 1 ? "logged" : "not yet"
        let careState: String = {
            guard let care = score.care else { return "no plan today" }
            if care >= 1 { return "complete" }
            if care > 0 { return "in progress" }
            return "not started"
        }()
        let lensState = score.lens >= 1 ? "captured this week" : "not yet this week"
        return "Log \(logState). Care \(careState). Lens \(lensState)."
    }
}

/// The Today rings card: `CompassRingsView` plus an identity-toned status line and a legend of
/// the three rings' raw state. Tapping anywhere opens today's check-in — the same action as the
/// hero's own log button — so the card reads as one more entry point into logging, not a
/// separate destination.
struct CompassRingsCard: View {
    let score: CompassScore
    /// Raw counts behind the Care ring, needed only for the legend's "2 of 3" readout — the
    /// ring itself only needs the fraction already folded into `score`.
    let medsDone: Int
    let medsTotal: Int
    /// True only on the very first day the app has any data at all, when today's log already
    /// exists because onboarding seeded it — not because the user tapped Log themselves today.
    var isDayOneSeed: Bool = false
    let onLog: () -> Void

    var body: some View {
        Button(action: onLog) {
            ClinicalCard {
                HStack(alignment: .center, spacing: 18) {
                    CompassRingsView(score: score, size: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Compass score")
                        Text(statusLine)
                            .font(.system(size: 14))
                            .foregroundStyle(Clinical.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 6) {
                            legendRow(.log, label: "Daily log", state: score.log >= 1 ? "Logged today" : "Not yet today")
                            legendRow(.care, label: "Care steps", state: careState)
                            legendRow(.lens, label: "Photo check",
                                      state: score.lens >= 1 ? "Done this week" : "Not yet this week")
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens today's check-in")
    }

    private var careState: String {
        guard score.care != nil else { return "No plan yet" }
        return "\(medsDone) of \(medsTotal) done"
    }

    /// Priority order: the day-one welcome is the rarest and most specific state (it only ever
    /// applies once, the first calendar day the app has any data), so it's checked ahead of the
    /// generic buckets — otherwise a seeded day-one log would always read as the plain
    /// "Logged. N ring(s) to go." line and the welcome would never show.
    private var statusLine: String {
        if isDayOneSeed && score.score > 0 {
            return "Day 1 is already on the board — you logged it during setup."
        }
        if score.allClosed {
            return "All rings closed. You showed up today."
        }
        if score.log < 1 {
            return "The check-in takes 20 seconds — it closes the copper ring."
        }
        let remaining = ringsRemaining
        return "Logged. \(remaining) ring\(remaining == 1 ? "" : "s") to go."
    }

    /// Open rings other than Log (which is already closed in every branch that reads this) —
    /// Care only counts when a plan actually exists today.
    private var ringsRemaining: Int {
        var count = 0
        if score.lens < 1 { count += 1 }
        if let care = score.care, care < 1 { count += 1 }
        return count
    }

    /// Plain nouns matching the tabs/actions each ring points at, with one normalized status
    /// grammar across all three rows — and a single combined VoiceOver label so the dot color
    /// coding is never the only carrier of meaning.
    private func legendRow(_ kind: CompassRingKind, label: String, state: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(kind.color).frame(width: 8, height: 8)
            Eyebrow(text: label)
            Spacer(minLength: 8)
            Text(state)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Clinical.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(state)")
    }
}
