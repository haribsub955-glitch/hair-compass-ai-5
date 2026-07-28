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

    /// `canvas` lifted ~1% — the top stop of the page wash, where the light falls.
    static let canvasLight = Color(red: 0.992, green: 0.976, blue: 0.953)
    /// `canvas` settled ~1% toward copper — the bottom stop, where the page rests in shadow.
    static let canvasWarm = Color(red: 0.973, green: 0.949, blue: 0.914)
    /// The page's light source, as a wash. `ClinicalCard` already earns its depth from a vertical
    /// wash plus layered shadows; before this the canvas *behind* those cards was a single flat
    /// fill, so the cards floated on nothing. Same instinct, one layer down.
    static var canvasWash: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: canvasLight, location: 0),
                .init(color: canvas, location: 0.45),
                .init(color: canvasWarm, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Paper grain for the page surface — generated once at first use rather than shipped as an
    /// asset, so it costs zero download size and stays resolution-independent when tiled.
    ///
    /// The noise is warm espresso (the `shadowWarm` family, never grey) written straight into a
    /// premultiplied pixel buffer — ~16k pixels, about a millisecond, versus the tens of
    /// milliseconds per-pixel `CGContext` fills would cost on the first screen to render. Built at
    /// scale 3 so one noise pixel is a third of a point: fine tooth, not visible speckle.
    ///
    /// Alpha tops out around 12% before the view layer thins it further. The intent is that the
    /// canvas stops reading as a flat digital fill — not that anyone ever notices a texture.
    static let grainTile: UIImage = {
        let side = 128
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        // Espresso #5A4637-ish, matching the warm-shadow family rather than a neutral grey.
        let (r, g, b) = (90.0, 70.0, 55.0)
        for i in 0..<(side * side) {
            let alpha = Double(UInt8.random(in: 0...255)) / 8.0   // 0…31
            let scale = alpha / 255.0                              // premultiply
            pixels[i * 4 + 0] = UInt8(r * scale)
            pixels[i * 4 + 1] = UInt8(g * scale)
            pixels[i * 4 + 2] = UInt8(b * scale)
            pixels[i * 4 + 3] = UInt8(alpha)
        }
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let cgImage = CGImage(
                width: side, height: side,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
            )
        else { return UIImage() }
        return UIImage(cgImage: cgImage, scale: 3, orientation: .up)
    }()

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

    // Dynamic Type step 2: the general-purpose body/caption tokens the rest of the app's
    // ~480 `.font(.system(size:))` call sites were hand-migrated onto. Same byte-identical-at-
    // `.large` guarantee as the three tokens above — `UIFontMetrics.scaledValue(for:)` is a 1.0
    // multiplier at the default content size category, so no call site's layout changes unless
    // the user has actually turned their text size up or down. `body` mirrors the `.system(size:
    // weight:)` initializer's own default `weight: .regular`; `caption` intentionally carries no
    // weight parameter, matching the many call sites that never specified one and scales through
    // `.caption1` so small labels/badges grow more conservatively than paragraph text at large
    // accessibility sizes, echoing `eyebrow()`'s own use of `.caption2` above.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: size), weight: weight)
    }
    static func caption(_ size: CGFloat) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .caption1).scaledValue(for: size))
    }
}

/// Generated brand artwork — one consistent painterly gouache style across the app.
///
/// **Screen-art grammar.** Every constant here has exactly one job, and a screen may carry at most
/// one of each. This is what keeps "more depth" from decaying back into the clutter that rounds
/// 1–13 removed:
///
/// - **Header wash** — a plate bleeding full-width behind a `ScreenHeader`, dissolving into the
///   canvas via `BrandWash`. Sets the screen's mood; never competes with the data below it.
/// - **Focal plate** — one illustration that *teaches* something (`LivingArtwork`, empty-state
///   art). Usually transient: it retires once the user no longer needs the lesson.
/// - **Page closer** — a bottom-bleeding garland that ends the scroll (`meadow` on Today).
/// - **Edge accent** — `CornerSprig` / `StrandDivider`. Punctuation, not imagery; a divider is a
///   seam between sections and doesn't count against a screen's art budget.
///
/// Every constant below must be referenced by a view. `BrandArtCoverageTests` fails the build if
/// one is declared and never rendered — the whole catalog silently drifted out of the UI once
/// already, and the test is what stops that happening twice.
enum BrandArt {
    // `hero-today` was retired rather than wired. Today's hero is an edgeless `EllipticalGradient`
    // glow that Round 13 built specifically so the screen would not break into sections — a banner
    // or wash behind it would put back the very edge that change removed. Today gets its depth
    // from the `meadow` page-closer and a section seam instead.
    // `hero-photos-empty` was retired for a shape reason, not a taste one: it is a centered square
    // composition, so any header-band crop parks the mirror behind the region-picker chips and
    // dims their labels. Photos teaches capture through `photoCaptureV2` and gets its atmosphere
    // from a corner sprig instead.
    static let baselineHero = "hero-baseline"

