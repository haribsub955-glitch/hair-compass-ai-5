//
//  Hair_Compass_AI_5App.swift
//  Hair Compass AI 5
//
//  Created by Harib Azri on 25/03/2026.
//

import SwiftUI
import SwiftData
import Foundation

@main
struct Hair_Compass_AI_5App: App {
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var affiliateCatalogStore = AffiliateCatalogStore()

    init() {
        seedOpenAIKeyIfProvided()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HairProfile.self,
            DailyObservation.self,
            CheckInEntry.self,
            RoutineTask.self,
            PhotoRecord.self,
            MedicationLog.self,
            MedicationDoseEntry.self,
            RoutineCompletionEntry.self,
            ProcedureEvent.self,
            LifestyleEntry.self,
            LabResultEntry.self,
            HairTriggerEvent.self,
        ])
        let persistentConfiguration = ModelConfiguration(
            "HairCompassAI5",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        // Attempt 1: Open existing store (SwiftData performs lightweight migration automatically).
        do {
            return try ModelContainer(for: schema, configurations: [persistentConfiguration])
        } catch {
            print("[HairCompass] Primary store failed: \(error). Attempting to delete corrupted store and retry.")
        }

        // Attempt 2: Delete every sidecar of the corrupted store and create a fresh one.
        // We remove all files in the store directory whose name shares the store's base
        // name (.store, .store-wal, .store-shm, and any other CoreData sidecars) so the
        // reset is reliable regardless of which extensions exist on disk.
        let storeURL = persistentConfiguration.url
        let storeDirectory = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent
        if let siblings = try? FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in siblings where file.lastPathComponent.hasPrefix(storeName) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        do {
            return try ModelContainer(for: schema, configurations: [persistentConfiguration])
        } catch {
            // Attempt 3: Last resort — keep the app launchable with an in-memory store
            // rather than crashing on launch. Data is already inaccessible at this point,
            // so this degrades gracefully instead of hard-failing for the user.
            print("[HairCompass] Store reset failed: \(error). Falling back to in-memory store.")
            let memoryConfiguration = ModelConfiguration(
                "HairCompassAI5",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfiguration])
            } catch {
                fatalError("[HairCompass] Could not create in-memory ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseManager)
                .environmentObject(affiliateCatalogStore)
                .task {
                    await purchaseManager.start()
                    await affiliateCatalogStore.start()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func seedOpenAIKeyIfProvided() {
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return }

        UserDefaults.standard.set(key, forKey: "openAIAPIKey")
    }
}
