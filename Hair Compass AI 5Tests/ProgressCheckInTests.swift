//
//  ProgressCheckInTests.swift
//  Hair Compass AI 5Tests
//
//  The periodic between-visit self-report (Model/Models.swift: ProgressCheckIn): the
//  clinician-readable lines `clinicianSummary()` produces, and the scalp-pain red-flag line
//  that only appears when the user reports it. Self-reported context, never a diagnosis.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct ProgressCheckInTests {

    // MARK: - A filled, improving check-in

    @Test func clinicianSummaryDescribesEachAnswerInPlainLanguage() {
        let checkIn = ProgressCheckIn(
            regrowth: .visible,
            density: .better,
            shedding: .better,
            hairline: .same,
            overall: .better,
            scalpPain: false
        )
        let lines = checkIn.clinicianSummary()

        #expect(lines.contains("New regrowth (baby hairs): Clearly visible"))
        #expect(lines.contains("Density: less scalp shows"))
        #expect(lines.contains("Shedding: less"))
        #expect(lines.contains("Hairline/part: stable"))
        #expect(lines.contains("Overall: better"))
    }

    @Test func noScalpPainMeansNoRedFlagLine() {
        let checkIn = ProgressCheckIn(regrowth: .visible, density: .better, shedding: .better,
                                       hairline: .same, overall: .better, scalpPain: false)
        let lines = checkIn.clinicianSummary()

        #expect(!lines.contains { $0.contains("⚠") })
        #expect(!lines.contains { $0.contains("scalp pain") })
    }

    // MARK: - The scalp-pain red flag (a safety nudge, never a diagnosis)

    @Test func scalpPainAddsARedFlagLineWithTheNote() {
        let checkIn = ProgressCheckIn(scalpPain: true, scalpPainNote: "sore crown")
        let lines = checkIn.clinicianSummary()

        let flag = lines.first { $0.contains("⚠") }
        #expect(flag != nil)
        #expect(flag?.contains("scalp pain/tenderness") == true)
        #expect(flag?.contains("sore crown") == true)
        // Honesty guardrail: a nudge to see a clinician, never a diagnosis or condition name.
        #expect(flag?.localizedCaseInsensitiveContains("diagnos") == false)
    }

    @Test func scalpPainWithoutANoteStillFlagsButOmitsTheDash() {
        let checkIn = ProgressCheckIn(scalpPain: true)
        let lines = checkIn.clinicianSummary()

        let flag = lines.first { $0.contains("⚠") }
        #expect(flag != nil)
        #expect(flag?.contains("scalp pain/tenderness") == true)
        #expect(flag?.contains(" — ") == false)
    }

    // MARK: - Free-text note

    @Test func noteLineOnlyAppearsWhenNoteIsNonEmpty() {
        let withNote = ProgressCheckIn(note: "Started using the derma roller weekly")
        #expect(withNote.clinicianSummary().contains("Note: Started using the derma roller weekly"))

        let withoutNote = ProgressCheckIn()
        #expect(!withoutNote.clinicianSummary().contains { $0.hasPrefix("Note:") })
    }

    // MARK: - Patches (alopecia areata-only; nil means "not asked")

    @Test func noPatchLineWhenPatchTrendWasNeverAsked() {
        let checkIn = ProgressCheckIn(regrowth: .visible, density: .better)
        #expect(checkIn.patchTrend == nil)
        #expect(!checkIn.clinicianSummary().contains { $0.hasPrefix("Patches:") })
    }

    @Test func patchLineAppearsWithTheRightDirectionWhenAnswered() {
        let worse = ProgressCheckIn(patchTrend: .worse)
        #expect(worse.clinicianSummary().contains("Patches: new or larger"))

        let better = ProgressCheckIn(patchTrend: .better)
        #expect(better.clinicianSummary().contains("Patches: fewer or smaller"))

        let same = ProgressCheckIn(patchTrend: .same)
        #expect(same.clinicianSummary().contains("Patches: about the same"))
    }

    @Test func patchTrendRoundTripsThroughTheStoredRawValue() {
        let checkIn = ProgressCheckIn()
        #expect(checkIn.patchTrend == nil)

        checkIn.patchTrend = .worse
        #expect(checkIn.patchTrendRaw == ProgressTrend.worse.rawValue)
        #expect(checkIn.patchTrend == .worse)

        checkIn.patchTrend = nil
        #expect(checkIn.patchTrendRaw == nil)
    }
}
