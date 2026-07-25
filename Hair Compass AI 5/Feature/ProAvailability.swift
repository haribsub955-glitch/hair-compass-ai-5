import SwiftUI

/// The one hard requirement Pro carries, disclosed *on* the paywall instead of after the charge.
///
/// Everything `hasPro` gates — `HairChatSheet` and `DeepAnalysisSheet` — runs on Apple Intelligence
/// with no cloud fallback. On an iPhone that can't run it, a subscription buys literally nothing,
/// so both purchase surfaces (`OnboardingPlanStep`, `ProGate`) put `ProAvailabilityNotice` above
/// their buttons and check `sellable` before offering them at all.
///
/// The three unavailable reasons are not equivalent and are deliberately not collapsed into one:
/// - `.notEnabled` / `.modelNotReady` — the person can fix this themselves (a Settings toggle, or
///   waiting for a download to finish). Warn, and still sell: refusing the sale to someone who is
///   one tap away from using it would be its own kind of wrong.
/// - `.deviceNotEligible` — nothing they do on *this* iPhone will ever make Pro work. Don't sell.
///
/// Restore stays available in every case, so someone who already subscribed elsewhere is never
/// locked out of a purchase they've already made.
enum ProAvailability {
    /// What the paywalls should read instead of `OnDeviceAvailability.current`.
    ///
    /// Identical to it in release. The DEBUG override exists because the Simulator always reports
    /// `.deviceNotEligible` (FoundationModels doesn't run there), which now correctly hides the
    /// purchase buttons — and would otherwise make it impossible to screenshot the offer itself
    /// without a physical Apple Intelligence device. Same spirit as `HC_PAYWALL_BOTTOM`.
    static var current: OnDeviceAvailability {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("HC_AI_AVAILABLE") { return .available }
        #endif
        return OnDeviceAvailability.current
    }

    /// Whether the purchase buttons should be offered at all. False only for permanently
    /// ineligible hardware — see the type doc for why the transient reasons still sell.
    static func sellable(_ status: OnDeviceAvailability) -> Bool { status != .deviceNotEligible }

    /// Paywall-specific wording. `OnDeviceAvailability.message` is written for someone already
    /// inside a feature ("everything else still works"); here the reader is deciding whether to
    /// pay, so each line leads with what it means for the purchase.
    static func message(for status: OnDeviceAvailability) -> String {
        switch status {
        case .available:
            return ""
        case .notEnabled:
            return "Both Pro features need Apple Intelligence, and it's switched off on this iPhone. "
                + "Turn it on in Settings › Apple Intelligence & Siri and they'll work."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready on this iPhone. Both Pro features will "
                + "work as soon as it finishes preparing."
        case .deviceNotEligible:
            return "Pro wouldn't work on this iPhone. Both of its features run on Apple Intelligence, "
                + "which needs iPhone 15 Pro or newer, and there's no cloud version to fall back on. "
                + "Everything else in Hair Compass works fully here, free."
        }
    }
}

/// The paywall's Apple Intelligence disclosure. Renders nothing when the model is available, a
/// fixable warning when the person can act, and a plain "this wouldn't work here" when they can't.
struct ProAvailabilityNotice: View {
    let status: OnDeviceAvailability

    @Environment(\.openURL) private var openURL

    private var isPermanent: Bool { status == .deviceNotEligible }

    var body: some View {
        if status != .available {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: isPermanent ? "exclamationmark.triangle" : "sparkles")
                            .font(Clinical.caption(14))
                            .foregroundStyle(isPermanent ? Clinical.critical : Clinical.warning)
                        Text(ProAvailability.message(for: status))
                            .font(Clinical.caption(13))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if status.showsSettingsButton {
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                        .accessibilityIdentifier("paywallOpenSettings")
                    }
                }
            }
            .accessibilityIdentifier("proAvailabilityNotice")
        }
    }
}
