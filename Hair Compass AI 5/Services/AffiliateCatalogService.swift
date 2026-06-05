import Combine
import Foundation

enum AffiliateProductCategory: String, Codable, CaseIterable {
    case supplement
    case hairCare
}

struct AffiliateProduct: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: AffiliateProductCategory
    let merchant: String
    let primaryURL: String
    let backupURL: String?
    let imageURL: String?
    let affiliateDisclosure: String
    let isActive: Bool
    let priority: Int
    let lastUpdated: String

    var resolvedURL: URL? {
        if let primary = URL(string: primaryURL), !primaryURL.isEmpty {
            return primary
        }
        guard let backupURL, let backup = URL(string: backupURL), !backupURL.isEmpty else { return nil }
        return backup
    }
}

@MainActor
final class AffiliateCatalogStore: ObservableObject {
    struct Configuration {
        static let bundledFileName = "AffiliateProducts"

        // Replace this with your own hosted JSON endpoint when ready.
        static let remoteCatalogURLString = ""

        static let refreshInterval: TimeInterval = 60 * 60 * 24
    }

    @Published private(set) var products: [AffiliateProduct] = []
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var errorMessage = ""

    private let userDefaults = UserDefaults.standard
    private let cacheKey = "affiliateCatalogCache"
    private let refreshDateKey = "affiliateCatalogLastRefreshDate"
    private var hasStarted = false

    func start() async {
        guard !hasStarted else {
            await refreshIfNeeded()
            return
        }

        hasStarted = true
        loadBundledFallback()
        loadCachedCatalog()
        await refreshIfNeeded()
    }

    func refreshIfNeeded(force: Bool = false) async {
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < Configuration.refreshInterval {
            return
        }

        guard let remoteURL = remoteCatalogURL else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let decoded = try JSONDecoder().decode([AffiliateProduct].self, from: data)
            apply(decoded)
            cache(data: data)
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func products(for category: AffiliateProductCategory) -> [AffiliateProduct] {
        products
            .filter { $0.category == category && $0.isActive && $0.resolvedURL != nil }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.title < rhs.title
                }
                return lhs.priority > rhs.priority
            }
    }

    private var remoteCatalogURL: URL? {
        guard !Configuration.remoteCatalogURLString.isEmpty else { return nil }
        return URL(string: Configuration.remoteCatalogURLString)
    }

    private func loadBundledFallback() {
        guard
            let url = Bundle.main.url(forResource: Configuration.bundledFileName, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([AffiliateProduct].self, from: data)
        else {
            return
        }

        apply(decoded, persistRefreshDate: false)
    }

    private func loadCachedCatalog() {
        guard
            let data = userDefaults.data(forKey: cacheKey),
            let decoded = try? JSONDecoder().decode([AffiliateProduct].self, from: data)
        else {
            lastRefreshDate = userDefaults.object(forKey: refreshDateKey) as? Date
            return
        }

        apply(decoded, persistRefreshDate: false)
        lastRefreshDate = userDefaults.object(forKey: refreshDateKey) as? Date
    }

    private func cache(data: Data) {
        userDefaults.set(data, forKey: cacheKey)
        let now = Date()
        userDefaults.set(now, forKey: refreshDateKey)
        lastRefreshDate = now
    }

    private func apply(_ products: [AffiliateProduct], persistRefreshDate: Bool = true) {
        self.products = products
        if persistRefreshDate, lastRefreshDate == nil {
            lastRefreshDate = Date()
        }
    }
}
