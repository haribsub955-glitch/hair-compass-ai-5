//
//  PregnancyCautionTests.swift
//  Hair Compass AI 5Tests
//
//  The medications flagged as usually-avoided in/around pregnancy (Model/PregnancyCaution.swift)
//  and the status gate that decides whether to show the note. A safety nudge, never a diagnosis
//  or a directive — the tests pin both the recognition and the honest framing.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct PregnancyCautionTests {

    // MARK: - Which statuses raise a caution

    @Test func onlyPregnantTryingOrBreastfeedingRaiseTheFlag() {
        #expect(PregnancyStatus.pregnant.flagsMedicationCaution)
        #expect(PregnancyStatus.tryingToConceive.flagsMedicationCaution)
        #expect(PregnancyStatus.breastfeeding.flagsMedicationCaution)
        #expect(!PregnancyStatus.no.flagsMedicationCaution)
        #expect(!PregnancyStatus.unspecified.flagsMedicationCaution)
    }

    // MARK: - Recognising the substances

    @Test func fiveAlphaReductaseInhibitorsAreFlaggedByClassAndByName() {
        // By treatment class…
        #expect(PregnancyCaution.info(treatmentClass: .finasteride, name: "")?.substance == "Finasteride")
        #expect(PregnancyCaution.info(treatmentClass: .dutasteride, name: "")?.substance == "Dutasteride")
        // …and by a name typed into an `.other` item.
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Topical finasteride 0.1%")?.kind == .reductaseInhibitor)
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Dutasteride 0.5mg")?.kind == .reductaseInhibitor)
    }

    @Test func minoxidilIsFlaggedByClassAndName() {
        #expect(PregnancyCaution.info(treatmentClass: .minoxidil, name: "")?.kind == .minoxidil)
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Oral minoxidil 2.5mg")?.kind == .minoxidil)
    }

    @Test func antiAndrogensAreFlaggedByName() {
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Spironolactone 100mg")?.substance == "Spironolactone")
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Aldactone")?.substance == "Spironolactone")
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Flutamide")?.kind == .antiAndrogen)
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Cyproterone acetate")?.kind == .antiAndrogen)
    }

    @Test func unrelatedItemsAreNotFlagged() {
        #expect(PregnancyCaution.info(treatmentClass: .shampoo, name: "Ketoconazole 2% shampoo") == nil)
        #expect(PregnancyCaution.info(treatmentClass: .oil, name: "Rosemary oil") == nil)
        #expect(PregnancyCaution.info(treatmentClass: .supplement, name: "Biotin 5000mcg") == nil)
        #expect(PregnancyCaution.info(treatmentClass: .prp, name: "PRP session") == nil)
        #expect(PregnancyCaution.info(treatmentClass: .other, name: "Vitamin D") == nil)
    }

    // MARK: - The status gate

    @Test func theStatusGateSuppressesTheNoteUnlessPregnancyIsFlagged() {
        // Finasteride is a recognised substance, but only a flagging status surfaces the note.
        #expect(PregnancyCaution.info(treatmentClass: .finasteride, name: "Fin", status: .no) == nil)
        #expect(PregnancyCaution.info(treatmentClass: .finasteride, name: "Fin", status: .unspecified) == nil)
        #expect(PregnancyCaution.info(treatmentClass: .finasteride, name: "Fin", status: .pregnant) != nil)
        // A non-recognised item never flags, even when pregnant.
        #expect(PregnancyCaution.info(treatmentClass: .oil, name: "Argan oil", status: .pregnant) == nil)
    }

    // MARK: - Honest framing

    @Test func messagesNameTheSubstanceAndPointToTheClinicianNeverDiagnose() {
        let fin = PregnancyCaution.info(treatmentClass: .finasteride, name: "")!
        #expect(fin.message.contains("Finasteride"))
        #expect(fin.message.localizedCaseInsensitiveContains("clinician"))
        #expect(fin.message.localizedCaseInsensitiveContains("diagnos") == false)

        let minox = PregnancyCaution.info(treatmentClass: .minoxidil, name: "")!
        #expect(minox.message.localizedCaseInsensitiveContains("clinician"))
    }
}
