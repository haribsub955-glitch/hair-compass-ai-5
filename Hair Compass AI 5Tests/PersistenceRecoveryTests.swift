import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct PersistenceRecoveryTests {
    @Test func currentVersionedSchemaOpensInMemoryWithMigrationPlan() throws {
        let schema = Schema(versionedSchema: HairCompassSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: HairCompassMigrationPlan.self,
                                           configurations: configuration)
        let context = ModelContext(container)
        context.insert(Profile(name: "durable"))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Profile>()).first?.name == "durable")
    }
}
