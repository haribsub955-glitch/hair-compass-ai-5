import SwiftUI

/// The colors behind the Compass Score's three effort inputs — used by the detail-row legend
/// tapping the ring reveals. Outer **Log** (copper) closes on today's check-in; **Care** (sage)
/// tracks today's dose completion, or reads as "no plan today" when nothing is scheduled;
/// **Lens** (antique gold) closes on a progress photo captured this calendar week. Every input
/// reflects only effort the user directly controls — shedding/scalp severity never touch it (see
/// `CompassScore`).
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

/// A single thin-stroke ring — the Compass Score said once, in margin scale, instead of a
/// hero-sized bullseye of three concentric pastel bands. Draws its arc in once on first
/// appearance (Reduce Motion: fades straight to the final reading, no trim animation) and pulses
/// a brief copper glow with a success haptic the moment every input closes for the day.
struct CompassRingView: View {
    let score: CompassScore
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Gates the initial 0 → value draw-in so the ring animates once on first appearance,
    /// instantly under Reduce Motion.
    @State private var shown = false
    /// Held explicitly so the very first appearance never reads as a "closure" — only a real
    /// change after the ring is already on screen can trigger the glow.
    @State private var previousScore: CompassScore?
    @State private var glowing = false

    private var strokeWidth: CGFloat { size / 11 }
    private var fraction: Double { Double(score.score) / 100 }

    var body: some View {
        ZStack {
            let clamped = shown ? max(0, min(1, fraction)) : 0
            Circle().stroke(Clinical.accent.opacity(0.18), lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8), value: clamped)
                .opacity(reduceMotion ? (shown ? 1 : 0) : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.3) : nil, value: shown)

            // No numeral before any effort was possible — a graded "0" at breakfast reads as a
            // scold, not a journal companion; the empty track alone already says "open"
            // honestly. The number appears the moment the first input closes, a small earned
            // moment of motion rather than static chrome, then keeps counting via
            // `.numericText()` on every later change.
            if score.score > 0 {
                Text("\(score.score)")
                    .font(Clinical.number(17, weight: .semibold))
                    .foregroundStyle(Clinical.ink)
                    .contentTransition(.numericText())
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.7)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: score.score)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Clinical.accent.opacity(glowing ? 0.8 : 0), radius: glowing ? 14 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: glowing)
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
            if let previousScore, !previousScore.allClosed, new.allClosed {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if !reduceMotion {
                    glowing = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        glowing = false
                    }
                }
            }
            previousScore = new
        }
        .accessibilityHidden(true)
    }
}

/// The Today rings card, un-boxed and decongested to a margin annotation: a small ring at the
/// head of the ledger with one line naming whatever's still open today — no three-part status
/// caption restating what the hero (log) and the Plan tab (care) already say. Tapping the ring
/// still expands the three detail rows in place (collapse on second tap) for anyone who wants the
/// breakdown; tapping the summary text opens today's check-in, same destination as before.
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
            HStack(alignment: .center, spacing: 14) {
                ringButton
                Button(action: onLog) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Compass score")
                        Text(openLine)
                            .font(.system(size: 14))
                            .foregroundStyle(Clinical.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compass score summary: \(openLine)")
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
            CompassRingView(score: score, size: 64)
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

    /// One line replacing the old three-part status caption ("Not logged · Care 0/3 · Photo
    /// pending") — the hero already names today's log state and the Plan tab owns care, so this
    /// names only what the ring itself still needs.
    private var openLine: String {
        if isDayOneSeed && score.score > 0 {
            return "Day 1 already on the board — logged during setup."
        }
        if score.allClosed {
            return "All rings closed. You showed up today."
        }
        // The ring itself carries no numeral yet at a true zero — its own sentence, rather than
        // the two-item "Care and photo" phrasing below, since nothing has closed at all.
        if score.score == 0 {
            return "Log, care and photo all open today."
        }
        var open: [String] = []
        if let care = score.care, care < 1 { open.append("Care") }
        if score.lens < 1 { open.append("Photo") }
        if open.isEmpty {
            return "Just today's check-in still open."
        }
        let joined = open.count > 1 ? "\(open[0]) and \(open[1].lowercased())" : open[0]
        return "\(joined) still open today."
    }

    /// Plain nouns matching the tabs/actions each input points at, with one normalized status
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
