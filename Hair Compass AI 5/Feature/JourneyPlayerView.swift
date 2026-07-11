import Combine
import SwiftUI

struct JourneyFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let caption: String
}

/// Plays a same-region photo series (any count) as a scrubbable timelapse. The count is
/// explicit ("aggregating N photos") so the journey reads as an aggregation of real captures,
/// never a synthesized prediction.
struct JourneyPlayerView: View {
    let frames: [JourneyFrame]
    var isExample: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index: Double = 0
    @State private var isPlaying = false

    private var count: Int { frames.count }
    private var currentIndex: Int {
        min(max(Int(index.rounded()), 0), max(count - 1, 0))
    }
    private var currentFrame: JourneyFrame? {
        guard frames.indices.contains(currentIndex) else { return nil }
        return frames[currentIndex]
    }

    // Loops every ~0.6s while playing; auto-advances one frame per tick.
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    imageStage

                    if let frame = currentFrame {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(frame.caption)
                                .font(Clinical.headline(20))
                                .foregroundStyle(Clinical.ink)
                            if count > 0 {
                                Text("FRAME \(currentIndex + 1) OF \(count)")
                                    .font(Clinical.eyebrow(10))
                                    .foregroundStyle(Clinical.secondary)
                            }
                        }
                    }

                    if count > 1 {
                        transport
                    }

                    Text("Aggregating \(count) photo\(count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(Clinical.secondary)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .onReceive(timer) { _ in
            guard isPlaying, count > 1 else { return }
            advance()
        }
    }

    // MARK: Image stage

    private var imageStage: some View {
        ZStack(alignment: .top) {
            Group {
                if let frame = currentFrame {
                    Image(uiImage: frame.image)
                        .resizable()
                        .scaledToFill()
                        .id(currentIndex)
                        .transition(reduceMotion ? .identity : .opacity)
                } else {
                    Clinical.canvas.overlay(Image(systemName: "photo").foregroundStyle(Clinical.tertiary))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))

            if isExample {
                Text("EXAMPLE — A TRACKED 6-MONTH JOURNEY")
                    .font(Clinical.eyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(Clinical.surface)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Clinical.accent, in: Capsule())
                    .padding(10)
                    .accessibilityLabel("Example. A tracked six month journey, not your own data.")
            }
        }
        .background(Clinical.canvas)
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { index },
                    set: { newValue in
                        isPlaying = false
                        index = newValue
                    }
                ),
                in: 0...Double(max(count - 1, 0)),
                step: 1
            )
            .tint(Clinical.accent)
            .accessibilityLabel("Journey timeline")
            .accessibilityValue("Frame \(currentIndex + 1) of \(count)")

            HStack {
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Clinical.surface)
                        .frame(width: 44, height: 44)
                        .background(Clinical.ink, in: Circle())
                }
                .buttonStyle(.clinicalPressable)
                .accessibilityLabel(isPlaying ? "Pause journey" : "Play journey")

                Spacer()
            }
        }
    }

    private func advance() {
        let next = currentIndex + 1
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            index = Double(next >= count ? 0 : next)
        }
    }
}
