//
//  SubmissionReadinessTests.swift
//  Hair Compass AI 5Tests
//
//  Tripwires for the pre-submission config that is invisible at runtime until Apple rejects it.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

/// Submission blockers that no other test would notice, because the app *builds and runs* perfectly
/// with them wrong. The classic failure mode is a privacy-policy URL that 404s: nothing crashes,
/// nothing looks broken in the simulator, and the rejection arrives days later.
///
/// These are deliberately red until the real values are in. A failing test here means "not ready to
/// submit", which is exactly what it should mean.
struct SubmissionReadinessTests {

    /// The GitHub Pages URL that was baked in as a placeholder. It has never resolved — the repo is
    /// private and Pages was never enabled — so shipping it would put a dead link on the
    /// subscription paywall (`PaywallLegal`), which is a Guideline 3.1.2 rejection.
    ///
    /// Replace both strings in `AppInfo` with wherever the pages are actually hosted, then this
    /// passes. Do not "fix" it by emptying the strings: an empty URL hides the link entirely, and
    /// App Review requires a reachable privacy policy link on any auto-renewable paywall.
    private static let deadPlaceholderHost = "haribsub955-glitch.github.io"

    @Test func privacyAndSupportURLsAreRealBeforeSubmission() {
        let privacy = AppInfo.privacyPolicyURL
        let support = AppInfo.supportURL

        #expect(privacy != nil, "App Store Connect requires a privacy policy URL, and PaywallLegal links it.")
        #expect(support != nil, "App Store Connect requires a support URL.")

        #expect(
            privacy?.host() != Self.deadPlaceholderHost,
            "AppInfo.privacyPolicyURLString still points at the placeholder GitHub Pages site, which does not resolve."
        )
        #expect(
            support?.host() != Self.deadPlaceholderHost,
            "AppInfo.supportURLString still points at the placeholder GitHub Pages site, which does not resolve."
        )
    }

    /// Both must be HTTPS — App Review rejects plain-HTTP legal links, and `Link` would happily
    /// render one.
    @Test func legalURLsAreHTTPS() {
        #expect(AppInfo.privacyPolicyURL?.scheme == "https")
        #expect(AppInfo.supportURL?.scheme == "https")
        #expect(AppInfo.termsOfUseURL?.scheme == "https")
    }

    /// The paywall's Terms link is Apple's standard EULA. It's a real, permanent Apple URL, so this
    /// only guards against it being blanked or mistyped.
    @Test func termsOfUsePointsAtAStandardEULA() {
        #expect(AppInfo.termsOfUseURL != nil)
        #expect(AppInfo.termsOfUseURLString.contains("apple.com"))
    }

    /// Feedback has no backend behind it — it opens a mail composer — so a malformed address fails
    /// silently for the user and invisibly for us.
    @Test func feedbackAddressIsAPlausibleEmail() {
        let email = AppInfo.feedbackEmail
        #expect(email.contains("@"))
        #expect(!email.hasPrefix("@"))
        #expect(!email.hasSuffix("@"))
        #expect(!email.contains(" "))
    }
}

/// Since 1.1, Pro carries device-independent value (check-ins, trends, labs, photos) alongside
/// the two Apple Intelligence features, so it is sold on every device; `ProAvailability`'s job
/// narrowed to disclosing the AI hardware bound honestly on the paywall.
struct ProAvailabilityTests {

    /// Pro now delivers real value on every iPhone, so no hardware status withdraws the sale.
    /// If Pro ever becomes AI-only again, this must flip back to refusing `.deviceNotEligible`.
    @Test func everyDeviceIsSoldPro() {
        #expect(ProAvailability.sellable(.deviceNotEligible))
        #expect(ProAvailability.sellable(.notEnabled))
        #expect(ProAvailability.sellable(.modelNotReady))
        #expect(ProAvailability.sellable(.available))
    }

    @Test func everyUnavailableReasonExplainsItselfOnThePaywall() {
        for status: OnDeviceAvailability in [.notEnabled, .modelNotReady, .deviceNotEligible] {
            #expect(!ProAvailability.message(for: status).isEmpty)
        }
        #expect(ProAvailability.message(for: .available).isEmpty)
    }

    /// The ineligible-hardware copy has one job now: name the AI hardware requirement, and say
    /// that the rest of Pro still works on this iPhone. Losing either half misleads a buyer.
    @Test func ineligibleCopyNamesTheRequirementAndWhatStillWorks() {
        let message = ProAvailability.message(for: .deviceNotEligible)
        #expect(message.contains("Apple Intelligence"))
        #expect(message.contains("iPhone 15"))
        #expect(message.lowercased().contains("everything else in pro works"))
    }
}
