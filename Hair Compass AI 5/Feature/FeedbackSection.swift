import SwiftUI
import UIKit
import MessageUI

/// A "Send feedback" section for the Baseline / profile screen. Hair Compass is fully on-device
/// with no backend, so feedback is collected the backend-free way: by email. Tapping opens the
/// system mail composer prefilled to the support address with the app version and device/OS so
/// issues can be reproduced — never any of the person's tracking data. If no mail account is set
/// up, it falls back to a `mailto:` link, then to an alert showing the address to copy.
struct FeedbackSection: View {
    @Environment(\.openURL) private var openURL
    @State private var showMailComposer = false
    @State private var showNoMailAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Feedback")

            VStack(alignment: .leading, spacing: 12) {
                Button(action: sendFeedback) {
                    Label("Send feedback", systemImage: "envelope")
                        .font(Clinical.body(15, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sendFeedback")

                Text("Tell us what's working or what's missing. It opens an email so you can send it directly — nothing is collected automatically.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
            }
            .padding(14)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposeView(
                recipient: AppInfo.feedbackEmail,
                subject: FeedbackDraft.subject,
                body: FeedbackDraft.body()
            )
            .ignoresSafeArea()
        }
        .alert("Set up Mail to send feedback", isPresented: $showNoMailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No email account is set up on this device. You can email your feedback to \(AppInfo.feedbackEmail).")
        }
    }

    private func sendFeedback() {
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else if let url = FeedbackDraft.mailtoURL() {
            openURL(url) { accepted in
                if !accepted { showNoMailAlert = true }
            }
        } else {
            showNoMailAlert = true
        }
    }
}

/// The prefilled subject/body for a feedback email — a friendly prompt plus app version and
/// device/OS so issues can be reproduced. No personal tracking data is ever included.
enum FeedbackDraft {
    static let subject = "Hair Compass feedback"

    static func body() -> String {
        """


        —
        Please write your feedback above this line.

        App: Hair Compass \(AppInfo.version)
        Device: \(deviceModel()) · iOS \(UIDevice.current.systemVersion)
        """
    }

    static func mailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppInfo.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body())
        ]
        return components.url
    }

    /// The hardware identifier (e.g. "iPhone16,1"), falling back to the coarse model name.
    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}

/// A thin SwiftUI wrapper over `MFMailComposeViewController` — presents the system mail composer
/// prefilled, and dismisses the sheet on send or cancel.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            dismiss()
        }
    }
}
