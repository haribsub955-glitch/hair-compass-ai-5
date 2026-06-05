import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct CheckInMetricSelector: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @Binding var selection: Double
    let levels: [MetricLevel]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: tint.opacity(0.30), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.49, blue: 0.46))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(levels) { level in
                    Button {
                        selection = level.value
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(level.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.17))
                                    .lineLimit(1)

                                Spacer()

                                if selection == level.value {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(tint)
                                }
                            }

                            Text(level.detail)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 0.43, green: 0.49, blue: 0.46))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Capsule()
                                    .fill(tint.opacity(selection == level.value ? 0.9 : 0.28))
                                    .frame(width: 24, height: 8)

                                Text("\(Int(level.value))%")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(selection == level.value ? tint : Color(red: 0.43, green: 0.49, blue: 0.46))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                        .padding(14)
                        .background(
                            selection == level.value ? tint.opacity(0.08) : Color.white.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(selection == level.value ? tint : Color.black.opacity(0.06), lineWidth: selection == level.value ? 2 : 1)
                        )
                        .scaleEffect(selection == level.value ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }
}

struct SymptomToggleCard: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isOn ? Color.white : Color(red: 0.69, green: 0.42, blue: 0.24))
                    .frame(width: 38, height: 38)
                    .background(
                        isOn ? Color(red: 0.69, green: 0.42, blue: 0.24) : Color(red: 0.97, green: 0.92, blue: 0.86),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
                    Text(isOn ? "Marked" : "Tap to mark")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.47, green: 0.52, blue: 0.49))
                }

                Spacer()
            }
            .padding(12)
            .background(
                isOn ? Color(red: 1.0, green: 0.95, blue: 0.90) : Color.white.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isOn ? Color(red: 0.86, green: 0.65, blue: 0.45) : Color.black.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(isOn ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

enum RoutineLibraryDestination: String, Identifiable {
    case medications
    case supplements
    case hairCare
    case labs
    case procedures
    case triggers

    var id: String { rawValue }
}

struct RoutineLibraryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: tint.opacity(0.30), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.14))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.47, green: 0.52, blue: 0.49))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(14)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

struct AffiliateProductSectionView: View {
    let title: String
    let subtitle: String
    let products: [AffiliateProduct]
    let onRefresh: () -> Void
    let lastRefreshDate: Date?

    var body: some View {
        Section(title) {
            VStack(alignment: .leading, spacing: 8) {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if let lastRefreshDate {
                    Text("Catalog refreshed \(lastRefreshDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                }
            }
            .padding(.vertical, 4)

            ForEach(products) { product in
                AffiliateProductRow(product: product)
            }

            Button {
                onRefresh()
            } label: {
                Label("Refresh Product Links", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
    }
}

struct AffiliateProductRow: View {
    let product: AffiliateProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
                    Text(product.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(product.merchant)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.47, blue: 0.79))
            }

            if let url = product.resolvedURL {
                Link(destination: url) {
                    Label("Open Product Link", systemImage: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }

            Text(product.affiliateDisclosure)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.50, green: 0.53, blue: 0.48))
        }
        .padding(.vertical, 4)
    }
}

struct SupplementLibraryView: View {
    @EnvironmentObject private var affiliateCatalogStore: AffiliateCatalogStore
    @State private var selectedSupplement: EvidenceBasedSupplementInfo?

