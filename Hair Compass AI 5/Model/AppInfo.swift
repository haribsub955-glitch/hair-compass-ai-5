import Foundation

/// App-level info + the legal strings needed before App Store submission.
nonisolated enum AppInfo {
    /// The docs/ GitHub Pages site on its custom domain, live since 2026-08-21: haircompass-ai.com
    /// (Namecheap) fronts the same Pages deployment, with HTTPS enforced and the old
    /// haribsub955-glitch.github.io URLs 301-redirecting here. Pages serves whatever is on the
    /// **default branch** — editing `docs/` on a feature branch changes nothing publicly until it
    /// merges. If either URL ever 404s, the app shows a broken link on the paywall and nothing in
    /// the app or test suite will notice.
    static let privacyPolicyURLString = "https://haircompass-ai.com/privacy-policy.html"
    static let supportURLString = "https://haircompass-ai.com/support.html"

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
