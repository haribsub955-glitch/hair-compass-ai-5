//
//  EraseAndStartOver.swift
//  Hair Compass AI 5
//
//  "Erase everything and start over": every record, photo and preference on this iPhone goes,
//  a fresh un-onboarded profile is seeded, and the app returns to onboarding. Two things are
//  deliberately left alone — the 3-day access window in the Keychain (1.1 rule: nothing restarts
//  it) and the StoreKit entitlement (Apple's, not ours). This file must never reference the
//  window's type or its Keychain store — EraseAndStartOverTests checks that structurally. Side
//  effects are parameters so the wipe is provable in a unit test without touching the device.
//

import Foundation
import SwiftData
import UserNotifications

enum EraseAndStartOver {

    @MainActor
    static func perform(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        defaultsDomain: String = Bundle.main.bundleIdentifier ?? "harib.Hair-Compass-AI-5",
        photoStore: PhotoStore = .shared,
        cancelNotifications: () async -> Void = {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        },
        writeWidget: (WidgetSnapshot) -> Void = WidgetBridge.write
    ) async throws {
        // 1. The record. One delete per model type: relationships cascade, but naming every
        //    type here is what makes "everything" true when a new model is added later.
        //    Treatment must be deleted before its cascade children (doses, missed doses, side
        //    effects) — `Treatment`'s `@Relationship(deleteRule: .cascade, ...)` compiles to a
        //    SQLite trigger, and batch-deleting a child row directly while it still points at a
        //    live parent trips that trigger ("mandatory OTO nullify inverse"). Deleting the
        //    parent first cascades the children away, so the batch delete lines below become
        //    no-ops for a real record with active treatments — Task 5's own unit test never
        //    caught this because it inserts a `TreatmentDose` with no `treatment` set.
        try context.delete(model: Treatment.self)
        try context.delete(model: TreatmentDose.self)
        try context.delete(model: MissedDoseRecord.self)
        try context.delete(model: SideEffectLog.self)
        try context.delete(model: DailyEntry.self)
        try context.delete(model: LabResult.self)
        try context.delete(model: PhotoRecord.self)
        try context.delete(model: HealthSnapshot.self)
        try context.delete(model: TriggerEvent.self)
        try context.delete(model: ProcedureAppointment.self)
        try context.delete(model: ProgressCheckIn.self)
        try context.delete(model: AgentMemory.self)
        try context.delete(model: Profile.self)
        try context.save()

        // 2. Photo files.
        photoStore.deleteAll()

        // 3. Every preference — tutorial, reminders, consent, budget, dismissals. The access
        //    window is in the Keychain, not here, so it survives by construction.
        defaults.removePersistentDomain(forName: defaultsDomain)
        CloudAIConsent.reset(in: defaults)

        // 4. Nothing scheduled may fire for a record that no longer exists.
        await cancelNotifications()

        // 5. The Home Screen widget must not keep showing the erased record.
        writeWidget(.placeholder)

        // 6. A fresh profile, un-onboarded, exactly as a first install gets.
        Seed.bootstrapIfNeeded(context: context, profiles: [])
        try context.save()
    }
}
