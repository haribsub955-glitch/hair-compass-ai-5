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
        defaults.set(true, forKey: "eveningCheckInEnabled")
        CloudAIConsent.record(true, in: defaults)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("erase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("a.jpg"))
        let photos = PhotoStore(testDirectory: dir)

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
        #expect(defaults.object(forKey: "eveningCheckInEnabled") == nil)
        #expect(CloudAIConsent.isDecided(defaults) == false)

        // Photos gone, side effects fired.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        #expect(cancelled)
        #expect(written == .placeholder)
    }

    /// The bug the UI test found: a dose linked to its treatment tripped a cascade constraint when
    /// children were deleted before the parent. Deterministic guard for the delete order.
    @Test func eraseHandlesTreatmentWithLinkedChildren() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile()
        profile.hasOnboarded = true
        context.insert(profile)
        let treatment = Treatment()
        context.insert(treatment)
        let dose = TreatmentDose(treatment: treatment)
        let missed = MissedDoseRecord(treatment: treatment)
        let sideEffect = SideEffectLog(treatment: treatment)
        context.insert(dose)
        context.insert(missed)
        context.insert(sideEffect)
        try context.save()

        let suite = "EraseAndStartOverTests.linked.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("erase-linked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try await EraseAndStartOver.perform(
            context: context, defaults: defaults, defaultsDomain: suite,
            photoStore: PhotoStore(testDirectory: dir),
            cancelNotifications: {}, writeWidget: { _ in }
        )

        #expect(try context.fetch(FetchDescriptor<Treatment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TreatmentDose>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MissedDoseRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SideEffectLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Profile>()).count == 1)
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

    /// "Everything" stays true only if every model the container declares is deleted by name.
    /// Reads the schema list in HairCompassApp.swift and the delete list in the service, so a
    /// model added to one without the other fails here instead of leaving records behind.
    @Test func eraseDeletesEveryModelTheContainerDeclares() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Hair Compass AI 5/App/HairCompassApp.swift"), encoding: .utf8)
        let service = try String(contentsOf: root.appendingPathComponent("Hair Compass AI 5/Service/EraseAndStartOver.swift"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"([A-Z][A-Za-z0-9]+)\.self"#)
        // The schema array is the first `[Profile.self, …]` literal in the app file.
        guard let start = app.range(of: "[Profile.self") else { Issue.record("schema list not found"); return }
        let tail = app[start.lowerBound...]
        guard let end = tail.firstIndex(of: "]") else { Issue.record("schema list end not found"); return }
        let list = String(tail[..<end])
        let ns = list as NSString
        let models = pattern.matches(in: list, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        #expect(models.count >= 13, "expected the full schema list, got \(models)")
        for model in models {
            #expect(service.contains("delete(model: \(model).self)"), "EraseAndStartOver never deletes \(model)")
        }
    }
}
