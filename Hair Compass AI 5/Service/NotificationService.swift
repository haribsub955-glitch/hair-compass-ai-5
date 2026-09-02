import Foundation
@preconcurrency import UserNotifications

protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func add(_ request: UNNotificationRequest) async throws
}

final class SystemNotificationCenterClient: NotificationCenterClient, @unchecked Sendable {
    let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { try await center.requestAuthorization(options: options) }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
}

actor NotificationRegistry {
    struct Result: Sendable { var error: String?; var acceptedCount: Int; var applied: Bool }
    private let client: any NotificationCenterClient
    private var latestGeneration: [String: UInt64] = [:]
    private var mutationTail: Task<Void, Never>?

    init(client: any NotificationCenterClient) { self.client = client }

    func reconcile(key: String, generation: UInt64, prefixes: [String],
                   desired: [UNNotificationRequest], limit: Int) async -> Result {
        guard generation >= latestGeneration[key, default: 0] else { return Result(error: nil, acceptedCount: 0, applied: false) }
        latestGeneration[key] = generation
        let predecessor = mutationTail
        let mutation = Task { [self] in
            if let predecessor { await predecessor.value }
            return await performReconcile(key: key, generation: generation, prefixes: prefixes,
                                          desired: desired, limit: limit)
        }
        mutationTail = Task { _ = await mutation.value }
        return await mutation.value
    }

    private func performReconcile(key: String, generation: UInt64, prefixes: [String],
                                  desired: [UNNotificationRequest], limit: Int) async -> Result {
        guard latestGeneration[key] == generation else { return Result(error: nil, acceptedCount: 0, applied: false) }
        let pending = await client.pendingNotificationRequests()
        // A newer call can arrive while the client suspends above. Do not let this generation
        // remove anything once it has lost ownership.
        guard latestGeneration[key] == generation else { return Result(error: nil, acceptedCount: 0, applied: false) }
        let owns: (String) -> Bool = { id in prefixes.contains { id.hasPrefix($0) } }
        let capacity = max(0, limit - pending.filter { !owns($0.identifier) }.count)
        let accepted = Array(desired.sorted { $0.identifier < $1.identifier }.prefix(capacity))
        var message = desired.count > capacity
            ? "Some reminders could not be scheduled because iOS allows at most \(limit) pending notifications." : nil
        let pendingIDs = Set(pending.map(\.identifier))
        var additionsSucceeded = true
        for request in accepted where !pendingIDs.contains(request.identifier) {
            do { try await client.add(request) }
            catch {
                additionsSucceeded = false
                message = "A reminder could not be scheduled: \(error.localizedDescription)"
            }
        }
        // Removing is the commit point. Until every desired addition succeeds, retain the old
        // valid schedule so a partial Notification Center failure cannot destroy it.
        if additionsSucceeded {
            let acceptedIDs = Set(accepted.map(\.identifier))
            let obsolete = pending.map(\.identifier).filter { owns($0) && !acceptedIDs.contains($0) }
            if !obsolete.isEmpty {
                await client.removePendingNotificationRequests(withIdentifiers: obsolete)
            }
        }
        return Result(error: message, acceptedCount: accepted.count, applied: true)
    }
}

/// Local (on-device) reminders that keep a person on their routine: a repeating notification at
/// each active daily treatment's slot time, a refill heads-up, and a monthly photo prompt — all
/// under the Plan tab's "Reminders" toggle (`reschedule()`). The evening check-in nudge
/// (`planEveningCheckIn`) is a separate, opt-in, user-timed reminder — see its doc comment. No
/// server, no data leaves the phone.
@MainActor
@Observable
final class NotificationService {
    static let enabledKey = "remindersEnabled"
    static let genericWordingKey = "genericNotificationWording"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// User-visible scheduling failure. Callers can render this instead of silently pretending a
    /// reminder exists when Notification Center rejected it.
    private(set) var schedulingError: String?
    private let client: any NotificationCenterClient
    private let registry: NotificationRegistry
    /// Routes a notification tap back to the app by identifier prefix (see `onNotificationTapped`).
    private let tapDelegate = NotificationTapDelegate()

    private let treatmentPrefix = "treatment."
    private let refillPrefix = "refill."
    private let photoReminderID = "photoReminder"
    private let eveningCheckInPrefix = "eveningCheckIn."
    private let procedurePrefix = "procedure."
    private let progressCheckInID = "progressCheckIn.0"
    private let milestonePrefix = "milestone."

