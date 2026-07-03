import Foundation

/// App-level info + the legal strings needed before App Store submission. The privacy/support URLs
/// are intentionally empty placeholders — fill them (the docs/ GitHub Pages site) before submitting;
/// empty means the link is simply hidden in-app rather than showing a broken button.
enum AppInfo {
    /// TODO before submission: set to the live privacy policy / support URLs.
    static let privacyPolicyURLString = ""
    static let supportURLString = ""

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
