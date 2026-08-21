import SwiftUI
import UIKit

/// The hair-science chat sheet — opened from the Compare screen's "Ask Wren" chip over a specific
/// chart, from Today's "Ask Wren" button over the whole record, and from Deep analysis's
/// "Ask a follow-up question" chip. Explains the on-screen context over the canonical `AIContext`
/// JSON and allows restricted chatting — hair science and the person's own data only (the
/// restriction lives in `HairChatPrompt.system`). Header copy and starter questions are
/// parameterized (`eyebrow`/`starterKind`) so each entry point reads naturally. Text
/// only: photos never enter this feature. Answers come from the cloud model (DeepSeek) once
/// consented — `CloudAIConsentCard` is shown here before the first request could ever leave the
/// device — with Apple Intelligence as the on-device path otherwise; a clear card explains the
/// state when neither engine can run.
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
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped on foreground: `service.availability` is a static system read SwiftUI does not
    /// track, so the unavailable notice would otherwise survive the person enabling Apple
    /// Intelligence in Settings and returning.
    @State private var availabilityRefresh = 0
    @State private var service = HairChatService()
    @State private var draft = ""
    #if DEBUG
    @Environment(\.modelContext) private var modelContext
    /// One conversation, one id, for the life of this sheet — what scopes the agent's
    /// session-level memories so an aside here can't surface in an unrelated chat later.
    @State private var agentSessionID = UUID().uuidString
    #endif
    /// Bumped when the consent card records a choice — `CloudAIConsent` lives in UserDefaults,
    /// which SwiftUI cannot observe, so this is what re-evaluates `service.engine`.
    @State private var consentVersion = 0

    /// What `gatedContent` renders for. In DEBUG with `HC_AGENT`, the agent server answers and
    /// neither engine's availability applies — the sheet must reach the input bar or the agent
    /// is never called (mirrors `HairChatService.isAvailable`).
    private var renderedEngine: AIEngine {
        #if DEBUG
        if AgentBridge.isEnabled { return .onDevice }
        #endif
        return service.engine
    }
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ProGate(
                feature: "AI hair chat",
                symbol: "bubble.left.and.text.bubble.right",
                description: "Ask anything about your tracked data — grounded in your own numbers, never a diagnosis.",
                requiresOnDeviceAI: true
            ) {
                gatedContent
            }
        }
        .clinicalScreen()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { availabilityRefresh += 1 }
        }
        // Watch availability every 2 s in both directions while the sheet is up: the unavailable
        // notice clears the moment the model becomes usable, and reappears if it stops being
        // usable mid-session. Bumps only on change.
        .task {
            var last = service.availability
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let now = service.availability
                if now != last { last = now; availabilityRefresh += 1 }
            }
        }
        #if DEBUG
        // `HC_CHAT_ASK <question>` submits one question on open, so a chat turn — the agent's
        // whole tool-calling round trip included — can be exercised from `simctl launch` without
        // a hand on the keyboard. Same argument shape as `HC_TAB <tab>`.
        .task {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "HC_CHAT_ASK"), i + 1 < args.count else { return }
            submit(args[i + 1])
        }
        #endif
    }

    @ViewBuilder
    private var gatedContent: some View {
        // Read both refresh tokens BEFORE branching: with the available branch rendered, nothing
        // else here reads them, so an available → unavailable flip (or a consent choice) would
        // bump a token no rendered view depends on and this body would never re-evaluate
        // (codex review, 2026-09-02).
        let _ = availabilityRefresh
        let _ = consentVersion
        switch renderedEngine {
        case .cloud, .onDevice:
            conversation
            inputBar
        case .needsCloudConsent:
            ScrollView(showsIndicators: false) {
                CloudAIConsentCard { consentVersion += 1 }
                    .padding(20)
            }
        case .unavailable(let message):
            unavailableNotice(message)
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
                    } else if let activity = service.activityNote {
                        activityRow(activity)
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
                .animation(.easeOut(duration: 0.2), value: service.activityNote)
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

    /// Two speakers, two shapes — and the asymmetry is the point.
    ///
    /// A question is an utterance: discrete, yours, so it keeps its copper pill. An answer is the
    /// app talking about your own record, so it is set as prose on the canvas with no card around
    /// it, the way every other considered surface in this app reads (`CareView`'s ledger rows,
    /// the retired tab-bar capsule). Boxing Wren's replies made the chat look like a widget
    /// bolted onto the app instead of part of it.
    private func bubble(_ message: ChatMessage) -> some View {
        message.role == .user ? AnyView(userBubble(message)) : AnyView(wrenReply(message))
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 44)
            Text(message.text)
                .font(Clinical.caption(14))
                .foregroundStyle(Clinical.surface)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Clinical.accent)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 6)
        .transition(entrance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You: \(message.text)")
        .id(message.id)
    }

    private func wrenReply(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // A hairline and the name instead of a bubble outline: it marks who is speaking
            // without drawing a container, and matches the eyebrow rhythm used app-wide.
            HStack(spacing: 7) {
                CompanionView(moment: .listening, variant: .avatar, size: 20)
                Text(Companion.name.uppercased())
                    .font(Clinical.eyebrow(10))
                    .foregroundStyle(Clinical.tertiary)
                Rectangle()
                    .fill(Clinical.hairline)
                    .frame(height: 1)
            }
            Text(Self.formatted(message.text))
                .font(Clinical.body(15))
                .foregroundStyle(Clinical.ink)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !message.sources.isEmpty {
                sourceLine(message.sources)
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .transition(entrance)
        .contextMenu {
            // Worth having in a health app: an answer is often the thing you want to paste into
            // a note or hand to a clinician.
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Copy answer", systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Companion.name): \(message.text)")
        .id(message.id)
    }

    /// What the answer above was actually read from.
    ///
    /// The paywall promises answers "grounded in your own numbers, never a diagnosis". This is
    /// that claim made checkable rather than asserted: the agent chooses which parts of the
    /// record to open, and naming them lets someone see that an answer about their labs really
    /// did read their labs — and, just as usefully, that a general answer read only the evidence
    /// library and nothing personal at all.
    ///
    /// Kept deliberately quiet: tertiary, small, below the answer. It is provenance, not a
    /// headline, and a loud version would compete with the words that matter.
    private func sourceLine(_ sources: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "leaf")
                .font(Clinical.caption(10))
                .foregroundStyle(Clinical.sage)
            Text("Read \(ListFormatter.localizedString(byJoining: sources))")
                .font(Clinical.caption(11))
                .foregroundStyle(Clinical.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Read \(ListFormatter.localizedString(byJoining: sources))")
    }

    private var entrance: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
    }

    /// Renders the model's markdown instead of printing it. Without this an answer arrives as
    /// literal `**Growth rate:**` and reads as broken — the one flaw everybody notices first.
    /// `inlineOnlyPreservingWhitespace` keeps the line breaks that carry the answer's structure;
    /// full block parsing would collapse them into a paragraph. Leading list dashes become real
    /// bullets, since the model writes them and stripping them would lose the grouping.
    static func formatted(_ text: String) -> AttributedString {
        let bulleted = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return String(line) }
                return "•  " + trimmed.dropFirst(2)
            }
            .joined(separator: "\n")
        let parsed = try? AttributedString(
            markdown: bulleted,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return parsed ?? AttributedString(text)
    }

    /// The assistant's reply rendered live as it streams in, replacing the thinking dots the
    /// moment the first token arrives. Same look as a finished assistant bubble in `bubble(_:)`,
    /// just re-rendered on every new snapshot instead of once at the end.
    private func streamingBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                CompanionView(moment: .listening, variant: .avatar, size: 20)
                Text(Companion.name.uppercased())
                    .font(Clinical.eyebrow(10))
                    .foregroundStyle(Clinical.tertiary)
                Rectangle().fill(Clinical.hairline).frame(height: 1)
            }
            Text(Self.formatted(text))
                .font(Clinical.body(15))
                .foregroundStyle(Clinical.ink)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 16)
        .padding(.top, 10)
        .id("streaming")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Companion.name) is typing: \(text)")
    }

    /// What Wren is doing, not saying. Kept deliberately quiet and un-bubbled so it never reads
    /// as an answer: the agent's tool waves can take a while, and a silent screen looks broken.
    private func activityRow(_ note: String) -> some View {
        HStack(spacing: 8) {
            CompanionView(moment: .thinking, variant: .pose, size: 26)
            Text(note)
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .transition(.opacity)
        .id("thinking")
        .accessibilityLabel(note)
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
        #if DEBUG
        let agentContext = AgentChatContext(modelContext: modelContext, sessionID: agentSessionID)
        Task { await service.send(trimmed, context: contextJSON, focus: focus, agentContext: agentContext) }
        #else
        Task { await service.send(trimmed, context: contextJSON, focus: focus) }
        #endif
    }

    // Shown when neither engine can answer right now — cloud declined (or unconfigured) and no
    // on-device model. The reason matters: someone who's switched Apple Intelligence off, or
    // whose model is still downloading, gets a next step instead of being told their iPhone can't
    // do this. Honest and reassuring either way: everything else in the app still works.
    private func unavailableNotice(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 20)
            CompanionView(moment: .resting, variant: .avatar, size: 56)
            Text("AI unavailable")
                .font(Clinical.headline(18))
                .foregroundStyle(Clinical.ink)
            Text(message)
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }
}
