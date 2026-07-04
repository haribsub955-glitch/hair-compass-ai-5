//
//  RxGateTests.swift
//  Hair Compass AI 5Tests
//
//  The prescription gate: which about-to-be-saved treatments pause on the "usually
//  prescribed — we'll assume it is" confirmation card, and which brand art fronts it.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct RxGateTests {

    // MARK: - Always-prescription classes

    @Test func finasterideFires() {
        let req = RxGate.requirement(treatmentClass: .finasteride, name: "Finasteride", dose: "1 mg")
        #expect(req?.medication == .finasteride)
        #expect(req?.art == .remedy)
    }

    @Test func dutasterideFires() {
        let req = RxGate.requirement(treatmentClass: .dutasteride, name: "Dutasteride", dose: "0.5 mg")
        #expect(req?.medication == .dutasteride)
        #expect(req?.art == .remedy)
    }

    // MARK: - Minoxidil is route-gated

    @Test func oralMinoxidilFiresWithRemedyArt() {
        let req = RxGate.requirement(
            treatmentClass: .minoxidil, name: "Minoxidil (oral, low-dose)", dose: "2.5 mg"
        )
        #expect(req?.medication == .oralMinoxidil)
        #expect(req?.art == .remedy)
    }

    @Test func topicalMinoxidilDoesNotFire() {
        #expect(RxGate.requirement(treatmentClass: .minoxidil, name: "Minoxidil 5%", dose: "1 mL") == nil)
    }

    @Test func minoxidilOralDetectionReadsEitherField() {
        // "oral" in the name alone is enough…
        #expect(RxGate.requirement(treatmentClass: .minoxidil, name: "Oral minoxidil", dose: "")?.medication == .oralMinoxidil)
        // …and so is a milligram dose alone.
        #expect(RxGate.requirement(treatmentClass: .minoxidil, name: "Minoxidil", dose: "5 mg")?.medication == .oralMinoxidil)
    }

    // MARK: - Procedures, devices, and plain other never fire

    @Test func proceduresAndOtherDoNotFire() {
        #expect(RxGate.requirement(treatmentClass: .microneedling, name: "Microneedling", dose: "0.5–1.5 mm") == nil)
        #expect(RxGate.requirement(treatmentClass: .prp, name: "PRP", dose: "per clinic protocol") == nil)
        #expect(RxGate.requirement(treatmentClass: .lllt, name: "Low-level laser", dose: "10–20 min session") == nil)
        #expect(RxGate.requirement(treatmentClass: .other, name: "Rosemary oil", dose: "A few drops in a carrier oil") == nil)
    }

    // MARK: - Name-based detection for `.other` (the science-products add-to-plan path)

    @Test func otherClassDetectsPrescriptionSubstanceByName() {
        #expect(RxGate.requirement(treatmentClass: .other, name: "Finasteride 1 mg", dose: "1 mg")?.medication == .finasteride)
        #expect(RxGate.requirement(treatmentClass: .other, name: "Dutasteride", dose: "0.5 mg")?.medication == .dutasteride)
        #expect(RxGate.requirement(treatmentClass: .other, name: "Minoxidil (oral)", dose: "2.5 mg")?.medication == .oralMinoxidil)
        // Topical minoxidil stays over-the-counter even via the `.other` path.
        #expect(RxGate.requirement(treatmentClass: .other, name: "Minoxidil 5%", dose: "1 mL") == nil)
    }

    // MARK: - Route-aware art pick

    @Test func artFollowsRoute() {
        #expect(RxGate.art(for: .oral) == .remedy)
        #expect(RxGate.art(for: .topical) == .dropper)
    }

    // MARK: - Notes

    @Test func notesAreNonEmptyAndMentionPrescription() {
        for medication in RxGate.Medication.allCases {
            let note = RxGate.note(for: medication)
            #expect(!note.isEmpty)
            #expect(note.lowercased().contains("prescri"))
        }
    }

    @Test func oralMinoxidilNoteSaysOffLabel() {
        #expect(RxGate.note(for: .oralMinoxidil).lowercased().contains("off-label"))
    }
}