    /// Coalescing guard for `reschedule()` (audit #5): a second call cancels the first's task
    /// before it starts a fresh reconciliation, so an older planner cannot prune requests after
    /// a newer generation has taken ownership — latest call always wins.
    private var generations: [String: UInt64] = [:]

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var usesGenericWording: Bool { UserDefaults.standard.bool(forKey: Self.genericWordingKey) }

    nonisolated static func wording(title: String, body: String, generic: Bool) -> (title: String, body: String) {
        generic ? ("Hair Compass reminder", "Open Hair Compass to see what’s due.") : (title, body)
    }

    /// Fired on the main actor with the tapped notification's identifier — `RootView` wires this
    /// to switch tabs and set the matching `DeepLinkRouter` flag (milestone → progress report,
    /// evening check-in → the log sheet, monthly photo → guided capture, refill/treatment →
    /// Plan, procedure → the procedures list, progress check-in → ProgressCheckInSheet), the same
    /// consume-once idiom the widget's `haircompass://log` URL already uses. Round 4: previously
    /// only `milestone.*` taps were routed at all — every other reminder (the evening check-in,
    /// the monthly photo prompt, a refill heads-up) dead-ended at the app icon instead of opening
    /// the thing it invited, right at the moment the user said yes. Round 5: `procedure.*` and
    /// `progressCheckIn.*` were still unmatched and got the same fix.
    var onNotificationTapped: ((String) -> Void)? {
        get { tapDelegate.onTapped }
        set { tapDelegate.onTapped = newValue }
    }

    init(client: (any NotificationCenterClient)? = nil) {
        let system = client == nil ? SystemNotificationCenterClient() : nil
        self.client = client ?? system!
        self.registry = NotificationRegistry(client: self.client)
        system?.center.delegate = tapDelegate
    }

    func refreshAuthorization() async {
        authorization = await client.authorizationStatus()
    }

    /// Pure guard condition shared by every `plan*`/`performReschedule` call: on, and the system
    /// permission is actually granted. Pulled out so it can be unit-tested without a live
    /// `UNUserNotificationCenter` (2026-07-21 audit: `authorization` starts `.notDetermined` on
    /// every cold launch and was previously only refreshed from `CareView`, so a user who lived
    /// on Today ate a silent remove-and-fail on every one of these calls — see the
    /// `await refreshAuthorization()` each caller now runs first).
    nonisolated static func canSchedule(enabled: Bool, authorization: UNAuthorizationStatus) -> Bool {
        enabled && (authorization == .authorized || authorization == .provisional)
    }

    /// Requests notification permission if it hasn't been decided yet, otherwise just reports
    /// the current grant state. Shared by any feature that needs permission before scheduling —
    /// independent of which toggle/UserDefaults flag that feature owns.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let granted: Bool
        if authorization == .notDetermined {
            granted = (try? await client.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        } else {
            granted = authorization == .authorized || authorization == .provisional
        }
        await refreshAuthorization()
        return granted
    }

    /// Turn reminders on: request permission if needed, then schedule. Returns whether it's on.
    @discardableResult
    func enable(
        treatments: [(name: String, slots: [String])],
        refills: [(name: String, refillBy: Date)] = []
    ) async -> Bool {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await reschedule(treatments: treatments, refills: refills)
        return true
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        let prefixes = [treatmentPrefix, refillPrefix, photoReminderID,
                        procedurePrefix, progressCheckInID, milestonePrefix]
        let generation = nextGeneration(for: prefixes)
        Task { await reconcile(prefixes: prefixes, desired: [], generation: generation) }
    }

    /// Replace all scheduled reminders with fresh ones for the current active daily treatments.
    /// No-op when reminders are off, so callers can fire it freely whenever treatments change.
    func reschedule(
        treatments: [(name: String, slots: [String])],
        refills: [(name: String, refillBy: Date)] = []
    ) async {
        let generation = nextGeneration(for: [treatmentPrefix, refillPrefix, photoReminderID])
        await performReschedule(treatments: treatments, refills: refills, generation: generation)
    }

