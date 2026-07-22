import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Share a clinician-readable summary or a full JSON export of the raw records. The data is the
/// user's own; nothing leaves the device except through the share sheet they invoke.
struct ExportSheet: View {
    var consultation: ProcedureAppointment?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query private var missedDoses: [MissedDoseRecord]
    @Query(sort: \LabResult.collectedAt, order: .reverse) private var labs: [LabResult]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \ProgressCheckIn.date, order: .reverse) private var progressCheckIns: [ProgressCheckIn]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \SideEffectLog.date, order: .reverse) private var sideEffects: [SideEffectLog]
    @Query(sort: \ProcedureAppointment.date, order: .reverse) private var procedures: [ProcedureAppointment]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]

    @State private var jsonURL: URL?
    @State private var pdfURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var backupURL: URL?
    @State private var backupErrorMessage: String?

    private var summary: String {
        let report = ExportService.clinicianSummary(
            profile: profiles.first, entries: entries, treatments: treatments,
            doses: doses, labs: labs, triggers: triggers, progressCheckIns: progressCheckIns,
            sideEffects: sideEffects, procedures: procedures
        )
        guard let visit = reportConsultation else { return report }
        return ExportService.visitAgendaSection(visit) + report
    }

    private var reportConsultation: ProcedureAppointment? {
        consultation ?? procedures
            .filter { $0.type == .consultation && $0.hasVisitAgenda }
            .sorted { $0.date < $1.date }.first
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "For your clinician")
                            Text("A plain-language summary of your baseline, recent signals, treatments, labs and triggers — ready to hand to a dermatologist or GP.")
                                .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                            ShareLink(item: summary) {
                                Label("Share summary", systemImage: "square.and.arrow.up")
                                    .font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.surface)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Clinical.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            Text(summary)
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Clinical.tertiary)
                                .lineLimit(6)
                        }
                    }

                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Visit report")
                            Text("The summary above as a print-ready PDF, with your trend charts and baseline-vs-latest photos — one document to bring to the appointment.")
                                .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                            if let pdfURL {
                                ShareLink(item: pdfURL) {
                                    Label("Visit report (PDF)", systemImage: "doc.richtext")
                                        .font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.ink)
                                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                                }
                            } else if let pdfErrorMessage {
                                Text(pdfErrorMessage)
                                    .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
                            } else {
                                preparingRow("Preparing visit report…")
                            }
                        }
                    }
                    .task { await preparePDF() }

                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Your data")
                            Text("A full backup of every record and photo, in the app's restorable format — if you lose this phone, restore it on a new one from onboarding's \u{201C}Restoring from a backup?\u{201D} link.")
                                .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                            if let backupURL {
                                ShareLink(item: backupURL) {
                                    Label("Back up everything (restorable, includes photos)", systemImage: "arrow.down.doc")
                                        .font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.surface)
                                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .background(Clinical.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            } else if let backupErrorMessage {
                                Text(backupErrorMessage)
                                    .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
                            } else {
                                preparingRow("Preparing backup…")
                            }

                            Divider().overlay(Clinical.hairline).padding(.vertical, 2)

                            Text("Machine-readable JSON for your own analysis — not restorable by the app; use \u{201C}Back up everything\u{201D} above for that.")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.tertiary)
                            if let jsonURL {
                                ShareLink(item: jsonURL) {
                                    Label("Export data (JSON)", systemImage: "doc.text")
                                        .font(Clinical.body(14, weight: .medium)).foregroundStyle(Clinical.ink)
                                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                                }
                            } else {
                                preparingRow("Preparing…")
                            }
                        }
                    }
                    .task { await prepareBackup() }
                    .task { await prepareJSON() }

                    Image("export-seal")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    Text("This is a self-tracked record for documentation, not a diagnosis.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// Quiet skeleton shown in place of a card's action button while its file is still being
    /// generated — so the card reads as "working on it" rather than looking broken or empty.
    private func preparingRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().tint(Clinical.tertiary)
            Text(label).font(Clinical.caption(13)).foregroundStyle(Clinical.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
    }

    /// Runs once per sheet presentation (`.task` on the card, not `onAppear` on the sheet), so
    /// the sheet's own presentation animation isn't competing with this work for the main
    /// actor. The actual byte-reading/base64/JSON-encoding happens off-main inside
    /// `exportBackupAsync` — the one that can realistically be hundreds of MB with a year of
    /// photos — so this `await` doesn't block the UI while it runs.
    private func prepareBackup() async {
        do {
            backupURL = try await BackupService.exportBackupAsync(
                profile: profiles.first, entries: entries, treatments: treatments,
                doses: doses, sideEffects: sideEffects,
                labs: labs, photos: photos, snapshots: snapshots, triggers: triggers,
                procedures: procedures, progressCheckIns: progressCheckIns,
                missedDoses: missedDoses
            )
        } catch {
            backupErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// `VisitReportPDF.render` is itself `async` — it renders the trend chart image on the main
    /// actor (SwiftUI's `ImageRenderer` needs it) but does the CoreText pagination and photo-page
    /// drawing off-main, so only the small, unavoidable part of this ever touches the main actor.
    private func preparePDF() async {
        let data = await VisitReportPDF.render(
            title: "Hair Compass — Visit Report", summaryText: summary,
            entries: entries, photos: photos
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HairCompassVisitReport.pdf")
        do {
            try data.write(to: url, options: .atomic)
            pdfURL = url
        } catch {
            pdfErrorMessage = "Couldn't prepare the visit report. Try again."
        }
    }

    /// Cheap — plain records, no photo bytes — but still deferred to a `.task` so its button
    /// appears through the same "preparing…" skeleton as the other two instead of just as an
    /// asymmetric flash.
    private func prepareJSON() async {
        guard let data = ExportService.dataJSON(
            profile: profiles.first, entries: entries, treatments: treatments, doses: doses,
            labs: labs, triggers: triggers, progressCheckIns: progressCheckIns, snapshots: snapshots,
            sideEffects: sideEffects, procedures: procedures
        ) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HairCompassData.json")
        try? data.write(to: url, options: .atomic)
        jsonURL = url
    }
}
