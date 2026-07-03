import Foundation

/// Holds the affiliate link for each science product, on-device (UserDefaults). No link is ever in
/// the repo — the owner pastes them in the Manage-links screen whenever they want, and a product's
/// "View on iHerb" button only appears once its link is set. `revision` bumps on every change so
/// @Observable views re-read.
@MainActor
@Observable
final class AffiliateStore {
    private let prefix = "affiliate.link."
    private let defaults = UserDefaults.standard
    private(set) var revision = 0

    func link(for id: String) -> String? {
        let value = defaults.string(forKey: prefix + id)?.trimmingCharacters(in: .whitespaces)
        return (value?.isEmpty == false) ? value : nil
    }

    func url(for id: String) -> URL? {
        _ = revision // read so SwiftUI tracks changes
        guard let link = link(for: id) else { return nil }
        return URL(string: link)
    }

    func hasLink(for id: String) -> Bool { url(for: id) != nil }

    func setLink(_ value: String, for id: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: prefix + id)
        } else {
            defaults.set(trimmed, forKey: prefix + id)
        }
        revision += 1
    }

    var configuredCount: Int {
        _ = revision
        return ScienceCatalog.products.filter { hasLink(for: $0.id) }.count
    }
}
