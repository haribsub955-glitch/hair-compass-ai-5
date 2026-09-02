import SwiftUI

/// Renders a `LabProposal`: for a lab-confirmed deficiency, the gated supplement(s) — each
/// carrying its evidence tier, funding disclosure, and buy link only once one is configured —
/// plus, for iron, a clinician caution alongside the product. For a medical finding (thyroid,
/// or any above-range result) it shows only the clinician note; this app never sells against a
/// hormonal or above-range result. Mirrors the product-row + disclosure idiom from
/// `ScienceProductsView`'s "Science-backed options" section.
struct LabProposalCard: View {
    let proposal: LabProposal
    @Environment(AffiliateStore.self) private var affiliates
    @Environment(\.openURL) private var openURL

    private var products: [ScienceProduct] {
        proposal.productIDs.compactMap { ScienceCatalog[$0] }
    }

    var body: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "What this may mean")
                Text(proposal.deficiency)
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.ink)

                if !products.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(products) { product in
                            productRow(product)
                            if product.id != products.last?.id {
                                Divider().overlay(Clinical.hairline)
                            }
                        }
                    }
                    Text("Affiliate disclosure: if you buy through these links we may earn a commission. It never changes a product's evidence rating.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }

                if let note = proposal.clinicianNote {
                    clinicianNote(note)
                }

                Text("Record-keeping, not medical advice.")
                    .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
            }
        }
    }

    private func productRow(_ product: ScienceProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(product.name).font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.ink)
                Label(product.route.label, systemImage: product.route.symbol)
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                Spacer()
                ProductBadge(evidence: product.evidence)
            }
            Text(product.summary).font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)

            if product.industryFunded {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "building.2").font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                    Text("Key trials were funded by the maker — weigh that in.")
                        .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                }
            }

            if let url = affiliates.url(for: product.id) {
                Button {
                    openURL(url)
                } label: {
                    Label("View on iHerb", systemImage: "arrow.up.right.square")
                        .font(Clinical.body(13, weight: .semibold)).foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func clinicianNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "stethoscope")
                .font(Clinical.body(14, weight: .semibold))
                .foregroundStyle(Clinical.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Talk to a clinician")
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                Text(text)
                    .font(Clinical.caption(12.5))
                    .foregroundStyle(Clinical.secondary)
            }
        }
        .padding(12)
        .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The proposal card presented as its own sheet — a plain nav shell with a Done toolbar. Used
/// both right after saving an out-of-range lab value (`AddLabSheet`) and from the persistent
/// deficiency banner on `LabsView`, so the same honest surface isn't a one-shot pop-up.
struct LabProposalSheet: View {
    let proposal: LabProposal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LabProposalCard(proposal: proposal)
                    .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Lab result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
