import Foundation

/// Decides whether an about-to-be-saved treatment is a medication that is usually
/// prescription-only, so the add flow can pause on a friendly confirmation card ("this is
/// usually prescribed — we'll assume yours is") instead of saving silently.
///
/// Pure and value-based: the gate reads the FINAL field values at save time (class + entered
/// name + entered dose), never a preset's identity. Posture rule: this is reassurance and
/// honest record-keeping, never gatekeeping — the app cannot verify a prescription and never
/// recommends starting a medication.
enum RxGate {

    /// The prescription-only medications the gate recognises.
    enum Medication: String, CaseIterable, Sendable {
        case finasteride, dutasteride, oralMinoxidil, spironolactone
    }

    /// How the medication reaches the body — drives which brand art represents it.
    enum Route: Sendable {
        case oral, topical
    }

    /// Which brand illustration fronts the confirmation card.
    enum Art: String, Sendable {
        case remedy    // amber pill bottle + tablets — oral tablets
        case dropper   // amber dropper bottle — topical liquids

        var assetName: String {
            switch self {
            case .remedy: return BrandArt.remedy
            case .dropper: return BrandArt.dropper
            }
        }
    }

    /// The gate's verdict: which recognised medication this is and the art that shows it.
    /// `Identifiable` so it can drive a `.sheet(item:)` presentation directly.
    struct Requirement: Equatable, Identifiable, Sendable {
        let medication: Medication
        let art: Art
        var id: String { medication.rawValue }
    }

    // MARK: - The gate

    /// nil = save as before, no card. Non-nil = pause on the confirmation card.
    static func requirement(treatmentClass: TreatmentClass, name: String, dose: String) -> Requirement? {
        guard let medication = medication(treatmentClass: treatmentClass, name: name, dose: dose) else {
            return nil
        }
        return Requirement(medication: medication, art: art(for: route(of: medication)))
    }

    /// Route-aware art pick, exposed so a future topical Rx (e.g. compounded topical
    /// finasteride) lands on the dropper without touching the card.
    static func art(for route: Route) -> Art {
        switch route {
        case .oral: return .remedy
        case .topical: return .dropper
        }
    }

    /// Every medication the gate currently recognises is taken orally.
    static func route(of medication: Medication) -> Route {
        switch medication {
        case .finasteride, .dutasteride, .oralMinoxidil, .spironolactone: return .oral
        }
    }

    // MARK: - Detection

    private static func medication(treatmentClass: TreatmentClass, name: String, dose: String) -> Medication? {
        switch treatmentClass {
        case .finasteride:
            return .finasteride
        case .dutasteride:
            return .dutasteride
        case .spironolactone:
            return .spironolactone
        case .minoxidil:
            // Only the oral route is prescription-only — topical 5% (mL doses) is
            // over-the-counter and must save without a card.
            return isOral(name: name, dose: dose) ? .oralMinoxidil : nil
        case .microneedling, .prp, .lllt:
            // Procedures and devices, not dispensed medications — never a card.
            return nil
        case .shampoo, .oil, .supplement:
            // Over-the-counter care products — never prescription-only, so never a card.
            return nil
        case .other:
            // Name-based detection so `.other`-class entries (one-tap science products,
            // free-typed names) still pause when the substance itself is prescription-only.
            let n = name.lowercased()
            if n.contains("finasteride") { return .finasteride }
            if n.contains("dutasteride") { return .dutasteride }
            if n.contains("minoxidil"), isOral(name: name, dose: dose) { return .oralMinoxidil }
            if n.contains("spironolactone") || n.contains("aldactone") { return .spironolactone }
            return nil
        }
    }

    /// Oral is read off the entered fields: "oral" anywhere in the name, or a milligram
    /// dose ("mg"). Topical liquids are dosed in mL, which never matches.
    private static func isOral(name: String, dose: String) -> Bool {
        name.lowercased().contains("oral") || dose.lowercased().contains("mg")
    }

    // MARK: - The friendly note

    /// One honest sentence per medication — reassurance, not a scare, and always explicit
    /// that the app assumes (never verifies, never recommends) the prescription.
    static func note(for medication: Medication) -> String {
        switch medication {
        case .finasteride:
            return "Finasteride is usually prescription-only. We'll assume yours was prescribed by a clinician — this app never recommends starting it."
        case .dutasteride:
            return "Dutasteride is usually prescription-only, and for hair it's typically prescribed off-label. We'll assume yours came from a clinician — this app never recommends starting it."
        case .oralMinoxidil:
            return "Oral minoxidil for hair is an off-label, prescription-only route. We'll assume a clinician prescribed yours — this app never recommends starting it."
        case .spironolactone:
            return "Spironolactone is prescription-only, and for hair it's typically prescribed off-label with periodic monitoring. We'll assume yours came from a clinician — this app never recommends starting it."
        }
    }
}
