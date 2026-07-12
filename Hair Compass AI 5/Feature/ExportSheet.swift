import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Share a clinician-readable summary or a full JSON export of the raw records. The data is the
/// user's own; nothing leaves the device except through the share sheet they invoke.
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \LabResult.collectedAt, order: .reverse) private var labs: [LabResult]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \ProgressCheckIn.date, order: .reverse) private var progressCheckIns: [ProgressCheckIn]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \SideEffectLog.date, order: .reverse) private var sideEffects: [SideEffectLog]
    @Query(sort: \ProcedureAppointment.date, order: .reverse) private var procedures: [ProcedureAppointment]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]

    @State private var jsonURL: URL?
    @State private var pdfURL: URL?

    private var summary: String {
        ExportService.clinicianSummary(
            profile: profiles.first, entries: entries, treatments: treatments,
            doses: doses, labs: labs, triggers: triggers, progressCheckIns: progressCheckIns,
            sideEffects: sideEffects, procedures: procedures
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "For your clinician")
                            Text("A plain-language summary of your baseline, recent signals, treatments, labs and triggers — ready to hand to a dermatologist or GP.")
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            ShareLink(item: summary) {
                                Label("Share summary", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.surface)
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
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            if let pdfURL {
                                ShareLink(item: pdfURL) {
                                    Label("Visit report (PDF)", systemImage: "doc.richtext")
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                                }
                            }
                        }
                    }

                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Your data")
                            Text("Export everything as a JSON file — a portable backup you own and can keep off-device.")
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                            if let jsonURL {
                                ShareLink(item: jsonURL) {
                                    Label("Export data (JSON)", systemImage: "arrow.down.doc")
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                                }
                            }
                        }
                    }

                    Image("export-seal")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    Text("This is a self-tracked record for documentation, not a diagnosis.")
                        .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                writeJSON()
                writePDF()
            }
        }
    }

    private func writePDF() {
        let data = VisitReportPDF.render(
            title: "Hair Compass — Visit Report", summaryText: summary,
            entries: entries, photos: photos
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HairCompassVisitReport.pdf")
        try? data.write(to: url, options: .atomic)
        pdfURL = url
    }

    private func writeJSON() {
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
