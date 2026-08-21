//
//  AIOutputValidatorRegressionTests.swift
//  Hair Compass AI 5Tests
//
//  Two audit fixes to `AIOutputValidator` (OnDeviceAnalysisService.swift), both pure and
//  networkless:
//
//  1. The `suppliedFacts:` overload used to build its numeric fact set from the raw regex
//     matches only, with no canonicalization — while the reply side (and `Facts.context`)
//     canonicalize every number (Double → trimmed). A date component like "08" in the fact
//     JSON could then never match a reply's canonicalized "8", so an honest reply citing a
//     date-derived number got replaced by the scary fallback text. Fixed by canonicalizing
//     the supplied numbers too (while keeping the raw string as well — a pure superset).
//
//  2. `analyzeIngredients` used to call `generate` with no validation source at all, and
//     `validated(_:context:)` returns text unchanged when there's no `AIContext` — so cloud
//     output rendered verbatim on exactly the one surface (a product label reader) that
//     invites invented dosage language. Fixed by gating ingredient output with
//     `suppliedFacts:` set to the OCR'd label text itself. These tests exercise the validator
//     function directly with label-shaped input, since that's the mechanism the fix wires up;
//     `HairAnalysisService.analyzeIngredients` end-to-end would require faking either network
//     transport or on-device model availability, which isn't worth the seam for this fix.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct AIOutputValidatorRegressionTests {

    // MARK: - Fix 1: canonicalization of supplied facts

    /// The exact bug scenario: a JSON fact string with a "yyyy-MM-dd" date contributes "08" and
    /// "05" as raw digit runs. A reply that legitimately cites "month 8" (canonical form "8")
    /// must be recognized as grounded, not rejected as an invented number.
    @Test func suppliedFactsCanonicalizeSoADateDerivedNumberInAReplyIsRecognized() {
        let facts = #"{"generatedAt":"2026-08-05T00:00:00Z","meta":{"entryCount":3}}"#

        // Before the fix, "8" (canonical) was never in a fact set built only from raw matches
        // ("2026", "08", "05") — this would have failed.
        #expect(AIOutputValidator.isSafe("Your shedding rose in month 8.", suppliedFacts: facts))

        // The fix is a superset, not a loosening: a genuinely invented number must still fail.
        #expect(!AIOutputValidator.isSafe("Your shedding rose in month 47.", suppliedFacts: facts))
    }

    /// Raw digit runs stay in the fact set alongside their canonical form — the fix adds to the
    /// set, it never narrows it. A reply citing the fact string's own literal substring must
    /// keep passing exactly as it did before.
    @Test func suppliedFactsKeepTheRawDigitRunTooNotJustTheCanonicalForm() {
        let facts = #"{"code":"007"}"#
        #expect(AIOutputValidator.isSafe("Reference code 007 is on file.", suppliedFacts: facts))
    }

    // MARK: - Fix 2: ingredient summaries are gated against the label text

    /// The label text is the fact set for a product summary. A reply that invents a dosage
    /// number the label never stated must be rejected — this is the exact shape the bypass
    /// used to let straight through to the UI.
    @Test func ingredientSummaryRejectsAnInventedDosageNumberNotOnTheLabel() {
        let label = "Rosemary Mint Scalp Serum. Ingredients: Rosmarinus officinalis leaf oil, " +
            "Simmondsia chinensis (jojoba) seed oil, Mentha piperita (peppermint) oil."
        let reply = "This is a rosemary and peppermint scalp oil blend. Take 2 tablets per day for best results."
        #expect(AIOutputValidator.safeText(reply, suppliedFacts: label) == AIOutputValidator.replacement)
    }

    /// An honest ingredient summary that invents nothing beyond the label passes unchanged —
    /// gating the surface must not make ordinary, grounded summaries unusable.
    @Test func ingredientSummaryPassesWhenItStaysGroundedInTheLabel() {
        let label = "Biotin & Collagen Hair Serum. Active ingredients: Biotin 10000mcg, Hydrolyzed Collagen."
        let reply = "This serum's main actives are biotin and hydrolyzed collagen, both commonly marketed for hair support with limited direct evidence."
        #expect(AIOutputValidator.safeText(reply, suppliedFacts: label) == reply)
    }
}
