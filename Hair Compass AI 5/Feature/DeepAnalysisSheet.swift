import SwiftData
import SwiftUI
import UIKit

/// One-time, plain-language consent shown before the FIRST deep analysis — scalp photos leave the
/// device, so that has to be an explicit, informed yes. "Not now" sends nothing. Granting persists
/// (see `AIConsent`) and is revocable anytime from Baseline → Privacy.
struct AIConsentSheet: View {
    /// Called after consent is recorded — the caller proceeds to the analysis sheet.
    var onAllow: () -> Void
    /// Called on decline — dismiss, nothing sent.
    var onNotNow: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    BrandBanner(art: BrandArt.analysis, height: 130)

                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Before your first deep analysis")
                        Text("Your photos would leave this device")
                            .font(Clinical.headline(24))
                            .foregroundStyle(Clinical.ink)
                    }

                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 16) {
                            consentRow("photo.on.rectangle.angled", "What is sent",
                                       "Your scalp photos and a short summary of your tracking (shedding, scalp scores, treatments).")
                            consentRow("cloud", "Where it goes",
                                       "To Anthropic, the cloud AI provider that runs the analysis. This data leaves your device for that one request.")
                            consentRow("doc.text", "Why",
                                       "To write a plain-language, record-keeping summary of what's visible. It is not a diagnosis.")
                            consentRow("hand.raised", "Your control",
                                       "Nothing is sent until you allow it, and you can turn this off later in your profile's Privacy section.")
                        }
                    }

                    Button("Allow and continue") {
                        AIConsent.grant()
                        onAllow()
                    }
                    .buttonStyle(ClinicalButtonStyle())
                    .accessibilityIdentifier("aiConsentAllow")

                    Button("Not now") { onNotNow() }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                        .accessibilityIdentifier("aiConsentNotNow")
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Deep analysis")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func consentRow(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Clinical.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Clinical.ink)
                Text(text)
                    .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
            }
        }
    }
}

/// Opt-in cloud "deep analysis". Explicit off-device-data consent up front, then a single Claude
/// Fable 5 call over the deterministic facts plus matched progress photos. Framed as
/// record-keeping, never diagnosis.
struct DeepAnalysisSheet: View {
    /// The on-device insight context the caller was showing. The cloud payload itself is the
    /// richer, versioned `AIContext` built below from the sheet's own queries.
    let context: InsightContext
    let images: [UIImage]

    @Environment(\.dismiss) private var dismiss
    @State private var service = CloudAnalysisService()
    @State private var consented = false

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
                feature: "AI deep photo analysis",
                symbol: "photo.on.rectangle.angled",
                description: "A one-time, standardized read of your matched progress photos — record-keeping, not diagnosis."
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
                        Eyebrow(text: "Deep analysis · Claude Fable 5")
                        Text("This sends your recent readings and \(images.count) matched progress photo\(images.count == 1 ? "" : "s") to Anthropic's cloud model for a one-time review. It's record-keeping, not diagnosis, and nothing is stored there beyond the request.")
                            .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                        Toggle(isOn: $consented) {
                            Text("Send this data off-device for analysis")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                        }
                        .tint(Clinical.accent)
                    }
                }

                if !service.hasKey {
                    ClinicalCard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "key").font(.system(size: 14)).foregroundStyle(Clinical.warning)
                            Text("No API key is configured, so deep analysis is unavailable. On-device insight on the Today screen still works fully and privately.")
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
                    Task { await service.analyze(context: payload, images: images) }
                }
                .buttonStyle(ClinicalButtonStyle())
                .disabled(!consented || !service.hasKey || service.isRunning)
                .opacity((!consented || !service.hasKey || service.isRunning) ? 0.5 : 1)
            }
            .padding(20)
        }
    }
}
