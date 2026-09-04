import SwiftUI

/// A compact greeting leaves the first screenful available for the daily check-in.
struct TodayJournalHeader: View {
  let greeting: String
  let onOpenBaseline: () -> Void

  var body: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 5) {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
          .font(Clinical.eyebrow(10)).tracking(1.3).foregroundStyle(Clinical.secondary)
        Text(greeting).font(Clinical.headline(27)).foregroundStyle(Clinical.ink)
      }
      Spacer(minLength: 8)
      HeaderActionButton(
        systemName: "person", accessibilityLabel: "Profile and settings", action: onOpenBaseline)
    }
    .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("todayJournalHeader")
  }
}

/// The Ceramic Horizon concept, driven by elapsed time only—not a hair-health score.
/// Supporting context below the daily actions, rather than a barrier to reaching them.
struct TodayJournalHero: View {
  let phase: EvidencePhase?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(spacing: 8) {
      ZStack {
        Circle().trim(from: 0.08, to: 0.92)
          .stroke(
            Clinical.hairline.opacity(0.65), style: StrokeStyle(lineWidth: 13, lineCap: .round)
          )
          .rotationEffect(.degrees(90))
        Circle().trim(from: 0.08, to: 0.08 + 0.84 * (phase?.progressToReview ?? 0))
          .stroke(
            AngularGradient(
              colors: [Clinical.gold, Clinical.accent, Clinical.accent.opacity(0.5)],
              center: .center, startAngle: .degrees(90), endAngle: .degrees(450)),
            style: StrokeStyle(lineWidth: 13, lineCap: .round)
          )
          .rotationEffect(.degrees(90))
        Circle().strokeBorder(Clinical.gold.opacity(0.25), lineWidth: 0.75).padding(14)
        VStack(spacing: 7) {
          Image(systemName: "sun.horizon")
            .font(.system(size: 31, weight: .ultraLight)).foregroundStyle(Clinical.accent)
          Text(phase.map { "Week \($0.week)" } ?? "Your compass")
            .font(Clinical.headline(31, weight: .medium)).foregroundStyle(Clinical.ink)
            .lineLimit(1).minimumScaleFactor(0.65)
          Text(phase.map { "of \($0.nextReviewWeek) to review" } ?? "One observation at a time")
            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
        }
        .padding(.horizontal, 22)
        .multilineTextAlignment(.center)
      }
      .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 236)
      .frame(height: dynamicTypeSize.isAccessibilitySize ? 310 : 236)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        phase.map {
          "Week \($0.week), next review at week \($0.nextReviewWeek). Elapsed time, not a health score."
        } ?? "Your record starts with one observation.")
      Text(phase?.label ?? "A beginning, not a verdict")
        .font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
      Text("One observation is not a trend.")
        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(alignment: .topTrailing) {
      BotanicalCardSprig(width: 150, opacity: 0.44).offset(x: 18, y: 0)
    }
    .background(alignment: .bottomLeading) {
      BotanicalCardSprig(width: 118, opacity: 0.30).rotationEffect(.degrees(180)).offset(
        x: -18, y: 0)
    }
    .padding(.vertical, 12)
    .accessibilityIdentifier("todayJournalHero")
  }
}
