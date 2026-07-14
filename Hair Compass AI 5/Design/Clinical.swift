import SwiftUI
import UIKit

/// Warm & premium design system — ivory surfaces, a signature copper accent, sage and
/// antique-gold supporting tones, serif headlines, soft tactile depth. Built around the
/// generated compass/botanical/hair artwork in Assets.xcassets (see BrandArt).
enum Clinical {

    // MARK: Palette
    static let canvas = Color(red: 0.984, green: 0.965, blue: 0.937)   // #FBF6EF warm ivory
    static let surface = Color(red: 0.996, green: 0.988, blue: 0.976)  // #FEFCF9 warm card white
    static let ink = Color(red: 0.169, green: 0.129, blue: 0.102)      // #2B211A espresso
    static let secondary = Color(red: 0.478, green: 0.420, blue: 0.365) // #7A6B5D warm taupe
    // #7C6D5F — darkened from #A69687 for legibility (UX audit #1). WCAG relative-luminance
    // contrast against canvas #FBF6EF, computed with python3: 4.639:1 (was 2.663:1), clearing
    // the 4.5:1 body-text threshold. Hue held at ~29° (warm umber), only lightness/saturation
    // moved (L 0.59→0.43, S 0.148→0.132) — same family, still reads as decorative/muted.
    static let tertiary = Color(red: 0.486, green: 0.427, blue: 0.373)  // #7C6D5F muted warm umber
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

    // MARK: Depth — layered warm shadows and paper washes (never grey/black).
    /// Base warm espresso-brown for layered shadows — always pass through `.opacity(...)` per layer.
    static let shadowWarm = Color(red: 0.353, green: 0.220, blue: 0.106)
    /// `surface` nudged ~3% toward copper — the bottom stop of the card wash.
    static let surfaceWarm = Color(red: 0.987, green: 0.969, blue: 0.952)
    /// Warm paper-white for top-edge inner catchlights (the paper-lift highlight).
    static let paperLight = Color(red: 1.0, green: 0.992, blue: 0.972)
    /// Barely-there vertical wash: card white settling into a copper-warmed bottom edge.
    static var surfaceWash: LinearGradient {
        LinearGradient(colors: [surface, surfaceWarm], startPoint: .top, endPoint: .bottom)
    }

    /// Maps a scroll content offset to a 0…1 header-condense fraction for `ScreenHeader`'s
    /// title — the serif title shrinks toward its eyebrow as the first ~64pt of content scrolls
    /// under it, then holds condensed for the rest of the scroll.
    static func headerCondenseFraction(_ offsetY: CGFloat, threshold: CGFloat = 64) -> CGFloat {
        max(0, min(1, offsetY / threshold))
    }

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
    //
    // Dynamic Type step 1: sizes route through `UIFontMetrics(forTextStyle:).scaledValue(for:)`
    // so the system text-size setting finally affects the app, while every existing call site's
    // output is byte-identical at the default (.large) content size category — at that category
    // UIFontMetrics' scale factor is exactly 1.0, so `scaledValue(for: s) == s`. Signatures,
    // weights and designs are unchanged.
    static func eyebrow(_ size: CGFloat = 11) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .caption2).scaledValue(for: size), weight: .semibold).monospaced()
    }
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: size), weight: weight).monospacedDigit()
    }
    static func headline(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .title2).scaledValue(for: size), weight: weight, design: .serif)
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

    // Design V2 — screen-specific narrative art. These stay data-adjacent: Plan explains the
    // routine, Labs frames context, Photos teaches repeatable capture.
    static let planRitualV2 = "v2-plan-ritual"
    static let labsContextV2 = "v2-labs-context"
    static let photoCaptureV2 = "v2-photo-capture"

    // Launch-ritual art (botanical backdrop + the comb that follows the finger).
    static let ritualBackdrop = "comb-bg"
    static let combTool = "comb-tool"

    // Transparent overlay accents — unboxed art that bleeds from screen edges instead of
    // sitting in banner boxes (rendered by CornerSprig / StrandDivider below).
    static let sprig = "brand-sprig"        // botanical cluster, cascades from a top corner
    static let divider = "brand-divider"    // horizontal copper hair-strand flourish
    static let meadow = "brand-meadow"      // wide botanical garland, art anchored to the bottom
    static let medallion = "brand-medallion" // laurel wreath with a copper strand — milestone emblem

    // Medication emblems (transparent gouache) — the Rx confirmation card's centered art.
    static let remedy = "brand-remedy"      // amber pill bottle + tablets (oral)
    static let dropper = "brand-dropper"    // amber dropper bottle (topical liquids)
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

