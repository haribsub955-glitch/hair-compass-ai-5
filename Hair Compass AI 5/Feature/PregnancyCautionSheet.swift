import SwiftUI

/// The honest pause before a medication that's usually avoided in or around pregnancy lands in
/// the plan. Shown only when the profile says pregnant / trying / breastfeeding and the entered
/// item matches a recognised substance. Mirrors `RxConfirmSheet`: one plain note, and never a
/// gate the app enforces — "Add anyway" runs the exact save the form was about to do (this is a
/// record, she may be tracking it to discuss with her clinician); "Go back" returns to the form.
struct PregnancyCautionSheet: View {
    let info: PregnancyCaution.Info
    let onProceed: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Clinical.body(42, weight: .medium))
                .foregroundStyle(Clinical.warning)
                .padding(.top, 8)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Usually avoided in pregnancy")
                    .font(Clinical.headline(24))
                    .foregroundStyle(Clinical.ink)
                    .multilineTextAlignment(.center)
                Text(info.substance)
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.secondary)
            }
            .padding(.top, 14)

            // The honest note: warning-tinted surface, but calm copy — a nudge to talk to a
            // clinician, never a scare and never a claim about her specific situation.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.warning)
                    .padding(.top, 2)
                Text(info.message)
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Clinical.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Clinical.warning.opacity(0.35), lineWidth: 1)
            )
            .padding(.top, 16)

            Spacer(minLength: 12)

            // "Go back" is the emphasised choice here; adding stays possible but quiet, so the
            // form never feels like it's encouraging the medication.
            Button("Go back") { dismiss() }
                .font(Clinical.body(16, weight: .semibold))
                .foregroundStyle(Clinical.surface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Clinical.accent, in: Capsule())
                .buttonStyle(.plain)

            Button("Add to plan anyway") { onProceed() }
                .font(Clinical.body(14, weight: .medium))
                .foregroundStyle(Clinical.secondary)
                .buttonStyle(.plain)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Clinical.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