    // Learn-library category art (generated in the same painterly gouache style).
    static let learnBasics = "learn-basics"
    static let learnConditions = "learn-conditions"
    static let learnTreatments = "learn-treatments"
    static let learnMyths = "learn-myths"
    static let learnDailyCare = "learn-dailycare"
    static let learnSupplements = "learn-supplements"

    // Section/screen banners (same gouache language).
    static let guidance = "art-guidance"    // Recommender "What helps" — banner
    static let analysis = "art-analysis"    // Deep analysis — banner
    static let trends = "art-trends"        // Trends — header wash (the plate is itself a trend line)

    // Design V2 — screen-specific narrative art. These stay data-adjacent: Plan explains the
    // routine, Labs frames context, Photos teaches repeatable capture. All three are focal
    // plates shown on first run and retired once the lesson has landed.
    static let planRitualV2 = "v2-plan-ritual"
    static let labsContextV2 = "v2-labs-context"
    static let photoCaptureV2 = "v2-photo-capture"

    // Launch-ritual art. `comb-tool` (a draggable comb that followed the finger) is gone with the
    // interaction it belonged to: `CombRitual` is now an automatic smoothing pass — "no combing
    // required" — so the tool had nothing left to be dragged across.
    static let ritualBackdrop = "comb-bg"

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

/// A first-run **focal plate**: living gouache art bleeding behind a left-anchored scrim, with the
/// lesson set over the legible side. Labs shipped the first one by hand; Plan and Photos now want
/// the same thing, so the construction lives here once instead of as three hand-tuned copies that
/// would drift apart.
///
/// The scrim is horizontal on purpose — these plates put their subject on the right and their
/// empty space on the left, so fading left-to-right lets the art stay fully saturated where it is
/// actually drawn and fully covered where the words go. No text ever sits on top of paint.
///
/// Every use is transient by contract: show it while the screen is empty, retire it once the user
/// has data. That is what keeps a teaching illustration from becoming permanent furniture.
struct TeachingPlate<Content: View>: View {
    let art: String
    var minHeight: CGFloat = 140
    var artOpacity: Double = 0.50
    /// Offsets this plate's drift so two on-screen plates never breathe in lockstep.
    var phase: Double = 0
    var textMaxWidth: CGFloat = 245

    @ViewBuilder var content: Content

