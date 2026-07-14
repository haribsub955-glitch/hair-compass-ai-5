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
                // Round-4 fix: at 0.15 opacity the three tracks (copper/sage/gold) read as one
                // washed-out target on the fresh-day state everyone sees first each morning —
                // bumped to a clearly hued 0.24 so Log/Care/Lens each read as a distinct
                // color-coded ring before any of them have progress.
                Circle().stroke(color.opacity(0.24), lineWidth: strokeWidth)
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

/// The Today rings card, dissolved out of its card box: the triple ring sits directly on the
/// canvas with one summary line beside it — no table restating what the ring already encodes.
/// Tapping the ring expands the three detail rows in place (collapse on second tap); tapping the
/// summary text opens today's check-in, same destination the old whole-card button used to open.
struct CompassRingsCard: View {
    let score: CompassScore
    /// Raw counts behind the Care ring, needed only for the detail row's "2 of 3" readout — the
    /// ring itself only needs the fraction already folded into `score`.
    let medsDone: Int
    let medsTotal: Int
    /// True only on the very first day the app has any data at all, when today's log already
    /// exists because onboarding seeded it — not because the user tapped Log themselves today.
    var isDayOneSeed: Bool = false
    let onLog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                ringButton
                Button(action: onLog) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Compass score")
                        summaryLine
                            .font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compass score summary: \(statusLine)")
                .accessibilityHint("Opens today's check-in")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    legendRow(.log, label: "Daily log", state: score.log >= 1 ? "Logged today" : "Not yet today")
                    legendRow(.care, label: "Care steps", state: careState)
                    legendRow(.lens, label: "Photo check",
                              state: score.lens >= 1 ? "Done this week" : "Not yet this week")
                }
                .padding(.leading, 2)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                          removal: .opacity))
            }
        }
    }

    private var ringButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.4, dampingFraction: 0.78)) {
                expanded.toggle()
            }
        } label: {
            CompassRingsView(score: score, size: 104)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compass score \(score.score) of 100")
        .accessibilityValue(expanded ? "Detail shown" : "Detail hidden")
        .accessibilityHint(expanded ? "Double-tap to hide the detail" : "Double-tap to show the detail")
    }

    private var careState: String {
        guard score.care != nil else { return "No plan yet" }
        return "\(medsDone) of \(medsTotal) done"
    }

    /// One line replacing the old three-row table — the pending item (whichever open ring is
    /// closest to view) reads in gold instead of a separate row spelling it out.
    private var summaryLine: Text {
        if isDayOneSeed && score.score > 0 {
            return Text("Day 1 already on the board — logged during setup.")
                .foregroundStyle(Clinical.ink)
        }
        if score.allClosed {
            return Text("All rings closed. You showed up today.")
                .foregroundStyle(Clinical.ink)
        }
        let dot = Text("  ·  ").foregroundStyle(Clinical.tertiary)
        var pieces: [Text] = []
        pieces.append(
            Text(score.log >= 1 ? "Logged today" : "Not logged")
                .foregroundStyle(score.log >= 1 ? Clinical.ink : Clinical.gold)
        )
        if let care = score.care {
            let done = care >= 1
            pieces.append(
                Text("Care \(medsDone)/\(medsTotal)")
                    .foregroundStyle(done ? Clinical.ink : Clinical.gold)
            )
        }
        pieces.append(
            Text(score.lens >= 1 ? "Photo done" : "Photo pending")
                .foregroundStyle(score.lens >= 1 ? Clinical.ink : Clinical.gold)
        )
        return pieces.dropFirst().reduce(pieces[0]) { $0 + dot + $1 }
    }

    /// Plain-language accessibility mirror of `summaryLine` — VoiceOver reads one sentence
    /// instead of walking a `Text` concatenation.
    private var statusLine: String {
        if isDayOneSeed && score.score > 0 {
            return "Day 1 is already on the board — you logged it during setup."
        }
        if score.allClosed {
            return "All rings closed. You showed up today."
        }
        var parts = [score.log >= 1 ? "Logged today" : "Not logged"]
        if score.care != nil { parts.append("Care \(medsDone) of \(medsTotal)") }
        parts.append(score.lens >= 1 ? "Photo done" : "Photo pending")
        return parts.joined(separator: ", ")
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
