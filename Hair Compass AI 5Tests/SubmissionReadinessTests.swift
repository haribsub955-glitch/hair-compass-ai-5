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

    /// This used to assert the URLs were *not* on `haribsub955-glitch.github.io`, because that host
    /// had never resolved: the repo was private and Pages was never enabled, so shipping it would
    /// have put a dead link on the subscription paywall (`PaywallLegal`) — a Guideline 3.1.2
    /// rejection.
    ///
    /// That premise no longer holds. On 2026-08-21 the repo was made public and Pages was enabled
    /// from `/docs` on the default branch, and both URLs were verified serving HTTP 200 with the
    /// right documents ("Hair Compass AI Privacy Policy" and the support index). The host is now the
    /// real home of the pages, so asserting *against* it would fail the app for being correct.
    ///
    /// What still matters is the shape of the links, which is what a unit test can actually prove:
    /// present, HTTPS, and pointing at a concrete document rather than a bare host. Do not "fix" a
    /// failure here by emptying the strings — an empty URL hides the link entirely, and App Review
    /// requires a reachable privacy policy link on any auto-renewable paywall.
    ///
    /// If the pages ever move, re-verify the new URLs resolve by hand; no test here makes network
    /// calls, so a 404 would once again be invisible until Apple finds it.
    @Test func privacyAndSupportURLsAreRealBeforeSubmission() {
        let privacy = AppInfo.privacyPolicyURL
        let support = AppInfo.supportURL

        #expect(privacy != nil, "App Store Connect requires a privacy policy URL, and PaywallLegal links it.")
        #expect(support != nil, "App Store Connect requires a support URL.")

        // A bare host is almost always a placeholder; the policy has to be an actual page.
        #expect(
            (privacy?.path().count ?? 0) > 1,
            "The privacy policy URL must point at a document, not just a hostname."
        )
        #expect(privacy?.host()?.contains(".") == true, "The privacy policy URL needs a real host.")
        #expect(support?.host()?.contains(".") == true, "The support URL needs a real host.")
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

/// Pro always sells — on every iPhone. Two of its twelve features run on Apple Intelligence with
/// no cloud fallback, and the rule that keeps only those two honest lives in `ProAvailability`.
struct ProAvailabilityTests {

    /// The commercial correctness of the whole paywall. Before this, an ineligible iPhone was
    /// offered nothing at all — a mostly-locked app with no button to unlock it, which is both a
    /// Guideline 3.1.2 risk and a dead end for the person holding the phone.
    @Test func proSellsOnHardwareThatCannotRunAppleIntelligence() {
        for feature in ProFeature.allCases where !feature.requiresAppleIntelligence {
            #expect(ProAvailability.canRun(feature, status: .deviceNotEligible),
                    "\(feature) has no on-device model dependency and must work on any iPhone.")
        }
    }

    /// The other half of that fix, and the one nothing asserted: `canRun` deciding what RUNS is
    /// only half the policy — what SELLS must not consult Apple Intelligence at all. Both purchase
    /// surfaces (`ProGate.locked`, `OnboardingPlanStep.footer`) route their buttons through this
    /// function, so re-introducing a sellability check would have to fail here or bypass the
    /// function outright.
    @Test func purchaseButtonsAreUnconditionalOnAppleIntelligence() {
        for status: OnDeviceAvailability in [.available, .notEnabled, .modelNotReady, .deviceNotEligible] {
            #expect(ProAvailability.showsPurchaseButtons(status: status, hasLoadedProducts: true),
                    "\(status) must still be able to buy Pro — ten of the twelve features run here.")
        }
    }

    /// The one honest reason to withhold them: no real prices to show. Never a placeholder price,
    /// never a device capability.
    @Test func purchaseButtonsWaitOnlyForRealPrices() {
        for status: OnDeviceAvailability in [.available, .notEnabled, .modelNotReady, .deviceNotEligible] {
            #expect(ProAvailability.showsPurchaseButtons(status: status, hasLoadedProducts: false) == false)
        }
    }

    /// `ProGate` asks this exact question to decide whether to show `ProAvailabilityNotice`, so
    /// the shipping path and the asserted path are now the same function.
    @Test func onlyTheAIFeaturesDiscloseAnAppleIntelligenceRequirement() {
        for feature in ProFeature.allCases {
            #expect(ProAvailability.canRun(feature, status: .deviceNotEligible) == !feature.requiresAppleIntelligence)
        }
    }

    @Test func theTwoAIFeaturesCannotRunOnIneligibleHardware() {
        #expect(ProAvailability.canRun(.askWren, status: .deviceNotEligible) == false)
        #expect(ProAvailability.canRun(.deepAnalysis, status: .deviceNotEligible) == false)
    }

    /// A switched-off or still-downloading model is something the person can fix themselves, so
    /// those states stay runnable-once-fixed and the notice tells them how.
    @Test func fixableStatesStillCountAsRunnable() {
        for status in [OnDeviceAvailability.available, .notEnabled, .modelNotReady] {
            #expect(ProAvailability.canRun(.askWren, status: status))
        }
    }

    @Test func everyUnavailableReasonExplainsItselfOnThePaywall() {
        for status: OnDeviceAvailability in [.notEnabled, .modelNotReady, .deviceNotEligible] {
            #expect(!ProAvailability.message(for: status).isEmpty)
        }
        #expect(ProAvailability.message(for: .available).isEmpty)
    }

    /// The ineligible-hardware copy's job flipped along with `canRun`'s scope: it must name the
    /// two features that won't run here, but it must NOT say Pro is worthless on this iPhone —
    /// that claim sits directly above live purchase buttons for the other ten features, so it
    /// would be false on the very screen asking for money.
    @Test func ineligibleCopyNamesTheTwoFeaturesWithoutDismissingTheSubscription() {
        let message = ProAvailability.message(for: .deviceNotEligible)
        #expect(message.contains("Apple Intelligence"))
        #expect(message.contains("Ask Wren"))
        #expect(message.contains("Deep analysis"))
        #expect(!message.lowercased().contains("pro wouldn't work"))
    }
}
