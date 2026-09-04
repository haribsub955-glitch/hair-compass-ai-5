import SwiftUI

/// An explicitly fictional record, never saved and never sent to a model. One entry settles
/// into a week; a reading follows. No simulated processing, endless motion or forced wait.
struct OnboardingRecordPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var record
    @State private var stage = 0
    @State private var replay = 0

    private var still: Bool { reduceMotion || MotionQA.isStatic }
    private var visibleStage: Int { still ? 2 : stage }
    private var playbackID: String { "\(replay)-\(still)-\(scenePhase == .active)" }

    var body: some View {
        ClinicalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow(text: "Example record")
                    Spacer()
                    if !still {
                        Button {
                            replay += 1
                        } label: {
                            Label("Replay", systemImage: "arrow.counterclockwise")
                                .font(Clinical.caption(12))
                                .foregroundStyle(Clinical.accent)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboardReplayPreview")
                    }
                }

                ZStack {
                    if visibleStage == 0 {
                        HStack(spacing: 12) {
                            recordMark
                                .frame(width: 38, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("A small check-in")
                                    .font(Clinical.body(15, weight: .medium))
                                Text("Shedding · scalp · daily context")
                                    .font(Clinical.caption(12))
                                    .foregroundStyle(Clinical.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(Clinical.canvas, in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(0..<7) { day in
                                VStack(spacing: 8) {
                                    if day == 3 {
                                        recordMark.frame(height: 44)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(day == 0 || day == 1 ? Clinical.sage.opacity(0.4) : Clinical.hairline.opacity(0.5))
                                            .frame(height: 44)
                                            .overlay {
                                                if day == 0 || day == 1 {
                                                    Image(systemName: "checkmark")
                                                        .font(Clinical.body(11, weight: .medium))
                                                        .foregroundStyle(Clinical.positive)
                                                }
                                            }
                                    }
                                    Text(["M", "T", "W", "T", "F", "S", "S"][day])
                                        .font(Clinical.eyebrow(10))
                                        .foregroundStyle(Clinical.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Example week: three check-ins. Unrecorded days remain empty.")
                    }
                }
                .frame(minHeight: 90)
                .foregroundStyle(Clinical.ink)

                HStack(alignment: .top, spacing: 10) {
                    Image(CompanionArt.listening)
                        .resizable().scaledToFit().frame(width: 38, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little context, from \(Companion.name)")
                            .font(Clinical.body(13, weight: .medium))
                            .foregroundStyle(Clinical.ink)
                        Text("“Three check-ins this week. The gaps stay visible, and it’s too early to call a trend.”")
                            .font(Clinical.caption(13))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(visibleStage >= 2 ? 1 : 0)
                .offset(y: visibleStage >= 2 || still ? 0 : 6)
                .accessibilityHidden(visibleStage < 2)
                Text("Illustration only—not your data or a prediction.")
                    .font(Clinical.caption(11))
                    .foregroundStyle(Clinical.secondary)
            }
        }
        .task(id: playbackID) {
            guard !still, scenePhase == .active else {
                stage = 2
                return
            }
            stage = 0
            do {
                try await Task.sleep(for: .seconds(MotionSpec.onboarding.recordDelay))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: MotionSpec.onboarding.settle)) { stage = 1 }
                try await Task.sleep(for: .seconds(MotionSpec.onboarding.noteDelay))
                try Task.checkCancellation()
                withAnimation(.easeOut(duration: MotionSpec.onboarding.noteFade)) { stage = 2 }
            } catch { /* Leaving the screen or changing accessibility cancels playback. */ }
        }
    }

    private var recordMark: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Clinical.accentSoft)
            .overlay {
                Image(systemName: "checkmark")
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.accent)
            }
            .matchedGeometryEffect(id: "check-in", in: record)
            .accessibilityHidden(true)
    }
}