    var body: some View {
        List {
            Section {
                Text("Evidence-based supplement options belong in a routine only when they add value to the user’s actual context.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }

            Section("Deficiency-Directed") {
                ForEach(SupplementEvidenceCatalog.deficiencyDirected) { supplement in
                    SupplementEvidenceCard(supplement: supplement) {
                        selectedSupplement = supplement
                    }
                }
            }

            Section("Limited Anti-DHT Evidence") {
                ForEach(SupplementEvidenceCatalog.limitedAntiDHT) { supplement in
                    SupplementEvidenceCard(supplement: supplement) {
                        selectedSupplement = supplement
                    }
                }
            }

            if !affiliateCatalogStore.products(for: .supplement).isEmpty {
                AffiliateProductSectionView(
                    title: "Affiliate Picks",
                    subtitle: "Editable non-medication product links. Update the JSON or remote catalog when a listing changes or goes out of stock.",
                    products: affiliateCatalogStore.products(for: .supplement),
                    onRefresh: {
                        Task {
                            await affiliateCatalogStore.refreshIfNeeded(force: true)
                        }
                    },
                    lastRefreshDate: affiliateCatalogStore.lastRefreshDate
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackground)
        .navigationTitle("Supplements")
        .sheet(item: $selectedSupplement) { supplement in
            QuickAddSupplementRoutineSheet(supplement: supplement)
        }
    }
}

struct HairCareLibraryView: View {
    @EnvironmentObject private var affiliateCatalogStore: AffiliateCatalogStore
    let suggestedHairCare: [HairCareRecommendation]
    @State private var selectedHairCare: EvidenceBasedHairCareInfo?

    private var suggestedItems: [EvidenceBasedHairCareInfo] {
        suggestedHairCare.compactMap { recommendation in
            HairCareEvidenceCatalog.valueAdding.first(where: { $0.id == recommendation.item.id })
        }
    }

    var body: some View {
        List {
            if !suggestedItems.isEmpty {
                Section("Suggested From Your Logs") {
                    ForEach(suggestedItems) { item in
                        HairCareEvidenceCard(item: item) {
                            selectedHairCare = item
                        }
                    }
                }
            }

            Section("Hair Care That Adds Value") {
                ForEach(HairCareEvidenceCatalog.valueAdding) { item in
                    HairCareEvidenceCard(item: item) {
                        selectedHairCare = item
                    }
                }
            }

            Section("What Not To Overweight") {
                ForEach(HairCareEvidenceCatalog.lowValueClaims, id: \.self) { claim in
                    Text("• \(claim)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }

            if !affiliateCatalogStore.products(for: .hairCare).isEmpty {
                AffiliateProductSectionView(
                    title: "Affiliate Picks",
                    subtitle: "These are editable non-medication product links. Swap URLs in one catalog location instead of changing Swift code.",
                    products: affiliateCatalogStore.products(for: .hairCare),
                    onRefresh: {
                        Task {
                            await affiliateCatalogStore.refreshIfNeeded(force: true)
                        }
                    },
                    lastRefreshDate: affiliateCatalogStore.lastRefreshDate
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackground)
        .navigationTitle("Hair Care")
        .sheet(item: $selectedHairCare) { item in
            QuickAddHairCareRoutineSheet(item: item)
        }
    }
}

struct LabLibraryView: View {
    @Query(sort: \LabResultEntry.collectedAt, order: .reverse) private var labResults: [LabResultEntry]
    @State private var selectedLabTest: HairRelevantLabTest? = HairLabCatalog.core.first
    @State private var isPresentingAddLabResult = false

    var body: some View {
        List {
            Section {
                Button {
                    selectedLabTest = HairLabCatalog.core.first
                    isPresentingAddLabResult = true
                } label: {
                    Label("Add Lab Result", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }

            Section("Core Hair Labs") {
                ForEach(HairLabCatalog.core) { test in
                    Button {
                        selectedLabTest = test
                        isPresentingAddLabResult = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(test.name)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
                                Spacer()
                                Text(test.evidenceStrength)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                            }
                            Text(test.rationale)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Selective Context Labs") {
                ForEach(HairLabCatalog.selective) { test in
                    Button {
                        selectedLabTest = test
                        isPresentingAddLabResult = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(test.name)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
                                Spacer()
                                Text(test.evidenceStrength)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.62, green: 0.41, blue: 0.15))
                            }
                            Text(test.rationale)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Logged Results") {
                if labResults.isEmpty {
                    ContentUnavailableView(
                        "No Lab Results Logged",
                        systemImage: "testtube.2",
                        description: Text("Add ferritin, CBC, thyroid, or other real lab results if you have them.")
                    )
                } else {
                    ForEach(labResults) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(result.testName)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Spacer()
                                Text(result.status)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.89, green: 0.93, blue: 0.97), in: Capsule())
                            }
                            Text("\(result.valueText) \(result.unit)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                            Text(result.collectedAt, format: .dateTime.month().day().year())
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackground)
        .navigationTitle("Labs")
        .sheet(isPresented: $isPresentingAddLabResult, onDismiss: {
            selectedLabTest = nil
        }) {
            AddLabResultSheet(initialTest: selectedLabTest)
        }
    }
}

struct ProcedureLibraryView: View {
    let procedureEvents: [ProcedureEvent]
    @State private var isPresentingAddProcedure = false
    @State private var selectedProcedureTemplate: ProcedureArticle?

    var body: some View {
        List {
            Section {
                Button {
                    isPresentingAddProcedure = true
                } label: {
                    Label("Add Procedure Event", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }

            Section("Procedure Guide") {
                Text("Short scientific summaries focused on effectiveness. Use these to understand what tends to help most, what works mainly as an adjunct, and what is worth logging over longer time windows.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                Text("Educational only: these summaries are not medical advice, do not diagnose disease, and do not replace clinician judgment. Procedure response varies by diagnosis, technique, operator, and follow-up care.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.66, green: 0.38, blue: 0.23))
                    .padding(.vertical, 2)

                ForEach(ProcedureArticleCatalog.items) { article in
                    ProcedureArticleCard(article: article) {
                        selectedProcedureTemplate = article
                    }
                }
            }

            Section("Procedure Events") {
                if procedureEvents.isEmpty {
                    ContentUnavailableView(
                        "No Procedures Logged",
                        systemImage: "cross.case",
                        description: Text("Log PRP, injectable dutasteride, microneedling, or other interventions so they can appear in your charts.")
                    )
                } else {
                    ForEach(procedureEvents) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(event.title)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                Spacer()
                                Text(event.category)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.89, green: 0.93, blue: 0.97), in: Capsule())
                            }
                            Text(event.performedAt, format: .dateTime.month().day().year())
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(event.procedureDescription)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackground)
        .navigationTitle("Procedures")
        .sheet(isPresented: $isPresentingAddProcedure) {
            AddProcedureEventSheet()
        }
        .sheet(item: $selectedProcedureTemplate) { article in
            AddProcedureEventSheet(template: article)
        }
    }
}

struct TriggerLibraryView: View {
    let triggerEvents: [HairTriggerEvent]
    @State private var selectedTriggerCategory: HairTriggerCategory?

    var body: some View {
        List {
            Section("Add Trigger History") {
                ForEach(HairTriggerCategory.allCases) { category in
                    Button {
                        selectedTriggerCategory = category
                    } label: {
                        HStack {
                            Text(category.rawValue)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color(red: 0.84, green: 0.46, blue: 0.28))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Current Trigger Timeline") {
                if triggerEvents.isEmpty {
                    ContentUnavailableView(
                        "No Trigger History Logged",
                        systemImage: "timeline.selection",
                        description: Text("Add illness, surgery, postpartum, weight change, styling, or seb derm context so later changes can be interpreted honestly.")
                    )
                } else {
                    ForEach(triggerEvents, id: \.persistentModelID) { trigger in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(trigger.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Spacer()
                                Text(trigger.severity)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.7), in: Capsule())
                            }
                            Text(trigger.category)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.84, green: 0.46, blue: 0.28))
                            Text(trigger.details)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackground)
        .navigationTitle("Triggers")
        .sheet(item: $selectedTriggerCategory) { category in
            AddTriggerEventSheet(category: category)
        }
    }
}

struct ProcedureArticle: Identifiable {
    let id: String
    let title: String
    let category: String
    let effectivenessSummary: String
    let evidenceDetail: String
    let practicalTakeaway: String
    let visualTitle: String
    let visualPlacement: String
    let visualPrompt: String
    let defaultDescription: String
    let sourceTitle: String
    let sourceURL: String
}

enum ProcedureArticleCatalog {
    static let items: [ProcedureArticle] = [
        ProcedureArticle(
            id: "hair-transplant",
            title: "Hair Transplant",
            category: "Clinic treatment",
            effectivenessSummary: "Strongest procedure for visible density restoration in patterned hair loss when donor supply is adequate.",
            evidenceDetail: "Effectiveness is generally high for cosmetic density improvement because follicles are moved from more androgen-resistant areas. It is a redistribution procedure, not a cure for ongoing miniaturization in non-transplanted hair.",
            practicalTakeaway: "Best when expectations, donor area limits, and long-term medical maintenance are handled realistically.",
            visualTitle: "Supporting Editorial Illustration",
            visualPlacement: "Place near the top of the hair transplant article card, just below the effectiveness summary.",
            visualPrompt: "Create a clean medical-editorial illustration of hair transplantation for patterned hair loss. Show scalp zones, donor-area concept, and restored frontal density in a tasteful simplified style. No before-and-after split, no gore, no visible surgery, soft blue and sand palette, premium health-app editorial aesthetic.",
            defaultDescription: "Hair transplant session logged for long-window density comparison. Use follow-up photos over months, not days.",
            sourceTitle: "Review: Hair transplantation in androgenetic alopecia",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/?term=hair+transplantation+androgenetic+alopecia+review"
        ),
        ProcedureArticle(
            id: "prp",
            title: "Platelet-Rich Plasma (PRP)",
            category: "PRP",
            effectivenessSummary: "Moderate evidence as an adjunct for androgenetic alopecia, with variable response and protocol differences across clinics.",
            evidenceDetail: "PRP can improve hair density or thickness in some patients, but results are inconsistent because preparation methods, injection schedules, and patient selection vary. It is usually better supported as an add-on rather than a stand-alone replacement for proven medical therapy.",
            practicalTakeaway: "Reasonable to track if done consistently, but evaluate over multi-month intervals and do not expect universal response.",
            visualTitle: "Mechanism + Timeline Graphic",
            visualPlacement: "Place directly under the PRP effectiveness paragraph as a support visual.",
            visualPrompt: "Design a minimalist medical infographic for platelet-rich plasma hair treatment. Show scalp cross-section, platelets being concentrated, and a simple 3-step timeline labeled baseline, repeated sessions, multi-month follow-up. Elegant white background, muted teal and amber accents, no blood emphasis, suitable for a premium mobile health app.",
            defaultDescription: "PRP session logged. Compare trends over months because short-term shedding changes can be noisy.",
            sourceTitle: "Systematic review: PRP for androgenetic alopecia",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/?term=platelet-rich+plasma+androgenetic+alopecia+systematic+review"
        ),
        ProcedureArticle(
            id: "microneedling",
            title: "Microneedling",
            category: "Microneedling",
            effectivenessSummary: "Best supported as an adjunct, especially when paired with topical therapy rather than used alone.",
            evidenceDetail: "Microneedling has shown benefit in some studies for androgenetic alopecia, particularly alongside minoxidil. Evidence is promising but smaller and less standardized than for core drug therapy, so technique, depth, and frequency matter.",
            practicalTakeaway: "More defensible as an add-on procedure than as a solo strategy for pattern hair loss.",
            visualTitle: "Adjunct Therapy Graphic",
            visualPlacement: "Place beside or just below the microneedling takeaway section.",
            visualPrompt: "Create a refined editorial medical illustration of microneedling as an adjunct scalp treatment. Show a simplified scalp surface, tiny controlled microchannels, and an adjacent icon suggesting paired topical therapy. Keep it clean, non-invasive, no bleeding, soft sage and steel-blue tones, scientific but approachable.",
            defaultDescription: "Microneedling session logged. Track alongside topical treatment consistency and compare results over longer intervals.",
            sourceTitle: "Systematic review: Microneedling for androgenetic alopecia",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/?term=microneedling+androgenetic+alopecia+systematic+review"
        ),
        ProcedureArticle(
            id: "low-level-laser",
            title: "Low-Level Laser Therapy",
            category: "Laser",
            effectivenessSummary: "Evidence suggests a possible modest benefit for some users, but average effect is usually smaller than transplantation or core medication therapy.",
            evidenceDetail: "Low-level laser devices may improve hair counts or thickness in some androgenetic alopecia users, but effect sizes are generally modest and depend heavily on regular use and device quality. It is typically an adjunct, not a high-impact replacement for better-established treatments.",
            practicalTakeaway: "Most useful when expectations are conservative and adherence is realistic.",
            visualTitle: "Device Use Scene",
            visualPlacement: "Place as the closing visual in the low-level laser section.",
            visualPrompt: "Generate a clean premium lifestyle-medical visual of a person using a low-level laser hair device at home. Emphasize calm routine use, subtle red-light cues, neat bathroom or bedroom setting, inclusive styling, no exaggerated regrowth claims, editorial wellness app aesthetic.",
            defaultDescription: "Low-level laser session logged. Interpret only after consistent repeated use, not isolated sessions.",
            sourceTitle: "Systematic review: Low-level laser therapy for androgenetic alopecia",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/?term=low-level+laser+therapy+androgenetic+alopecia+systematic+review"
        )
    ]
}

struct ProcedureArticleCard: View {
    let article: ProcedureArticle
    let onAddActivity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(article.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.19))

                    Text(article.category)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.34, green: 0.41, blue: 0.38))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.88), in: Capsule())
                }

                Text(article.effectivenessSummary)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.24, green: 0.38, blue: 0.60))
            }

            ProcedureSupportingIllustration(article: article)

            Text(article.evidenceDetail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.37, green: 0.42, blue: 0.40))

            Text(article.practicalTakeaway)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.63, green: 0.40, blue: 0.24))

