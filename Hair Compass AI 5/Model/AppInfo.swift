import Foundation

/// App-level info and public legal/support destinations. Release checks must verify these
/// pages remain reachable and match the build's actual data flows, not just that URLs parse.
nonisolated enum AppInfo {
    /// Production custom domain; HTTPS reachability verified in the September release audit.
    static let privacyPolicyURLString = "https://haircompass-ai.com/privacy-policy.html"
    static let supportURLString = "https://haircompass-ai.com/"

    /// Apple's standard end-user licence (EULA) — used on the subscription paywall when you don't
    /// host a custom one. Swap for your own Terms URL if you write one.
    static let termsOfUseURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    static var termsOfUseURL: URL? { URL(string: termsOfUseURLString) }

    /// Where the in-app "Send feedback" button addresses its email. Change this to your support
    /// inbox. Feedback itself has no backend — it's delivered straight to this address — though
    /// AI answers elsewhere in the app may use the opt-in cloud model.
    static let feedbackEmail = "harib.alazri@gmail.com"

    static var privacyPolicyURL: URL? {
        privacyPolicyURLString.isEmpty ? nil : URL(string: privacyPolicyURLString)
    }
    static var supportURL: URL? {
        supportURLString.isEmpty ? nil : URL(string: supportURLString)
    }

    static let medicalDisclaimer = "Hair Compass is a documentation and education tool — not a medical device. It does not diagnose or treat. Always consult a qualified clinician about your hair and health."

    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