    /// The actual remove+add sequence, isolated so `reschedule()` can coalesce overlapping
    /// calls into a single in-flight `Task` (see `rescheduleTask`).
    private func performReschedule(
        treatments: [(name: String, slots: [String])],
        refills: [(name: String, refillBy: Date)], generation: UInt64
    ) async {
        // Self-refresh rather than trusting a caller to have called `refreshAuthorization()`
        // first: `authorization` starts `.notDetermined` on every cold launch, and nothing but
        // `CareView`'s `.task` previously re-derived it, so a user who never opened Plan would
        // fail this guard on every relaunch — after the remove-all below already ran.
        await refreshAuthorization()
        guard Self.canSchedule(enabled: isEnabled, authorization: authorization) else {
            await reconcile(prefixes: [treatmentPrefix, refillPrefix, photoReminderID],
                            desired: [], generation: generation)
            return
        }
        guard !Task.isCancelled else { return }
        var desired: [UNNotificationRequest] = []

        // Coalesce every treatment that shares a time slot into ONE notification: a 21:00 regimen
        // of three items becomes a single "Evening routine — 3 steps" banner instead of three
        // separate pings at the same minute — the biggest fatigue win. One request per distinct
        // slot, keyed `treatment.<slot>` so the tap router's `treatment.` prefix still routes to Plan.
        // `.passive` (a repeating daily nudge shouldn't light up the screen) and a shared thread so
        // Notification Center groups them.
        var namesBySlot: [String: [String]] = [:]
        for t in treatments {
            for slot in t.slots where Self.components(from: slot) != nil {
                namesBySlot[slot, default: []].append(t.name)
            }
        }
        for (slot, names) in namesBySlot {
            guard let comps = Self.components(from: slot) else { continue }
            let content = UNMutableNotificationContent()
            let wording = Self.wording(
                title: Self.routineTitle(slot: slot, stepCount: names.count, firstName: names[0]),
                body: Self.routineBody(names: names), generic: usesGenericWording
            )
            content.title = wording.title
            content.body = wording.body
            content.sound = .default
            content.threadIdentifier = "routine"
            content.interruptionLevel = .passive
            if let art = NotificationArt.attachment() { content.attachments = [art] }
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: "\(treatmentPrefix)\(slot)", content: content, trigger: trigger)
            desired.append(request)
        }

