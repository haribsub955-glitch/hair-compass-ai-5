import SwiftUI

/// The four launch rituals — all now implemented: `comb`, `knot`, `massage`, `serum`.
enum RitualKind: String, CaseIterable, Identifiable {
    case comb, massage, serum, knot

    var id: String { rawValue }

    /// The kinds the coordinator is allowed to roll.
    static let implemented: [RitualKind] = [.comb, .knot, .massage, .serum]
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
    /// Factory used by `RitualView` — maps each kind to its concrete ritual.
    /// (Lives on `RitualKind`, not the `Ritual` protocol, because `Ritual` has `Self` requirements.)
    static func make(_ kind: RitualKind) -> any Ritual {
        switch kind {
        case .comb: return CombRitual()
        case .knot: return KnotRitual()
        case .massage: return MassageRitual()
        case .serum: return SerumRitual()
        }
    }
}
