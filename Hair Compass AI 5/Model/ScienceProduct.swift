import Foundation

/// The science-backed product catalog. Curated, code-defined, and honest: every product carries the
/// tier of its actual human evidence, and the catalog CANNOT hold a myth (biotin, hair/skin/nails
/// gummies, collagen, zinc, niacinamide have no positive signal — they stay as Learn myth cards, not
/// products). Anchored to the 2026-07-03 supplement evidence pass.

/// Honest, product-specific evidence framing — deliberately separate from the tracked-variable
/// EvidenceTier so a supplement is never dressed up as a treatment.
enum ProductEvidence: Int, CaseIterable {
    case moderate     // real controlled trials (best a supplement gets — still below minoxidil/finasteride)
    case limited      // weak-but-real: single/soft/industry-funded trials
    case early        // lab, animal, or wrong-indication signal only
    case conditional  // only helps if a blood test shows you're deficient

    var label: String {
        switch self {
        case .moderate: return "Moderate evidence"
        case .limited: return "Limited evidence"
        case .early: return "Early / lab-stage"
        case .conditional: return "Only if deficient"
        }
    }
    var short: String {
        switch self {
        case .moderate: return "Moderate"
        case .limited: return "Limited"
        case .early: return "Early"
        case .conditional: return "If low"
        }
    }
}

enum ProductRoute: String {
    case topical, oral
    var label: String { self == .topical ? "Topical" : "Oral" }
    var symbol: String { self == .topical ? "drop" : "pills" }
}

struct ScienceProduct: Identifiable {
    let id: String
    let name: String            // the substance the user shops for
    let route: ProductRoute
    let evidence: ProductEvidence
    let summary: String         // one honest line
    let detail: String          // "what the evidence says"
    let industryFunded: Bool    // disclose when the key trials were manufacturer-funded
    let deficiencyGated: Bool   // only relevant with a low blood test

    /// The iHerb search term shown in the DEBUG owner-links tool — never a live link in the repo.
    var searchHint: String { name }
}