/// Design V2's low-cost living-art treatment. A project illustration receives a few points of
/// slow drift and a 1–2% breath—enough to feel tactile, never enough to distract from data. The
/// shared scheduler caps this at 15 fps and pauses it off-screen/inactive/under Reduce Motion.
struct LivingArtwork: View {
    let art: String
    var contentMode: ContentMode = .fill
    var travel: CGFloat = 5
    var zoom: CGFloat = 0.018
    var phase: Double = 0

    var body: some View {
        MotionTimeline(cadence: .decorative) { timeline, reduceMotion in
            let t = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3600)
            let wave = sin(t * 0.28 + phase)
            let crossWave = cos(t * 0.22 + phase)

            Image(art)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .scaleEffect(reduceMotion ? 1 : 1 + zoom * (0.55 + 0.45 * wave))
                .offset(
                    x: reduceMotion ? 0 : CGFloat(crossWave) * travel,
                    y: reduceMotion ? 0 : CGFloat(wave) * travel * 0.45
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An unboxed botanical accent that bleeds off a screen corner — the brand living in the
/// interface itself rather than inside a banner rectangle. Attach it with
/// `.background(alignment: .topTrailing) { CornerSprig() }` on a header block: background
/// views take no layout space, so the off-screen bleed can never widen a ScrollView's
/// content — the scroll view simply clips it at the screen edge. Purely decorative:
/// never intercepts touches, invisible to accessibility, kept translucent so ink text
/// in front stays fully legible. One sprig per screen, no more.
struct CornerSprig: View {
    enum Corner { case topTrailing, topLeading }
    var corner: Corner = .topTrailing
    var width: CGFloat = 210
    var opacity: Double = 0.5

    var body: some View {
        let mirrored = corner == .topLeading
        Image(BrandArt.sprig)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width)
            .scaleEffect(x: mirrored ? -1 : 1)
            .opacity(opacity)
            // Nudge down and away from the corner — every header that carries a sprig also
            // carries a 44pt HeaderActionButton at this exact corner, so the artwork's mass
            // stays clear of the button rather than bleeding straight into it.
            .offset(x: (mirrored ? -1 : 1) * width * 0.05, y: width * 0.04)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A flowing copper hair-strand flourish used between sections instead of a plain `Divider()`.
/// The painted wave occupies the middle ~half of its canvas, so the image renders at twice the
/// slot height inside a fixed-size overlay: the wave fills the slot while the transparent canvas
/// margins overflow harmlessly — overlays take no layout space, so neighbors are unaffected.
struct StrandDivider: View {
    var height: CGFloat = 54
    var opacity: Double = 0.6

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                Image(BrandArt.divider)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height * 2)
                    .opacity(opacity)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Reusable structure

/// A warm card with soft tactile depth. Depth comes from three layered cues, not one flat drop:
/// a barely-there vertical wash (surface warming toward copper at the bottom), a dual warm shadow
/// (tight contact + soft ambient), and a 0.5pt warm-white catchlight along the top inner edge —
/// paper lifted off the ivory canvas. This is the opposite instinct from a clinical instrument,
/// on purpose.
struct ClinicalCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Clinical.surfaceWash)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
            .overlay(
                // Top-edge catchlight: a 0.5pt warm-white inner hairline that fades out by a
                // quarter of the way down — the subtle paper-lift cue.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Clinical.paperLight.opacity(0.9), location: 0),
                                .init(color: Clinical.paperLight.opacity(0), location: 0.25),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Clinical.shadowWarm.opacity(0.10), radius: 2, y: 1)   // contact
            .shadow(color: Clinical.shadowWarm.opacity(0.07), radius: 16, y: 6)  // ambient
    }
}

/// Press treatment for tappable cards: a soft dip to 0.98 scale with a quick spring while
/// pressed. Under Reduce Motion the scale is dropped and the press reads as a gentle dim
/// instead. Opt-in only — apply `.buttonStyle(.clinicalPressable)` at call sites.
struct ClinicalPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
            .opacity(reduceMotion && configuration.isPressed ? 0.85 : 1)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == ClinicalPressableStyle {
    static var clinicalPressable: ClinicalPressableStyle { .init() }
}

// MARK: - Motion scheduling

/// Shared frame budgets for procedural Canvas animation. Interactive simulations stay fluid at
/// 60 fps, while ambient card motifs use 30 fps—their movement is intentionally slow and gains no
/// visible fidelity from ProMotion's 120 updates per second.
enum MotionCadence {
    case interactive
    case ambient
    case decorative

