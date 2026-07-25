import SwiftUI

/// The in-clinic options catalogue — every procedure a clinic might offer for hair loss, in one
/// place, each with its own illustration, an evidence grade on the app's shared scale, the typical
/// rhythm, and the one caution worth raising before agreeing to it.
///
/// This is **not** `ProceduresView`. That screen is the person's own booked and completed
/// appointments — a log. This one is a reference you read *before* you have anything booked, and
/// the two are deliberately separate: mixing "what exists" into "what I've had" would make a
/// browsing list look like a history.
///
/// The framing rule, inherited from `ProcedureGuide` and stated at the top of the screen where it
/// cannot be missed: **education only, never a recommendation to undergo.** Listing something is
/// not endorsing it — which is exactly why mesotherapy appears here graded `.weak` rather than
/// being quietly omitted. A catalogue that only showed the flattering options would be an advert.
///
/// Ordering is `ProcedureGuide.catalogueOrder` — strongest evidence first, non-treatments last —
/// so the screen never opens on its weakest entry.
struct InClinicOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(eyebrow: "Procedures", title: "In-clinic options")
                        .padding(.top, 8)

                    InfoCallout(
                        text: "Education only — what clinics offer for hair loss and how strong the "
                            + "evidence is. Never a recommendation to undergo anything; discuss any "
                            + "procedure with your clinician."
                    )

                    ForEach(ProcedureGuide.catalogueOrder) { type in
                        OptionCard(type: type)
                    }

                    Colophon(text: "Evidence grades describe the published research for hair loss in "
                                 + "general, not a prediction for you. Costs, protocols and who's a "
                                 + "suitable candidate all vary by clinic.")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Clinical.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct OptionCard: View {
    let type: ProcedureType

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(type.art)
                .resizable()
                .scaledToFill()
                .frame(height: typeSize.isAccessibilitySize ? 130 : 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Clinical.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                // Title and evidence badge share a row normally; at accessibility sizes the badge
                // drops beneath so neither gets squeezed to a sliver.
                titleAndBadge

                Text(ProcedureGuide.summary(for: type))
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let cadence = ProcedureGuide.cadence(for: type) {
                    detailLine(symbol: "calendar", text: cadence, tint: Clinical.tertiary)
                }

                if let caution = ProcedureGuide.caution(for: type) {
                    detailLine(symbol: "exclamationmark.triangle", text: caution, tint: Clinical.warning)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Clinical.surfaceWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Clinical.hairline, lineWidth: 1)
        )
        .shadow(color: Clinical.cardShadow, radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var titleAndBadge: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                title
                TierBadge(tier: ProcedureGuide.evidence(for: type))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                title
                Spacer(minLength: 8)
                TierBadge(tier: ProcedureGuide.evidence(for: type))
            }
        }
    }

    private var title: some View {
        Text(type.title)
            .font(Clinical.headline(19))
            .foregroundStyle(Clinical.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detailLine(symbol: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(Clinical.caption(12))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One sentence for VoiceOver instead of six fragments, with the evidence grade spoken as
    /// words rather than left as an unlabelled pill.
    private var accessibilityDescription: String {
        var parts = [
            type.title,
            ProcedureGuide.evidence(for: type).title,
            ProcedureGuide.summary(for: type),
        ]
        if let cadence = ProcedureGuide.cadence(for: type) { parts.append("Typical rhythm: \(cadence).") }
        if let caution = ProcedureGuide.caution(for: type) { parts.append("Worth asking about: \(caution)") }
        return parts.joined(separator: ". ")
    }
}
