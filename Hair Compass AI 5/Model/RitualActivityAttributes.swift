import ActivityKit
import Foundation

// KEEP IN SYNC — RitualActivityAttributes is duplicated verbatim (same type name, same fields,
// same Codable encoding) in:
//   Model/RitualActivityAttributes.swift                          (app target, this file)
//   Hair Compass CheckIn Widget/RitualActivityAttributes.swift    (widget extension target)
// ActivityKit matches an Activity to its widget-side ActivityConfiguration purely by type name +
// Codable encoding across the two processes — there is no shared framework to import from, so a
// drift between the two copies (a renamed/reordered/retyped field) breaks the Live Activity
// silently at runtime instead of at compile time. Mirrors the WidgetSnapshot duplication pattern
// in Service/WidgetBridge.swift and Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift —
// change both copies together.
//
/// Drives the Ritual Live Activity (Dynamic Island + Lock Screen) shown while a launch ritual
/// (Feature/Ritual/RitualView.swift) is on screen. Launch rituals are short, full-screen mini
/// games (Feature/Ritual/{Comb,Knot,Massage,Serum}Ritual.swift) — today each is a single
/// continuous phase, not a multi-page sequence, so `stepIndex`/`totalSteps` are fixed at 1/1;
/// they exist so a future multi-phase ritual doesn't need an ActivityAttributes migration.
struct RitualActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Human-readable phase label — the ritual's title ("Smooth", "Loosen the knot",
        /// "Breathe", "One drop at a time") while running, "Complete" once it finishes.
        var stepName: String
        /// 1-based index into the ritual's steps (see type doc — always 1 today).
        var stepIndex: Int
        var totalSteps: Int
        /// 0...1 completion fraction. Time-driven for the auto-advancing rituals (comb/massage);
        /// interaction-driven (relaxed knot points / filled serum level) for knot/serum.
        var progress: Double
        /// Wall-clock date this phase is projected to auto-complete, set only for the
        /// fixed-duration rituals (comb/massage) so the widget can render a system countdown via
        /// `Text(timerInterval:)`. Nil for interaction-paced rituals (knot/serum), which have no
        /// fixed end time and show `progress` as a plain bar instead.
        var endDate: Date?
    }

    /// Display name shown in the Live Activity — the ritual's title (e.g. "Smooth").
    var ritualName: String
    /// `RitualKind.rawValue` ("comb"/"knot"/"massage"/"serum"), kept as a plain String so the
    /// widget extension doesn't need the app target's `RitualKind` enum.
    var ritualKind: String
    var startDate: Date
}