    var minimumInterval: Double {
        switch self {
        case .interactive: return 1.0 / 60.0
        case .ambient: return 1.0 / 30.0
        case .decorative: return 1.0 / 15.0
        }
    }
}

/// Lifecycle-aware replacement for a raw `TimelineView(.animation)`. It prevents procedural
/// Canvas views from consuming frames when clipped out of a scroll view, while the app is not
/// active, or when Reduce Motion requests a static representative frame.
struct MotionTimeline<Content: View>: View {
    let cadence: MotionCadence
    let explicitlyPaused: Bool
    private let content: (TimelineViewDefaultContext, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = true

    init(
        cadence: MotionCadence,
        paused: Bool = false,
        @ViewBuilder content: @escaping (TimelineViewDefaultContext, Bool) -> Content
    ) {
        self.cadence = cadence
        self.explicitlyPaused = paused
        self.content = content
    }

    private var isPaused: Bool {
        explicitlyPaused || reduceMotion || scenePhase != .active || !isVisible
    }

    var body: some View {
        TimelineView(
            .animation(minimumInterval: cadence.minimumInterval, paused: isPaused)
        ) { timeline in
            content(timeline, reduceMotion)
        }
        .onAppear { isVisible = true }
        .onScrollVisibilityChange(threshold: 0.02) { isVisible = $0 }
    }
}

/// One-shot entrance: fade from 0 and rise ~10pt, staggered by `index` (50ms per step by
/// default), with a soft spring settle. Runs once per appearance (guarded by @State — a revisit
/// of a live view never re-triggers). Under Reduce Motion it becomes a plain fade. Cheap by
/// design: no TimelineView, no repeating animation.
private struct StaggeredEntrance: ViewModifier {
    let index: Int
    var step: Double = 0.05
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                let delay = Double(index) * step
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.28).delay(delay)) { shown = true }
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    /// Staggered card entrance — pass the card's position in its stack (0, 1, 2, …). `step`
    /// (seconds between items) defaults to 50ms; a tighter ledger of quiet rows (e.g. Today's
    /// signal ledger) can pass a smaller step so a longer list still settles quickly.
    func staggeredEntrance(index: Int, step: Double = 0.05) -> some View {
        modifier(StaggeredEntrance(index: index, step: step))
    }
}