            if let url = URL(string: article.sourceURL) {
                Link(destination: url) {
                    Label(article.sourceTitle, systemImage: "book.pages")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }

            Button {
                onAddActivity()
            } label: {
                Label("Add This Activity To Log", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.18, green: 0.39, blue: 0.35))

            Text("If the procedure is actually done, log it with a baseline photo plan so the app can remind you to repeat standardized photos over the following months.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.44, green: 0.49, blue: 0.46))
        }
        .padding(16)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

struct ProcedureSupportingIllustration: View {
    let article: ProcedureArticle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = UIImage(named: assetName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(backgroundGradient)
                        .overlay {
                            illustrationBody
                                .padding(18)
                        }
                }
            }
            .frame(height: 188)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(article.visualTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(article.visualPlacement)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.42), Color.black.opacity(0.08)],
                    startPoint: .bottom,
                    endPoint: .top
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
    }

    private var assetName: String {
        switch article.id {
        case "hair-transplant":
            return "procedure-hair-transplant"
        case "prp":
            return "procedure-prp"
        case "microneedling":
            return "procedure-microneedling"
        default:
            return "procedure-low-level-laser"
        }
    }

    private var backgroundGradient: LinearGradient {
        switch article.id {
        case "hair-transplant":
            return LinearGradient(
                colors: [Color(red: 0.63, green: 0.75, blue: 0.86), Color(red: 0.92, green: 0.85, blue: 0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "prp":
            return LinearGradient(
                colors: [Color(red: 0.80, green: 0.90, blue: 0.91), Color(red: 0.96, green: 0.84, blue: 0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "microneedling":
            return LinearGradient(
                colors: [Color(red: 0.79, green: 0.88, blue: 0.83), Color(red: 0.88, green: 0.92, blue: 0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color(red: 0.74, green: 0.80, blue: 0.90), Color(red: 0.94, green: 0.89, blue: 0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var illustrationBody: some View {
        switch article.id {
        case "hair-transplant":
            HairTransplantSupportingGraphic()
        case "prp":
            PRPSupportingGraphic()
        case "microneedling":
            MicroneedlingSupportingGraphic()
        default:
            LaserSupportingGraphic()
        }
    }
}

struct HairTransplantSupportingGraphic: View {
    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 10) {
                scalpIcon(receding: true)
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                scalpIcon(receding: false)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                supportingTag("Frontal restoration", systemName: "person.crop.circle")
                supportingTag("Donor planning", systemName: "checkmark.seal.fill")
                supportingTag("Density strategy", systemName: "square.grid.3x3.fill")
            }
        }
    }

    private func scalpIcon(receding: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.97, green: 0.86, blue: 0.74))
                .frame(width: 62, height: 62)

            Path { path in
                path.move(to: CGPoint(x: 11, y: receding ? 25 : 18))
                path.addQuadCurve(
                    to: CGPoint(x: 51, y: receding ? 25 : 18),
                    control: CGPoint(x: 31, y: receding ? 7 : 5)
                )
            }
            .stroke(Color(red: 0.30, green: 0.22, blue: 0.18), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

struct PRPSupportingGraphic: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 10) {
                processPill("Draw", icon: "drop.fill")
                processPill("Separate", icon: "circle.dashed.inset.filled")
                processPill("Inject", icon: "sparkles")
            }

            Spacer()

            VStack(spacing: 10) {
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 86, height: 86)
                    .overlay(
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(red: 0.79, green: 0.43, blue: 0.30))
                    )
                Text("Multi-session adjunct")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private func processPill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.20, green: 0.25, blue: 0.23))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.84), in: Capsule())
    }
}

struct MicroneedlingSupportingGraphic: View {
    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .frame(height: 92)
                .overlay {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { _ in
                                VStack(spacing: 2) {
                                    Rectangle()
                                        .fill(Color(red: 0.31, green: 0.37, blue: 0.34))
                                        .frame(width: 3, height: 12)
                                    Rectangle()
                                        .fill(Color(red: 0.77, green: 0.62, blue: 0.53))
                                        .frame(width: 3, height: 20)
                                }
                            }
                        }

                        Capsule()
                            .fill(Color(red: 0.87, green: 0.71, blue: 0.61))
                            .frame(height: 20)
                            .overlay(
                                Text("controlled microchannels")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.27, green: 0.23, blue: 0.20))
                            )
                    }
                }

            HStack(spacing: 10) {
                supportingTag("Adjunct", systemName: "plus.circle.fill")
                supportingTag("Topicals", systemName: "drop.fill")
                supportingTag("Routine", systemName: "calendar")
            }
        }
    }
}

