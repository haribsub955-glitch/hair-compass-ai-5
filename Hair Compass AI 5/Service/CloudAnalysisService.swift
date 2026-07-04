import Foundation
import UIKit

/// Opt-in cloud "deep analysis" via the Claude Messages API (`claude-fable-5`, the most capable
/// model). Off-device and per-request only — the caller must show consent before invoking it.
///
/// Swift has no official Anthropic SDK, so this is a raw HTTPS call. Fable specifics handled here:
/// no `thinking`/`temperature` params (they 400), `stop_reason == "refusal"` is checked before
/// reading content, and a server-side fallback to `claude-opus-4-8` is requested by default.
@MainActor
@Observable
final class CloudAnalysisService {
    private(set) var isRunning = false
    private(set) var result: String?
    private(set) var errorMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when an API key is configured (env var → UserDefaults; never committed to the repo).
    var hasKey: Bool { AIConfig.claudeKey?.isEmpty == false }

    struct AnalysisError: Error { let message: String }

    func analyze(context: InsightContext, images: [UIImage]) async {
        isRunning = true
        result = nil
        errorMessage = nil
        defer { isRunning = false }
        do {
            result = try await request(context: context, images: images)
        } catch let e as AnalysisError {
            errorMessage = e.message
        } catch {
            errorMessage = "Couldn't reach the analysis service. Check your connection and try again."
        }
    }

    // MARK: - Request

    private func request(context: InsightContext, images: [UIImage]) async throws -> String {
        // Belt and braces: no code path may send photos off-device without explicit consent.
        // The UI gates the entry point (AIConsentSheet); this is the last line of defense.
        guard AIConsent.isGranted(defaults) else {
            throw AnalysisError(message: "Deep analysis is off: sending photos off-device needs your consent first. You'll be asked when you start a deep analysis, and you can manage it in your profile's Privacy section.")
        }
        guard let key = AIConfig.claudeKey, !key.isEmpty else {
            throw AnalysisError(message: "No API key configured. Deep analysis needs a Claude API key (set OPENAI/ANTHROPIC key in the run scheme).")
        }

        var content: [[String: Any]] = [[
            "type": "text",
            "text": prompt(context: context, imageCount: images.count)
        ]]
        for image in images.prefix(4) {
            if let b64 = Self.downscaledJPEGBase64(image) {
                content.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]
                ])
            }
        }

        let body: [String: Any] = [
            "model": "claude-fable-5",
            "max_tokens": 1024,
            "fallbacks": [["model": "claude-opus-4-8"]],
            "messages": [["role": "user", "content": content]]
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-06-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AnalysisError(message: "Unexpected response from the analysis service.")
        }
        guard (200...299).contains(http.statusCode) else {
            let apiMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
            throw AnalysisError(message: apiMessage ?? "Analysis failed (HTTP \(http.statusCode)).")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalysisError(message: "Couldn't read the analysis response.")
        }

        // Fable can decline benign requests via safety classifiers — handle before reading content.
        if let stop = json["stop_reason"] as? String, stop == "refusal" {
            throw AnalysisError(message: "The model declined to analyze this request. Try again with different photos or notes.")
        }

        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AnalysisError(message: "The analysis came back empty. Please try again.")
        }
        return text
    }

    private func prompt(context: InsightContext, imageCount: Int) -> String {
        let photoNote = imageCount > 0
            ? "\n\nAttached are \(imageCount) progress photo(s) taken under matched conditions. Describe visible change between them in plain, non-diagnostic terms (density, coverage, hairline). Do not diagnose."
            : ""
        return """
        You are helping someone keep records of their hair. This is documentation, NOT diagnosis, and you must not diagnose or name a condition they didn't state. Only discuss whether a treatment is 'working' if it is past its 24-week judging point. Ground everything in the facts below and the attached photos; do not invent numbers. Write a short, warm, plainly-worded summary (about 4–6 sentences) that prioritizes what matters most and notes honest uncertainty. End with one gentle, evidence-aligned suggestion.

        Facts:
        \(RuleBasedInsight.facts(context))\(photoNote)
        """
    }

    // MARK: - Image helpers

    /// Downscale to a sane long edge and JPEG-encode to base64 — keeps the request small and fast.
    static func downscaledJPEGBase64(_ image: UIImage, maxEdge: CGFloat = 1024, quality: CGFloat = 0.7) -> String? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}

/// One-time, revocable consent for sending scalp photos (and the tracking summary) off-device to
/// the cloud AI provider. Granted in plain language via `AIConsentSheet` before the first deep
/// analysis; revocable from the profile's Privacy section. `CloudAnalysisService` refuses to send
/// anything while this is false.
enum AIConsent {
    static let grantedKey = "aiConsentGranted"
    static let dateKey = "aiConsentDate"

    static func isGranted(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: grantedKey)
    }

    /// When consent was given, for the Privacy section's status line.
    static func grantedDate(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: dateKey) as? Date
    }

    static func grant(_ defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(true, forKey: grantedKey)
        defaults.set(now, forKey: dateKey)
    }

    /// Revoking means the next deep-analysis tap re-asks in plain language.
    static func revoke(_ defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: grantedKey)
        defaults.removeObject(forKey: dateKey)
    }
}

/// Where the Claude API key lives. Seeded once from an environment variable at launch and stored
/// in UserDefaults — there is never a key in the repo.
enum AIConfig {
    static let keyDefaultsKey = "claudeAPIKey"

    static var claudeKey: String? {
        UserDefaults.standard.string(forKey: keyDefaultsKey)
    }

    /// Copy a launch-provided key into UserDefaults if we don't already have one.
    static func seedKeyIfProvided() {
        guard UserDefaults.standard.string(forKey: keyDefaultsKey) == nil else { return }
        let env = ProcessInfo.processInfo.environment
        if let key = env["ANTHROPIC_API_KEY"] ?? env["CLAUDE_API_KEY"], !key.isEmpty {
            UserDefaults.standard.set(key, forKey: keyDefaultsKey)
        }
    }
}