/// A quiet text-tab selector: plain labels with a sliding copper underline driven by
/// `matchedGeometryEffect` — the shared selector language that replaces bordered segmented
/// capsules and boxed filter pills (Trends' range picker, Photos' region picker). Crossfades
/// instead of sliding under Reduce Motion (the underline's `matchedGeometryEffect` move is itself
/// gated by the spring/easeInOut choice below, not a separate transition, so there's nothing
/// further to disable).
struct InkTabs<T: Hashable, TabLabel: View>: View {
    let options: [T]
    @Binding var selection: T
    var namespace: Namespace.ID
    var spacing: CGFloat = 20
    var accessibilityLabel: (T) -> String
    var accessibilityHint: (T) -> String = { _ in "" }
    @ViewBuilder var label: (T, Bool) -> TabLabel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(options, id: \.self) { option in
                tab(option)
            }
        }
    }

    private func tab(_ option: T) -> some View {
        let isOn = option == selection
        return Button {
            guard option != selection else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(tabAnimation) {
                selection = option
            }
        } label: {
            VStack(spacing: 6) {
                label(option, isOn)
                ZStack {
                    if isOn {
                        Capsule()
                            .fill(Clinical.accent)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "inkTabsUnderline", in: namespace)
                    }
                }
                .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        // Trends hosts this picker inside a `.transaction { $0.animation = nil }` subtree (it
        // keeps Swift Charts' marks from interpolating on range changes — see TrendsView) which
        // would otherwise silently cancel the `withAnimation` above. Re-asserting the animation
        // here, closer to the leaf, wins back the underline's slide for this view specifically
        // without touching that ancestor's chart-stabilizing transaction.
        .transaction { $0.animation = tabAnimation }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(option))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(accessibilityHint(option))
    }

    private var tabAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.82)
    }
}

/// Small uppercase tracked label used as a section eyebrow.
struct Eyebrow: View {
    let text: String
    // Default darkened from `tertiary` to `secondary` (UX audit #1) — eyebrows are read as
    // text, not decoration, and `secondary` measures 4.78:1 on canvas #FBF6EF vs `tertiary`'s
    // pre-fix 2.66:1. Call sites that intentionally want the fainter tone still pass `tertiary`.
    var color: Color = Clinical.secondary
    var body: some View {
        Text(text.uppercased())
            .font(Clinical.eyebrow())
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// A screen title block: eyebrow + warm serif headline. The title condenses as content scrolls
/// beneath it — pass `condensed` (0 = fully expanded, 1 = fully condensed) driven by the hosting
/// screen's own `.onScrollGeometryChange` (see `Clinical.headerCondenseFraction`). Direct,
/// 1:1-with-the-finger scroll coupling like this mirrors a native large-title collapse, which
/// isn't gated by Reduce Motion (it's the user's own gesture moving it, not an autonomous
/// animation) — so `condensed` applies unconditionally.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    var trailing: AnyView? = nil
    var condensed: CGFloat = 0

    private var titleSize: CGFloat { 30 - 9 * condensed }
    private var titleOpacity: Double { 1 - 0.25 * Double(condensed) }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow)
                Text(title)
                    .font(Clinical.headline(titleSize))
                    .foregroundStyle(Clinical.ink)
                    .opacity(titleOpacity)
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// A consistent 44pt header action. The visible circle remains compact, while the full control
/// meets the platform's comfortable touch-target guidance and carries an explicit spoken label.
struct HeaderActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if prominent {
                    Circle()
                        .fill(Clinical.ink)
                        .frame(width: 40, height: 40)
                }
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(prominent ? Clinical.surface : Clinical.ink)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel(accessibilityLabel)
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
        Text("EVIDENCE · \(tier.short.uppercased())")
            .font(Clinical.eyebrow(8)).tracking(0.65)
            .foregroundStyle(Clinical.tierColor(tier))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Clinical.tierColor(tier).opacity(0.12), in: Capsule())
            .accessibilityLabel("Evidence strength: \(tier.short)")
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

/// A section header driven by the tracked-variable catalog. Status and evidence intentionally live
/// on separate rows so an evidence label can never be mistaken for the user's selected severity.
/// `trailing` is an optional live readout (e.g. the scalp composite in the log sheet).
struct VariableSectionHeader: View {
    let variableID: String
    var trailing: AnyView? = nil
    var body: some View {
        if let v = TrackedVariable[variableID] {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Eyebrow(text: v.title)
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                }
                HStack(spacing: 8) {
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

    /// Fades the trailing edge of a horizontally scrolling row (chip rows, region pickers) to
    /// clear over `width` points — a soft cue that there's more to scroll to, instead of a hard
    /// cut-off at the container edge. Apply as the last modifier on the `ScrollView` itself so
    /// the fade stays pinned to the viewport regardless of scroll offset.
    func trailingFade(width: CGFloat = 24) -> some View {
        mask(
            HStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: width)
            }
        )
    }
}
