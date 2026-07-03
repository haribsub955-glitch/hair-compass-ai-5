import Foundation

/// The evidence-based flash-card library. Every answer mirrors docs/TrackingSpec.md and the
/// 2026-07-02 evidence pass — including the named myths — so the Learn tab never over-claims.
/// Pure content; the UI (LearnView) renders it.

enum LearnCategory: String, CaseIterable, Identifiable {
    case basics, conditions, treatments, supplements, myths, dailyCare
    var id: String { rawValue }

    var title: String {
        switch self {
        case .basics: return "Basics"
        case .conditions: return "Conditions"
        case .treatments: return "Treatments"
        case .supplements: return "Supplements"
        case .myths: return "Myths"
        case .dailyCare: return "Daily care"
        }
    }
    var eyebrow: String {
        switch self {
        case .basics: return "Hair 101"
        case .conditions: return "Patterns"
        case .treatments: return "What helps"
        case .supplements: return "Nature's evidence"
        case .myths: return "Myth vs fact"
        case .dailyCare: return "Everyday"
        }
    }
    var art: String {
        switch self {
        case .basics: return BrandArt.learnBasics
        case .conditions: return BrandArt.learnConditions
        case .treatments: return BrandArt.learnTreatments
        case .supplements: return BrandArt.learnSupplements
        case .myths: return BrandArt.learnMyths
        case .dailyCare: return BrandArt.learnDailyCare
        }
    }
}

struct FlashCard: Identifiable {
    let id: String
    let category: LearnCategory
    let question: String
    let answer: String
    let tier: EvidenceTier

    /// Myth cards read as a verdict ("MYTH") rather than an evidence tier.
    var isMyth: Bool { category == .myths }
}

enum LearnLibrary {
    static let cards: [FlashCard] = basics + conditions + treatments + supplements + myths + dailyCare

    static func cards(in category: LearnCategory) -> [FlashCard] {
        cards.filter { $0.category == category }
    }

    private static let basics: [FlashCard] = [
        .init(id: "b1", category: .basics, tierQ: .strong,
              q: "How fast does hair actually grow?",
              a: "About 1 cm (roughly ½ inch) a month, and each strand grows for 2–6 years before resting and shedding. Change is slow — judge it over months, not days."),
        .init(id: "b2", category: .basics, tierQ: .strong,
              q: "Is it normal to lose hair every day?",
              a: "Yes. Shedding ~50–100 hairs a day is normal turnover. A widening part, a receding hairline, or sustained handfuls are what's worth tracking."),
        .init(id: "b3", category: .basics, tierQ: .strong,
              q: "What is the hair growth cycle?",
              a: "Every follicle cycles through growing, a brief transition, and resting before the hair sheds and a new one begins. Most of your hair is in the growing phase at any time."),
    ]

    private static let conditions: [FlashCard] = [
        .init(id: "c1", category: .conditions, tierQ: .strong,
              q: "What is pattern hair loss?",
              a: "The most common type — gradual, genetically-driven thinning in a set pattern (crown and hairline in men, a widening part in women), driven by follicle sensitivity to the hormone DHT."),
        .init(id: "c2", category: .conditions, tierQ: .strong,
              q: "What's the strongest risk factor?",
              a: "Family history. In pooled data, having affected relatives raises the odds of pattern loss about 2.7× — the single biggest measured factor."),
        .init(id: "c3", category: .conditions, tierQ: .strong,
              q: "What is telogen effluvium?",
              a: "A temporary, diffuse shedding that usually follows a trigger — illness, crash diet, major stress, childbirth — by about 2–3 months, and typically recovers once the trigger passes."),
        .init(id: "c4", category: .conditions, tierQ: .weak,
              q: "Does stress cause hair loss?",
              a: "Severe stress can trigger temporary shedding. Everyday stress is a weaker, context-level signal — worth noting, but not a proven cause of pattern loss."),
    ]

    private static let treatments: [FlashCard] = [
        .init(id: "t1", category: .treatments, tierQ: .strong,
              q: "When can I judge if a treatment works?",
              a: "At 24 weeks (6 months) — the standard point in clinical trials for measuring hair-density change. Judging sooner is misleading; early shedding can even mean it's starting to work."),
        .init(id: "t2", category: .treatments, tierQ: .strong,
              q: "What does the evidence support most?",
              a: "For male pattern loss, minoxidil and finasteride are the best-studied, and combining them outperforms either alone. Confirm suitability and dosing with a clinician before starting anything."),
        .init(id: "t3", category: .treatments, tierQ: .strong,
              q: "Does smoking affect hair?",
              a: "Yes — smoking is a genuine, measured risk factor for pattern loss (about 1.8× the odds in pooled data). Quitting is one of the few clearly evidence-backed lifestyle moves."),
        .init(id: "t4", category: .treatments, tierQ: .moderate,
              q: "Do I need blood tests?",
              a: "Sometimes. Ferritin (iron stores), thyroid (TSH/T4), and vitamin D are the ones dermatologists commonly check for diffuse shedding — individualized, not a routine panel for everyone."),
    ]

