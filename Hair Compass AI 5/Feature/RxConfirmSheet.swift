import SwiftUI

/// The friendly pause before a prescription-only medication lands in the plan: the brand's
/// illustration of the medication, the entered name and regimen, and one honest note — "this
/// is usually prescribed; we'll assume yours is." Reassurance, never a scare, and never a
/// gate the app enforces: Confirm runs the exact save the form was about to do; Go back
/// returns to the untouched form underneath.
struct RxConfirmSheet: View {
    let name: String
    let dose: String
    let schedule: String          // comma-separated daily slots ("08:00,21:00"); "" = periodic
    let requirement: RxGate.Requirement
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // The medication in the brand's own hand — unboxed on the warm canvas.
            Image(requirement.art.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 148, height: 148)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(name)
                    .font(Clinical.headline(26))
                    .foregroundStyle(Clinical.ink)
                    .multilineTextAlignment(.center)
                if !regimenSummary.isEmpty {
                    Text(regimenSummary)
                        .font(.system(size: 14))
                        .foregroundStyle(Clinical.secondary)
                }
            }
            .padding(.top, 6)

            // The "usually prescribed — we're assuming it is" note: soft info treatment,
            // secondary ink on a plain surface card. Deliberately not a warning color.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Clinical.secondary)
                    .padding(.top, 2)
                Text(RxGate.note(for: requirement.medication))
                    .font(.system(size: 13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1)
            )
            .padding(.top, 14)

            Spacer(minLength: 12)

            Button(action: onConfirm) {
                Text("Confirm — it's prescribed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Clinical.surface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Clinical.accent, in: Capsule())
                    .shadow(color: Clinical.accent.opacity(0.28), radius: 12, y: 5)
            }
            .buttonStyle(.plain)

            Button("Go back") { dismiss() }
                .font(.system(size: 14, weight: .medium))
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

    /// "1 mg · 1×/day" — the same cadence language as the regimen preset chips.
    private var regimenSummary: String {
        let slots = schedule
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cadence: String
        switch slots.count {
        case 0: cadence = "periodic"
        case 1: cadence = "1×/day"
        default: cadence = "\(slots.count)×/day"
        }
        return dose.isEmpty ? cadence : "\(dose) · \(cadence)"
    }
}
