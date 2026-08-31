import SwiftUI

/// The one hard requirement Pro carries, disclosed *on* the paywall instead of after the charge.
///
/// Everything `hasPro` gates — `HairChatSheet` and `DeepAnalysisSheet` — runs on Apple Intelligence
/// with no cloud fallback. So both purchase surfaces (`OnboardingPlanStep`, `ProGate`) put
/// `ProAvailabilityNotice` above their buttons and check `sellable` before offering them at all.
///
/// **Pro is sold only while the model is `.available` right now.** The earlier design still sold
/// in `.notEnabled`/`.modelNotReady` ("they're one tap away"), and that is exactly the state App
/// Review tests in: the reviewer subscribes, opens a Pro feature, and finds a "needs Apple
/// Intelligence" card instead of the feature — a paid product that doesn't work on the device it
/// was just bought on (Guidelines 2.1 + 3.1.2, rejected build 4, 2026-08). Charging anyone in a
/// state where the purchase can't deliver was wrong for users for the same reason. The notice
/// still tells fixable states exactly how to enable Apple Intelligence; the buttons return the
/// moment `current` reads `.available`.
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

    /// Whether the purchase buttons should be offered at all. Only while the model can actually
    /// run — see the type doc for why the transient reasons no longer sell.
    static func sellable(_ status: OnDeviceAvailability) -> Bool { status == .available }

    /// Paywall-specific wording. `OnDeviceAvailability.message` is written for someone already
    /// inside a feature ("everything else still works"); here the reader is deciding whether to
    /// pay, so each line leads with what it means for the purchase.
    static func message(for status: OnDeviceAvailability) -> String {
        switch status {
        case .available:
            return ""
        case .notEnabled:
            return "Both Pro features need Apple Intelligence, and it's switched off on this iPhone. "
                + "Turn it on in Settings › Apple Intelligence & Siri, then come back — Pro unlocks "
                + "here as soon as it's ready."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready on this iPhone. Pro will be available "
                + "to unlock as soon as it finishes preparing."
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
                    // No "Open Settings" shortcut: `UIApplication.openSettingsURLString` opens
                    // THIS app's settings page, not Apple Intelligence & Siri, and no public URL
                    // reaches that pane — the message carries the manual path instead.
                }
            }
            .accessibilityIdentifier("proAvailabilityNotice")
        }
    }
}
