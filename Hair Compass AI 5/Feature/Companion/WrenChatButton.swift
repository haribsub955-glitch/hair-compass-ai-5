import SwiftData
import SwiftUI

/// The always-available way to reach Wren: a small avatar button that sits above the tab bar and,
/// when tapped, expands into a bubble naming what she can do *on the screen you're actually on*
/// (`Companion.openingLine(for:)`). Tapping the expanded bubble opens the chat with that screen's
/// focus already set, so the first answer lands on what's in front of you.
///
/// Two states, deliberately:
/// - **Collapsed** — just Wren's portrait. Small enough to ignore, and it never covers content
///   (it sits in the tab bar's inset, right-aligned, clear of the bar's own labels).
/// - **Expanded** — the contextual line beside her. Auto-collapses after a few seconds so it can't
///   sit on top of the screen indefinitely.
///
/// It builds the same canonical `AIContext` snapshot at open time that `TodayView` and
/// `CompareView` do, from its own queries, so `RootView` doesn't grow five more of them.
struct WrenChatButton: View {
    let tab: AppTab
    let profile: Profile?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query private var snapshots: [HealthSnapshot]
    @Query private var triggers: [TriggerEvent]
    @Query private var labs: [LabResult]
    @Query private var sideEffects: [SideEffectLog]
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]
    @Query private var progressCheckIns: [ProgressCheckIn]

    @State private var expanded = false
    @State private var showChat = false
    @State private var contextJSON = ""
    /// Bumped on every expand so a later auto-collapse can tell whether it's still the current one.
    @State private var expansionID = 0

    private var line: String { Companion.openingLine(for: tab) }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showChat) {
            HairChatSheet(
                contextJSON: contextJSON,
                focus: Companion.chatFocus(for: tab),
                eyebrow: "Ask \(Companion.name)",
                // Per-screen starters: the chat opens proposing questions about the screen the
                // person is actually on, not the generic full-record set.
                starterKind: .screen(tab)
            )
        }
        // A new screen invalidates whatever she was offering about the old one.
        .onChange(of: tab) { _, _ in collapse() }
    }

    @ViewBuilder
    private var control: some View {
        if expanded {
            Button(action: openChat) {
                HStack(spacing: 10) {
                    avatar
                    Text(line)
                        .font(Clinical.caption(12.5))
                        .foregroundStyle(Clinical.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(Clinical.caption(11))
                        .foregroundStyle(Clinical.accent)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(bubbleBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask \(Companion.name). \(line)")
            .accessibilityHint("Opens the chat about this screen")
            .transition(
                reduceMotion
                    ? .opacity
                    : .scale(scale: 0.86, anchor: .trailing).combined(with: .opacity)
            )
        } else {
            Button(action: expand) {
                avatar
                    .padding(5)
                    .background(bubbleBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask \(Companion.name)")
            .accessibilityHint("Shows what \(Companion.name) can tell you about this screen")
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    private var avatar: some View {
        CompanionView(moment: .greeting, variant: .avatar, size: 34)
            .overlay(alignment: .bottomTrailing) {
                // The chat affordance the request asked for: she reads as a message button at a
                // glance, without losing the character.
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Clinical.surface)
                    .padding(3)
                    .background(Clinical.accent, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.canvas, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
    }

    private var bubbleBackground: some View {
        Capsule(style: .continuous)
            .fill(Clinical.surface)
            .overlay(Capsule(style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .shadow(color: Clinical.cardShadow, radius: 10, y: 4)
    }

    private func expand() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(motion) { expanded = true }
        expansionID += 1
        let id = expansionID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            // Only retract the expansion this task opened — a re-tap in the meantime wins.
            guard id == expansionID, expanded else { return }
            withAnimation(motion) { expanded = false }
        }
    }

    private func collapse() {
        expansionID += 1
        guard expanded else { return }
        withAnimation(motion) { expanded = false }
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    /// Snapshot the canonical context at open time — same pattern as `TodayView.openChat()`.
    private func openChat() {
        contextJSON = AIContext.build(
            entries: entries, treatments: treatments, doses: doses,
            snapshots: snapshots, triggers: triggers,
            labs: labs, sideEffects: sideEffects, photos: photos,
            profile: profile, progressCheckIns: progressCheckIns, now: .now
        ).jsonString()
        collapse()
        showChat = true
    }
}
