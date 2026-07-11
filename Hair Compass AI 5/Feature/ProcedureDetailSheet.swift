import SwiftData
import SwiftUI

/// Per-appointment detail: the booked/logged procedure, a "Mark completed" action while it's
/// still pending, and delete. A private record for the user's own clinician conversations —
/// never medical advice, matching `TreatmentDetailSheet`'s framing.
struct ProcedureDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var appointment: ProcedureAppointment

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if !appointment.type.art.isEmpty {
                        BrandBanner(art: appointment.type.art, height: 140)
                    }
                    header
                    if !appointment.isCompleted {
                        Button("Mark completed", action: markCompleted)
                            .buttonStyle(ClinicalButtonStyle())
                    }
                    deleteButton
                    Text("A private record for your own clinician conversations — not medical advice.")
                        .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle(appointment.type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: appointment.type.symbol)
                    .font(.system(size: 16)).foregroundStyle(Clinical.accent)
                    .frame(width: 38, height: 38)
                    .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(appointment.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text(statusLine)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(statusTint)
                }
                Spacer()
            }
            if !appointment.location.isEmpty {
                Label(appointment.location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
            }
            if !appointment.note.isEmpty {
                Text(appointment.note)
                    .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLine: String {
        if appointment.isCompleted {
            let done = appointment.completedAt ?? appointment.date
            return "Completed \(done.formatted(date: .abbreviated, time: .omitted))"
        }
        return appointment.isUpcoming ? "Upcoming" : "Past · not marked done"
    }
    private var statusTint: Color {
        if appointment.isCompleted { return Clinical.positive }
        return appointment.isUpcoming ? Clinical.accent : Clinical.warning
    }

    // MARK: Actions

    private func markCompleted() {
        appointment.isCompleted = true
        appointment.completedAt = .now
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Hand-drawn destructive style (matches `PhotoDetailView.deleteButton`) rather than
    /// `ClinicalButtonStyle(filled: false)`, which hard-codes its label to `Clinical.ink` and
    /// would bury the destructive intent.
    private var deleteButton: some View {
        Button(role: .destructive) {
            context.delete(appointment)
            dismiss()
        } label: {
            Label("Delete procedure", systemImage: "trash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Clinical.critical)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Clinical.critical.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
