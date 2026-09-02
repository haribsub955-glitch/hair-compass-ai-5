import SwiftUI

/// The one hardware bound Pro can carry, disclosed *on* the paywall instead of after the charge.
///
/// Since 1.1, Pro is the whole app except medication logging — check-ins, trends, labs, photos,
/// export — plus the two AI features (`HairChatSheet`, `DeepAnalysisSheet`). Which engine those
/// two use is a build-time fact (`CloudAIConfig`):
/// - With the cloud model configured — the shipping configuration — Ask Wren and Deep analysis
///   run on every iPhone and there is nothing to disclose: `message` is empty for every status,
///   so `ProAvailabilityNotice` renders nothing. The consent story is told at first use
///   (`CloudAIConsentCard`), not on the paywall — a person who declines cloud AI has made a
///   choice, not hit a device limit.
/// - Without it, the two features run on Apple Intelligence only, and this type's job is to say
///   honestly, before the buttons, what they need and whether *this* iPhone has it.
///
/// The non-AI half works on every iPhone, so the sale is never withdrawn in either build.
///
/// The three unavailable reasons are not equivalent and are deliberately not collapsed into one:
/// - `.notEnabled` / `.modelNotReady` — the person can fix this themselves (a Settings toggle, or
///   waiting for a download to finish). Name the path, and sell.
/// - `.deviceNotEligible` — the two AI features will never run on this iPhone. Say so plainly,
///   and say what still works, so nobody buys expecting Wren on an iPhone 12.
///
/// Restore stays available in every case, so someone who already subscribed elsewhere is never
/// locked out of a purchase they've already made.
enum ProAvailability {
    /// What the paywalls should read instead of `OnDeviceAvailability.current`.
    ///
    /// Identical to it in release. The DEBUG override exists because the unavailable states are
    /// otherwise unreachable in QA: an iOS 26 Simulator on an Apple Intelligence Mac reports
    /// `.available`, so the notice could only ever be seen by finding a physically ineligible
    /// iPhone. `HC_AI_STATUS <case>` forces any of the four. Same shape as `HC_ONBOARD_STEP <n>`
    /// and `HC_RITUAL_KIND <kind>`.
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

    /// Since 1.1, Pro contains device-independent value (check-ins, trends, labs, photos,
    /// reports) alongside the two AI features, so the purchase buttons are offered on every
    /// device — ineligible hardware gets an honest AI disclosure instead of a withdrawn sale.
    static func sellable(_ status: OnDeviceAvailability) -> Bool { true }

    /// Paywall-specific wording. `OnDeviceAvailability.message` is written for someone already
    /// inside a feature ("everything else still works"); here the reader is deciding whether to
    /// pay, so each line leads with what it means for the purchase.
    ///
    /// With the cloud model configured there is nothing to warn about — the AI features run on
    /// every iPhone — so every status maps to the empty string and the notice renders nothing.
    /// `cloudConfigured` is a parameter (defaulting to the build's truth) so tests can pin the
    /// contract for both builds regardless of which one the test host happens to be.
    static func message(
        for status: OnDeviceAvailability,
        cloudConfigured: Bool = CloudAIConfig.current.isConfigured
    ) -> String {
        if cloudConfigured { return "" }
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
            return "The two AI features (Ask Wren and Deep analysis) run on Apple Intelligence, "
                + "which needs iPhone 15 Pro or newer, so they won't work on this iPhone. "
                + "Everything else in Pro works fully here."
        }
    }
}

/// The paywall's AI-availability disclosure. Renders nothing whenever there is nothing to warn
/// about — the cloud model is configured, or the on-device model is available — a fixable
/// warning when the person can act, and a plain "this wouldn't work here" when they can't.
struct ProAvailabilityNotice: View {
    let status: OnDeviceAvailability

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
                    // No "Open Settings" button: `openSettingsURLString` opens THIS app's
                    // settings page, not Apple Intelligence & Siri (which has no public URL),
                    // so a button here would land the person somewhere the toggle isn't. The
                    // copy names the exact Settings path instead.
                }
            }
            .accessibilityIdentifier("proAvailabilityNotice")
        }
    }
}