struct LaserSupportingGraphic: View {
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 92, height: 92)

                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color(red: 0.87, green: 0.38, blue: 0.34))

                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 2)
                        .frame(width: CGFloat(92 + index * 18), height: CGFloat(92 + index * 18))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Home-use support")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Modest effect")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.90))
                Text("Consistency matters")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.90))
            }
        }
    }
}

func supportingTag(_ text: String, systemName: String) -> some View {
    Label(text, systemImage: systemName)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(Color(red: 0.19, green: 0.24, blue: 0.22))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.82), in: Capsule())
}

struct MedicationTab: View {
    @Environment(\.modelContext) private var modelContext
    let medications: [MedicationLog]

    @State private var isPresentingAddMedication = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Medication Scope")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Hair Compass should only surface approved medication categories and help you track what you are using. It should not decide treatment for you.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("FDA-Approved Pattern Hair Loss Options") {
                ForEach(MedicationEvidenceCatalog.androgeneticAlopecia) { medication in
                    MedicationEvidenceCard(medication: medication, onAdd: {})
                }
            }

            Section("FDA-Approved Severe Alopecia Areata Options") {
                ForEach(MedicationEvidenceCatalog.alopeciaAreata) { medication in
                    MedicationEvidenceCard(medication: medication, onAdd: {})
                }
            }

            Section("Your Medication Record") {
                if medications.isEmpty {
                    ContentUnavailableView(
                        "No Medications Logged",
                        systemImage: "pills",
                        description: Text("Track what you are using, when you started, and whether it was clinician-directed.")
                    )
                } else {
                    ForEach(medications) { medication in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(medication.name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                Spacer()
                                Text(medication.isActive ? "Active" : "Stopped")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background((medication.isActive ? Color.green : Color.gray).opacity(0.14), in: Capsule())
                                    .foregroundStyle(medication.isActive ? Color.green : Color.gray)
                            }

                            Text("\(medication.form)  •  \(medication.indication)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text("Started \(medication.startedAt, format: .dateTime.month().day().year())")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text(medication.schedule)
                                .font(.system(size: 14, weight: .medium, design: .rounded))

                            Text(medication.prescribedByClinician ? "Clinician-directed" : "Self-initiated")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(medication.prescribedByClinician ? Color.blue : Color.orange)

                            if !medication.notes.isEmpty {
                                Text(medication.notes)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .swipeActions {
                            Button(medication.isActive ? "Stop" : "Resume") {
                                medication.isActive.toggle()
                            }
                            .tint(medication.isActive ? .orange : .green)
                        }
                    }
                    .onDelete(perform: deleteMedications)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackground)
        .navigationTitle("Medications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddMedication = true
                } label: {
                    Label("Add Medication", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddMedication) {
            AddMedicationSheet()
        }
    }

    private func deleteMedications(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(medications[index])
        }
    }
}

struct MedicationEvidenceCard: View {
    let medication: ApprovedMedicationInfo
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(medication.route)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Color.green)
            }

            Text(medication.approvalScope)
                .font(.system(size: 14, weight: .medium, design: .rounded))

            Text(medication.keyUse)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack {
                Text("Typical start: \(medication.defaultDosage), \(frequencyText(for: medication.defaultFrequencyPerDay))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                Spacer()
                Button("Add to Routine") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(medication.cautions, id: \.self) { caution in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .padding(.top, 2)
                    Text(caution)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func frequencyText(for frequency: Int) -> String {
        frequency == 1 ? "once daily" : "\(frequency)x daily"
    }
}

struct SupplementEvidenceCard: View {
    let supplement: EvidenceBasedSupplementInfo
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(supplement.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(supplement.focus)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                }

                Spacer()

                Button("Add to Routine") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
            }

            Text(supplement.evidenceLevel)
                .font(.system(size: 14, weight: .medium, design: .rounded))

            Text(supplement.keyUse)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Routine default: \(supplement.defaultRoutineDetail)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.26, green: 0.56, blue: 0.42))

            ForEach(supplement.cautions, id: \.self) { caution in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .padding(.top, 2)
                    Text(caution)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HairCareEvidenceCard: View {
    let item: EvidenceBasedHairCareInfo
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(item.focus)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                }
                Spacer()
                Button("Add to Routine") {
                    addAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.20, green: 0.47, blue: 0.79))
            }

            Text(item.evidenceLevel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.28, green: 0.55, blue: 0.44))

            Text(item.whyItAddsValue)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Routine default: \(item.defaultRoutineDetail)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.41, green: 0.46, blue: 0.43))

            ForEach(item.cautions, id: \.self) { caution in
                Label(caution, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.76, green: 0.49, blue: 0.23))
            }
        }
        .padding(.vertical, 6)
    }
}

