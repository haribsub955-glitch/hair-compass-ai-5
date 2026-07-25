import Foundation
import SwiftUI

/// Opt-in consent to contribute de-identified records toward improving the app's models — the
/// "Share iPhone Analytics" pattern, deliberately.
///
/// **Nothing in this file transmits anything.** It records a *decision* and nothing else. Uploading
/// health data is a separate, deliberate piece of work that must not ship until the items in
/// `ResearchConsent.blockersBeforeAnyUpload` are genuinely done. Storing the decision first is the
/// right order: consent has to exist, be revocable, and be auditable *before* there is a pipeline
/// that could act on it.
///
/// Design rules, all of which are legal requirements rather than preferences:
/// - **Default off.** Consent that ships pre-ticked is not consent (GDPR Art. 4(11), and the EDPB
///   is explicit that pre-ticked boxes fail). `isEnabled` defaults to `false` and only a deliberate
///   toggle changes it.
/// - **Revocable, as easily as it was given** (GDPR Art. 7(3)) — the same switch, in the same place.
/// - **Specific and informed.** The screen says what would be shared, what would not, and what it
///   would be used for, in plain sentences, before the switch.
/// - **Not a condition of using the app.** Every feature works identically either way, and the copy
///   says so. Bundling consent into access invalidates it (Art. 7(4)).
/// - **Auditable.** We keep the timestamp and the version of the wording that was agreed to, so a
///   later change of terms can't silently inherit an older consent.
@MainActor
@Observable
final class ResearchConsent {
    /// Bump whenever the *substance* of what's being consented to changes. A stored decision made
    /// against an older version must be treated as not-yet-given for the new terms.
    static let currentTermsVersion = 1

    private enum Key {
        static let enabled = "researchConsentEnabled"
        static let date = "researchConsentDate"
        static let version = "researchConsentTermsVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storedEnabled = defaults.bool(forKey: Key.enabled)
        self.decidedAt = defaults.object(forKey: Key.date) as? Date
        self.agreedVersion = defaults.object(forKey: Key.version) as? Int
    }

    private var storedEnabled: Bool
    private(set) var decidedAt: Date?
    private(set) var agreedVersion: Int?

    /// Whether the person is currently contributing. Writing it records the decision, when it was
    /// made, and which wording it was made against.
    var isEnabled: Bool {
        get { storedEnabled && agreedVersion == Self.currentTermsVersion }
        set {
            storedEnabled = newValue
            decidedAt = .now
            agreedVersion = newValue ? Self.currentTermsVersion : nil
            defaults.set(newValue, forKey: Key.enabled)
            defaults.set(decidedAt, forKey: Key.date)
            if newValue {
                defaults.set(Self.currentTermsVersion, forKey: Key.version)
            } else {
                defaults.removeObject(forKey: Key.version)
            }
        }
    }

    /// True when consent was given against wording that has since changed — the UI should re-ask
    /// rather than assume the old yes still covers the new terms.
    var needsReconsent: Bool {
        storedEnabled && agreedVersion != Self.currentTermsVersion
    }

    /// What must be true before a single record may leave a device. Written down in code because a
    /// checklist that lives only in someone's head is the failure mode this whole file exists to
    /// prevent.
    ///
    /// 1. A lawful basis for special-category health data — explicit consent under GDPR Art. 9(2)(a)
    ///    — plus a completed DPIA (Art. 35), since this is large-scale health processing.
    /// 2. US state coverage, notably the Washington My Health My Data Act, which requires separate
    ///    written authorisation to *share* consumer health data and carries a private right of action.
    /// 3. A privacy policy that actually describes the collection, and an App Store privacy label
    ///    updated to match — the current label says data is not collected.
    /// 4. App Review 5.1.1(iii)/5.1.3: health research needs documented consent, and human-subjects
    ///    research needs ethics-board approval.
    /// 5. A real de-identification standard with a written re-identification risk assessment.
    ///    Photos and free text are not de-identifiable by field-stripping and should be excluded.
    /// 6. Deletion that propagates: revoking here must delete already-contributed records, or the
    ///    revocation is cosmetic.
    /// 7. Transport and storage security, retention limits, and a named data controller.
    static let blockersBeforeAnyUpload = 7
}

