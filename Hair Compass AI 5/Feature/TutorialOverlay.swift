import SwiftUI
import UIKit

/// The first-launch coach sequence: five cards anchored above the floating tab bar. Advancing
/// switches the LIVE tab underneath so the user sees the real screen each card describes,
/// rather than a static mockup. "Skip tour" is always available; the last page's primary
/// button reads "Done". Presented from `RootView` as a full-screen `.overlay`, positioned so
/// the tab bar (zIndex 100, drawn via `.safeAreaInset`) stays undimmed and interactive above
/// the scrim.
struct TutorialOverlay: View {
    @Binding var tab: AppTab
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private struct Page {
        let tab: AppTab
        let title: String
        let line: String
    }

    private static let pages: [Page] = [
        .init(tab: .today, title: "Today",
              line: "Log your day in seconds — shedding, scalp, and treatments live here."),
        .init(tab: .trends, title: "Trends",
              line: "Every log builds these charts. Apple Health fills in sleep and recovery automatically."),
        .init(tab: .care, title: "Plan",
              line: "Your treatments and routines, with reminders and refill tracking."),
        .init(tab: .labs, title: "Labs",
              line: "The blood work that matters for hair — ferritin, thyroid, vitamin D."),
        .init(tab: .photos, title: "Photos",
              line: "Standardized progress photos — your most objective signal."),
    ]

    private var current: Page { Self.pages[page] }
    private var isLast: Bool { page == Self.pages.count - 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed scrim. It geometrically extends under the tab bar too, but the tab bar
            // (opaque, zIndex 100, drawn via the enclosing safeAreaInset) always paints above
            // it — so the tab bar itself never reads as dimmed, and taps land on it, not here.
            Clinical.ink.opacity(0.25)
                .ignoresSafeArea()

            card
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
        .transition(.opacity)
        .onAppear { tab = current.tab }
        .onChange(of: page) { _, newValue in
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
                tab = Self.pages[newValue].tab
            }
        }
    }

    // MARK: Card

    private var card: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Eyebrow(text: "Quick tour · \(page + 1) of \(Self.pages.count)")
                    Spacer(minLength: 8)
                    dots
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(current.title)
                        .font(Clinical.headline(22))
                        .foregroundStyle(Clinical.ink)
                    Text(current.line)
                        .font(.system(size: 14))
                        .foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(page)
                .transition(pageTransition)

                VStack(spacing: 10) {
                    Button(isLast ? "Done" : "Next") { advance() }
                        .buttonStyle(ClinicalButtonStyle())
                        .accessibilityIdentifier("tutorialNext")

                    Button("Skip tour") { skip() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Clinical.tertiary)
                        .accessibilityIdentifier("tutorialSkip")
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(Self.pages.indices, id: \.self) { i in
                Circle()
                    .fill(i == page ? Clinical.accent : Clinical.hairline)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    // MARK: Actions

    private func advance() {
        if isLast {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) { page += 1 }
        }
    }

    private func skip() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onDone()
    }
}