struct SuggestedHairCareCard: View {
    let recommendation: HairCareRecommendation
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.item.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(recommendation.item.focus)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                }
                Spacer()
                Button("Add") {
                    addAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.28, green: 0.55, blue: 0.44))
            }

            Text(recommendation.rationale)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.44, blue: 0.40))
        }
        .padding(14)
        .background(Color(red: 0.93, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct QuickAddSupplementRoutineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let supplement: EvidenceBasedSupplementInfo

    @State private var timeLabel = "08:00"
    @State private var recurrenceType: RoutineRecurrenceType = .daily

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplement") {
                    Text(supplement.name)
                    Text(supplement.evidenceLevel)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(supplement.keyUse)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Section("Add To Routine") {
                    TextField("Time", text: $timeLabel)
                    Picker("Recurs", selection: $recurrenceType) {
                        Text("Daily").tag(RoutineRecurrenceType.daily)
                        Text("Weekly").tag(RoutineRecurrenceType.weekly)
                    }
                }
            }
            .navigationTitle("Add Supplement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let task = RoutineTask(
                            title: supplement.defaultRoutineTitle,
                            detail: supplement.defaultRoutineDetail,
                            timeLabel: timeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "08:00" : timeLabel,
                            weekday: Calendar.current.component(.weekday, from: .now),
                            category: "Supplement",
                            recurrenceType: recurrenceType.rawValue,
                            recurrenceWeekdays: recurrenceType == .weekly ? "\(Calendar.current.component(.weekday, from: .now))" : ""
                        )
                        modelContext.insert(task)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QuickAddHairCareRoutineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: EvidenceBasedHairCareInfo

    @State private var frequencyLabel: String
    @State private var notes = ""
    @State private var recurrenceType: RoutineRecurrenceType
    @State private var recurrenceInterval = 3

    init(item: EvidenceBasedHairCareInfo) {
        self.item = item
        _frequencyLabel = State(initialValue: item.defaultFrequencyLabel)
        if item.defaultFrequencyLabel.localizedCaseInsensitiveContains("daily") || item.defaultFrequencyLabel.localizedCaseInsensitiveContains("each wash") {
            _recurrenceType = State(initialValue: .daily)
        } else if item.defaultFrequencyLabel.localizedCaseInsensitiveContains("monthly") {
            _recurrenceType = State(initialValue: .monthly)
        } else {
            _recurrenceType = State(initialValue: .weekly)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hair Care") {
                    Text(item.name)
                    Text(item.evidenceLevel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.28, green: 0.55, blue: 0.44))
                    Text(item.whyItAddsValue)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Section("Routine") {
                    TextField("Frequency", text: $frequencyLabel)
                    Picker("Recurs", selection: $recurrenceType) {
                        Text("Daily").tag(RoutineRecurrenceType.daily)
                        Text("Weekly").tag(RoutineRecurrenceType.weekly)
                        Text("Every N Days").tag(RoutineRecurrenceType.everyNDays)
                        Text("Monthly").tag(RoutineRecurrenceType.monthly)
                    }
                    if recurrenceType == .everyNDays {
                        Stepper("Every \(recurrenceInterval) days", value: $recurrenceInterval, in: 2...14)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("Add to Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        modelContext.insert(
                            RoutineTask(
                                title: item.defaultRoutineTitle,
                                detail: "\(item.defaultRoutineDetail) Frequency: \(frequencyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.defaultFrequencyLabel : frequencyLabel). \(notes.trimmingCharacters(in: .whitespacesAndNewlines))".trimmingCharacters(in: .whitespacesAndNewlines),
                                timeLabel: "19:00",
                                weekday: Calendar.current.component(.weekday, from: .now),
                                category: "Hair Care",
                                recurrenceType: recurrenceType.rawValue,
                                recurrenceInterval: recurrenceType == .everyNDays ? recurrenceInterval : 1,
                                recurrenceWeekdays: recurrenceType == .weekly ? "\(Calendar.current.component(.weekday, from: .now))" : ""
                            )
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddLabResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let initialTest: HairRelevantLabTest?

    @State private var selectedTestID: String
    @State private var valueText = ""
    @State private var unit: String
    @State private var status = "Normal"
    @State private var collectedAt = Date()
    @State private var notes = ""

    private let statuses = [
        "Normal",
        "Borderline / low-normal",
        "Low",
        "High",
        "Not sure"
    ]

    private var recommendedTests: [HairRelevantLabTest] {
        HairLabCatalog.core + HairLabCatalog.selective
    }

    private var selectedTest: HairRelevantLabTest {
        recommendedTests.first(where: { $0.id == selectedTestID }) ?? recommendedTests[0]
    }

    init(initialTest: HairRelevantLabTest?) {
        self.initialTest = initialTest
        let fallback = initialTest ?? HairLabCatalog.core.first ?? HairLabCatalog.selective.first!
        _selectedTestID = State(initialValue: fallback.id)
        _unit = State(initialValue: fallback.unitHint)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Test") {
                    Picker("Recommended test", selection: $selectedTestID) {
                        ForEach(recommendedTests) { test in
                            Text(test.name).tag(test.id)
                        }
                    }

                    Text(selectedTest.name)
                    Text(selectedTest.evidenceStrength)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedTest.category == "Core baseline" ? Color(red: 0.20, green: 0.47, blue: 0.79) : Color(red: 0.62, green: 0.41, blue: 0.15))
                    Text(selectedTest.rationale)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Section("Result") {
                    TextField("Value", text: $valueText)
                    TextField("Unit", text: $unit)

                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }

                    DatePicker("Collected", selection: $collectedAt, displayedComponents: .date)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("Log Lab Result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = LabResultEntry(
                            testID: selectedTest.id,
                            testName: selectedTest.name,
                            valueText: valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not entered" : valueText,
                            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedTest.unitHint : unit,
                            status: status,
                            collectedAt: collectedAt,
                            notes: notes
                        )
                        modelContext.insert(entry)
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedTestID) { _, _ in
                unit = selectedTest.unitHint
            }
        }
    }
}

struct AddTriggerEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let category: HairTriggerCategory

    @State private var title: String
    @State private var details: String
    @State private var startedAt = Date()
    @State private var endedAt: Date?
    @State private var hasEndDate = false
    @State private var severity = "Moderate"

    private let severities = ["Mild", "Moderate", "High"]

    init(category: HairTriggerCategory) {
        self.category = category
        _title = State(initialValue: category.templateTitle)
        _details = State(initialValue: category.summary)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trigger") {
                    Text(category.rawValue)
                    Text(category.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("Title", text: $title)
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Timing") {
                    DatePicker("Started", selection: $startedAt, displayedComponents: .date)
                    Toggle("Track end date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ended", selection: Binding(
                            get: { endedAt ?? startedAt },
                            set: { endedAt = $0 }
                        ), displayedComponents: .date)
                    }
                    Picker("Severity", selection: $severity) {
                        ForEach(severities, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                }
            }
            .navigationTitle("Add Trigger")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let event = HairTriggerEvent(
                            category: category.rawValue,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.templateTitle : title,
                            details: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.summary : details,
                            startedAt: startedAt,
                            endedAt: hasEndDate ? endedAt : nil,
                            severity: severity
                        )
                        modelContext.insert(event)
                        dismiss()
                    }
                }
            }
        }
    }
}

