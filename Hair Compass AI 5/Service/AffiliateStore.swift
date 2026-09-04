import Foundation

/// Owner-controlled affiliate links. Users never enter links: they ship inside the app bundle
/// (`Resources/AffiliateLinks.json`) and the owner can update them over the air by hosting the
/// same JSON shape at `RemoteConfig.catalogURLString`. A fetched payload is cached in
/// UserDefaults so remote links keep serving offline.
///
/// Resolution order per product id:
///   1. DEBUG owner override (`affiliate.debugOverride.<id>`, debug builds only)
///   2. cached remote payload (`affiliate.remoteCache`) — only while a remote catalog is configured
///   3. bundled AffiliateLinks.json
///   4. nil → the product's buy button stays hidden
///
/// `revision` bumps on every change so @Observable views re-read.
@MainActor
@Observable
final class AffiliateStore {

    /// Where the owner hosts the remote catalog. Empty string = remote refresh disabled
    /// (bundled links still serve). The endpoint must return the same JSON shape as the
    /// bundled file: `{"version": 1, "updatedAt": "…", "links": {"<productID>": "https://…"}}`.
    ///
    /// **Deliberately empty on the managed-links model.** The bundled links point at the owner's
    /// own redirect host, so the destination is edited at the DNS provider rather than fetched —
    /// which is what makes the buy buttons independent of any server of ours, this app's AI
    /// backend included. Setting a URL here re-enables the fetch; it is not needed for links to
    /// be remotely editable.
    struct RemoteConfig {
        static var catalogURLString = ""

        /// True only while an owner-hosted catalog is configured. Gates BOTH the network refresh
        /// and the rehydration of a previously cached payload.
        static var isEnabled: Bool { !catalogURLString.isEmpty }
    }

    /// The one JSON shape used by both the bundled file and the remote catalog.
    struct Payload: Codable {
        let version: Int
        let updatedAt: String?
        let links: [String: String]
    }

    static let supportedVersion = 1
    static let maximumPayloadBytes = 64 * 1024
    static let maximumLinkCount = 32
    static let remoteCacheKey = "affiliate.remoteCache"
    #if DEBUG
    static let debugOverridePrefix = "affiliate.debugOverride."
    #endif

    private let defaults: UserDefaults
    private let bundledLinks: [String: String]
    private var remoteLinks: [String: String]
    private(set) var revision = 0

    /// `defaults`, `bundledLinks` and `remoteCatalogEnabled` are injectable for tests;
    /// production uses `.standard`, the JSON shipped in the app bundle, and whether a catalog
    /// URL is configured.
    init(defaults: UserDefaults = .standard,
         bundledLinks: [String: String]? = nil,
         remoteCatalogEnabled: Bool = RemoteConfig.isEnabled) {
        self.defaults = defaults
        self.bundledLinks = bundledLinks ?? Self.loadBundledLinks()
        if remoteCatalogEnabled {
            self.remoteLinks = Self.decodeLinks(from: defaults.data(forKey: Self.remoteCacheKey)) ?? [:]
            // Kick off an over-the-air refresh at construction.
            Task { await self.refresh() }
        } else {
            // A catalog that was configured in an EARLIER build leaves its payload in
            // UserDefaults, and the cache outranks the bundled links — so a device that once
            // fetched a legacy catalog would keep serving those destinations forever, silently
            // bypassing the managed redirect links this build ships. Nothing can refresh or
            // correct it, because `refresh()` no-ops without a URL. Drop the row rather than
            // merely ignoring it: an ignored row comes back the day a catalog is configured
            // again, carrying links nobody has looked at in months.
            self.remoteLinks = [:]
            defaults.removeObject(forKey: Self.remoteCacheKey)
        }
    }

    // MARK: - Resolution

    func link(for id: String) -> String? {
        #if DEBUG
        if let override = normalized(defaults.string(forKey: Self.debugOverridePrefix + id)) {
            return override
        }
        #endif
        if let remote = normalized(remoteLinks[id]) { return remote }
        return normalized(bundledLinks[id])
    }

    func url(for id: String) -> URL? {
        _ = revision // read so SwiftUI tracks changes
        guard let link = link(for: id) else { return nil }
        return URL(string: link)
    }

    func hasLink(for id: String) -> Bool { url(for: id) != nil }

    var configuredCount: Int {
        _ = revision
        return ScienceCatalog.products.filter { hasLink(for: $0.id) }.count
    }

    // MARK: - Remote refresh

    /// Fetches the owner's remote catalog if a URL is configured. Failures are silent by
    /// design — the bundled links (and any previously cached remote payload) keep serving.
    func refresh() async {
        guard !RemoteConfig.catalogURLString.isEmpty,
              let url = Self.validHTTPSURL(RemoteConfig.catalogURLString) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return }
            ingestRemotePayload(data)
        } catch {
            // Offline / DNS / TLS — say nothing, serve bundled + cached links.
        }
    }

    /// Validates a remote payload and, when accepted, caches the raw data in UserDefaults so
    /// the links survive offline and app relaunches. Rejects anything whose `version` isn't
    /// `supportedVersion`. Returns whether the payload was accepted. Internal so tests can
    /// exercise validation without a network. Remote data is deliberately small and owner-only:
    /// unknown products and unsafe/non-HTTPS destinations reject the complete payload.
    @discardableResult
    func ingestRemotePayload(_ data: Data) -> Bool {
        guard let links = Self.decodeLinks(from: data) else { return false }
        defaults.set(data, forKey: Self.remoteCacheKey)
        remoteLinks = links
        revision += 1
        return true
    }

    // MARK: - DEBUG owner overrides

    #if DEBUG
    /// Owner tool (debug builds only): a per-product override that beats every other source.
    /// Lives under its own key namespace so it can never leak into release resolution.
    func setDebugOverride(_ value: String, for id: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.debugOverridePrefix + id)
        } else {
            defaults.set(trimmed, forKey: Self.debugOverridePrefix + id)
        }
        revision += 1
    }

    func debugOverride(for id: String) -> String? {
        normalized(defaults.string(forKey: Self.debugOverridePrefix + id))
    }
    #endif

    // MARK: - Helpers

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static func decodeLinks(from data: Data?) -> [String: String]? {
        guard let data, data.count <= maximumPayloadBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == supportedVersion,
              payload.links.count <= maximumLinkCount else { return nil }
        let knownIDs = Set(ScienceCatalog.products.map(\.id))
        guard payload.links.keys.allSatisfy(knownIDs.contains),
              payload.links.values.allSatisfy({ validHTTPSURL($0) != nil }) else { return nil }
        return payload.links
    }

    /// Accept only ordinary HTTPS web URLs with a syntactically usable host and no embedded
    /// credentials. Fragments and paths are fine; an empty/whitespace link is not.
    nonisolated static func validHTTPSURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let host = components.host, !host.isEmpty,
              !host.hasPrefix("."), !host.hasSuffix("."), !host.contains(".."),
              host.unicodeScalars.allSatisfy({ CharacterSet.urlHostAllowed.contains($0) }) else { return nil }
        components.scheme = "https"
        return components.url
    }

    private static func loadBundledLinks() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "AffiliateLinks", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return decodeLinks(from: data) ?? [:]
    }
}
