import SwiftUI

/// The "Science-backed options" section shown on the Plan tab. Every product wears its honest
/// evidence tier, funding is disclosed, deficiency items are gated behind "test first", and the
/// affiliate relationship is stated up front. The buy button appears only once the owner has set
/// that product's link in Manage links.
struct ScienceProductsSection: View {
    @Environment(AffiliateStore.self) private var affiliates
    @Environment(\.openURL) private var openURL
    @State private var showManage = false

    private var grouped: [(evidence: ProductEvidence, items: [ScienceProduct])] {
        ProductEvidence.allCases.compactMap { e in
            let items = ScienceCatalog.products.filter { $0.evidence == e }
            return items.isEmpty ? nil : (e, items)
        }
    }

    var body: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow(text: "Science-backed options")
                    Spacer()
                    Button { showManage = true } label: {
                        Label("Manage links", systemImage: "link")
                            .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
                    }
                }
                Text("Substances with real evidence — each shown with how strong that evidence actually is. None of these rival minoxidil or finasteride.")
                    .font(.system(size: 13)).foregroundStyle(Clinical.secondary)

                ForEach(grouped, id: \.evidence) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.evidence.label.uppercased())
                            .font(Clinical.eyebrow(10)).tracking(1)
                            .foregroundStyle(Clinical.productColor(group.evidence))
                            .padding(.top, 4)
                        ForEach(group.items) { product in
                            ProductRow(product: product)
                            if product.id != group.items.last?.id {
                                Divider().overlay(Clinical.hairline)
                            }
                        }
                    }
                }

                Text("Affiliate disclosure: if you buy through these links we may earn a commission. It never changes a product's evidence rating.")
                    .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
                    .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showManage) { ManageLinksSheet() }
    }
}

private struct ProductRow: View {
    let product: ScienceProduct
    @Environment(AffiliateStore.self) private var affiliates
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(product.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.ink)
                Label(product.route.label, systemImage: product.route.symbol)
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                Spacer()
                ProductBadge(evidence: product.evidence)
            }
            Text(product.summary).font(.system(size: 13)).foregroundStyle(Clinical.secondary)

            if product.deficiencyGated {
                note(icon: "testtube.2", "Only worth it if a blood test shows you're low — check ferritin / vitamin D in Labs first.")
            }
            if product.industryFunded {
                note(icon: "building.2", "Key trials were funded by the maker — weigh that in.")
            }

            WhyDisclosure(text: product.detail)

            if let url = affiliates.url(for: product.id) {
                Button {
                    openURL(url)
                } label: {
                    Label("View on iHerb", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Clinical.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func note(icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
            Text(text).font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
        }
    }
}

/// Where the owner pastes an iHerb affiliate URL for each product — on-device, no rebuild needed.
struct ManageLinksSheet: View {
    @Environment(AffiliateStore.self) private var affiliates
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: "Affiliate links")
                            Text("Paste your iHerb affiliate URL for any product. Links stay on this device; a product's buy button appears only once its link is set. Leave blank to hide it.")
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        }
                    }
                    ForEach(ScienceCatalog.products) { product in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(product.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                                ProductBadge(evidence: product.evidence)
                                Spacer()
                                if affiliates.hasLink(for: product.id) {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Clinical.positive)
                                }
                            }
                            TextField("https://iherb.com/…  (search: \(product.searchHint))", text: binding(for: product.id))
                                .font(.system(size: 13))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(10)
                                .background(Clinical.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                                .onSubmit { affiliates.setLink(drafts[product.id] ?? "", for: product.id) }
                        }
                    }
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Manage links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveAll(); dismiss() } }
            }
            .onAppear {
                for product in ScienceCatalog.products {
                    drafts[product.id] = affiliates.link(for: product.id) ?? ""
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(get: { drafts[id] ?? "" }, set: { drafts[id] = $0 })
    }

    private func saveAll() {
        for (id, value) in drafts { affiliates.setLink(value, for: id) }
    }
}
