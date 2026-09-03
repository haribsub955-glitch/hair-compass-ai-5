//
//  EraseAndStartOverTests.swift
//  Hair Compass AI 5Tests
//
//  "Erase everything and start over" must leave nothing of the record behind — every model,
//  every photo file, every preference — and must leave exactly two things alone: the 3-day
//  access window (1.1 rule: nothing restarts it) and the subscription (Apple's, not ours). The
//  access-window guarantee is structural (the service has no path to the Keychain at all), so
//  it is proved by inspecting the service's source rather than by a counting store.
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
    }

    /// The 3-day window lives in the Keychain and must never restart. The guarantee is
    /// structural — the erase has no path to the anchor at all — so the test is structural too:
    /// the service's source must not name the window or its store.
    @Test func eraseNeverReferencesTheAccessWindow() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Hair Compass AI 5Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Hair Compass AI 5/Service/EraseAndStartOver.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        for forbidden in ["AccessWindow", "KeychainAnchorStore", "AccessAnchorStoring", "SecItem"] {
            #expect(!text.contains(forbidden), "EraseAndStartOver must never touch the access window (found \(forbidden))")
        }
    }
}
