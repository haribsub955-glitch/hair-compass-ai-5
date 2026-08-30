import SwiftUI

/// What the paywalls disclose about the two AI features, decided in one place.
///
/// With the cloud model configured (`CloudAIConfig` — the shipping configuration), Ask Wren and
/// Deep analysis run on every iPhone and there is nothing to disclose: `canRun` is true
/// everywhere and `message` is empty, so `ProAvailabilityNotice` renders nothing. The consent
/// story is told at first use (`CloudAIConsentCard`), not on the paywall — a person who
/// declines cloud AI has made a choice, not hit a device limit.
///
/// In a build *without* the cloud key, the two features fall back to needing Apple Intelligence
/// hardware, and the original disclosure rules apply. The three unavailable reasons are not
/// equivalent and are deliberately not collapsed into one:
/// - `.notEnabled` / `.modelNotReady` — the person can fix this themselves (a Settings toggle, or
///   waiting for a download to finish). Warn, and it still runs once fixed.
/// - `.deviceNotEligible` — nothing they do on *this* iPhone will make the on-device model work.
///   The subscription still sells regardless — the other ten features run fine.
///
/// Restore stays available in every case, so someone who already subscribed elsewhere is never
/// locked out of a purchase they've already made.
enum ProAvailability {
    /// What the paywalls should read instead of `OnDeviceAvailability.current`.
    ///
    /// Identical to it in release. The DEBUG override exists because the unavailable states are
    /// otherwise unreachable in QA: an iOS 26 Simulator on an Apple Intelligence Mac reports
    /// `.available`, so the notice and the withdrawn purchase buttons could only ever be seen by
    /// finding a physically ineligible iPhone. `HC_AI_STATUS <case>` forces any of the four.
    /// Same shape as `HC_ONBOARD_STEP <n>` and `HC_RITUAL_KIND <kind>`.
    static var current: OnDeviceAvailability {
        #if DEBUG
        if let forced = forcedStatus { return forced }
        #endif
        return OnDeviceAvailability.current
    }

    #if DEBUG
    /// `HC_AI_STATUS available | notEnabled | modelNotReady | deviceNotEligible`.
    static var forcedStatus: OnDeviceAvailability? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "HC_AI_STATUS"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "available": return .available
        case "notEnabled": return .notEnabled
        case "modelNotReady": return .modelNotReady
        case "deviceNotEligible": return .deviceNotEligible
        default: return nil
        }
    }
    #endif

    /// Whether a given Pro feature can actually run on this device right now.
    ///
    /// This replaced `sellable(_:)`, and the change of scope is the point. `sellable` asked "may
    /// we sell a subscription at all", which tied the entire product to Apple Intelligence and
    /// left ineligible hardware with nothing to buy. This asks the narrower, correct question:
    /// the subscription always sells, and only features that can genuinely not run here are
    /// disclosed. With the cloud model configured, that set is empty — DeepSeek answers on any
    /// iPhone, so device eligibility stops being an input.
    static func canRun(
        _ feature: ProFeature,
        status: OnDeviceAvailability,
        cloudConfigured: Bool = CloudAIConfig.current.isConfigured
    ) -> Bool {
        guard feature.usesAI else { return true }
        return cloudConfigured || status != .deviceNotEligible
    }

    /// Whether a paywall may show its purchase buttons. **Apple Intelligence is not an input.**
    ///
    /// This function exists to be the one place that question is asked, and to be asserted: the
    /// old `sellable(_:)` withdrew the buttons on ineligible hardware, which left an iPhone 14
    /// with a mostly-locked app and nothing to buy. Ten of the twelve Pro features run on any
    /// supported iPhone, so the sale is always honest. The only reason to withhold the buttons is
    /// having no real prices to show — never a device capability, never a feature.
    static func showsPurchaseButtons(status: OnDeviceAvailability, hasLoadedProducts: Bool) -> Bool {
        hasLoadedProducts
    }

    /// Paywall-specific wording. `OnDeviceAvailability.message` is written for someone already
    /// inside a feature ("everything else still works"); here the reader is deciding whether to
    /// pay, so each line leads with what it means for the purchase. Crucially, none of these three
    /// says Pro is worthless here — Ask Wren and Deep analysis are 2 of 12 gated features, so even
    /// `.deviceNotEligible` is a scoped limitation next to live purchase buttons, never a reason
    /// not to buy.
    ///
    /// With the cloud model configured there is nothing to warn about — the AI features run on
    /// every iPhone — so every status maps to the empty string and the notice renders nothing.
    static func message(
        for status: OnDeviceAvailability,
        cloudConfigured: Bool = CloudAIConfig.current.isConfigured
    ) -> String {
        if cloudConfigured { return "" }
        switch status {
        case .available:
            return ""
        case .notEnabled:
            return "Ask Wren and Deep analysis need Apple Intelligence, and it's switched off on "
                + "this iPhone. Turn it on in Settings › Apple Intelligence & Siri and they'll work."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready on this iPhone. Ask Wren and Deep "
                + "analysis will work as soon as it finishes preparing."
        case .deviceNotEligible:
            return "Two Pro features — Ask Wren and Deep analysis — run on Apple Intelligence, "
                + "which this iPhone can't run. Everything else Pro unlocks works here normally."
        }
    }
}

/// The paywall's AI-availability disclosure. Renders nothing whenever there is nothing to warn
/// about — the cloud model is configured, or the on-device model is available — a fixable
/// warning when the person can act, and a plain "this wouldn't work here" when they can't.
struct ProAvailabilityNotice: View {
    let status: OnDeviceAvailability

    @Environment(\.openURL) private var openURL

    private var isPermanent: Bool { status == .deviceNotEligible }

    var body: some View {
        let message = ProAvailability.message(for: status)
        if !message.isEmpty {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: isPermanent ? "exclamationmark.triangle" : "sparkles")
                            .font(Clinical.caption(14))
                            .foregroundStyle(isPermanent ? Clinical.critical : Clinical.warning)
                        Text(message)
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
