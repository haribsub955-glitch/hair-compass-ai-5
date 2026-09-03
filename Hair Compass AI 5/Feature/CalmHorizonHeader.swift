//
//  CalmHorizonHeader.swift
//  Hair Compass AI 5
//
//  Where the person is in the plan, drawn as a quiet path: Baseline — You are here — Review.
//  Wren sits on the current position instead of floating as an unrelated button. The answer is
//  ahead in time; the header says how far. Nothing here is a score.
//
//  Motion (G2 motion amendment M1): the path draws Baseline → current once on first appear, the
//  Wren marker seeks to its position and settles, then carries a subtle decorative drift. Every
//  stage gates on Reduce Motion or the DEBUG HC_MOTION_STATIC switch and keeps its end state.
//

import SwiftUI

struct CalmHorizonHeader: View {
    let greeting: String
    let phase: EvidencePhase?
    var onOpenBaseline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                        .font(Clinical.eyebrow(10)).tracking(1.4).foregroundStyle(Clinical.secondary)
                    Text(greeting).font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
                }
                Spacer()
                Button(action: onOpenBaseline) {
                    Image(systemName: "person.circle")
                        .font(Clinical.caption(22))
                        .foregroundStyle(Clinical.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile and settings")
            }
            if let phase {
                Text(phaseEyebrow(phase))
                    .font(Clinical.eyebrow(11)).tracking(1.4)
                    .foregroundStyle(Clinical.secondary)
                    .accessibilityAddTraits(.isHeader)
                HorizonPath(phase: phase)
                Text(reviewLine(phase))
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calmHorizon")
    }

    private func phaseEyebrow(_ phase: EvidencePhase) -> String {
        "Day \(phase.dayNumber) · \(phase.label)".uppercased()
    }

    private func reviewLine(_ phase: EvidencePhase) -> String {
        switch phase.daysToReview {
        case 0: return "Your next meaningful review is today."
        case 1: return "Your next meaningful review is tomorrow."
        default: return "Your next meaningful review is in \(phase.daysToReview) days."
        }
    }
}

/// Baseline — You are here — Review, drawn once. A hairline runs the full width; an accent
/// segment draws from the Baseline dot to the Wren marker's rest position over
/// `MotionSpec.horizon.draw`, the marker seeks from the Baseline dot to that position on a
/// spring beginning `MotionSpec.horizon.markerDelay` into the draw, the Review dot fades in as
/// the line finishes, and — only once the marker has settled — it carries a slow decorative
/// bob through `MotionTimeline(cadence: .decorative)`. Reduce Motion / `MotionQA.isStatic`
/// render every mark in its final position with a single 0.28 s opacity fade.
private struct HorizonPath: View {
    let phase: EvidencePhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAnimated = false
    @State private var lineDrawn: CGFloat = 0       // 0…1, Baseline → marker rest position
    @State private var markerProgress: CGFloat = 0  // 0 = at Baseline, 1 = at rest position
    @State private var markerOpacity: Double = 0
    @State private var reviewDotOpacity: Double = 0
    @State private var settled = false              // gates the decorative drift
    @State private var staticVisible = false

    private var isStatic: Bool { reduceMotion || MotionQA.isStatic }
    private let rowHeight: CGFloat = 36
    private let dotRadius: CGFloat = 5
    private let markerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let markerStartX = dotRadius
                let restX = markerRestX(width: width)
                let travel = max(0, restX - markerStartX)
                let lineWidth = travel * lineDrawn
                let markerX = markerStartX + travel * markerProgress
                let midY = rowHeight / 2

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Clinical.hairline)
                        .frame(width: max(0, width), height: 1)
                        .position(x: width / 2, y: midY)
                    Rectangle()
                        .fill(Clinical.accent)
                        .frame(width: lineWidth, height: 1.5)
                        .position(x: markerStartX + lineWidth / 2, y: midY)
                    Circle()
                        .fill(Clinical.sage)
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .position(x: markerStartX, y: midY)
                    Circle()
                        .strokeBorder(Clinical.hairline, lineWidth: 1.5)
                        .background(Circle().fill(Clinical.canvas))
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .opacity(reviewDotOpacity)
                        .position(x: width - dotRadius, y: midY)
                    marker
                        .opacity(markerOpacity)
                        .position(x: markerX, y: midY)
                }
            }
            .frame(height: rowHeight)
            // Labels: "Baseline" and "Week N review" stay anchored to the row's ends; "You are
            // here" centres under the marker's rest position (Important 4) via `.position`,
            // rather than sitting equidistant between the other two the way a plain three-way
            // HStack would place it once the marker itself is no longer always centered.
            GeometryReader { geo in
                let restX = markerRestX(width: geo.size.width)
                ZStack {
                    HStack {
                        Text("Baseline")
                        Spacer()
                        Text("Week \(phase.nextReviewWeek) review")
                    }
                    Text("You are here")
                        .position(x: restX, y: geo.size.height / 2)
                }
            }
            .frame(height: 14)
            .font(Clinical.caption(10.5))
            .foregroundStyle(Clinical.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 2)
        .opacity(isStatic ? (staticVisible ? 1 : 0) : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Baseline behind you, you are here, week \(phase.nextReviewWeek) review ahead")
        .onAppear { animate() }
    }

    /// The marker's target x, as a fraction of the row's own width — `progressToReview`
    /// (Important 4) clamped away from either dot so the marker (and Wren) never sits on top of
    /// Baseline or the review dot.
    private func markerRestX(width: CGFloat) -> CGFloat {
        let markerStartX = dotRadius
        let fullTravel = max(0, width - 2 * dotRadius)
        let clampedProgress = min(0.88, max(0.12, phase.progressToReview))
        return markerStartX + fullTravel * clampedProgress
    }

    @ViewBuilder
    private var marker: some View {
        MotionTimeline(cadence: .decorative) { timeline, timelineReduceMotion in
            let amplitude: CGFloat = (settled && !timelineReduceMotion && !MotionQA.isStatic)
                ? MotionSpec.horizon.driftAmplitude : 0
            let t = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: MotionSpec.horizon.driftPeriod)
            let bob = amplitude * CGFloat(sin(2 * .pi * t / MotionSpec.horizon.driftPeriod))
            ZStack {
                Circle().strokeBorder(Clinical.accent, lineWidth: 1.5).frame(width: markerRadius * 2, height: markerRadius * 2)
                CompanionView(moment: .resting, variant: .avatar, size: markerRadius * 5 / 3)
            }
            .offset(y: bob)
        }
    }

    private func animate() {
        guard !hasAnimated else { return }
        hasAnimated = true
        if isStatic {
            lineDrawn = 1
            markerProgress = 1
            markerOpacity = 1
            reviewDotOpacity = 1
            settled = true
            withAnimation(.easeOut(duration: 0.28)) { staticVisible = true }
            return
        }
        staticVisible = true
        withAnimation(.easeInOut(duration: MotionSpec.horizon.draw)) {
            lineDrawn = 1
        }
        withAnimation(.easeOut(duration: MotionSpec.horizon.markerFade).delay(MotionSpec.horizon.markerDelay)) {
            markerOpacity = 1
        }
        withAnimation(
            .spring(response: MotionSpec.horizon.markerSpring.response,
                    dampingFraction: MotionSpec.horizon.markerSpring.damping)
            .delay(MotionSpec.horizon.markerDelay),
            completionCriteria: .logicallyComplete
        ) {
            markerProgress = 1
        } completion: {
            settled = true
        }
        withAnimation(.easeOut(duration: MotionSpec.horizon.reviewDotFade).delay(0.9)) {
            reviewDotOpacity = 1
        }
    }
}
