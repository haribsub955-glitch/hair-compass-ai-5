import SwiftUI

/// The legal footer App Review requires on any auto-renewable-subscription paywall: the renewal
/// disclosure plus **functional** links to the Terms of Use (EULA) and the Privacy Policy. Shared
/// by the onboarding paywall and the in-app `ProGate` upsell so both stay compliant.
struct PaywallLegal: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Auto-renews until cancelled. Manage or cancel anytime in Settings.")
                .font(.system(size: 10))
                .foregroundStyle(Clinical.tertiary)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                if let terms = AppInfo.termsOfUseURL {
                    Link("Terms of Use", destination: terms)
                }
                if let privacy = AppInfo.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacy)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Clinical.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
