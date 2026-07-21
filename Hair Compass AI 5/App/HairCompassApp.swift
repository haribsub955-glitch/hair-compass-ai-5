import SwiftData
import SwiftUI

enum HairCompassSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self,
         SideEffectLog.self, LabResult.self, PhotoRecord.self, HealthSnapshot.self,
         TriggerEvent.self, ProcedureAppointment.self, ProgressCheckIn.self]
    }
}

enum HairCompassMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HairCompassSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor @Observable
final class PersistenceController {
    private(set) var container: ModelContainer?
    private(set) var failureMessage: String?
    private(set) var recoveryURL: URL?

    init() { openStore() }

    func retry() { openStore() }

    func resetAfterConfirmation() {
        do {
            recoveryURL = try Self.moveStoreAside()
            openStore()
        } catch {
            failureMessage = "The existing data could not be preserved for recovery: \(error.localizedDescription)"
        }
    }

    private func openStore() {
        do {
            let schema = Schema(versionedSchema: HairCompassSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema,
                                           migrationPlan: HairCompassMigrationPlan.self,
                                           configurations: configuration)
            failureMessage = nil
        } catch {
            container = nil
            failureMessage = error.localizedDescription
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_IN_MEMORY_FALLBACK") {
                let schema = Schema(versionedSchema: HairCompassSchemaV1.self)
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try? ModelContainer(for: schema,
                                                migrationPlan: HairCompassMigrationPlan.self,
                                                configurations: configuration)
            }
            #endif
        }
    }

    /// Explicit reset is recoverable: the store and SQLite sidecars are moved, never deleted.
    static func moveStoreAside(fileManager: FileManager = .default, date: Date = .now) throws -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let store = support.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: store.path) else { return nil }
        let stamp = Int(date.timeIntervalSince1970)
        let directory = support.appendingPathComponent("HairCompass-Persistence-Recovery-\(stamp)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let source = support.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: directory.appendingPathComponent(name))
        }
        return directory
    }
}

@main
struct HairCompassApp: App {
    @State private var persistence = PersistenceController()

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = persistence.container {
                    RootView().modelContainer(container)
                } else {
                    PersistenceRecoveryView(controller: persistence)
                }
            }
            .preferredColorScheme(.light)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

private struct PersistenceRecoveryView: View {
    let controller: PersistenceController
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your data couldn't be opened")
                .font(Clinical.headline(30)).foregroundStyle(Clinical.ink)
            Text("Hair Compass has not deleted or replaced your records. Retry first. Reset only if retry continues to fail.")
                .font(Clinical.body(16)).foregroundStyle(Clinical.secondary)
            if let message = controller.failureMessage {
                Text(message).font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
            }
            Button("Retry opening data") { controller.retry() }
                .buttonStyle(ClinicalButtonStyle(filled: true))
            Button("Reset app data…", role: .destructive) { confirmReset = true }
                .font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.critical)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Clinical.canvas.ignoresSafeArea())
        .alert("Reset all app data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset and start over", role: .destructive) { controller.resetAfterConfirmation() }
        } message: {
            Text("This removes all Hair Compass records from the app, including health logs and photo references. The failed database will be preserved in a recovery folder, but it may require technical help to recover.")
        }
    }
}
