//
//  PendingCompletions.swift
//  Hair Compass AI 5
//
//  The widget cannot open SwiftData. It leaves a small request in the App Group; the app validates
//  it against the real plan and writes through DoseRepository on its next foreground pass.
//

import Foundation
import SwiftData

// KEEP IN SYNC — PendingCompletion is duplicated in
//   Service/PendingCompletions.swift  and
//   Hair Compass CheckIn Widget/HairCompassCheckInWidget.swift
struct PendingCompletion: Codable, Equatable {
    let treatmentName: String
    let slot: String
    let requestedAt: Date

    var key: String { "\(treatmentName)|\(slot)" }
}

enum PendingCompletionStore {
    static let key = "pendingCompletions.v1"

    static func load(
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetStore.appGroup)
    ) -> [PendingCompletion] {
        guard let defaults, let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingCompletion].self, from: data)) ?? []
    }

    static func append(
        _ item: PendingCompletion,
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetStore.appGroup)
    ) {
        guard let defaults else { return }
        var items = load(defaults: defaults).filter { $0.key != item.key }
        items.append(item)
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    static func clear(
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetStore.appGroup)
    ) {
        defaults?.removeObject(forKey: key)
    }
}

enum PendingCompletionApplier {
    /// Applies requests for today or yesterday only. Unknown, inactive, stale, and no-longer-due
    /// items are discarded. `DoseRepository`'s natural key makes a replay idempotent.
    @MainActor
    @discardableResult
    static func apply(
        context: ModelContext,
        treatments: [Treatment],
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetStore.appGroup)
    ) throws -> Int {
        let pending = PendingCompletionStore.load(defaults: defaults)
        guard !pending.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        let repository = DoseRepository(context: context, calendar: calendar)
        var applied = 0

        for item in pending {
            let requestedDay = calendar.startOfDay(for: item.requestedAt)
            guard requestedDay == today || requestedDay == yesterday else { continue }
            guard let treatment = treatments.first(where: {
                let name = $0.name.isEmpty ? $0.treatmentClass.title : $0.name
                return $0.isActive && name == item.treatmentName
            }) else { continue }
            guard PlanAdherence.expectedSlots(
                treatment,
                on: requestedDay,
                calendar: calendar
            ).contains(item.slot) else { continue }

            _ = try repository.log(treatment: treatment, day: item.requestedAt, slot: item.slot)
            applied += 1
        }

        // Save before clearing. If persistence fails, the queue survives for a later retry.
        try context.save()
        PendingCompletionStore.clear(defaults: defaults)
        return applied
    }
}
