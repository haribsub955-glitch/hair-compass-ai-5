import SwiftUI

/// Clinical-minimal design system. Pure white, a single precise accent, hairline structure,
/// tabular numerals. Deliberately nothing like the previous pearl/forest/serif look.
enum Clinical {

    // MARK: Palette — a near-neutral instrument with one signal accent.
    static let surface = Color.white
    static let canvas = Color(red: 0.97, green: 0.97, blue: 0.975)   // #F7F7F9 grouped background
    static let ink = Color(red: 0.043, green: 0.043, blue: 0.047)    // #0B0B0C
    static let secondary = Color(red: 0.42, green: 0.44, blue: 0.47) // #6B7078
    static let tertiary = Color(red: 0.62, green: 0.64, blue: 0.67)  // #9FA3A8
    static let hairline = Color(red: 0.90, green: 0.905, blue: 0.915) // #E6E7EA

    static let accent = Color(red: 0.09, green: 0.36, blue: 0.84)    // #1666D6 clinical blue
    static let accentSoft = Color(red: 0.09, green: 0.36, blue: 0.84).opacity(0.08)

    // Flags only — used sparingly, never decoratively.
    static let positive = Color(red: 0.11, green: 0.49, blue: 0.33)  // #1C7C54
    static let warning = Color(red: 0.71, green: 0.41, blue: 0.055)  // #B4690E
    static let critical = Color(red: 0.78, green: 0.21, blue: 0.21)  // #C73636

    static func bandColor(_ band: SeverityBand) -> Color {
        switch band {
        case .mild: return positive
        case .moderate: return warning
        case .severe: return critical
        }
    }

    static func flagColor(_ flag: LabFlag) -> Color {
        switch flag {
        case .normal: return positive
        case .low, .high: return warning
        }
    }

    // MARK: Type — SF with tabular figures for all data.
    static func eyebrow(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold).monospaced()
    }
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

// MARK: - Reusable structure

/// A hairline-bordered card. No heavy shadow — structure comes from the rule, not depth.
struct ClinicalCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
    }
}

/// Small uppercase tracked label used as a section eyebrow.
struct Eyebrow: View {
    let text: String
    var color: Color = Clinical.tertiary
    var body: some View {
        Text(text.uppercased())
            .font(Clinical.eyebrow())
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// A screen title block: eyebrow + serifless bold headline.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Clinical.ink)
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// A labeled statistic with a big tabular number.
struct StatBlock: View {
    let value: String
    let label: String
    var accent: Color = Clinical.ink
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Clinical.number(28, weight: .semibold))
                .foregroundStyle(accent)
            Text(label.uppercased())
                .font(Clinical.eyebrow(10))
                .tracking(1.1)
                .foregroundStyle(Clinical.tertiary)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Clinical.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A flat segmented selector styled to match the clinical grid.
struct ClinicalSegmented<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Clinical.surface : Clinical.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isOn ? Clinical.ink : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Clinical.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
    }
}

/// Primary action styled as a solid ink bar — high contrast, no gradient.
struct ClinicalButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(filled ? Clinical.surface : Clinical.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(filled ? Clinical.ink : Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(filled ? Color.clear : Clinical.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A stepper rendered as discrete pips — used for the 0–3 / 1–5 self-report items.
struct PipStepper: View {
    let title: String
    var caption: String? = nil
    let range: ClosedRange<Int>
    @Binding var value: Int
    var tint: Color = Clinical.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                Spacer()
                if let caption {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(Clinical.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(range), id: \.self) { i in
                    let on = i <= value
                    Button {
                        value = i
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? tint : Clinical.canvas)
                            .frame(height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension View {
    /// Standard screen scaffold: canvas background + generous horizontal gutter.
    func clinicalScreen() -> some View {
        self
            .background(Clinical.canvas.ignoresSafeArea())
    }
}
