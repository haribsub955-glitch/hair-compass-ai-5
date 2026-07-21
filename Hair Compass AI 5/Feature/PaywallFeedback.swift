import SwiftUI

/// Shared purchase-feedback building blocks for `ProGate` and `OnboardingPlanStep`'s paywall
/// footers, so both surfaces stay one honest voice instead of drifting apart: a spinner baked
/// into the tapped buy button, a status line under the buttons for the outcome (a pending
/// Ask-to-Buy hold, a failed purchase, a restore result), and the "can't reach the store" empty
/// state that replaces silently-missing purchase buttons with an explanation and a retry.

/// Swaps a purchase button's label for a spinner (matching the button's own foreground color)
/// while its purchase is in flight — the label keeps its layout size via a hidden copy underneath
/// so the button never changes width or height when the spinner appears.
struct PurchaseButtonLabel<Label: View>: View {
    let isPurchasing: Bool
    var tint: Color
    @ViewBuilder var label: () -> Label

    var body: some View {
        label()
            .opacity(isPurchasing ? 0 : 1)
            .overlay {
                if isPurchasing {
                    ProgressView().tint(tint)
                }
            }
    }
}

/// The small honest line under the purchase/restore buttons. Shows at most one message —
/// purchase feedback (a pending hold, a failure) takes priority over a stale restore result so
/// the user is never reading two contradictory lines at once.
struct PurchaseStatusLine: View {
    let purchaseState: PurchaseFlowState
    let restoreResult: String?

    var body: some View {
        if let message {
            Text(message)
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }

    private var message: String? {
        switch purchaseState {
        case .pending:
            return "Waiting for approval — ask the account holder to approve this in Screen Time."
        case .failed(let text):
            return text
        case .purchasing:
            return nil // a fresh attempt in flight — let the button's own spinner speak instead
        case .idle:
            return restoreResult
        }
    }
}

/// Replaces the purchase buttons when the App Store hasn't returned products yet — never a
/// placeholder price, an honest explanation and a way to try again instead.
struct StoreUnavailableView: View {
    let isLoading: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView()
            } else {
                Text("Can't reach the App Store right now.")
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
                Button(action: retry) {
                    Text("Retry")
                }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .accessibilityIdentifier("paywallRetryLoad")
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}
