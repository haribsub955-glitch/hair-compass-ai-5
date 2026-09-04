import Foundation

/// The section whose leading edge most recently passed beneath the pinned navigator.
/// Gaps between sections belong to the previous section; overscroll remains on Today.
enum PlanSectionSelection {
    static func active(orderedIDs: [String], positions: [String: CGFloat], readingLine: CGFloat) -> String? {
        orderedIDs.last { id in positions[id].map { $0 <= readingLine } ?? false } ?? orderedIDs.first
    }
}
