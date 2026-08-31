import Foundation

/// App-level info + the legal strings needed before App Store submission. The privacy/support URLs
/// are intentionally empty placeholders — fill them (the docs/ GitHub Pages site) before submitting;
/// empty means the link is simply hidden in-app rather than showing a broken button.
nonisolated enum AppInfo {
    /// The live site (GitHub Pages behind the custom domain — the old
    /// haribsub955-glitch.github.io URLs 301 here, so link the destination directly:
    /// no redirect hop for App Review to trip on). Verified 200 on 2026-08-31.
    static let privacyPolicyURLString = "https://haircompass-ai.com/privacy-policy.html"
    static let supportURLString = "https://haircompass-ai.com/"

    /// Apple's standard end-user licence (EULA) — used on the subscription paywall when you don't
    /// host a custom one. Swap for your own Terms URL if you write one.
    static let termsOfUseURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    static var termsOfUseURL: URL? { URL(string: termsOfUseURLString) }

    /// Where the in-app "Send feedback" button addresses its email. Change this to your support
    /// inbox. The app has no backend, so feedback is delivered straight to this address.
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
