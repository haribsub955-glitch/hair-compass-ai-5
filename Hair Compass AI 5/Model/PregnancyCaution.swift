import Foundation

/// The hair-loss medications that are usually avoided in and around pregnancy, and the honest
/// one-line note the app shows when one is added while the profile says pregnant / trying /
/// breastfeeding.
///
/// Posture (mirrors `RxGate`): this is a safety nudge and honest record-keeping, never a
/// diagnosis, never a directive to start or stop anything, and never a gate the app enforces.
/// The app cannot know an individual's situation — every message points back to the clinician.
/// Detection reads the FINAL field values at save time (class + entered name), so a substance
/// typed into an `.other` item still gets flagged.
enum PregnancyCaution {

    /// The kind of concern, which drives the wording. Kept coarse on purpose — the message is a
    /// prompt to talk to a clinician, not a pharmacology lesson.
    enum Kind: Sendable {
        case reductaseInhibitor   // finasteride, dutasteride — teratogenic
        case minoxidil            // not established safe in pregnancy / breastfeeding
        case antiAndrogen         // spironolactone and other anti-androgens — teratogenic
    }

    /// A recognised substance plus its concern. `Identifiable`/`Equatable` so it can drive a
    /// `.sheet(item:)` presentation directly.
    struct Info: Identifiable, Equatable, Sendable {
        let substance: String     // display name, e.g. "Finasteride"
        let kind: Kind
        var id: String { substance }

        /// One honest sentence — plain, non-alarmist, and always ending at the clinician.
        var message: String {
            switch kind {
            case .reductaseInhibitor:
                return "\(substance) isn't used during pregnancy or when trying to conceive — it can affect a developing baby, and even broken tablets shouldn't be handled. This app doesn't give medical advice; please talk to your clinician before continuing."
            case .minoxidil:
                return "Minoxidil isn't established as safe in pregnancy or while breastfeeding, so it's usually paused. This app can't advise on your situation — please check the timing with your clinician."
            case .antiAndrogen:
                return "\(substance) is an anti-androgen that can affect a developing baby and is generally avoided in pregnancy. This app doesn't give medical advice; please discuss it with your clinician."
            }
        }
    }

    /// nil = nothing to flag. Non-nil = show the caution card before saving. Only the caller's
    /// pregnancy-status check decides *whether* to consult this; this function just recognises the
    /// substance from the class and typed name.
    static func info(treatmentClass: TreatmentClass, name: String) -> Info? {
        let n = name.lowercased()

        if treatmentClass == .finasteride || n.contains("finasteride") {
            return Info(substance: "Finasteride", kind: .reductaseInhibitor)
        }
        if treatmentClass == .dutasteride || n.contains("dutasteride") {
            return Info(substance: "Dutasteride", kind: .reductaseInhibitor)
        }
        if treatmentClass == .minoxidil || n.contains("minoxidil") {
            return Info(substance: "Minoxidil", kind: .minoxidil)
        }
        // Anti-androgens reach the plan as free-typed `.other` items — match by name. Spironolactone
        // (Aldactone), and the less common flutamide / bicalutamide / cyproterone acetate.
        if n.contains("spironolactone") || n.contains("aldactone") {
            return Info(substance: "Spironolactone", kind: .antiAndrogen)
        }
        if n.contains("flutamide") {
            return Info(substance: "Flutamide", kind: .antiAndrogen)
        }
        if n.contains("bicalutamide") {
            return Info(substance: "Bicalutamide", kind: .antiAndrogen)
        }
        if n.contains("cyproterone") {
            return Info(substance: "Cyproterone acetate", kind: .antiAndrogen)
        }
        return nil
    }

    /// Convenience: the caution to show for a given profile status, or nil when the status raises
    /// no caution (not pregnant / declined) or the substance isn't a recognised one.
    static func info(treatmentClass: TreatmentClass, name: String, status: PregnancyStatus) -> Info? {
        guard status.flagsMedicationCaution else { return nil }
        return info(treatmentClass: treatmentClass, name: name)
    }
}
