import SwiftUI

/// The one-time cloud-AI question, asked in place — inside the chat sheet, the deep-analysis
/// sheet and the ingredient reader — before the first request could ever leave the device.
///
/// Honesty rules for this card: it names the provider, says exactly what is sent (the same
/// tracking summary the on-device model already reads — numbers, dates, logged notes) and what
/// is never sent (name, contact details, photos — `AIContextBuilder` structurally has no such
/// fields), and neither button is dressed up as the "right" answer. Declining keeps the
/// on-device path where the hardware has one, and the choice is always reversible from the
/// Baseline screen (`CloudAISettingsSection`).
struct CloudAIConsentCard: View {
    /// Called after either choice is recorded so the presenting view re-reads `AIEngine.current`.
    var onDecided: () -> Void

    private var onDeviceAvailable: Bool { OnDeviceAvailability.current.isAvailable }

    var body: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    CompanionView(moment: .listening, variant: .avatar, size: 36)
                    Eyebrow(text: "Cloud AI · one-time choice")
                }

                Text("Answer from the cloud?")
                    .font(Clinical.headline(18))
                    .foregroundStyle(Clinical.ink)

                Text("Wren's answers can be written by a secure cloud model (DeepSeek). Each question sends the tracking summary this app builds — numbers, dates and notes you've logged — and, for the ingredient reader, the text read off a product label. Your name, contact details and photos are never included, and what's sent is used only to write the answer.")
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(onDeviceAvailable
                     ? "If you'd rather keep everything on this iPhone, answers stay on-device instead."
                     : "This iPhone can't run on-device AI, so without cloud AI these features stay off. Everything else in Hair Compass works fully on this device.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Use cloud AI") {
                    CloudAIConsent.record(true)
                    onDecided()
                }
                .buttonStyle(ClinicalButtonStyle())
                .accessibilityIdentifier("cloudAIConsentAccept")

                Button(onDeviceAvailable ? "Stay on-device only" : "Not now") {
                    CloudAIConsent.record(false)
                    onDecided()
                }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .accessibilityIdentifier("cloudAIConsentDecline")

                if let url = AppInfo.privacyPolicyURL {
                    Link("How your data is handled", destination: url)
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.tertiary)
                }
            }
        }
        .accessibilityIdentifier("cloudAIConsentCard")
    }
}

/// The standing switch for the choice `CloudAIConsentCard` records — on the Baseline screen so
/// consent is never a one-way door. Flipping it off routes the AI features back to the
/// on-device model (or turns them off on hardware without one); flipping it on is the same
/// grant the card records.
struct CloudAISettingsSection: View {
    /// Local mirror of the persisted choice — `CloudAIConsent` is plain UserDefaults, which
    /// SwiftUI cannot observe, so the view keeps its own source of truth and writes through.
    @State private var granted = CloudAIConsent.isDecided() && CloudAIConsent.isGranted()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Cloud AI")

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $granted) {
                    Text("Cloud AI answers")
                        .font(Clinical.body(15, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                }
                .tint(Clinical.accent)
                .accessibilityIdentifier("cloudAIToggle")
                .onChange(of: granted) {
                    // Flipping this toggle either way deliberately collapses "undecided" into an
                    // explicit answer — there is no third, unasked state once Baseline has been
                    // opened, by design (mirrors what `CloudAIConsentCard`'s buttons record).
                    CloudAIConsent.record(granted)
                }

                Text("When on, Ask Wren, Deep analysis and the ingredient reader are answered by a secure cloud model (DeepSeek). Each request sends your tracking summary — numbers, dates and notes — and, for the ingredient reader, the text read off a product label. Never your name, contact details or photos. When off, they run on-device where this iPhone supports it.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = AppInfo.privacyPolicyURL {
                    Link("Privacy policy", destination: url)
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.tertiary)
                }
            }
            .padding(14)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
        }
        // Re-sync the local mirror every time Baseline appears: the `@State` above only
        // snapshots once at init, and would otherwise go stale if consent were recorded
        // elsewhere (e.g. `CloudAIConsentCard`, reached from chat/deep-analysis/ingredients)
        // while this screen stayed alive underneath.
        .onAppear { granted = CloudAIConsent.isDecided() && CloudAIConsent.isGranted() }
    }
}
