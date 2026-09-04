import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Hair_Compass_AI_5

/// Exercises the real PurchaseService against Xcode's local StoreKit engine. These tests
/// never charge an Apple Account and do NOT certify App Store Connect or production payments.
@Suite(.serialized)
@MainActor
struct StoreKitPurchaseIntegrationTests {
    private func makeSession() throws -> SKTestSession {
        // Use the scheme's single fixture, not a second copy that can drift from its products.
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HairCompass.storekit")
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test func bothPlansPurchaseRestoreAndExpire() async throws {
        let session = try makeSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let service = PurchaseService()
        await service.load()
        #expect(Set(service.products.map(\.id)) == [PurchaseService.monthlyID, PurchaseService.yearlyID])
        #expect(!service.hasPro)

        for id in [PurchaseService.monthlyID, PurchaseService.yearlyID] {
            let product = try #require(service.products.first { $0.id == id })
            #expect(await service.purchase(product))
            #expect(service.hasPro)
            #expect(service.purchaseState == .idle)
            await service.restore()
            #expect(service.restoreResult == "Pro restored.")
            try session.expireSubscription(productIdentifier: id)
            await service.load()
            #expect(!service.hasPro, "Expired subscriptions must not leave Pro unlocked")
        }
    }

    @Test func cancellationAndFailureDoNotUnlockPro() async throws {
        let session = try makeSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let service = PurchaseService()
        await service.load()
        let product = try #require(service.monthly)
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: StoreKitPurchaseAPI())
        #expect(!(await service.purchase(product)))
        #expect(service.purchaseState == .idle)
        #expect(!service.hasPro)

        try await session.setSimulatedError(.purchase(.purchaseNotAllowed), forAPI: StoreKitPurchaseAPI())
        #expect(!(await service.purchase(product)))
        #expect(service.purchaseState == .failed("Purchases aren't allowed on this device."))
        #expect(!service.hasPro)
    }

    @Test func pendingApprovalAndRefundRespectEntitlement() async throws {
        let session = try makeSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        session.askToBuyEnabled = true
        let service = PurchaseService()
        await service.load()
        let product = try #require(service.monthly)
        #expect(!(await service.purchase(product)))
        #expect(service.purchaseState == .pending)
        #expect(!service.hasPro)

        let pending = try #require(session.allTransactions().first { $0.productIdentifier == product.id })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        await service.load()
        #expect(service.hasPro)
        try session.refundTransaction(identifier: pending.identifier)
        await service.load()
        #expect(!service.hasPro, "A refunded purchase must not leave Pro unlocked")
    }
}
