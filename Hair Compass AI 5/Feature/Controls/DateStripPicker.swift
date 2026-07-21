import SwiftUI

/// A tactile horizontal date-timeline strip that replaces the system date picker in the
/// add-treatment and add-lab sheets: a calm, scannable row of day cells the user scrubs
/// (native horizontal scroll) or taps through, with the selected day in copper and small
/// month markers wherever the month changes.
struct DateStripPicker: View {
    @Binding var selection: Date
    var range: ClosedRange<Date>? = nil

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            strip
        }
    }

    // MARK: Day range

    /// Bounds normalized to start-of-day. Default: 540 days back (old lab dates) through
    /// 30 days ahead (near-future treatment starts).
    private var dayBounds: ClosedRange<Date> {
        let today = calendar.startOfDay(for: .now)
        guard let range else {
            let lower = calendar.date(byAdding: .day, value: -540, to: today) ?? today
            let upper = calendar.date(byAdding: .day, value: 30, to: today) ?? today
            return lower...max(lower, upper)
        }
        let lower = calendar.startOfDay(for: range.lowerBound)
        let upper = calendar.startOfDay(for: range.upperBound)
        return lower...max(lower, upper)
    }

    /// One start-of-day `Date` per day in the bounds, built explicitly via the calendar.
    private var days: [Date] {
        var result: [Date] = []
        var cursor = dayBounds.lowerBound
        let end = dayBounds.upperBound
        while cursor <= end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private var selectedDay: Date { calendar.startOfDay(for: selection) }

    private var relativeNote: String {
        let today = calendar.startOfDay(for: .now)
        let diff = calendar.dateComponents([.day], from: today, to: selectedDay).day ?? 0
        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let d where d > 0: return "in \(d) days"
        default: return "\(-diff) days ago"
        }
    }

    // MARK: Header

    /// Readable selected-date line. Exposed to VoiceOver as a single adjustable element so
    /// the date can be set with swipe up/down, without scrubbing the strip.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(selection.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(Clinical.headline(17))
                .foregroundStyle(Clinical.ink)
            Spacer(minLength: 8)
            Text(relativeNote)
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Date")
        .accessibilityValue("\(selection.formatted(date: .complete, time: .omitted)), \(relativeNote)")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1 : -1
            guard let moved = calendar.date(byAdding: .day, value: step, to: selectedDay) else { return }
            let bounds = dayBounds
            selection = min(max(moved, bounds.lowerBound), bounds.upperBound)
        }
    }

    // MARK: Strip

    private var strip: some View {
        let allDays = days
        let selected = selectedDay
        let today = calendar.startOfDay(for: .now)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 6) {
                    ForEach(allDays.indices, id: \.self) { index in
                        let day = allDays[index]
                        let newMonth = index == 0
                            || !calendar.isDate(day, equalTo: allDays[index - 1], toGranularity: .month)
                        dayCell(day, isSelected: day == selected, isToday: day == today, showsMonth: newMonth)
                            .id(day)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(selected, anchor: .center)
            }
            .onChange(of: selection) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(selectedDay, anchor: .center)
                }
            }
        }
    }

    private func dayCell(_ day: Date, isSelected: Bool, isToday: Bool, showsMonth: Bool) -> some View {
        Button {
            selection = day
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 4) {
                // Month marker slot kept in every cell so heights stay aligned.
                Text(showsMonth ? day.formatted(.dateTime.month(.abbreviated)).uppercased() : " ")
                    .font(Clinical.eyebrow(9))
                    .tracking(0.8)
                    .foregroundStyle(Clinical.accent)
                    .opacity(showsMonth ? 1 : 0)

                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(Clinical.eyebrow(9))
                        .tracking(0.6)
                        .foregroundStyle(isSelected ? Clinical.surface.opacity(0.85) : Clinical.tertiary)
                    Text(day.formatted(.dateTime.day()))
                        .font(Clinical.number(17))
                        .foregroundStyle(isSelected ? Clinical.surface : Clinical.ink)
                    // Today dot (only when today is not the selected cell).
                    Circle()
                        .fill((isToday && !isSelected) ? Clinical.accent : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(minWidth: 46)
                .padding(.vertical, 9)
                .background(isSelected ? Clinical.accent : Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.clear : Clinical.hairline, lineWidth: 1)
                )
                .shadow(color: isSelected ? Clinical.accent.opacity(0.25) : .clear, radius: 8, y: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