        // One-off refill heads-up, 7 days before each refill-by date at 10:00. Skipped when
        // that moment is already past — the in-app chip carries urgent/overdue from there.
        for (i, r) in refills.enumerated() {
            guard let fireDate = Self.refillReminderDate(for: r.refillBy), fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            let wording = Self.wording(title: "Running low", body: "Time to reorder \(r.name).", generic: usesGenericWording)
            content.title = wording.title
            content.body = wording.body
            content.sound = .default
            content.threadIdentifier = "refill"
            content.interruptionLevel = .passive
            if let art = NotificationArt.attachment() { content.attachments = [art] }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "\(refillPrefix)\(i)", content: content, trigger: trigger)
            desired.append(request)
        }

        // Monthly photo prompt — a comparable set on the 1st of each month.
        var monthly = DateComponents(); monthly.day = 1; monthly.hour = 10
        let photo = UNMutableNotificationContent()
        let photoWording = Self.wording(title: "Monthly photo", body: "Same light, same spot.", generic: usesGenericWording)
        photo.title = photoWording.title
        photo.body = photoWording.body
        photo.sound = .default
        photo.threadIdentifier = "photo"
        photo.interruptionLevel = .passive
        if let art = NotificationArt.attachment() { photo.attachments = [art] }
        let photoRequest = UNNotificationRequest(
            identifier: photoReminderID,
            content: photo,
            trigger: UNCalendarNotificationTrigger(dateMatching: monthly, repeats: true)
        )
        desired.append(photoRequest)
        await reconcile(prefixes: [treatmentPrefix, refillPrefix, photoReminderID], desired: desired, generation: generation)
    }

    /// One reminder ~1 day before each upcoming, not-yet-completed procedure appointment (a PRP
    /// session, a transplant, …) — beautiful, low-text, the same brand image as every other
    /// reminder, ids `procedure.<appointment id>`. Only ever touches its own `procedure.*` ids
    /// (never `removeAllPendingNotificationRequests()`), so it's safe to call independently of
    /// `reschedule()` — though callers that also call `reschedule()` in the same cycle should
    /// call this AFTER it, since `reschedule()`'s remove-all would otherwise wipe reminders this
    /// call just scheduled (see `CareView`'s shared `.task(id:)`). No-op (after clearing stale
    /// ids) when reminders are off.
    func planProcedureReminders(_ items: [(id: String, title: String, date: Date, isConsultation: Bool)]) async {
        let generation = nextGeneration(for: [procedurePrefix])
        await refreshAuthorization()
        guard Self.canSchedule(enabled: isEnabled, authorization: authorization) else {
            await reconcile(prefixes: [procedurePrefix], desired: [], generation: generation); return
        }
        guard !Task.isCancelled else { return }
        var desired: [UNNotificationRequest] = []

        for item in items {
            guard let fireDate = Self.procedureReminderDate(for: item.date), fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            let wording = Self.wording(
                title: "Upcoming: \(item.title)",
                body: Self.procedureReminderBody(fireDate: fireDate, appointmentDate: item.date, isConsultation: item.isConsultation),
                generic: usesGenericWording
            )
            content.title = wording.title
            content.body = wording.body
            content.sound = .default
            content.threadIdentifier = "procedure"   // day-before, time-relevant — default (active) level
            if let art = NotificationArt.attachment() { content.attachments = [art] }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "\(procedurePrefix)\(item.id)", content: content, trigger: trigger)
            desired.append(request)
        }
        await reconcile(prefixes: [procedurePrefix], desired: desired, generation: generation)
    }

    /// ONE low-frequency monthly nudge toward the Plan tab's Progress check-in — the between-
    /// visit questions a dermatologist asks (new regrowth, density/shedding/hairline trend,
    /// overall, scalp red flag). Fires once, ~30 days after `lastCheckIn` (30 days from now if
    /// there's never been one) at 10:00, id `progressCheckIn.0`. Only ever touches that one id
    /// (never `removeAllPendingNotificationRequests()`), so — like `planProcedureReminders` —
    /// it's safe to call after `reschedule()` in the same cycle (see `CareView`'s shared
    /// `.task(id:)`, which re-plans this whenever the latest check-in date changes). No-op
    /// (after clearing the stale id) when reminders are off — it shares the same "Reminders"
    /// toggle as the treatment/refill/procedure reminders rather than adding a new one.
    func planProgressCheckInReminder(lastCheckIn: Date?) async {
        let generation = nextGeneration(for: [progressCheckInID])
        await refreshAuthorization()
        guard Self.canSchedule(enabled: isEnabled, authorization: authorization) else {
            await reconcile(prefixes: [progressCheckInID], desired: [], generation: generation); return
        }
        guard !Task.isCancelled else { return }

        let calendar = Calendar.current
        let base = lastCheckIn ?? .now
        guard let dueDay = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: base)) else { return }
        var comps = calendar.dateComponents([.year, .month, .day], from: dueDay)
        comps.hour = 10; comps.minute = 0
        guard let fireDate = calendar.date(from: comps), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        let wording = Self.wording(title: "Monthly progress check-in", body: "A minute on how it's going.", generic: usesGenericWording)
        content.title = wording.title
        content.body = wording.body
        content.sound = .default
        content.threadIdentifier = "progress"
        content.interruptionLevel = .passive   // a gentle monthly nudge, never an interruption
        if let art = NotificationArt.attachment() { content.attachments = [art] }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: progressCheckInID, content: content, trigger: trigger)
        await reconcile(prefixes: [progressCheckInID], desired: [request], generation: generation)
    }

    /// One-shot reminders for the app's central honest promise — "judge treatment response at
    /// 24 weeks, not sooner." Schedules up to three per active treatment (weeks 4, 12, 24 from
    /// its start date, at 10:00), so the assessment window opening is a moment the user is told
    /// about rather than one that only surfaces if they happen to open Plan during that exact
    /// week. Gated under the same "Reminders" toggle as the treatment/refill/procedure
    /// reminders. Only ever touches its own `milestone.*` ids (never
    /// `removeAllPendingNotificationRequests()`), so — like `planProcedureReminders` — it's safe
    /// to call after `reschedule()` in the same cycle.
    func planMilestoneReminders(_ treatments: [(id: String, name: String, startDate: Date)]) async {
        let generation = nextGeneration(for: [milestonePrefix])
        await refreshAuthorization()
        guard Self.canSchedule(enabled: isEnabled, authorization: authorization) else {
            await reconcile(prefixes: [milestonePrefix], desired: [], generation: generation); return
        }
        guard !Task.isCancelled else { return }

        let calendar = Calendar.current
        var desired: [UNNotificationRequest] = []
        for t in treatments {
            for week in Self.milestoneWeeks {
                guard let day = calendar.date(byAdding: .weekOfYear, value: week, to: calendar.startOfDay(for: t.startDate))
                else { continue }
                var comps = calendar.dateComponents([.year, .month, .day], from: day)
                comps.hour = 10; comps.minute = 0
                guard let fireDate = calendar.date(from: comps), fireDate > .now else { continue }

                let content = UNMutableNotificationContent()
                let wording = Self.wording(title: "Week \(week) of \(t.name)", body: Self.milestoneBody(week: week), generic: usesGenericWording)
                content.title = wording.title
                content.body = wording.body
                content.sound = .default
                content.threadIdentifier = "milestone"   // the assessment-window moment — default (active) level
                if let art = NotificationArt.attachment() { content.attachments = [art] }
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "\(milestonePrefix)\(t.id).\(week)", content: content, trigger: trigger
                )
                desired.append(request)
            }
        }
        await reconcile(prefixes: [milestonePrefix], desired: desired, generation: generation)
    }

    /// Same weeks `ProgressReport`'s milestone cadence starts with — 4 · 12 · 24. The report
    /// keeps naming milestones every 12 weeks after that; the reminder deliberately stops at 24,
    /// the one moment this feature exists to surface.
    static let milestoneWeeks = [4, 12, 24]

    static func milestoneBody(week: Int) -> String {
        switch week {
        case 24: return "Your assessment window opens — your progress report is ready to bring to your clinician."
        case 12: return "Halfway to the 24-week assessment window. Your progress report is ready to look at."
        default: return "A first checkpoint. Your progress report is ready to look at."
        }
    }

    /// Converts the `eveningCheckInMinutes` AppStorage int (minutes since midnight) into the
    /// `DateComponents` `planEveningCheckIn` wants. Shared by every re-planning call site
    /// (`RootView`, always alive, and `CareView`'s own toggle UI) so a minutes value maps to the
    /// exact same fire time no matter which surface last re-planned it.
    static func eveningCheckInComponents(minutesSinceMidnight: Int) -> DateComponents {
        var comps = DateComponents()
        comps.hour = minutesSinceMidnight / 60
        comps.minute = minutesSinceMidnight % 60
        return comps
    }

    /// Implementation-intention evening reminder (research: a user-chosen time beats generic
    /// smart timing, and caps at ≤1/day keep retention high). Independent of the routine
    /// "Reminders" toggle above — OFF until the Plan tab's evening-check-in toggle turns it on.
    /// Schedules up to 3 non-repeating reminders (today + the next two days) at `time`, skipping
    /// today when `hasLoggedToday` so a logged day is never nagged. Invitation-toned, never
    /// guilt: streak-aware once a streak exists, otherwise a plain, calm invite.
    ///
    /// Idempotent (it removes its own 3 pending ids before re-adding), and cheap — safe to call
    /// from more than one surface. It must be re-called at least every 3 days or the schedule
    /// silently runs out, so `RootView` — always alive regardless of which tab is on screen —
    /// re-plans it on every relevant state change and again on every foreground, in addition to
    /// `CareView`'s own toggle UI re-planning it on the spot when the user flips it.
    func planEveningCheckIn(enabled: Bool, time: DateComponents, hasLoggedToday: Bool, streak: Int) async {
        let generation = nextGeneration(for: [eveningCheckInPrefix])
        // Self-refresh first (see `canSchedule`'s doc comment): `RootView`'s launch/foreground
        // replans are the only surface keeping this alive for a user who never opens Plan, and
        // `authorization` starts `.notDetermined` on every cold launch — without this, the
        // remove-below ran every relaunch and nothing ever got re-added.
        await refreshAuthorization()
        guard Self.canSchedule(enabled: enabled, authorization: authorization) else {
            await reconcile(prefixes: [eveningCheckInPrefix], desired: [], generation: generation); return
        }

        let calendar = Calendar.current
        let body = streak >= 3
            ? "Day \(streak + 1). Twenty seconds."
            : "Twenty seconds."

        var desired: [UNNotificationRequest] = []
        for offset in 0..<3 {
            if offset == 0 && hasLoggedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: .now) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = time.hour
            comps.minute = time.minute
            guard let fireDate = calendar.date(from: comps), fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            let wording = Self.wording(title: "Tonight's check-in", body: body, generic: usesGenericWording)
            content.title = wording.title
            content.body = wording.body
            content.sound = .default
            content.threadIdentifier = "checkin"   // the user picked this time — default (active) level
            if let art = NotificationArt.attachment() { content.attachments = [art] }
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: "\(eveningCheckInPrefix)\(offset)", content: content, trigger: trigger)
            desired.append(request)
        }
        await reconcile(prefixes: [eveningCheckInPrefix], desired: desired, generation: generation)
    }

    /// One immutable desired schedule followed by one ownership-scoped reconciliation. Existing
    /// requests owned by other apps/features are counted and never removed. Stable identifier
    /// ordering makes the 64-request cap deterministic.
    private func nextGeneration(for prefixes: [String]) -> UInt64 {
        let key = prefixes.sorted().joined(separator: "|")
        generations[key, default: 0] += 1
        return generations[key]!
    }

    private func reconcile(prefixes: [String], desired: [UNNotificationRequest], generation: UInt64) async {
        let key = prefixes.sorted().joined(separator: "|")
        let result = await registry.reconcile(key: key, generation: generation, prefixes: prefixes,
                                              desired: desired, limit: Self.pendingRequestLimit)
        if result.applied { schedulingError = result.error }
    }

    static let pendingRequestLimit = 64

    /// Pure cap computation used by tests and by reconciliation.
    nonisolated static func acceptedOwnedCount(desired: Int, foreignPending: Int) -> Int {
        min(max(0, desired), max(0, pendingRequestLimit - max(0, foreignPending)))
    }

    /// 10:00 local time, 7 days before the refill-by date. nil if the calendar math fails.
    static func refillReminderDate(for refillBy: Date, calendar: Calendar = .current) -> Date? {
        guard let weekBefore = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: refillBy)) else { return nil }
        return calendar.date(byAdding: .hour, value: 10, to: weekBefore)
    }

    /// 10:00 local time the day before the appointment — or the appointment's own time when
    /// that 10:00 slot has already passed (the appointment is less than a day away, e.g. booked
    /// same-day). nil only if the calendar math fails.
    static func procedureReminderDate(for appointmentDate: Date, calendar: Calendar = .current) -> Date? {
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: appointmentDate) else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: dayBefore)
        comps.hour = 10; comps.minute = 0
        guard let candidate = calendar.date(from: comps) else { return nil }
        return candidate > .now ? candidate : appointmentDate
    }

    /// "Tomorrow"/"Today" reads correctly whichever branch `procedureReminderDate` took. A
    /// consultation (round-6 addition) gets its own body pointing back at the visit report the
    /// app already builds, rather than the generic "at your clinic" line.
    static func procedureReminderBody(fireDate: Date, appointmentDate: Date, isConsultation: Bool = false, calendar: Calendar = .current) -> String {
        let when = calendar.isDate(fireDate, inSameDayAs: appointmentDate) ? "Today" : "Tomorrow"
        if isConsultation { return "\(when). Your visit report is ready to bring." }
        return "\(when) at your clinic."
    }

    /// A coalesced routine reminder's title: one step keeps its own name; several read as the
    /// time-of-day block, so a 21:00 stack of three items becomes "Evening routine".
    static func routineTitle(slot: String, stepCount: Int, firstName: String) -> String {
        guard stepCount > 1 else { return firstName }
        let hour = Int(slot.split(separator: ":").first ?? "") ?? 12
        switch hour {
        case 0..<12: return "Morning routine"
        case 12..<17: return "Afternoon routine"
        default: return "Evening routine"
        }
    }

    /// One step keeps the calm "A tap when it's done."; several list the names so the single
    /// banner still says exactly what's due.
    static func routineBody(names: [String]) -> String {
        guard names.count > 1 else { return "A tap when it's done." }
        return "\(names.count) steps: \(names.joined(separator: " · "))"
    }

    /// "08:00" → hour/minute DateComponents for a repeating daily trigger.
    static func components(from slot: String) -> DateComponents? {
        let parts = slot.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var comps = DateComponents(); comps.hour = h; comps.minute = m
        return comps
    }
}

/// A minimal `UNUserNotificationCenterDelegate`: shows banners for foreground notifications
/// (these are occasional, high-value nudges, not spam) and routes ANY notification tap back into
/// the app via a closure `NotificationService` exposes as `onNotificationTapped`, passing the raw
/// identifier so the caller can dispatch by prefix. A separate `NSObject` subclass rather than
/// retrofitting `NotificationService` itself, which is an `@Observable` class with no `NSObject`
/// ancestry.
private final class NotificationTapDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onTapped: ((String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        Task { @MainActor [onTapped] in onTapped?(identifier) }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
