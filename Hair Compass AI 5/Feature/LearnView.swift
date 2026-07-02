import SwiftUI

/// The Learn library — evidence-based flash cards you flip to reveal the answer. Category art is the
/// generated gouache brand style; every answer carries an honest evidence tier (or a "MYTH" verdict).
struct LearnView: View {
    @State private var selected: LearnCategory?

    private var cards: [FlashCard] {
        selected.map { LearnLibrary.cards(in: $0) } ?? LearnLibrary.cards
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: "Evidence library", title: "Learn").padding(.top, 8)

                categoryChips

                if let featured = cards.first {
                    FlashCardView(card: featured, featured: true)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(cards.dropFirst()) { card in
                            FlashCardView(card: card)
                        }
                    }
                }

                Text("Tap any card to flip it. Every answer is graded by how strong the evidence actually is.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", on: selected == nil) { selected = nil }
                ForEach(LearnCategory.allCases) { c in
                    chip(c.title, on: selected == c) { selected = (selected == c ? nil : c) }
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { action() } } label: {
            Text(title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(on ? Clinical.ink : Clinical.surface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A single flippable flash card. Front = question (+ category art on the featured card); back = the
/// evidence-aligned answer. Standard two-face 3D flip.
struct FlashCardView: View {
    let card: FlashCard
    var featured: Bool = false
    @State private var flipped = false

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)).opacity(flipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { flipped.toggle() }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: Faces

    private var front: some View {
        cardShell {
            VStack(alignment: .leading, spacing: featured ? 14 : 10) {
                if featured {
                    Image(card.category.art)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                HStack {
                    Eyebrow(text: card.category.eyebrow)
                    Spacer()
                    badge
                }
                Text(card.question)
                    .font(Clinical.headline(featured ? 22 : 17))
                    .foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label("Tap to flip", systemImage: "hand.tap")
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private var back: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Answer")
                    Spacer()
                    badge
                }
                Text(card.answer)
                    .font(.system(size: featured ? 16 : 13))
                    .foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label("Tap to flip back", systemImage: "arrow.uturn.backward")
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    @ViewBuilder
    private func cardShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: featured ? 300 : 168, alignment: .topLeading)
            .background(Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .shadow(color: Clinical.cardShadow, radius: 12, y: 5)
    }

    @ViewBuilder
    private var badge: some View {
        if card.isMyth {
            Text("MYTH")
                .font(Clinical.eyebrow(9)).tracking(0.8)
                .foregroundStyle(Clinical.critical)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Clinical.critical.opacity(0.12), in: Capsule())
        } else {
            TierBadge(tier: card.tier)
        }
    }
}
