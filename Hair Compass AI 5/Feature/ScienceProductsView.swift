import SwiftUI

/// The "Science-backed options" section shown on the Plan tab. Every product wears its honest
/// evidence tier, funding is disclosed, deficiency items are gated behind "test first", and the
/// affiliate relationship is stated up front. Links are owner-controlled (bundled JSON + remote
/// catalog, see AffiliateStore) — a product's buy button appears only once its link resolves.
/// Users never manage links; the owner tool is DEBUG-only behind the HC_LINKS launch flag.
struct ScienceProductsSection: View {
    @Environment(AffiliateStore.self) private var affiliates
    @Environment(\.openURL) private var openURL
    #if DEBUG
    @State private var showManage = false
    private var showOwnerTools: Bool { ProcessInfo.processInfo.arguments.contains("HC_LINKS") }
    #endif

    private var grouped: [(evidence: ProductEvidence, items: [ScienceProduct])] {
        ProductEvidence.allCases.compactMap { e in
            let items = ScienceCatalog.products.filter { $0.evidence == e }
            return items.isEmpty ? nil : (e, items)
        }
    }

    var body: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(BrandArt.learnSupplements)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    Eyebrow(text: "Science-backed options")
                    Spacer()
                    #if DEBUG
                    if showOwnerTools {
                        Button { showManage = true } label: {
                            Label("Owner links", systemImage: "link")
                                .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
                        }
                    }
                    #endif
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
        #if DEBUG
        .sheet(isPresented: $showManage) { ManageLinksSheet() }
        #endif
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

#if DEBUG
/// Owner tool, debug builds only (opened via the HC_LINKS launch flag): paste an iHerb URL to
/// try a product's buy flow before shipping it. Writes to the `affiliate.debugOverride.<id>`
/// layer, which takes top precedence in DEBUG resolution and is compiled out of release —
/// shipping links live in the bundled AffiliateLinks.json / remote catalog instead.
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
                            Eyebrow(text: "Owner link overrides (debug)")
                            Text("Debug-only overrides that beat the bundled and remote catalogs on this device. Use them to preview a product's buy flow; ship real links via AffiliateLinks.json or the remote catalog. Leave blank to fall back.")
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        }
                    }
                    ForEach(ScienceCatalog.products) { product in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(product.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                                ProductBadge(evidence: product.evidence)
                                Spacer()
                                if affiliates.debugOverride(for: product.id) != nil {
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
                                .onSubmit { affiliates.setDebugOverride(drafts[product.id] ?? "", for: product.id) }
                        }
                    }
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Owner links (debug)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveAll(); dismiss() } }
            }
            .onAppear {
                for product in ScienceCatalog.products {
                    drafts[product.id] = affiliates.debugOverride(for: product.id) ?? ""
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(get: { drafts[id] ?? "" }, set: { drafts[id] = $0 })
    }

    private func saveAll() {
        for (id, value) in drafts { affiliates.setDebugOverride(value, for: id) }
    }
}
#endif
