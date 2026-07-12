//
//  LabUnitAndRangeTests.swift
//  Hair Compass AI 5Tests
//
//  Two correctness fixes to lab flags: (1) alternate-unit entry (vitamin D in nmol/L, B12 in
//  pmol/L) must convert deterministically to the canonical stored unit before any range check,
//  and (2) a user-supplied "range from your lab report" override must be honored by the flag
//  and gauge instead of always assuming the app's generic adult default.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct LabUnitAndRangeTests {

    // MARK: - Unit conversion

    @Test func vitaminDCanonicalUnitIsIdentity() {
        let ngPerML = LabTest.vitaminD.unitOptions.first { $0.label == "ng/mL" }!
        #expect(ngPerML.toCanonical(75) == 75)
    }

    @Test func vitaminDConvertsNmolToCanonicalNgPerML() {
        // A healthy 75 nmol/L should land well inside the 30...100 ng/mL range, not below it —
        // this is the exact false "Below range" the audit flagged.
        let nmol = LabTest.vitaminD.unitOptions.first { $0.label == "nmol/L" }!
        let converted = nmol.toCanonical(75)
        #expect((29...31).contains(converted))   // ~30.0
        #expect(LabTest.vitaminD.referenceRange.contains(converted))
    }

    @Test func vitaminB12ConvertsPmolToCanonicalPgPerML() {
        let pmol = LabTest.vitaminB12.unitOptions.first { $0.label == "pmol/L" }!
        let converted = pmol.toCanonical(400)
        #expect((540...545).contains(converted))   // 400 * 1.355 = 542
        #expect(LabTest.vitaminB12.referenceRange.contains(converted))
    }

    @Test func ferritinTshFreeT4HaveNoAlternateUnit() {
        #expect(LabTest.ferritin.unitOptions.count == 1)
        #expect(LabTest.tsh.unitOptions.count == 1)
        #expect(LabTest.freeT4.unitOptions.count == 1)
    }

    @Test func canonicalUnitIsAlwaysTheFirstOption() {
        for test in LabTest.allCases {
            #expect(test.unitOptions.first?.label == test.unit)
            #expect(test.unitOptions.first?.factorToCanonical == 1)
        }
    }

    // MARK: - Custom reference range override

    @Test func effectiveRangeFallsBackToDefaultWhenNoOverride() {
        let lab = LabResult(test: .ferritin, value: 50)
        #expect(lab.effectiveRange == LabTest.ferritin.referenceRange)
        #expect(!lab.hasCustomRange)
    }

    @Test func effectiveRangeUsesValidOverride() {
        let lab = LabResult(test: .ferritin, value: 20, refLow: 15, refHigh: 150)
        #expect(lab.effectiveRange == 15...150)
        #expect(lab.hasCustomRange)
        // 20 is below the app default (30) but inside this lab's own printed range.
        #expect(lab.flag == .normal)
    }

    @Test func invalidOverrideFallsBackToDefault() {
        // low >= high is not a real interval — ignored rather than trusted.
        let lab = LabResult(test: .ferritin, value: 20, refLow: 150, refHigh: 15)
        #expect(lab.effectiveRange == LabTest.ferritin.referenceRange)
        #expect(!lab.hasCustomRange)
        #expect(lab.flag == .low)
    }

    @Test func overrideThatMatchesTheDefaultIsNotFlaggedAsCustom() {
        let range = LabTest.tsh.referenceRange
        let lab = LabResult(test: .tsh, value: 2.0, refLow: range.lowerBound, refHigh: range.upperBound)
        #expect(!lab.hasCustomRange)
    }

    @Test func rangeBasedFlagMatchesTestBasedFlag() {
        #expect(HairAnalytics.flag(for: 20, range: LabTest.ferritin.referenceRange)
                == HairAnalytics.flag(for: 20, test: .ferritin))
        #expect(HairAnalytics.flag(for: 150, range: LabTest.ferritin.referenceRange)
                == HairAnalytics.flag(for: 150, test: .ferritin))
    }
}
