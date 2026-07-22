import SwiftUI

/// A row of seven tappable weekday circles bound to a `Treatment.scheduledWeekdays`-shaped set
/// (Calendar weekday numbers 1=Sun…7=Sat). Shared by `AddTreatmentSheet` (creation) and
/// `TreatmentDetailSheet` (post-creation editing) so a periodic item's cadence — weekly
/// microneedling, an LLLT cap used a few times a week, a shampoo used Mon/Thu — can be set once
/// and corrected later without wiping it. An empty selection means "every day"; `Treatment
/// .isDueToday()` reads it the same way on both sides.
struct WeekdaySchedulePicker: View {
    @Binding var selection: Set<Int>

    /// Sun→Sat, single-letter labels, Calendar weekday numbers.
    private static let options: [(num: Int, label: String)] =
        [(1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.options, id: \.num) { day in
                let on = selection.contains(day.num)
                Button {
                    if on { selection.remove(day.num) } else { selection.insert(day.num) }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(day.label)
                        .font(Clinical.body(14, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                        .frame(width: 40, height: 40)
                        .background(on ? Clinical.accent : Clinical.surface, in: Circle())
                        .overlay(Circle().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel(Self.fullWeekdayName(day.num))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private static func fullWeekdayName(_ weekdayNumber: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols // index 0 = Sunday, matching weekday number 1.
        let index = weekdayNumber - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}