    var body: some View {
        ClinicalCard(padding: 0) {
            ZStack {
                LivingArtwork(art: art, travel: 3.5, zoom: 0.012, phase: phase)
                    .frame(maxWidth: .infinity, minHeight: minHeight)
                    .clipped()
                    .opacity(artOpacity)
                LinearGradient(
                    stops: [
                        .init(color: Clinical.surface.opacity(0.99), location: 0),
                        .init(color: Clinical.surface.opacity(0.94), location: 0.58),
                        .init(color: Clinical.surface.opacity(0.42), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                VStack(alignment: .leading, spacing: 7) {
                    content
                }
                .frame(maxWidth: textMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }
}

/// The bottom bookend of a long scroll: a botanical garland growing out of the end of the page,
/// unboxed. Today has closed this way since the field-journal round; the app's other long scrolls
/// now end in the same voice rather than stopping dead on their last footnote.
///
/// The plate's transparent upper canvas *is* the breathing room above it, so callers should not add
/// their own top padding.
///
/// **Do not give this a negative horizontal padding to force a full bleed inside a gutter.** Unlike
/// `CornerSprig` or `BrandWash` — which attach as backgrounds and therefore take no layout space —
/// this is real content, so widening it past its parent widens the ScrollView's content and the
/// page starts drifting sideways under a finger. Today can bleed because its closer already sits
/// outside the padded stack; everywhere else it stays inside the gutter.
struct PageCloser: View {
    var art: String = BrandArt.meadow
    var opacity: Double = 1

    var body: some View {
        Image(art)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The app's page surface, behind every screen via `.clinicalScreen()`.
///
/// Two layers, each imperceptible alone: a vertical wash so the page has a light source, and a
/// tiled paper grain so it stops reading as a flat digital fill. Deliberately contains no imagery
/// — that is what makes it safe to apply to all five tabs at once. It adds depth that cannot
/// become clutter, which is the only kind every screen can take.
struct ClinicalCanvas: View {
    var body: some View {
        Clinical.canvasWash
            .overlay {
                Image(uiImage: Clinical.grainTile)
                    .resizable(resizingMode: .tile)
                    .opacity(0.55)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The unboxed counterpart to `BrandBanner`, and the screen-art grammar's "header wash".
///
/// A banner puts art *inside* a bordered, shadowed, corner-radiused rectangle. Rounds 1–13 spent
/// their effort dissolving exactly that kind of chrome, so this renders the same plates with no
/// border, no shadow and no corner radius: the art bleeds the full screen width and dissolves
/// into the canvas through a bottom gradient mask. It reads as painted-on paper rather than as a
/// picture in a frame.
///
/// It works because the gouache plates are painted on the same warm ivory as `Clinical.canvas`,
/// so once the bottom edge is masked away there is no visible boundary at all. Art is top-anchored
/// because these plates put their empty sky at the top and their saturated mass at the bottom —
/// cropping from the bottom keeps ink text in front legible without needing a scrim.
///
/// Attach as a `.background(alignment: .top)` so it takes no layout space, and give it
/// `.padding(.horizontal, -n)` to escape the parent's gutter — a background can't widen a
/// ScrollView's content, so the bleed is clipped harmlessly at the screen edge.
/// Purely decorative: never hit-tested, invisible to VoiceOver.
struct BrandWash: View {
    let art: String
    var height: CGFloat = 168
    var opacity: Double = 0.55
    /// Fraction of the height over which the plate dissolves into the canvas at the bottom.
    var fade: Double = 0.45

    var body: some View {
        Image(art)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .clipped()
            .opacity(opacity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: max(0, 1 - fade)),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
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

/// Expands compact visual controls to Apple's minimum interactive target without resizing their
/// artwork. Apply this to the actionable control rather than to a decorative glyph in its label.
private struct MinimumHitTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}

extension View {
    func minimumHitTarget() -> some View { modifier(MinimumHitTargetModifier()) }
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

/// The app's one completion "ink" gesture, shared by every routine row (Today's ledger and Plan's
/// ritual list): a copper underline draws in beneath a step's name on check, holds while the text
/// settles to its dimmed color, then fades for good. Attach to the name `Text` with
/// `.completionInkUnderline(trigger:)`; flip the bound `Bool` to `true` on a genuine check-off
/// (never on uncheck — the caller decides that) and the modifier resets it back to `false` once
/// the sequence finishes, so it's armed to fire again next time. Under Reduce Motion the trigger
/// is consumed instantly with no underline at all — completion still reads from the check circle
/// and the dimmed text alone.
private struct CompletionInkUnderline: ViewModifier {
    @Binding var trigger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: CGFloat = 0
    @State private var lineOpacity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                Capsule()
                    .fill(Clinical.accent.opacity(0.55))
                    .frame(height: 1.5)
                    .scaleEffect(x: draw, y: 1, anchor: .leading)
                    .opacity(lineOpacity)
                    .offset(y: 2)
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) { _, fired in
                guard fired else { return }
                guard !reduceMotion else {
                    trigger = false
                    return
                }
                withAnimation(.smooth(duration: 0.4)) {
                    draw = 1
                    lineOpacity = 1
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    withAnimation(.easeOut(duration: 0.45)) { lineOpacity = 0 }
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    draw = 0
                    trigger = false
                }
            }
    }
}

extension View {
    /// Fires the app's shared routine-completion underline flourish (see `CompletionInkUnderline`)
    /// whenever `trigger` flips to `true`.
    func completionInkUnderline(trigger: Binding<Bool>) -> some View {
        modifier(CompletionInkUnderline(trigger: trigger))
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
            // The underline used to live in its own `ZStack` row beneath the label — but an
            // unconstrained `Capsule` has infinite ideal width, so the HStack treated whichever
            // tab currently held it as the one "flexible" child and handed it all the row's
            // leftover space (the 3M underline spanning to 6M). Attaching it as a bottom overlay
            // on the label itself proposes the *label's* size to the Capsule, so its width is
            // always exactly the word's width, never the row's.
            label(option, isOn)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    if isOn {
                        Capsule()
                            .fill(Clinical.accent)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "inkTabsUnderline", in: namespace)
                    }
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

/// The app's one closing-sentence voice — the honest, non-decorative line that signs off a
/// ledger the way a book's colophon closes its last page: a hairline rule above, one plain
/// sentence, no icon, no small-caps, generous vertical breathing room. Promoted from Plan's
/// `gateExplainer` so the same element class (Labs' "context, not a diagnosis" line, Plan's
/// "density judged at 24 weeks" line) is unmistakably one hand's writing wherever it closes a
/// screen.
struct Colophon: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Clinical.hairline)
            Text(text)
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 13)
        }
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

/// A consistent 44pt header action — a bare copper glyph, no disc behind it. Every card in the
/// app dissolved its chrome rounds ago; this is the one-header-action-voice that keeps the
/// screen's top-right corner on canvas instead of wearing the last white coin in the app. The
/// glyph sits inside the full 44pt tappable frame so it still meets the platform's comfortable
/// touch-target guidance, and carries an explicit spoken label for VoiceOver.
struct HeaderActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Clinical.body(20, weight: .semibold))
                .foregroundStyle(Clinical.accent)
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
                    .font(Clinical.caption(11))
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
                        .font(Clinical.body(13, weight: isOn ? .semibold : .regular))
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
            .font(Clinical.body(16, weight: .semibold))
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
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)
                Spacer()
                if let caption {
                    Text(caption)
                        .font(Clinical.caption(12))
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
                    .minimumHitTarget()
                }
            }
        }
    }
}

/// A destination row with a tinted medallion, a serif title and a plain second line — the shape
/// the sibling skin app uses for "Explore products by goal" / "Explore in-clinic procedures".
///
/// It exists because the app kept re-declaring the same row inline as a 15pt SF Symbol beside two
/// `Text`s, which reads as a settings list rather than as this brand. The medallion (accent symbol
/// on `accentSoft` in a circle) plus a serif title is what makes a navigation row look like it
/// belongs to the same hand as the gouache artwork.
struct BrandNavRow: View {
    let symbol: String
    let title: String
    let line: String
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(Clinical.body(17, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                    .frame(width: 44, height: 44)
                    .background(Clinical.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Clinical.headline(17))
                        .foregroundStyle(Clinical.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line)
                        .font(Clinical.caption(13))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // At accessibility sizes the chevron is pure decoration competing for width the
                // two lines need, and VoiceOver already announces the button.
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(Clinical.body(14, weight: .semibold))
                        .foregroundStyle(Clinical.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Clinical.surfaceWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
            .shadow(color: Clinical.cardShadow, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The bordered "read this first" card — an `i` medallion beside a short paragraph, used where a
/// screen has to set expectations before the content starts (education-only framing, scope limits,
/// "discuss with your clinician"). The sibling skin app opens its procedures screen with exactly
/// this, and it reads as deliberate authorship in a way a loose grey paragraph never does.
///
/// Distinct from `Colophon`, which *closes* a screen with one quiet sentence. This one opens it.
struct InfoCallout: View {
    let text: String
    var symbol: String = "info.circle.fill"
    var tint: Color = Clinical.accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(Clinical.body(15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())

            Text(text)
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
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
                Text(text).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
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
            .background(ClinicalCanvas().ignoresSafeArea())
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
