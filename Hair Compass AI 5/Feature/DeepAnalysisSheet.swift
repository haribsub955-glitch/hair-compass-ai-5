import SwiftData
import SwiftUI
import UIKit

/// Pro "deep analysis": a single, on-device written summary of the full tracking record via Apple
/// Intelligence (Foundation Models). Everything stays on the device — no network, no key, no
/// consent. Text only: it reasons over the deterministic `AIContext`, never over photo pixels
/// (Foundation Models has no image input), so scalp photos are not sent anywhere. Framed as
/// record-keeping, never diagnosis. Shows a clear card on hardware without on-device AI.
struct DeepAnalysisSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var service = OnDeviceAnalysisService()
    @State private var showChat = false
    @State private var chatDetent: PresentationDetent = .large
    @State private var chatContext = ""

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
                feature: "AI record summary",
                symbol: "sparkles.rectangle.stack",
                description: "A one-tap written read of your full tracking record — on-device and private, record-keeping, not diagnosis.",
                requiresOnDeviceAI: true
            ) {
                analysisContent
            }
            .clinicalScreen()
            .navigationTitle("Record summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .sheet(isPresented: $showChat) {
            HairChatSheet(
                contextJSON: chatContext, focus: chatFocus,
                eyebrow: "Ask about your record",
                starterKind: .fullRecord
            )
            .presentationDetents([.medium, .large], selection: $chatDetent)
        }
    }

    private var analysisContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // A masthead rather than a framed picture: the plate bleeds to the sheet's edges
                // and dissolves into the canvas instead of sitting in a bordered, shadowed
                // rectangle. `-20` cancels the `.padding(20)` on this stack; the sheet clips the
                // overflow at its own edge. `-8` on top pulls the art up under the grabber so the
                // sheet opens on paint, not on a margin.
                BrandWash(art: BrandArt.analysis, height: 138, opacity: 0.55, fade: 0.5)
                    .padding(.horizontal, -20)
                    .padding(.top, -8)
                ClinicalCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Record summary · on-device")
                        Text("Writes a plain-language summary of your recent readings, treatments and labs using Apple Intelligence. It runs entirely on your iPhone — nothing leaves the device — and it's record-keeping, not diagnosis.")
                            .font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
                    }
                }

                if !service.isAvailable {
                    let status = service.availability
                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkles").font(Clinical.caption(14)).foregroundStyle(Clinical.warning)
                                Text(status.message)
                                    .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                            }
                            if status.showsSettingsButton {
                                Button("Open Settings") {
                                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                    openURL(url)
                                }
                                .buttonStyle(ClinicalButtonStyle(filled: false))
                                .accessibilityIdentifier("deepAnalysisOpenSettings")
                            }
                        }
                    }
                }

                // Streams into view as the on-device model writes it: while running, this shows
                // the growing `streamingText` snapshot; once finished, `result` takes over (the
                // two never disagree — `result` is just the last snapshot, trimmed).
                if let text = service.result ?? service.streamingText, !text.isEmpty {
                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: service.result == nil ? "Writing…" : "Summary")
                            Text(text).font(Clinical.caption(15)).foregroundStyle(Clinical.ink)
                            Text("For record-keeping, not diagnosis.")
                                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                    if service.result != nil {
                        followUpChip
                    }
                }

                if let error = service.errorMessage {
                    ClinicalCard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").font(Clinical.caption(14)).foregroundStyle(Clinical.critical)
                            Text(error).font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                        }
                    }
                }

                Button {
                    let payload = AIContext.build(
                        entries: entries, treatments: treatments, doses: doses,
                        snapshots: snapshots, triggers: triggers,
                        labs: labs, sideEffects: sideEffects, photos: photos,
                        profile: profiles.first, progressCheckIns: progressCheckIns, now: .now
                    )
                    Task { await service.analyze(context: payload) }
                } label: {
                    if service.isRunning {
                        HStack(spacing: 8) {
                            ProgressView().tint(Clinical.surface)
                            Text("Analyzing…")
                        }
                    } else {
                        Text("Create record summary")
                    }
                }
                .buttonStyle(ClinicalButtonStyle())
                .disabled(!service.isAvailable || service.isRunning)
                .opacity((!service.isAvailable || service.isRunning) ? 0.5 : 1)
            }
            .padding(20)
        }
    }

    // MARK: Chat follow-up

    /// Same chip language as Compare's "Ask Wren about this": opens the restricted hair-science
    /// chat, grounded on the same full-record `AIContext` this summary was written from.
    private var followUpChip: some View {
        Button { openChat() } label: {
            Label("Ask a follow-up question", systemImage: "bubble.left.and.text.bubble.right")
                .font(Clinical.body(12, weight: .semibold))
                .foregroundStyle(Clinical.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Clinical.accentSoft)
                .clipShape(Capsule())
        }
        .buttonStyle(.clinicalPressable)
        .accessibilityLabel("Ask a follow-up question about this summary")
    }

    /// One line telling the chat what's on screen — the same full record the summary was
    /// written from, not a single chart.
    private var chatFocus: String {
        "User just created an on-device summary of their full tracking record and is asking a follow-up question about it."
    }

    /// Snapshot the canonical AIContext at open time — the chat consumes the same versioned
    /// JSON record the deep-analysis summary was written from.
    private func openChat() {
        chatContext = AIContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers,
            labs: labs, sideEffects: sideEffects, photos: photos,
            profile: profiles.first, progressCheckIns: progressCheckIns, now: .now
        ).jsonString()
        showChat = true
    }
}
