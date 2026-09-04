import SwiftUI

/// A calm orientation card for the evidence clock already calculated by `EvidencePhase`.
/// It reports timing only; it never judges response or recommends a treatment.
struct EvidenceHorizonCard: View {
    let phase: EvidencePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ClinicalCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                horizonHeading

                Divider().overlay(Clinical.hairline)

                VStack(alignment: .leading, spacing: 7) {
                    reviewHeading
                    EvidenceProgressTrack(
                        value: phase.progressToReview,
                        accessibilityLabel: "Progress toward the next evidence review"
                    )
                    HStack {
                        Text("Started \(phase.start.formatted(.dateTime.day().month(.abbreviated)))")
                        Spacer()
                        Text("Week \(phase.nextReviewWeek) review")
                    }
                    .font(Clinical.caption(10))
                    .foregroundStyle(Clinical.tertiary)
                }
            }
            .background(alignment: .topTrailing) {
                BotanicalCardSprig(width: 115, opacity: 0.15).offset(x: 18, y: -18)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("evidenceHorizon")
    }

    @ViewBuilder
    private var horizonHeading: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    weekMedallion
                    Eyebrow(text: "Evidence horizon")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                phaseHeading
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                weekMedallion
                phaseHeading
                Spacer(minLength: 0)
            }
        }
    }

    private var phaseHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !dynamicTypeSize.isAccessibilitySize {
                Eyebrow(text: "Evidence horizon")
            }
            Text(phase.label)
                .font(Clinical.headline(19))
                .foregroundStyle(Clinical.ink)
            Text(anchorLine)
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.secondary)
        }
    }

    private var reviewHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                reviewLineText
                Spacer(minLength: 8)
                reviewDateText
            }
            VStack(alignment: .leading, spacing: 3) {
                reviewLineText
                reviewDateText
            }
        }
    }

    private var reviewLineText: some View {
        Text(reviewLine)
            .font(Clinical.body(13, weight: .medium))
            .foregroundStyle(Clinical.ink)
    }

    private var reviewDateText: some View {
        Text(phase.nextReviewDate.formatted(.dateTime.day().month(.abbreviated)))
            .font(Clinical.number(12))
            .foregroundStyle(Clinical.secondary)
    }

    private var weekMedallion: some View {
        ZStack {
            Image(BrandArt.medallion)
                .resizable().scaledToFit().blendMode(.multiply)
                .scaleEffect(1.4).clipShape(Circle())
            Circle().fill(Clinical.surface).padding(21)
            Circle().strokeBorder(Clinical.gold.opacity(0.30), lineWidth: 0.8).padding(5)
            VStack(spacing: -1) {
                Text("WEEK")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Clinical.secondary)
                Text("\(phase.week)")
                    .font(.system(size: 29, weight: .medium, design: .serif))
                    .foregroundStyle(Clinical.ink)
                    .minimumScaleFactor(0.7)
            }
            .padding(5)
        }
        .frame(width: 92, height: 92)
        .dynamicTypeSize(.large)
        .accessibilityLabel("Week \(phase.week)")
    }

    private var anchorLine: String {
        switch phase.anchor {
        case .treatment(let name): return "Tracking from the start of \(name)."
        case .record: return "Tracking from your first recorded day."
        }
    }

    private var reviewLine: String {
        phase.daysToReview == 0
            ? "Review window reached"
            : "Next review in \(phase.daysToReview) day\(phase.daysToReview == 1 ? "" : "s")"
    }
}
