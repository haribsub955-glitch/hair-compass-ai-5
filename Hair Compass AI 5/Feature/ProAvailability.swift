import SwiftUI

/// The one hard requirement two of Pro's features carry, disclosed *on* the paywall instead of
/// after the charge.
///
/// Two of Pro's twelve features — `HairChatSheet` and `DeepAnalysisSheet` — run on Apple
/// Intelligence with no cloud fallback. On an iPhone that can't run them, the other ten still
/// work, so the subscription always sells; both purchase surfaces (`OnboardingPlanStep`,
/// `ProGate`) put `ProAvailabilityNotice` next to the two AI features only, never in front of
/// the purchase buttons themselves.
///
/// The three unavailable reasons are not equivalent and are deliberately not collapsed into one:
/// - `.notEnabled` / `.modelNotReady` — the person can fix this themselves (a Settings toggle, or
///   waiting for a download to finish). Warn, and it still runs once fixed.
/// - `.deviceNotEligible` — nothing they do on *this* iPhone will ever make Ask Wren or Deep
///   analysis work. The subscription still sells regardless — the other ten features run fine.
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
    /// the subscription always sells, and only the two on-device-model features are withheld.
    static func canRun(_ feature: ProFeature, status: OnDeviceAvailability) -> Bool {
        guard feature.requiresAppleIntelligence else { return true }
        return status != .deviceNotEligible
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
    static func message(for status: OnDeviceAvailability) -> String {
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
