import SwiftUI

/// Warm & premium design system — ivory surfaces, a signature copper accent, sage and
/// antique-gold supporting tones, serif headlines, soft tactile depth. Built around the
/// generated compass/botanical/hair artwork in Assets.xcassets (see BrandArt).
enum Clinical {

    // MARK: Palette
    static let canvas = Color(red: 0.984, green: 0.965, blue: 0.937)   // #FBF6EF warm ivory
    static let surface = Color(red: 0.996, green: 0.988, blue: 0.976)  // #FEFCF9 warm card white
    static let ink = Color(red: 0.169, green: 0.129, blue: 0.102)      // #2B211A espresso
    static let secondary = Color(red: 0.478, green: 0.420, blue: 0.365) // #7A6B5D warm taupe
    static let tertiary = Color(red: 0.651, green: 0.588, blue: 0.529)  // #A69687 muted warm gray
    static let hairline = Color(red: 0.929, green: 0.882, blue: 0.827)  // #EDE1D3 soft warm tan

    static let accent = Color(red: 0.694, green: 0.349, blue: 0.180)    // #B1592E copper/terracotta
    static let accentSoft = Color(red: 0.694, green: 0.349, blue: 0.180).opacity(0.10)
    static let gold = Color(red: 0.788, green: 0.631, blue: 0.353)      // #C9A15A antique gold
    static let sage = Color(red: 0.541, green: 0.616, blue: 0.482)      // #8A9D7B

    // Flags only — used sparingly, never decoratively.
    static let positive = Color(red: 0.361, green: 0.478, blue: 0.322)  // #5C7A52 warm sage
    static let warning = Color(red: 0.725, green: 0.545, blue: 0.180)   // #B98B2E ochre
    static let critical = Color(red: 0.651, green: 0.263, blue: 0.180)  // #A6432E brick

    static let cardShadow = Color(red: 0.353, green: 0.220, blue: 0.106).opacity(0.10) // warm espresso shadow

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

    /// Confidence, not good/bad — how much weight to give a signal. Strong reads authoritative,
    /// weaker tiers recede into the muted palette so nothing overclaims.
    static func tierColor(_ tier: EvidenceTier) -> Color {
        switch tier {
        case .strong: return ink
        case .moderate: return gold
        case .weak: return tertiary
        case .context: return tertiary
        }
    }

    /// Product evidence — the same honest recede: real trials read confident, lab-stage recedes.
    static func productColor(_ evidence: ProductEvidence) -> Color {
        switch evidence {
        case .moderate: return positive
        case .limited: return gold
        case .early: return tertiary
        case .conditional: return accent
        }
    }

    // MARK: Type — serif headlines for warmth, SF body/data with tabular figures.
    static func eyebrow(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold).monospaced()
    }
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    static func headline(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// Generated brand artwork — one consistent painterly gouache style across the app.
enum BrandArt {
    static let todayHero = "hero-today"
    static let baselineHero = "hero-baseline"
    static let photosEmpty = "hero-photos-empty"

    // Learn-library category art (generated in the same painterly gouache style).
    static let learnBasics = "learn-basics"
    static let learnConditions = "learn-conditions"
    static let learnTreatments = "learn-treatments"
    static let learnMyths = "learn-myths"
    static let learnDailyCare = "learn-dailycare"
    static let learnSupplements = "learn-supplements"

    // Section/screen banners (same gouache language).
    static let guidance = "art-guidance"    // Recommender "What helps"
    static let analysis = "art-analysis"    // Deep analysis
    static let trends = "art-trends"        // Trends header

    // Launch-ritual art (botanical backdrop + the comb that follows the finger).
    static let ritualBackdrop = "comb-bg"
    static let combTool = "comb-tool"
}

/// A rounded brand-art banner in the warm gouache style — reused across screens so imagery reads as
/// one system (Today/Baseline heroes, and now Trends/Recommender/Deep-analysis/Science).
struct BrandBanner: View {
    let art: String
    var height: CGFloat = 120
    var body: some View {
        Image(art)
            .resizable().aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity).frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .shadow(color: Clinical.cardShadow, radius: 12, y: 5)
    }
}

// MARK: - Reusable structure

/// A warm card with soft tactile depth. Depth comes from a diffuse warm shadow, not a shadow-free
/// hairline — this is the opposite instinct from a clinical instrument, on purpose.
struct ClinicalCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
            .shadow(color: Clinical.cardShadow, radius: 14, y: 6)
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

/// A screen title block: eyebrow + warm serif headline.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(Clinical.headline(30))
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

/// A warm segmented selector — the active pill uses the signature copper accent.
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
                        .background(isOn ? Clinical.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Clinical.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
    }
}

/// Primary action styled as a solid copper bar with a warm glow.
struct ClinicalButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(filled ? Clinical.surface : Clinical.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(filled ? Clinical.accent : Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(filled ? Color.clear : Clinical.hairline, lineWidth: 1)
            )
            .shadow(color: filled ? Clinical.accent.opacity(0.28) : .clear, radius: 12, y: 5)
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
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? tint : Clinical.canvas)
                            .frame(height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A small pill stating how strong the evidence for a signal is — the app's honesty made visible.
struct TierBadge: View {
    let tier: EvidenceTier
    var body: some View {
        Text(tier.short.uppercased())
            .font(Clinical.eyebrow(9)).tracking(0.8)
            .foregroundStyle(Clinical.tierColor(tier))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Clinical.tierColor(tier).opacity(0.12), in: Capsule())
    }
}

/// A small pill stating a product's honest evidence tier — never dressed up as a treatment.
struct ProductBadge: View {
    let evidence: ProductEvidence
    var body: some View {
        Text(evidence.short.uppercased())
            .font(Clinical.eyebrow(9)).tracking(0.8)
            .foregroundStyle(Clinical.productColor(evidence))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Clinical.productColor(evidence).opacity(0.12), in: Capsule())
    }
}

/// A "Why this matters" affordance that expands to the plain-language rationale — progressive
/// disclosure so a logging screen stays calm but the evidence is a tap away.
struct WhyDisclosure: View {
    let text: String
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                Label(expanded ? "Hide" : "Why this matters", systemImage: expanded ? "chevron.up" : "info.circle")
                    .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(text).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
            }
        }
    }
}

/// A section header driven by the tracked-variable catalog: title + evidence tier + capture badge
/// + a why-this-matters disclosure, all from one source of truth.
struct VariableSectionHeader: View {
    let variableID: String
    var body: some View {
        if let v = TrackedVariable[variableID] {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Eyebrow(text: v.title)
                    TierBadge(tier: v.tier)
                    if v.capture == .auto {
                        Label(v.capture.badge, systemImage: v.capture.symbol)
                            .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                WhyDisclosure(text: v.why)
            }
        } else {
            Eyebrow(text: variableID)
        }
    }
}

extension View {
    /// Standard screen scaffold: warm ivory canvas.
    func clinicalScreen() -> some View {
        self
            .background(Clinical.canvas.ignoresSafeArea())
    }
}
