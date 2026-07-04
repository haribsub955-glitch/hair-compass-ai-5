import Foundation

/// Owner-controlled affiliate links. Users never enter links: they ship inside the app bundle
/// (`Resources/AffiliateLinks.json`) and the owner can update them over the air by hosting the
/// same JSON shape at `RemoteConfig.catalogURLString`. A fetched payload is cached in
/// UserDefaults so remote links keep serving offline.
///
/// Resolution order per product id:
///   1. DEBUG owner override (`affiliate.debugOverride.<id>`, debug builds only)
///   2. cached remote payload (`affiliate.remoteCache`)
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
    struct RemoteConfig {
        static var catalogURLString = ""
    }

    /// The one JSON shape used by both the bundled file and the remote catalog.
    struct Payload: Codable {
        let version: Int
        let updatedAt: String?
        let links: [String: String]
    }

    static let supportedVersion = 1
    static let remoteCacheKey = "affiliate.remoteCache"
    #if DEBUG
    static let debugOverridePrefix = "affiliate.debugOverride."
    #endif

    private let defaults: UserDefaults
    private let bundledLinks: [String: String]
    private var remoteLinks: [String: String]
    private(set) var revision = 0

    /// `defaults` and `bundledLinks` are injectable for tests; production uses `.standard`
    /// and the JSON shipped in the app bundle.
    init(defaults: UserDefaults = .standard, bundledLinks: [String: String]? = nil) {
        self.defaults = defaults
        self.bundledLinks = bundledLinks ?? Self.loadBundledLinks()
        self.remoteLinks = Self.decodeLinks(from: defaults.data(forKey: Self.remoteCacheKey)) ?? [:]
        // Kick off an over-the-air refresh at construction; a no-op while the URL is unset.
        if !RemoteConfig.catalogURLString.isEmpty {
            Task { await self.refresh() }
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
              let url = URL(string: RemoteConfig.catalogURLString) else { return }
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
    /// exercise validation without a network.
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
        guard let data,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == supportedVersion else { return nil }
        return payload.links
    }

    private static func loadBundledLinks() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "AffiliateLinks", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return decodeLinks(from: data) ?? [:]
    }
}
