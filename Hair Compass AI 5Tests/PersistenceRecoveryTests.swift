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

    @Test func recoveryCopiesMainStoreOnlyThenRemovesOriginal() throws {
        let ops = try RecoveryTestFileOps(files: ["default.store": Data("main".utf8)])
        let recovered = try #require(try PersistenceController.moveStoreAside(fileManager: ops, recoveryID: { "fixed" }))
        #expect(FileManager.default.fileExists(atPath: recovered.appendingPathComponent("default.store").path))
        #expect(!FileManager.default.fileExists(atPath: ops.support.appendingPathComponent("default.store").path))
    }

    @Test func recoveryCopiesWalAndShmAsOneSet() throws {
        let files = ["default.store": Data("main".utf8), "default.store-wal": Data("wal".utf8),
                     "default.store-shm": Data("shm".utf8)]
        let ops = try RecoveryTestFileOps(files: files)
        let recovered = try #require(try PersistenceController.moveStoreAside(fileManager: ops, recoveryID: { "set" }))
        for name in files.keys {
            #expect(FileManager.default.contentsEqual(atPath: recovered.appendingPathComponent(name).path,
                                                      andPath: ops.backup.appendingPathComponent(name).path))
        }
    }

    @Test func recoveryNamesDoNotCollide() throws {
        let first = try RecoveryTestFileOps(files: ["default.store": Data("one".utf8)])
        let firstURL = try #require(try PersistenceController.moveStoreAside(fileManager: first, recoveryID: { "uuid-1" }))
        try Data("two".utf8).write(to: first.support.appendingPathComponent("default.store"))
        let secondURL = try #require(try PersistenceController.moveStoreAside(fileManager: first, recoveryID: { "uuid-2" }))
        #expect(firstURL != secondURL)
    }

    @Test func stagingFailureLeavesEveryOriginalIntact() throws {
        let files = ["default.store": Data("main".utf8), "default.store-wal": Data("wal".utf8),
                     "default.store-shm": Data("shm".utf8)]
        let ops = try RecoveryTestFileOps(files: files, failCopyNumber: 2)
        #expect(throws: (any Error).self) {
            try PersistenceController.moveStoreAside(fileManager: ops, recoveryID: { "failure" })
        }
        for (name, data) in files {
            #expect(try Data(contentsOf: ops.support.appendingPathComponent(name)) == data)
        }
    }

    @Test func removalFailureRollsBackAlreadyRemovedOriginals() throws {
        let files = ["default.store": Data("main".utf8), "default.store-wal": Data("wal".utf8),
                     "default.store-shm": Data("shm".utf8)]
        let ops = try RecoveryTestFileOps(files: files, failRemoveNumber: 2)
        #expect(throws: (any Error).self) {
            try PersistenceController.moveStoreAside(fileManager: ops, recoveryID: { "rollback" })
        }
        for (name, data) in files { #expect(try Data(contentsOf: ops.support.appendingPathComponent(name)) == data) }
    }

    @Test func rollbackCopyFailureSurfacesSplitStoreAndRecoveryDirectory() throws {
        let files = ["default.store": Data("main".utf8), "default.store-wal": Data("wal".utf8),
                     "default.store-shm": Data("shm".utf8)]
        let ops = try RecoveryTestFileOps(files: files, failCopyNumber: 4, failRemoveNumber: 2)
        do {
            _ = try PersistenceController.moveStoreAside(fileManager: ops, recoveryID: { "split" })
            Issue.record("Expected rollback failure")
        } catch let error as PersistenceRecoveryRollbackError {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("split"))
            #expect(error.localizedDescription.contains("HairCompass-Persistence-Recovery-split"))
            #expect(error.recoveryDirectory.lastPathComponent == "HairCompass-Persistence-Recovery-split")
        }
    }


    @Test func corruptStoreOpenFailurePreservesBytesForRecovery() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let corrupt = Data("not a sqlite store".utf8)
        try corrupt.write(to: url)
        let controller = PersistenceController(storeOpener: {
            _ = try Data(contentsOf: url)
            throw CocoaError(.fileReadCorruptFile)
        })
        #expect(controller.container == nil)
        #expect(controller.failureMessage != nil)
        #expect(try Data(contentsOf: url) == corrupt)
    }
}

private final class RecoveryTestFileOps: PersistenceFileOperating, @unchecked Sendable {
    let support: URL
    let backup: URL
    private let manager = FileManager.default
    private let failCopyNumber: Int?
    private let failRemoveNumber: Int?
    private var copies = 0
    private var removals = 0

    init(files: [String: Data], failCopyNumber: Int? = nil, failRemoveNumber: Int? = nil) throws {
        support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        backup = support.appendingPathComponent("expected")
        self.failCopyNumber = failCopyNumber
        self.failRemoveNumber = failRemoveNumber
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        try manager.createDirectory(at: backup, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: support.appendingPathComponent(name))
            try data.write(to: backup.appendingPathComponent(name))
        }
    }
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] { [support] }
    func fileExists(atPath path: String) -> Bool { manager.fileExists(atPath: path) }
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                         attributes: [FileAttributeKey: Any]?) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        copies += 1
        if copies == failCopyNumber { throw CocoaError(.fileWriteUnknown) }
        try manager.copyItem(at: srcURL, to: dstURL)
    }
    func removeItem(at URL: URL) throws {
        removals += 1
        if removals == failRemoveNumber { throw CocoaError(.fileWriteUnknown) }
        try manager.removeItem(at: URL)
    }
    func contentsEqual(atPath path1: String, andPath path2: String) -> Bool {
        manager.contentsEqual(atPath: path1, andPath: path2)
    }
}
