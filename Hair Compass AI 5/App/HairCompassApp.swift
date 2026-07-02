import SwiftData
import SwiftUI

@main
struct HairCompassApp: App {
    let container: ModelContainer

    init() {
        AIConfig.seedKeyIfProvided()
        let schema = Schema([
            Profile.self,
            DailyEntry.self,
            Treatment.self,
            TreatmentDose.self,
            LabResult.self,
            PhotoRecord.self,
            HealthSnapshot.self,
            TriggerEvent.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A stale store from an older schema is unrecoverable in place — delete the
            // on-disk store and its sidecars, then recreate. Never fatalError on launch.
            Self.destroyStore()
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: schema, configurations: [fallback])
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }

    private static func destroyStore() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        for base in appSupport {
            for suffix in ["default.store", "default.store-wal", "default.store-shm"] {
                try? fm.removeItem(at: base.appendingPathComponent(suffix))
            }
        }
    }
}
