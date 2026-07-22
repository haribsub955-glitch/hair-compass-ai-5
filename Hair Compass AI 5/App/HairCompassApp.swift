import SwiftData
import SwiftUI

protocol PersistenceFileOperating {
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL]
    func fileExists(atPath path: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                         attributes: [FileAttributeKey: Any]?) throws
    func copyItem(at srcURL: URL, to dstURL: URL) throws
    func removeItem(at URL: URL) throws
    func contentsEqual(atPath path1: String, andPath path2: String) -> Bool
}

extension FileManager: PersistenceFileOperating {}

struct PersistenceRecoveryRollbackError: LocalizedError {
    let originalErrorDescription: String
    let recoveryDirectory: URL
    let rollbackFailureDescriptions: [String]

    var errorDescription: String? {
        "Persistence recovery left the live SQLite set split after rollback failed "
            + "(original error: \(originalErrorDescription); rollback: "
            + "\(rollbackFailureDescriptions.joined(separator: "; "))). The verified recovery set is at "
            + recoveryDirectory.path
    }
}

enum HairCompassSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Profile.self, DailyEntry.self, Treatment.self, TreatmentDose.self, MissedDoseRecord.self,
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
    private let storeOpener: @MainActor () throws -> ModelContainer

    init(storeOpener: @escaping @MainActor () throws -> ModelContainer = PersistenceController.makeContainer) {
        self.storeOpener = storeOpener
        openStore()
    }

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
            container = try storeOpener()
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

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: HairCompassSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, migrationPlan: HairCompassMigrationPlan.self,
                                  configurations: configuration)
    }

    /// Copies and verifies the complete SQLite recovery set before touching any live file. A copy
    /// failure therefore leaves the original store/WAL/SHM together and openable in place.
    static func moveStoreAside(
        fileManager: any PersistenceFileOperating = FileManager.default,
        recoveryID: @Sendable () -> String = { UUID().uuidString }
    ) throws -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let store = support.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: store.path) else { return nil }
        let directory = support.appendingPathComponent("HairCompass-Persistence-Recovery-\(recoveryID())", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        var copied: [(source: URL, destination: URL)] = []
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let source = support.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent(name)
            try fileManager.copyItem(at: source, to: destination)
            guard fileManager.contentsEqual(atPath: source.path, andPath: destination.path) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            copied.append((source, destination))
        }
        // Commit only after every present member has a byte-identical recovery copy. If a later
        // removal fails, restore any already-removed member from that verified copy before
        // surfacing the error, so the live set is never left split.
        do {
            for item in copied { try fileManager.removeItem(at: item.source) }
        } catch {
            var rollbackFailures: [String] = []
            for item in copied where !fileManager.fileExists(atPath: item.source.path) {
                do { try fileManager.copyItem(at: item.destination, to: item.source) }
                catch {
                    rollbackFailures.append("\(item.source.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if !rollbackFailures.isEmpty {
                throw PersistenceRecoveryRollbackError(
                    originalErrorDescription: error.localizedDescription,
                    recoveryDirectory: directory,
                    rollbackFailureDescriptions: rollbackFailures
                )
            }
            throw error
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
        }
    }
}

private struct PersistenceRecoveryView: View {
    let controller: PersistenceController
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
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
            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Clinical.canvas.ignoresSafeArea())
        .alert("Reset all app data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset and start over", role: .destructive) { controller.resetAfterConfirmation() }
        } message: {
            Text("This removes all Hair Compass records from the app, including health logs and photo references. The failed database will be preserved in a recovery folder, but it may require technical help to recover.")
        }
    }
}
