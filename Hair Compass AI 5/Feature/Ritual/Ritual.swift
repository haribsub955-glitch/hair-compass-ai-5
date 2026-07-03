import SwiftUI

/// The four launch rituals. Two are implemented today (`comb`, `knot`); `massage` and `serum`
/// land in a follow-up. The coordinator only ever rolls among `implemented`, but the factory
/// still returns a safe, instantly-completable placeholder for the others so nothing can crash.
enum RitualKind: String, CaseIterable, Identifiable {
    case comb, massage, serum, knot

    var id: String { rawValue }

    /// The kinds the coordinator is allowed to roll right now.
    static let implemented: [RitualKind] = [.comb, .knot]
}

/// A single touch event forwarded from `RitualView`'s drag gesture into the active ritual.
/// `previous` carries the prior location so rituals can compute drag speed (pt/frame or pt/sec).
struct RitualTouch {
    enum Phase { case began, moved, ended }
    var location: CGPoint
    var previous: CGPoint
    var phase: Phase

    /// Convenience distance from the previous sample — useful for speed-gated beats (massage).
    var travel: CGFloat {
        let dx = location.x - previous.x, dy = location.y - previous.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A ritual is a tiny procedural mini-game rendered with `Canvas`. It owns its own particle/point
/// state, advances one physics step per frame (`step`), draws itself (`draw`), and reports when it
/// is finished (`isComplete`). It is a value type held in a reference box inside `RitualView` so the
/// per-frame mutation doesn't thrash SwiftUI state (mirrors `HairSimBox` in HairPhysics.swift).
protocol Ritual {
    var kind: RitualKind { get }
    var title: String { get }
    var hint: String { get }
    var isComplete: Bool { get }

    /// Feed a touch (began/moved/ended) into the simulation.
    mutating func handle(_ touch: RitualTouch)

    /// Advance the simulation by `dt` seconds within the current canvas `size`.
    /// Returns a light "satisfying beat" event count for haptics (e.g. a lock/coil just fully
    /// smoothed this frame) — `RitualView` fires a light impact when this is > 0.
    @discardableResult
    mutating func step(dt: CGFloat, size: CGSize) -> Int

    /// Draw the current frame. `ctx` is inout so rituals can add filters/layers freely.
    func draw(in ctx: inout GraphicsContext, size: CGSize)
}

extension RitualKind {
    /// Factory used by `RitualView`. Implemented kinds return their real ritual; not-yet-built kinds
    /// return an instantly-completable placeholder so a stale roll can never crash the app.
    /// (Lives on `RitualKind`, not the `Ritual` protocol, because `Ritual` has `Self` requirements.)
    static func make(_ kind: RitualKind) -> any Ritual {
        switch kind {
        case .comb: return CombRitual()
        case .knot: return KnotRitual()
        case .massage, .serum: return PlaceholderRitual(kind: kind)
        }
    }
}

/// Safe stand-in for the not-yet-implemented rituals. Renders nothing and is complete the moment
/// it is touched, so the finish/reveal sequence still runs and the user reaches the app. The
/// coordinator never rolls these; this only guards against a persisted/forced stale kind.
struct PlaceholderRitual: Ritual {
    let kind: RitualKind
    private var touched = false

    init(kind: RitualKind) { self.kind = kind }

    var title: String {
        switch kind {
        case .massage: return "Massage in circles"
        case .serum: return "One drop at a time"
        default: return "Take a breath"
        }
    }
    var hint: String { "Tap anywhere to continue." }
    var isComplete: Bool { touched }

    mutating func handle(_ touch: RitualTouch) {
        if touch.phase == .ended || touch.phase == .began { touched = true }
    }
    mutating func step(dt: CGFloat, size: CGSize) -> Int { 0 }
    func draw(in ctx: inout GraphicsContext, size: CGSize) {}
}