enum ScienceCatalog {
    static let products: [ScienceProduct] = [
        // MARK: Moderate — genuinely defensible
        .init(id: "rosemary", name: "Rosemary oil", route: .topical, evidence: .moderate,
              summary: "The strongest natural topical — a 6-month trial matched minoxidil 2% for regrowth, with less itch.",
              detail: "A single randomized trial (Panahi 2015) found rosemary oil comparable to 2% minoxidil over 6 months. It rests on one study and is an active-comparator (not placebo) — promising, not proven. Dilute in a carrier oil.",
              industryFunded: false, deficiencyGated: false),
        .init(id: "ketoconazole", name: "Ketoconazole shampoo", route: .topical, evidence: .moderate,
              summary: "A medicated shampoo that improves density as an anti-inflammatory adjunct; best evidence is for 2%.",
              detail: "Controlled studies show improved hair density and thickness, likely by calming scalp inflammation and local DHT. Use as an add-on, not a standalone. The OTC strength (1%) is less studied than 2%.",
              industryFunded: false, deficiencyGated: false),
        .init(id: "sawpalmetto", name: "Saw palmetto", route: .oral, evidence: .moderate,
              summary: "A plant DHT-blocker with several positive trials — real, but clearly milder than finasteride.",
              detail: "A systematic review found mostly positive trials (~27% count improvement), but head-to-head it's weaker than finasteride and brand potency varies. A reasonable natural option, not a replacement.",
              industryFunded: false, deficiencyGated: false),

        // MARK: Limited — weak but real
        .init(id: "pumpkin", name: "Pumpkin seed oil", route: .oral, evidence: .limited,
              summary: "One trial showed a large count gain — but the capsule was a blend, so it can't all be pinned on pumpkin oil.",
              detail: "A 24-week RCT (Cho 2014) reported +40% hair count vs +10% placebo, but the test capsule contained several ingredients and the trial was industry-adjacent. Encouraging, single-study.",
              industryFunded: true, deficiencyGated: false),
        .init(id: "melatonin", name: "Melatonin (topical)", route: .topical, evidence: .limited,
              summary: "A positive pilot trial plus many open-label reports; promising but not yet high-quality evidence.",
              detail: "A small placebo-controlled pilot (Fischer 2004) increased anagen (growing) hairs; most other supporting studies are uncontrolled. Well tolerated.",
              industryFunded: false, deficiencyGated: false),
        .init(id: "marineprotein", name: "Marine protein complex", route: .oral, evidence: .limited,
              summary: "Viviscal/Nourkrin-type complexes have real placebo-controlled trials — but all are manufacturer-funded.",
              detail: "Several double-blind RCTs report more terminal hairs and less shedding, yet every key trial was funded by the maker and used self-perceived-thinning groups. Contains shellfish.",
              industryFunded: true, deficiencyGated: false),
        .init(id: "caffeine", name: "Caffeine (topical)", route: .topical, evidence: .limited,
              summary: "Broadly positive but low-quality trials; safe to use as a supporting active.",
              detail: "A review of nine studies leaned positive (one found 0.2% comparable to minoxidil on anagen fraction), but the evidence was graded low quality with inconsistent dosing.",
              industryFunded: false, deficiencyGated: false),
        .init(id: "procapil", name: "Procapil / Redensyl", route: .topical, evidence: .limited,
              summary: "Cosmeceutical actives with some controlled data — but on soft, bias-prone endpoints.",
              detail: "A comparison vs 5% minoxidil scored higher on global photos, but endpoints were subjective and the data industry-sourced. A plausible add-on, weakly evidenced.",
              industryFunded: true, deficiencyGated: false),

        // MARK: Early — lab / animal / wrong-indication signal only
        .init(id: "greentea", name: "Green tea / EGCG", route: .topical, evidence: .early,
              summary: "Only lab-dish evidence for hair growth so far — no controlled human trial.",
              detail: "EGCG stimulates dermal-papilla cells in vitro, plus a tiny 4-day test in 3 people. Interesting mechanism, not a treatment yet.",
              industryFunded: false, deficiencyGated: false),
        .init(id: "peppermint", name: "Peppermint oil", route: .topical, evidence: .early,
              summary: "Promising in mice, but there are zero human hair-loss trials.",
              detail: "A mouse study found peppermint oil outperformed minoxidil, which hasn't been tested in people. Undiluted menthol can irritate — dilute well.",
              industryFunded: false, deficiencyGated: false),
        .init(id: "onion", name: "Onion juice", route: .topical, evidence: .early,
              summary: "A small trial showed regrowth — but for patchy alopecia areata, not pattern hair loss.",
              detail: "An unblinded RCT (Sharquie 2002) found high regrowth in alopecia areata, a condition that often remits on its own. No evidence for male/female pattern loss.",
              industryFunded: false, deficiencyGated: false),
        .init(id: "omega3", name: "Omega-3 (fish oil)", route: .oral, evidence: .early,
              summary: "One density trial exists, but it tested a fish-oil-plus-antioxidant blend — benefit can't be pinned on omega-3.",
              detail: "A controlled trial (Le Floc'h 2015) showed gains, but combined omega-3 with antioxidants and used self-assessment. Good general-health fat; hair benefit unproven alone.",
              industryFunded: true, deficiencyGated: false),
        .init(id: "ashwagandha", name: "Ashwagandha", route: .oral, evidence: .early,
              summary: "Lowers stress hormones, but no study has measured a hair outcome — the link is mechanism-only.",
              detail: "Ashwagandha reliably reduces cortisol, and stress can drive temporary shedding, but no trial connects it to hair. Speculative for hair specifically.",
              industryFunded: false, deficiencyGated: false),

        // MARK: Conditional — deficiency-gated (test first)
        .init(id: "iron", name: "Iron (ferritin support)", route: .oral, evidence: .conditional,
              summary: "Helps shedding only if a blood test shows low ferritin — blanket dosing risks iron overload.",
              detail: "Low iron stores are linked to shedding, and correcting a confirmed deficiency is standard care. Supplementing without a low ferritin result does nothing and can be harmful. Test first.",
              industryFunded: false, deficiencyGated: true),
        .init(id: "vitamind", name: "Vitamin D", route: .oral, evidence: .conditional,
              summary: "Worth correcting only if measured low — there's no proof it regrows hair in people who aren't deficient.",
              detail: "Low vitamin D is associated with several hair problems, but supplementation hasn't been shown to regrow hair when levels are normal, and megadoses are toxic. Test first.",
              industryFunded: false, deficiencyGated: true),
    ]

    static subscript(_ id: String) -> ScienceProduct? { products.first { $0.id == id } }
}