/// Shows the person the *literal* payload that would be contributed from their device — every
/// field, with its actual value, rendered from the same `ResearchAggregator` output that a real
/// contribution would use.
///
/// This is the strongest available form of informed consent and the best legal posture: consent is
/// only "informed" if the person could know what they agreed to, and nothing informs like reading
/// the actual thing. It also acts as a live audit — if a future change ever added a field it
/// shouldn't, it would appear on this screen in front of the user.
struct ResearchPayloadPreview: View {
    let payload: ResearchPayload?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InfoCallout(
                        text: "This is exactly what would be sent — the whole thing, nothing held back. "
                            + "It's a set of averages about your record, not your record.",
                        symbol: "eye.fill"
                    )

                    if let payload {
                        Text(json(payload))
                            .font(.system(size: 12).monospaced())
                            .foregroundStyle(Clinical.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Clinical.hairline, lineWidth: 1)
                            )
                    } else {
                        Text("Nothing would be sent from this device yet. Contribution needs at least "
                             + "\(ResearchPayload.minimumLoggedDays) logged days — a shorter record is both "
                             + "too thin to be useful and more identifying, not less.")
                            .font(Clinical.caption(13))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Colophon(text: "Your name, your notes and your photos are not in this list, and there "
                                 + "is no device or account identifier — so two contributions can't be "
                                 + "linked back to one person.")
                }
                .padding(20)
            }
            .background(Clinical.canvas.ignoresSafeArea())
            .navigationTitle("What would be shared")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func json(_ payload: ResearchPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8)
        else { return "(couldn't render)" }
        return string
    }
}

/// The consent screen. Explains before it asks, in that order.
struct ResearchConsentSection: View {
    @Bindable var consent: ResearchConsent
    /// Built by the caller from live data so the preview shows real values, not a mock.
    var payload: ResearchPayload? = nil

    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Improve Hair Compass")

            VStack(alignment: .leading, spacing: 12) {
                InfoCallout(
                    text: "Hair research is thin, especially outside of male-pattern loss. Records "
                        + "contributed by people actually living with this are how that gets better.",
                    symbol: "flask.fill"
                )

                Toggle(isOn: $consent.isEnabled) {
                    Text("Contribute my record to research")
                        .font(Clinical.body(15, weight: .medium))
                        .foregroundStyle(Clinical.ink)
                }
                .tint(Clinical.accent)
                .accessibilityIdentifier("researchConsentToggle")

                Text("Off by default. Every feature works exactly the same either way, and you can "
                     + "switch this off whenever you like.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Clinical.hairline)

                detail("What would be shared",
                       "Your check-in numbers, routine adherence, lab values and self-reported "
                       + "context — stripped of anything naming you.")
                detail("What would never be shared",
                       "Your photos, your name, your notes, and anything that could identify you or "
                       + "your device.")
                detail("What it would be used for",
                       "Training models that make the app's readings better for people like you. "
                       + "Never sold, never used for advertising.")

                Button {
                    showPreview = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("See exactly what would be shared")
                    }
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("researchPayloadPreview")

                if consent.isEnabled, let date = consent.decidedAt {
                    Text("You turned this on \(date.formatted(date: .abbreviated, time: .omitted)).")
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.tertiary)
                }

                Colophon(text: "Not yet active. Nothing is being collected or sent today — this only "
                             + "records your choice, so it's already set if and when contribution opens.")
            }
        }
        .sheet(isPresented: $showPreview) {
            ResearchPayloadPreview(payload: payload)
        }
    }

    private func detail(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Clinical.body(13, weight: .semibold))
                .foregroundStyle(Clinical.ink)
            Text(line)
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
