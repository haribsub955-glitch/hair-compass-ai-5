import SwiftUI
import UIKit

/// The hair-science chat sheet — opened from the Compare screen's "Ask AI" chip over a specific
/// chart, from Today's "Ask AI" button over the whole record, and from Deep analysis's
/// "Ask a follow-up question" chip. Explains the on-screen context over the canonical `AIContext`
/// JSON and allows restricted chatting — hair science and the person's own data only (the
/// restriction lives in `HairChatPrompt.system`). Header copy and starter questions are
/// parameterized (`eyebrow`/`title`/`starterKind`) so each entry point reads naturally. Text
/// only: photos never enter this feature, and it runs entirely on-device (Apple Intelligence) —
/// nothing leaves the device. Shows a clear card on hardware without on-device AI.
struct HairChatSheet: View {
    /// `AIContext.jsonString()` snapshot built by the caller when the sheet opens.
    let contextJSON: String
    /// One line describing what's on screen, so answers land on it — a specific chart
    /// comparison, or the person's whole record when opened from Today/deep analysis.
    let focus: String
    /// Header eyebrow — defaults to the original Compare-sheet copy so existing callers are
    /// unaffected. Override for entry points that aren't about a chart.
    var eyebrow: String = "Ask about your data"
    /// Which starter questions to show in the empty state — see `HairChatPrompt.StarterKind`.
    var starterKind: HairChatPrompt.StarterKind = .chartComparison

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var service = HairChatService()
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ProGate(
                feature: "AI hair chat",
                symbol: "bubble.left.and.text.bubble.right",
                description: "Ask anything about your tracked data — grounded in your own numbers, never a diagnosis."
            ) {
                gatedContent
            }
        }
        .clinicalScreen()
    }

    @ViewBuilder
    private var gatedContent: some View {
        if service.isAvailable {
            conversation
            inputBar
        } else {
            unavailableNotice
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CompanionView(moment: .listening, variant: .avatar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(Companion.name)
                    .font(Clinical.headline(22))
                    .foregroundStyle(Clinical.ink)
                Text(eyebrow)
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(Clinical.secondary)
                    .frame(width: 30, height: 30)
                    .background(Clinical.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Close chat")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if service.messages.isEmpty {
                        emptyState
                    }
                    ForEach(service.messages) { bubble($0) }
                    if let streaming = service.streamingText {
                        streamingBubble(streaming)
                    } else if service.isRunning {
                        thinkingRow.id("thinking")
                    }
                    if let error = service.errorMessage {
                        errorRow(error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                // Drive the bubble insertion transitions: a soft spring as a message lands
                // (Reduce Motion: a plain ease, and the transition itself is opacity-only).
                .animation(
                    reduceMotion ? .easeOut(duration: 0.22) : .spring(response: 0.35, dampingFraction: 0.8),
                    value: service.messages.count
                )
                .animation(.easeOut(duration: 0.2), value: service.isRunning)
                .animation(.easeOut(duration: 0.2), value: service.streamingText != nil)
            }
            .onChange(of: service.messages.count) {
                guard let last = service.messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: service.isRunning) {
                guard service.isRunning else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("thinking", anchor: .bottom) }
            }
            .onChange(of: service.streamingText) {
                guard service.streamingText != nil else { return }
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            Text(message.text)
                .font(Clinical.caption(14))
                .foregroundStyle(isUser ? Clinical.surface : Clinical.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Clinical.accent : Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isUser ? Color.clear : Clinical.hairline, lineWidth: 1)
                )
            if !isUser { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isUser ? "You" : Companion.name): \(message.text)")
        .id(message.id)
    }

    /// The assistant's reply rendered live as it streams in, replacing the thinking dots the
    /// moment the first token arrives. Same look as a finished assistant bubble in `bubble(_:)`,
    /// just re-rendered on every new snapshot instead of once at the end.
    private func streamingBubble(_ text: String) -> some View {
        HStack(spacing: 0) {
            Text(text)
                .font(Clinical.caption(14))
                .foregroundStyle(Clinical.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Clinical.hairline, lineWidth: 1)
                )
            Spacer(minLength: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("streaming")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Companion.name) is typing: \(text)")
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            CompanionView(moment: .thinking, variant: .pose, size: 30)
            Text("\(Companion.name) is thinking")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.tertiary)
        }
        .transition(.opacity)
        .accessibilityLabel("\(Companion.name) is thinking")
    }

    private func errorRow(_ text: String) -> some View {
        Text(text)
            .font(Clinical.caption(12))
            .foregroundStyle(Clinical.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            CompanionView(moment: .listening, variant: .pose, size: 84)
            if let hello = Companion.line(for: .greeting) {
                Text(hello)
                    .font(Clinical.body(14, weight: .medium))
                    .foregroundStyle(Clinical.ink)
            }
            Text("Answers stay about hair science and your own data. Not medical advice.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(HairChatPrompt.starters(focus: focus, kind: starterKind).enumerated()), id: \.element) { index, starter in
                    Button { submit(starter) } label: {
                        Text(starter)
                            .font(Clinical.body(13, weight: .medium))
                            .foregroundStyle(Clinical.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Clinical.accentSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.clinicalPressable)
                    .staggeredEntrance(index: min(index, 2))
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your hair data…", text: $draft, axis: .vertical)
                .font(Clinical.caption(14))
                .foregroundStyle(Clinical.ink)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Clinical.hairline, lineWidth: 1)
                )
                .focused($inputFocused)
                .onSubmit { submit(draft) }
            Button { submit(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(Clinical.body(15, weight: .semibold))
                    .foregroundStyle(Clinical.surface)
                    .frame(width: 38, height: 38)
                    .background(Clinical.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.clinicalPressable)
            .minimumHitTarget()
            .disabled(sendDisabled)
            .opacity(sendDisabled ? 0.4 : 1)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Clinical.canvas)
    }

    private var sendDisabled: Bool {
        service.isRunning || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !service.isRunning else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        draft = ""
        Task { await service.send(trimmed, context: contextJSON, focus: focus) }
    }

    // Shown when on-device chat can't run right now. Chat is on-device only, so there's no cloud
    // fallback — but the reason matters: someone who's simply switched Apple Intelligence off, or
    // whose model is still downloading, gets a next step instead of being told their iPhone can't
    // do this. Honest and reassuring either way: everything else in the app still works.
    private var unavailableNotice: some View {
        let status = service.availability
        return VStack(spacing: 12) {
            Spacer(minLength: 20)
            CompanionView(moment: .resting, variant: .avatar, size: 56)
            Text("On-device AI unavailable")
                .font(Clinical.headline(18))
                .foregroundStyle(Clinical.ink)
            Text(status.message)
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if status.showsSettingsButton {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .accessibilityIdentifier("hairChatOpenSettings")
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }
}
