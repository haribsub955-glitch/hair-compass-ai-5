import Foundation

/// Maps a lab result to an honest, evidence-gated proposal. A supplement suggestion is only ever
/// offered for a lab-*confirmed* deficiency (ferritin / vitamin D / vitamin B12, each below its
/// reference range) — the exact case `ScienceProduct.deficiencyGated` exists for. Anything medical
/// (thyroid, or any test that comes back above range) routes to a clinician note instead, never a
/// sale. Pure and deterministic; it never invents a product for a test it doesn't recognize, and
/// an in-range result never produces a card.
struct LabProposal: Identifiable, Equatable {
    enum Kind: Equatable {
        case supplement   // a lab-confirmed deficiency — the gated product is legitimate to offer
        case clinician    // a medical finding — no product, just a clinician note
        case both         // a confirmed deficiency where the product ALSO needs a clinician caution
    }

    let kind: Kind
    /// Honest one-liner describing the finding, e.g. "Ferritin is below the range often cited
    /// for hair." Never phrased as a diagnosis.
    let deficiency: String
    /// `ScienceCatalog` ids to offer — empty for `.clinician`. Only ever the three known,
    /// lab-gated products (`iron`, `vitamind`, `b12`); this function never invents an id.
    let productIDs: [String]
    /// Non-nil for `.clinician` / `.both`. For iron specifically this doubles as the overload
    /// caution — supplementing without a confirmed low result is not just useless but harmful.
    let clinicianNote: String?

    /// Each rule below produces a distinct `deficiency` string, which is stable identity enough
    /// for `.sheet(item:)` — no stored UUID that would make two logically-identical proposals
    /// compare unequal.
    var id: String { deficiency }

    /// nil when the value is in range, or the test isn't one this app maps to a proposal.
    static func `for`(_ result: LabResult) -> LabProposal? {
        let flag = result.flag
        switch (result.test, flag) {
        case (.ferritin, .low):
            return LabProposal(
                kind: .both,
                deficiency: "Ferritin is below the range often cited for hair.",
                productIDs: ["iron"],
                clinicianNote: "Iron only helps if you're genuinely low — and too much iron is harmful. Confirm with a clinician before supplementing."
            )
        case (.vitaminD, .low):
            return LabProposal(
                kind: .supplement,
                deficiency: "Vitamin D is below range.",
                productIDs: ["vitamind"],
                clinicianNote: nil
            )
        case (.vitaminB12, .low):
            return LabProposal(
                kind: .supplement,
                deficiency: "Vitamin B12 is below range.",
                productIDs: ["b12"],
                clinicianNote: nil
            )
        // Thyroid is medical management either direction — checked before the generic
        // above-range case so a high or low TSH/free T4 gets the thyroid-specific note
        // rather than the generic "above range" one. Each out-of-range case is listed
        // explicitly: a `where` on a comma-separated case only binds to its last pattern,
        // which would let an in-range TSH fall through here.
        case (.tsh, .low), (.tsh, .high), (.freeT4, .low), (.freeT4, .high):
            return LabProposal(
                kind: .clinician,
                deficiency: "\(result.test.title) is out of range.",
                productIDs: [],
                clinicianNote: "Thyroid changes are a treatable shedding driver, but they need a clinician — not a supplement."
            )
        // Any other above-range result (including high ferritin or high B12) is worth a
        // clinician's review, never a sale.
        case (_, .high):
            return LabProposal(
                kind: .clinician,
                deficiency: "\(result.test.title) is above range.",
                productIDs: [],
                clinicianNote: "An above-range result is worth reviewing with a clinician."
            )
        default:
            return nil
        }
    }
}
