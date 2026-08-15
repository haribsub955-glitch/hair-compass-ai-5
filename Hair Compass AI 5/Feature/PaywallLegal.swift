import SwiftUI

/// The legal footer App Review requires on any auto-renewable-subscription paywall: the renewal
/// disclosure plus **functional** links to the Terms of Use (EULA) and the Privacy Policy. Shared
/// by the onboarding paywall and the in-app `ProGate` upsell so both stay compliant.
struct PaywallLegal: View {
    /// The subscription always sells now, so both callers pass `true`. The parameter stays
    /// rather than becoming a constant: a screen that genuinely offers nothing purchasable would
    /// still need to say so without a renewal disclosure, and this is where that switch lives.
    /// The Terms and Privacy links stay either way — they're useful, and restore is still on screen.
    var showsRenewalDisclosure: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            if showsRenewalDisclosure {
                Text("Auto-renews until cancelled. Manage or cancel anytime in Settings.")
                    .font(Clinical.caption(10))
                    .foregroundStyle(Clinical.tertiary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 14) {
                if let terms = AppInfo.termsOfUseURL {
                    Link("Terms of Use", destination: terms)
                }
                if let privacy = AppInfo.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacy)
                }
            }
            .font(Clinical.body(11, weight: .medium))
            .foregroundStyle(Clinical.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
