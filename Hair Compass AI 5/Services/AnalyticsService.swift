import Foundation
import os

enum AnalyticsService {
    private static let logger = Logger(subsystem: "com.harib.HairCompassAI5", category: "analytics")
    private static let defaults = UserDefaults.standard
    private static let eventCountPrefix = "analytics.event.count."
    private static let eventLastAtPrefix = "analytics.event.lastAt."
    private static let propertyPrefix = "analytics.event.property."

    static func log(_ name: String, properties: [String: String] = [:]) {
        let sanitizedName = sanitize(name)
        let countKey = eventCountPrefix + sanitizedName
        let lastAtKey = eventLastAtPrefix + sanitizedName

        let currentCount = defaults.integer(forKey: countKey)
        defaults.set(currentCount + 1, forKey: countKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastAtKey)

        if !properties.isEmpty {
            for (key, value) in properties {
                defaults.set(value, forKey: propertyPrefix + sanitizedName + "." + sanitize(key))
            }
        }

        if properties.isEmpty {
            logger.log("event=\(sanitizedName, privacy: .public)")
        } else {
            let propertySummary = properties
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            logger.log("event=\(sanitizedName, privacy: .public) properties=\(propertySummary, privacy: .public)")
        }
    }

    private static func sanitize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}
