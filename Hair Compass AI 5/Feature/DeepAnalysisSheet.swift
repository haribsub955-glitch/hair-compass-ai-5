import SwiftData
import SwiftUI

/// Pro "deep analysis": a single, on-device written summary of the full tracking record via Apple
/// Intelligence (Foundation Models). Everything stays on the device — no network, no key, no
/// consent. Text only: it reasons over the deterministic `AIContext`, never over photo pixels
/// (Foundation Models has no image input), so scalp photos are not sent anywhere. Framed as
/// record-keeping, never diagnosis. Shows a clear card on hardware without on-device AI.
struct DeepAnalysisSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = OnDeviceAnalysisService()

    // The full record the AIContext snapshot is built from at run time — labs, tolerability
    // and photo metadata included, which the on-device InsightContext doesn't carry.
    @Query(sort: \DailyEntry.date) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date) private var triggers: [TriggerEvent]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]
    @Query private var sideEffects: [SideEffectLog]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]
    @Query private var profiles: [Profile]
    @Query(sort: \ProgressCheckIn.date) private var progressCheckIns: [ProgressCheckIn]

    var body: some View {
        NavigationStack {
            ProGate(
                feature: "AI deep analysis",
                symbol: "sparkles.rectangle.stack",
                description: "A one-tap written read of your full tracking record — on-device and private, record-keeping, not diagnosis."
            ) {
                analysisContent
            }
            .clinicalScreen()
            .navigationTitle("Deep analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var analysisContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                BrandBanner(art: BrandArt.analysis, height: 130)
                ClinicalCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Deep analysis · on-device")
                        Text("Writes a plain-language summary of your recent readings, treatments and labs using Apple Intelligence. It runs entirely on your iPhone — nothing leaves the device — and it's record-keeping, not diagnosis.")
                            .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                    }
                }

                if !service.isAvailable {
                    ClinicalCard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(Clinical.warning)
                            Text(OnDeviceAnalysisService.unavailableMessage)
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        }
                    }
                }

                if let result = service.result {
                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "Summary")
                            Text(result).font(.system(size: 15)).foregroundStyle(Clinical.ink)
                            Text("For record-keeping, not diagnosis.")
                                .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                }

                if let error = service.errorMessage {
                    ClinicalCard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 14)).foregroundStyle(Clinical.critical)
                            Text(error).font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        }
                    }
                }

                Button(service.isRunning ? "Analyzing…" : "Run deep analysis") {
                    let payload = AIContext.build(
                        entries: entries, treatments: treatments, doses: doses,
                        snapshots: snapshots, triggers: triggers,
                        labs: labs, sideEffects: sideEffects, photos: photos,
                        profile: profiles.first, progressCheckIns: progressCheckIns, now: .now
                    )
                    Task { await service.analyze(context: payload) }
                }
                .buttonStyle(ClinicalButtonStyle())
                .disabled(!service.isAvailable || service.isRunning)
                .opacity((!service.isAvailable || service.isRunning) ? 0.5 : 1)
            }
            .padding(20)
        }
    }
}
