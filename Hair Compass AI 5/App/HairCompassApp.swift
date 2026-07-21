import SwiftData
import SwiftUI

@main
struct HairCompassApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            Profile.self,
            DailyEntry.self,
            Treatment.self,
            TreatmentDose.self,
            SideEffectLog.self,
            LabResult.self,
            PhotoRecord.self,
            HealthSnapshot.self,
            TriggerEvent.self,
            ProcedureAppointment.self,
            ProgressCheckIn.self
        ])
        // CloudKit readiness — the schema already satisfies CloudKit's model rules:
        // every attribute has a default value or is optional, every relationship is
        // optional (or an array defaulting to []) with a declared inverse, and no
        // @Attribute(.unique) constraints are used. Turning sync on is a manual Xcode
        // signing step that cannot be done in code:
        //   1. Target "Hair Compass AI 5" → Signing & Capabilities → + Capability → iCloud.
        //   2. Check "CloudKit" and add a container (e.g. iCloud.harib.Hair-Compass-AI-5).
        //   3. + Capability → Background Modes → check "Remote notifications".
        //   4. Replace the line below with:
        //        ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        //   5. Photos live outside SwiftData (Documents/ScalpPhotos, path-only records) —
        //      they will NOT sync via CloudKit; keep the JSON backup for them or move the
        //      bytes into an @Attribute(.externalStorage) Data property first.
        // Until then, the full-backup file (Profile sheet → "Your data") is the durability story.
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
                // The design is deliberately single-appearance: every Clinical token is a fixed
                // warm colour. Pin Light so the invariant is explicit — any future system-adaptive
                // colour or default sheet/list background can't silently break in dark mode.
                .preferredColorScheme(.light)
                // Dynamic Type step 2: the app's body copy now genuinely scales (Clinical.body/
                // .caption), which is the point — but a handful of hand-drawn layouts (the tab
                // bar, compass gauges, log-sheet tiles) size their chrome in fixed points around
                // that text. Clamping the top of the range at `.accessibility2` (roughly double
                // system text) keeps those tight compositions intact while still giving anyone up
                // to that size real, working growth — the other three AX sizes above it exist for
                // system text (Settings, alerts), not for a densely custom app layout like this one.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
