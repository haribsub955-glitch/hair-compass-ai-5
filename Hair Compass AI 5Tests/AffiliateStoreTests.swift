//
//  AffiliateStoreTests.swift
//  Hair Compass AI 5Tests
//
//  Owner-controlled affiliate links: resolution precedence
//  (DEBUG override → remote cache → bundled → nil), remote payload
//  validation, and offline cache survival.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct AffiliateStoreTests {

    /// A throwaway UserDefaults suite so tests never touch the app's real domain.
    private func freshDefaults() -> UserDefaults {
        let name = "affiliate-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func payloadData(version: Int = 1, links: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": version,
            "updatedAt": "2026-07-04",
            "links": links,
        ])
    }

    // MARK: - Resolution precedence

    @Test func bundledLinkServesWhenNoOtherSource() {
        let store = AffiliateStore(defaults: freshDefaults(),
                                   bundledLinks: ["rosemary": "https://example.com/bundled"])
        #expect(store.url(for: "rosemary")?.absoluteString == "https://example.com/bundled")
        #expect(store.hasLink(for: "rosemary") == true)
    }

    @Test func nilWhenNoSourceKnowsTheProduct() {
        let store = AffiliateStore(defaults: freshDefaults(), bundledLinks: [:])
        #expect(store.url(for: "rosemary") == nil)
        #expect(store.hasLink(for: "rosemary") == false)
    }

    @Test func remoteCacheBeatsBundled() throws {
        let store = AffiliateStore(defaults: freshDefaults(),
                                   bundledLinks: ["rosemary": "https://example.com/bundled"])
        let accepted = store.ingestRemotePayload(
            try payloadData(links: ["rosemary": "https://example.com/remote"]))
        #expect(accepted)
        #expect(store.url(for: "rosemary")?.absoluteString == "https://example.com/remote")
    }

    @Test func debugOverrideBeatsRemoteAndBundled() throws {
        let store = AffiliateStore(defaults: freshDefaults(),
                                   bundledLinks: ["rosemary": "https://example.com/bundled"])
        store.ingestRemotePayload(try payloadData(links: ["rosemary": "https://example.com/remote"]))
        store.setDebugOverride("https://example.com/override", for: "rosemary")
        #expect(store.url(for: "rosemary")?.absoluteString == "https://example.com/override")

        // Clearing the override falls back to the next layer (remote), never to nothing.
        store.setDebugOverride("", for: "rosemary")
        #expect(store.url(for: "rosemary")?.absoluteString == "https://example.com/remote")
    }

    @Test func remoteFillsGapsBundledLeavesOpen() throws {
        // Remote wins per id, not wholesale: a product missing from the remote payload
        // still serves its bundled link.
        let store = AffiliateStore(defaults: freshDefaults(),
                                   bundledLinks: ["rosemary": "https://example.com/bundled-r",
                                                  "caffeine": "https://example.com/bundled-c"])
        store.ingestRemotePayload(try payloadData(links: ["rosemary": "https://example.com/remote-r"]))
        #expect(store.url(for: "rosemary")?.absoluteString == "https://example.com/remote-r")
        #expect(store.url(for: "caffeine")?.absoluteString == "https://example.com/bundled-c")
    }

    // MARK: - Remote payload validation

    @Test func rejectsPayloadWithWrongVersion() throws {
        let defaults = freshDefaults()
        let store = AffiliateStore(defaults: defaults,
                                   bundledLinks: ["rosemary": "https://example.com/bundled"])
        let accepted = store.ingestRemotePayload(
            try payloadData(version: 2, links: ["rosemary": "https://example.com/remote"]))
        #expect(accepted == false)
        // Nothing cached, bundled still serves.
        #expect(defaults.data(forKey: AffiliateStore.remoteCacheKey) == nil)
        #expect(store.url(for: "rosemary")?.absoluteString == "https://example.com/bundled")
    }

    @Test func rejectsMalformedPayload() {
        let store = AffiliateStore(defaults: freshDefaults(), bundledLinks: [:])
        #expect(store.ingestRemotePayload(Data("not json".utf8)) == false)
        #expect(store.ingestRemotePayload(Data("{\"links\":{}}".utf8)) == false) // missing version
    }

    // MARK: - Offline cache survival

    @Test func acceptedRemotePayloadSurvivesRelaunch() throws {
        let defaults = freshDefaults()
        let bundled = ["rosemary": "https://example.com/bundled"]
        AffiliateStore(defaults: defaults, bundledLinks: bundled)
            .ingestRemotePayload(try payloadData(links: ["rosemary": "https://example.com/remote"]))

        // A brand-new store over the same defaults (fresh launch, no network) reads the cache.
        let relaunched = AffiliateStore(defaults: defaults, bundledLinks: bundled)
        #expect(relaunched.url(for: "rosemary")?.absoluteString == "https://example.com/remote")
    }

    // MARK: - Hygiene

    @Test func blankAndWhitespaceLinksResolveToNil() throws {
        let store = AffiliateStore(defaults: freshDefaults(),
                                   bundledLinks: ["rosemary": "   "])
        #expect(store.hasLink(for: "rosemary") == false)
        store.ingestRemotePayload(try payloadData(links: ["rosemary": ""]))
        #expect(store.hasLink(for: "rosemary") == false)
    }

    @Test func userEnteredLegacyKeysAreIgnored() {
        // The old app let users paste links under affiliate.link.<id> — that layer is no
        // longer a source. Owner-shipped links only.
        let defaults = freshDefaults()
        defaults.set("https://example.com/user-pasted", forKey: "affiliate.link.rosemary")
        let store = AffiliateStore(defaults: defaults, bundledLinks: [:])
        #expect(store.url(for: "rosemary") == nil)
    }
}
