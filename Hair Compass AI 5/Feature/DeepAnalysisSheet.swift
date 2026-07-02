import SwiftUI
import UIKit

/// Opt-in cloud "deep analysis". Explicit off-device-data consent up front, then a single Claude
/// Fable 5 call over the deterministic facts plus matched progress photos. Framed as
/// record-keeping, never diagnosis.
struct DeepAnalysisSheet: View {
    let context: InsightContext
    let images: [UIImage]

    @Environment(\.dismiss) private var dismiss
    @State private var service = CloudAnalysisService()
    @State private var consented = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
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
                        Task { await service.analyze(context: context, images: images) }
                    }
                    .buttonStyle(ClinicalButtonStyle())
                    .disabled(!consented || !service.hasKey || service.isRunning)
                    .opacity((!consented || !service.hasKey || service.isRunning) ? 0.5 : 1)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Deep analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