    private static let supplements: [FlashCard] = [
        .init(id: "s1", category: .supplements, tierQ: .moderate,
              q: "Does rosemary oil actually work?",
              a: "In a 6-month trial it matched minoxidil 2% for regrowth, with less itching — the strongest natural topical. But it rests on a single study, so treat it as promising, not proven."),
        .init(id: "s2", category: .supplements, tierQ: .moderate,
              q: "Is saw palmetto as good as finasteride?",
              a: "No. It's a milder natural DHT-blocker with several positive trials, but clearly weaker than finasteride, and potency varies by brand. A reasonable option, not an equal."),
        .init(id: "s3", category: .supplements, tierQ: .weak,
              q: "Are any supplements as good as minoxidil?",
              a: "No supplement reaches the evidence level of minoxidil or finasteride. The best natural options only match minoxidil 2% — the weak strength — and usually in single studies."),
        .init(id: "s4", category: .supplements, tierQ: .weak,
              q: "Do biotin or 'hair, skin & nails' pills help?",
              a: "No — the best trial found biotin no better than placebo unless you have a rare true deficiency, and hair-vitamin gummies can even cause shedding from too much vitamin A."),
        .init(id: "s5", category: .supplements, tierQ: .weak,
              q: "Do iron or vitamin D pills grow hair?",
              a: "Only if a blood test shows you're low. Correcting a real deficiency can ease shedding; taking them when your levels are normal doesn't help and can be harmful. Test first."),
    ]

    private static let myths: [FlashCard] = [
        .init(id: "m1", category: .myths, tierQ: .weak,
              q: "Does drinking more water grow hair?",
              a: "No evidence links hydration to hair loss or growth. Hydrate for general health — not as a hair treatment."),
        .init(id: "m2", category: .myths, tierQ: .weak,
              q: "Does coffee cause hair loss?",
              a: "No. Dietary caffeine has no proven effect. The caffeine studies people cite are topical and lab-based — they don't transfer to drinking coffee."),
        .init(id: "m3", category: .myths, tierQ: .weak,
              q: "Does exercise make you lose hair?",
              a: "No credible evidence that exercise causes or prevents hair loss. Train for your health; it won't hurt your hair."),
        .init(id: "m4", category: .myths, tierQ: .weak,
              q: "Do hats cause baldness?",
              a: "No — a normal hat doesn't cause pattern loss. Only constant, tight tension (very tight styles) can cause traction loss over time."),
        .init(id: "m5", category: .myths, tierQ: .weak,
              q: "Does cutting hair make it grow back thicker?",
              a: "No. Cutting changes the blunt tip, not the follicle. Growth rate and thickness come from the root, unaffected by trimming."),
    ]

    private static let dailyCare: [FlashCard] = [
        .init(id: "d1", category: .dailyCare, tierQ: .weak,
              q: "Does washing too often cause hair loss?",
              a: "No. Wash frequency doesn't cause follicular loss — do what keeps your scalp comfortable. The hairs in the drain are normal shed, not extra loss."),
        .init(id: "d2", category: .dailyCare, tierQ: .strong,
              q: "Can tight hairstyles damage hair?",
              a: "Yes. Sustained tension from tight braids, ponytails and extensions causes traction alopecia — preventable and reversible if you ease off early."),
        .init(id: "d3", category: .dailyCare, tierQ: .moderate,
              q: "Does heat styling hurt hair?",
              a: "It can cause breakage and weathering of the strand (not follicle loss). Lower the heat, use it less often, and protect the hair to limit damage."),
        .init(id: "d4", category: .dailyCare, tierQ: .moderate,
              q: "How should I handle wet hair?",
              a: "Gently. Wet hair stretches and breaks more easily — use a wide-tooth comb, avoid rough towel-drying, and don't tie it tightly while wet."),
    ]
}

// Ergonomic initializer so the catalog above reads cleanly.
private extension FlashCard {
    init(id: String, category: LearnCategory, tierQ tier: EvidenceTier, q question: String, a answer: String) {
        self.init(id: id, category: category, question: question, answer: answer, tier: tier)
    }
}
