import SwiftUI

/// The hair-science chat sheet, opened from the Compare screen's "Ask AI" chip. Explains the
/// on-screen relationship over the canonical `AIContext` JSON and allows restricted chatting —
/// hair science and the person's own data only (the restriction lives in `HairChatPrompt.system`).
/// Text only: photos never enter this feature, and nothing is sent without `AIConsent`.
struct HairChatSheet: View {
    /// `AIContext.jsonString()` snapshot built by the caller when the sheet opens.
    let contextJSON: String
    /// One line describing what comparison is on screen, so answers land on it.
    let focus: String

    @Environment(\.dismiss) private var dismiss
    @State private var service = HairChatService()
    @State private var draft = ""
    @State private var consented = AIConsent.isGranted()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if consented {
                conversation
                if service.hasKey {
                    inputBar
                } else {
                    noKeyNotice
                }
            } else {
                ScrollView(showsIndicators: false) {
                    consentCard
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }
            }
        }
        .clinicalScreen()
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.text)")
        .id(message.id)
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(Clinical.tertiary)
            Text("Thinking…").font(.system(size: 13)).foregroundStyle(Clinical.tertiary)
        }
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
                ForEach(HairChatPrompt.starters(focus: focus), id: \.self) { starter in
                    Button { submit(starter) } label: {
                        Text(starter)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Clinical.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Clinical.accentSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
        draft = ""
        Task { await service.send(trimmed, context: contextJSON, focus: focus) }
    }

    private var noKeyNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key")
                .font(.system(size: 13))
                .foregroundStyle(Clinical.warning)
            Text("No API key is configured, so chat is unavailable. Everything else in the app works fully on-device.")
                .font(.system(size: 12))
                .foregroundStyle(Clinical.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Consent (first open, plain language — same spirit as AIConsentSheet, but for
    // the text-only chat: questions and the tracking summary leave the device, never photos)

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "Before your first chat")
                    Text("Your tracking summary would leave this device")
                        .font(Clinical.headline(20))
                        .foregroundStyle(Clinical.ink)
                    consentRow("doc.text", "What is sent",
                               "Your questions and a text summary of your tracking (shedding, scalp scores, treatments, labs). Never your photos.")
                    consentRow("cloud", "Where it goes",
                               "To Anthropic, the cloud AI provider that answers the chat. Data leaves your device only when you send a message.")
                    consentRow("hand.raised", "Your control",
                               "Nothing is sent until you allow it, and you can turn this off later in your profile's Privacy section.")
                }
            }
            Button("Allow and continue") {
                AIConsent.grant()
                consented = true
            }
            .buttonStyle(ClinicalButtonStyle())
            .accessibilityIdentifier("chatConsentAllow")

            Button("Not now") { dismiss() }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .accessibilityIdentifier("chatConsentNotNow")
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
