import Foundation
import StoreKit

/// The single egress for the app's cloud AI (Claude Messages). Routes through the **owner's proxy**
/// — which holds the API key server-side and verifies the App Store subscription before spending —
/// whenever `AIConfig.proxyURL` is set. Otherwise it posts directly to Anthropic with a
/// launch-provided dev key (local testing only; never shipped). The proxy path attaches the
/// StoreKit 2 entitlement JWS so the server can confirm Pro without the key ever touching the app.
enum AIGateway {
    struct GatewayError: Error { let message: String }

    /// True when the app can reach a cloud model at all — a proxy URL or a dev key is configured.
    static var isConfigured: Bool {
        AIConfig.proxyURL != nil || (AIConfig.claudeKey?.isEmpty == false)
    }

    /// POST a Claude Messages `body`; returns the parsed top-level JSON or throws a `GatewayError`
    /// with a user-facing message. Shared by deep analysis, ingredient ID, and (cloud) chat.
    static func postMessages(_ body: [String: Any]) async throws -> [String: Any] {
        let payload = try JSONSerialization.data(withJSONObject: body)

        var req: URLRequest
        if let proxy = AIConfig.proxyURL {
            req = URLRequest(url: proxy)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // The proxy verifies this and adds the API key + Anthropic headers itself.
            if let jws = await currentEntitlementJWS() {
                req.setValue(jws, forHTTPHeaderField: "X-Subscription")
            }
        } else if let key = AIConfig.claudeKey, !key.isEmpty {
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("server-side-fallback-2026-06-01", forHTTPHeaderField: "anthropic-beta")
        } else {
            throw GatewayError(message: "AI isn't configured for this build.")
        }
        req.httpMethod = "POST"
        req.httpBody = payload
        req.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError(message: "Unexpected response from the analysis service.")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 402 || http.statusCode == 403 {
                throw GatewayError(message: "This is a Pro feature — we couldn't verify your subscription. If you just subscribed, try Restore Purchases.")
            }
            let apiMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            throw GatewayError(message: apiMessage ?? "The request failed (HTTP \(http.statusCode)).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GatewayError(message: "Couldn't read the response.")
        }
        return json
    }

    /// The signed JWS for the current Pro entitlement (StoreKit 2) — what the proxy verifies against
    /// Apple before spending. nil when there is no active Pro entitlement.
    private static func currentEntitlementJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == PurchaseService.monthlyID
                    || transaction.productID == PurchaseService.yearlyID,
                  transaction.revocationDate == nil else { continue }
            return result.jwsRepresentation
        }
        return nil
    }
}
