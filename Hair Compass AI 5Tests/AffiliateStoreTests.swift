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

    @Test func acceptsKnownProductWithOrdinaryHTTPSURL() throws {
        let store = AffiliateStore(defaults: freshDefaults(), bundledLinks: [:])
        #expect(store.ingestRemotePayload(try payloadData(
            links: ["rosemary": "https://shop.example.com/products/rosemary?ref=hair"])))
    }

    @Test(arguments: [
        "http://example.com/product",
        "https://user:secret@example.com/product",
        "https:///missing-host",
        "https://.example.com/product",
        "https://example..com/product",
    ])
    func rejectsUnsafeOrMalformedLink(url: String) throws {
        let store = AffiliateStore(defaults: freshDefaults(), bundledLinks: [:])
        #expect(store.ingestRemotePayload(try payloadData(links: ["rosemary": url])) == false)
    }

    @Test func rejectsUnknownProductID() throws {
        let store = AffiliateStore(defaults: freshDefaults(), bundledLinks: [:])
        #expect(store.ingestRemotePayload(try payloadData(
            links: ["not-in-the-catalog": "https://example.com/product"])) == false)
    }

    @Test func rejectsOversizedPayloadAndTooManyLinks() throws {
        let store = AffiliateStore(defaults: freshDefaults(), bundledLinks: [:])
        let oversized = Data(repeating: 0x20, count: AffiliateStore.maximumPayloadBytes + 1)
        #expect(store.ingestRemotePayload(oversized) == false)

        var links: [String: String] = [:]
        for index in 0...AffiliateStore.maximumLinkCount {
            links["unknown-\(index)"] = "https://example.com/\(index)"
        }
        #expect(store.ingestRemotePayload(try payloadData(links: links)) == false)
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

    // MARK: - Disclosure and resolved-link count

    /// 16 CFR Part 255 requires a clear, conspicuous disclosure wherever an affiliate link is
    /// presented. Asserted here so the shop cannot ship without it.
    @Test func shopCarriesAnAffiliateDisclosure() {
        #expect(ShopView.affiliateDisclosure.isEmpty == false)
        #expect(ShopView.affiliateDisclosure.lowercased().contains("commission"))
    }

    /// Counts ids that resolve across the whole resolution order — asserted with injected
    /// fixtures so the counter's arithmetic is proven independently of whatever the shipped
    /// catalogue holds (that file has its own test below).
    @Test func resolvedLinkCountReflectsTheCatalogue() {
        let store = AffiliateStore(defaults: freshDefaults(), bundledLinks: [:])
        #expect(store.resolvedLinkCount == 0)

        let stocked = AffiliateStore(defaults: freshDefaults(),
                                     bundledLinks: ["minoxidil-topical-5": "https://example.com/a"])
        #expect(stocked.resolvedLinkCount == 1)
    }

    /// The promise `resolvedLinkCount` was built to keep: "the moment a catalogue lands, a test
    /// can prove the buy buttons actually appear." The catalogue landed on 2026-08-21 (untagged
    /// Amazon search links — brand-neutral, no Associates tag yet), so this test now reads the
    /// REAL bundled `AffiliateLinks.json` (the test host is the app, so `Bundle.main` is the app
    /// bundle) and proves every product in the shop resolves a link. If a product is ever added
    /// to `ScienceCatalog` without a link, this is the tripwire that says its buy button is
    /// silently missing.
    @Test func everyCatalogueProductResolvesABundledLink() {
        let store = AffiliateStore(defaults: freshDefaults())
        for product in ScienceCatalog.products {
            #expect(store.url(for: product.id) != nil,
                    "\(product.id) has no link in the bundled AffiliateLinks.json — its buy button will not render.")
        }
        #expect(store.resolvedLinkCount == ScienceCatalog.products.count)
    }

    // MARK: - Merchant labels

    /// The buy button names the merchant from the resolved link's own host, never from a
    /// hardcoded string — a hardcoded "View on iHerb" above Amazon links would name the wrong
    /// merchant directly beneath the disclosure promising honesty.
    @Test func merchantLabelFollowsTheLinkHost() {
        #expect(AffiliateStore.merchantLabel(for: URL(string: "https://www.amazon.com/s?k=rosemary")!) == "View on Amazon")
        #expect(AffiliateStore.merchantLabel(for: URL(string: "https://amazon.co.uk/s?k=rosemary")!) == "View on Amazon")
        #expect(AffiliateStore.merchantLabel(for: URL(string: "https://www.iherb.com/search?kw=rosemary")!) == "View on iHerb")
        // Unknown merchants get a neutral label, not a guessed name.
        #expect(AffiliateStore.merchantLabel(for: URL(string: "https://example-shop.com/x")!) == "View product")
    }

    /// Every shipped link is an Amazon search link today, so every rendered button should read
    /// "View on Amazon" — the label the old hardcode got wrong.
    @Test func everyBundledLinkLabelsAsAmazon() {
        let store = AffiliateStore(defaults: freshDefaults())
        for product in ScienceCatalog.products {
            guard let url = store.url(for: product.id) else { continue } // covered above
            #expect(AffiliateStore.merchantLabel(for: url) == "View on Amazon")
        }
    }
}
