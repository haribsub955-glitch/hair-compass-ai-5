import SwiftUI

/// Deterministic journal guidance, not an AI answer or a clinical interpretation.
struct WrenJournalNote: View {
    let moment: CompanionMoment
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CompanionView(moment: moment, size: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Clinical.headline(17)).foregroundStyle(Clinical.ink)
                Text(message).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Clinical.sage.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Clinical.sage.opacity(0.17)))
        .accessibilityElement(children: .combine)
    }
}
