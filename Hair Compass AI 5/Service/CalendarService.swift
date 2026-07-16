import EventKit
import Foundation

/// Adds a booked procedure to the user's Calendar via EventKit. Uses **write-only** access
/// (iOS 17+) — the minimal, most private scope: the app can add an event but never read the
/// calendar. A one-hour event at the appointment time on the default calendar. Record-keeping,
/// nothing more.
@MainActor
enum CalendarService {
    enum AddResult { case added, denied, failed }

    static func addProcedure(title: String, date: Date, location: String, notes: String) async -> AddResult {
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = try await store.requestWriteOnlyAccessToEvents()
        } catch {
            return .failed
        }
        guard granted else { return .denied }
        guard let calendar = store.defaultCalendarForNewEvents else { return .failed }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(60 * 60)   // a one-hour block
        if !location.isEmpty { event.location = location }
        if !notes.isEmpty { event.notes = notes }
        // A day-before alert mirrors the app's own procedure reminder.
        event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 24))

        do {
            try store.save(event, span: .thisEvent)
            return .added
        } catch {
            return .failed
        }
    }
}
