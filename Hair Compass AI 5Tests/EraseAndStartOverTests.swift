//
//  EraseAndStartOverTests.swift
//  Hair Compass AI 5Tests
//
//  "Erase everything and start over" must leave nothing of the record behind — every model,
//  every photo file, every preference — and must leave exactly two things alone: the 3-day
//  access window (1.1 rule: nothing restarts it) and the subscription (Apple's, not ours).
//

import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct EraseAndStartOverTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self, MissedDoseRecord.self,
            SideEffectLog.self, LabResult.self, PhotoRecord.self,
            HealthSnapshot.self, TriggerEvent.self,
            ProcedureAppointment.self, ProgressCheckIn.self, AgentMemory.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// An in-memory access-window store that counts writes, so the test can prove the erase
    /// never wrote a new anchor.
    private final class MemoryAnchorStore: AccessAnchorStoring {
        var anchor: Date?
        var saveCount = 0
        init(anchor: Date?) { self.anchor = anchor }
        func loadAnchor() -> Date? { anchor }
        func saveAnchor(_ date: Date) { anchor = date; saveCount += 1 }
    }

    @Test func eraseLeavesAFreshProfileAndNothingElse() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let onboarded = Profile()
        onboarded.hasOnboarded = true
        context.insert(onboarded)
        context.insert(TriggerEvent())
        context.insert(TreatmentDose())
        try context.save()

        let suite = "EraseAndStartOverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "hasSeenTutorial")
        CloudAIConsent.record(true, in: defaults)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("erase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("a.jpg"))
        let photos = PhotoStore(directoryOverride: dir)

        let anchorDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MemoryAnchorStore(anchor: anchorDate)
        _ = AccessWindow(store: store)   // reads the anchor; must not be touched by the erase

        var cancelled = false
        var written: WidgetSnapshot?
        try await EraseAndStartOver.perform(
            context: context,
            defaults: defaults,
            defaultsDomain: suite,
            photoStore: photos,
            cancelNotifications: { cancelled = true },
            writeWidget: { written = $0 }
        )

        // Exactly one fresh, un-onboarded profile; every other table empty.
        let profiles = try context.fetch(FetchDescriptor<Profile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.hasOnboarded == false)
        #expect(try context.fetch(FetchDescriptor<TriggerEvent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).isEmpty)

        // Preferences gone, consent back to undecided.
        #expect(defaults.object(forKey: "hasSeenTutorial") == nil)
        #expect(CloudAIConsent.isDecided(defaults) == false)

        // Photos gone, side effects fired.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        #expect(cancelled)
        #expect(written == .placeholder)

        // The access window is untouched: same anchor, no new write.
        #expect(store.anchor == anchorDate)
        #expect(store.saveCount == 0)
    }
}
