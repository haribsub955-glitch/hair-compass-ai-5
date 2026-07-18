import SwiftUI

/// The hair-science chat sheet, opened from the Compare screen's "Ask AI" chip. Explains the
/// on-screen relationship over the canonical `AIContext` JSON and allows restricted chatting —
/// hair science and the person's own data only (the restriction lives in `HairChatPrompt.system`).
/// Text only: photos never enter this feature, and it runs entirely on-device (Apple Intelligence)
/// — nothing leaves the device. Shows a clear card on hardware without on-device AI.
struct HairChatSheet: View {
    /// `AIContext.jsonString()` snapshot built by the caller when the sheet opens.
    let contextJSON: String
    /// One line describing what comparison is on screen, so answers land on it.
    let focus: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "Ask about your data")
                Text("Explain this chart")
                    .font(Clinical.headline(24))
                    .foregroundStyle(Clinical.ink)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Clinical.secondary)
                    .frame(width: 30, height: 30)
                    .background(Clinical.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
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
                    if service.isRunning {
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
            }
            .onChange(of: service.messages.count) {
                guard let last = service.messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: service.isRunning) {
                guard service.isRunning else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("thinking", anchor: .bottom) }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            Text(message.text)
                .font(.system(size: 14))
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
        .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.text)")
        .id(message.id)
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                // Reduce Motion: no looping animation — a static ellipsis.
                Text("…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Clinical.tertiary)
                    .accessibilityHidden(true)
            } else {
                ThinkingDots()
            }
            Text("Thinking").font(.system(size: 13)).foregroundStyle(Clinical.tertiary)
        }
        .transition(.opacity)
        .accessibilityLabel("Assistant is thinking")
    }

    private func errorRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Clinical.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(BrandArt.sprig)
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .opacity(0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Text("Answers stay about hair science and your own data. Not medical advice.")
                .font(.system(size: 13))
                .foregroundStyle(Clinical.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(HairChatPrompt.starters(focus: focus).enumerated()), id: \.element) { index, starter in
                    Button { submit(starter) } label: {
                        Text(starter)
                            .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 14))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Clinical.surface)
                    .frame(width: 38, height: 38)
                    .background(Clinical.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.clinicalPressable)
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

    // Shown on hardware without Apple Intelligence — chat runs on-device only, so there's no
    // cloud fallback. Honest and reassuring: everything else in the app still works.
    private var unavailableNotice: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 20)
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(Clinical.accent)
                .frame(width: 56, height: 56)
                .background(Clinical.accentSoft, in: Circle())
            Text("On-device AI unavailable")
                .font(Clinical.headline(18))
                .foregroundStyle(Clinical.ink)
            Text("Hair chat runs privately on your device with Apple Intelligence, which needs an iPhone 15 Pro or newer on iOS 26. Everything else in Hair Compass works fully on this device.")
                .font(.system(size: 13))
                .foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }
}

/// Three dots pulsing in sequence while the assistant is thinking — the app's only repeating
/// animation, alive only while the thinking row is on screen (it's torn down with the row when
/// `isRunning` flips off). Callers must swap this for static text under Reduce Motion.
private struct ThinkingDots: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Clinical.tertiary)
                    .frame(width: 6, height: 6)
                    .opacity(pulsing ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: pulsing
                    )
            }
        }
        .onAppear { pulsing = true }
        .onDisappear { pulsing = false }
        .accessibilityHidden(true)
    }
}
