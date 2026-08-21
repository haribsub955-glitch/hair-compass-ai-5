//
//  AIOutputValidatorRegressionTests.swift
//  Hair Compass AI 5Tests
//
//  Audit fixes to `AIOutputValidator` (OnDeviceAnalysisService.swift), all pure and networkless:
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
//  3. `Facts.canonical`'s `String(Int(value))` conversion trapped whenever `value` exceeded
//     Int64's range (~±9.2e18) — reachable from a 19-20+ digit batch/lot code in OCR'd label
//     text, or from a reply that echoes one back. Fixed with a magnitude guard shared by every
//     call site, so the crash can't resurface somewhere the guard was forgotten and both sides
//     always agree on a huge number's canonical form.
//
//  4. The facts-side number extraction used `\b\d+(?:\.\d+)?\b`, which cannot match a digit run
//     glued to a unit ("Biotin 10000mcg") — `\b` never matches between two `\w` characters, so
//     it silently failed to extract the number at all. Honest ingredient summaries quoting
//     label amounts got replaced by the scary fallback text as a result. Fixed by dropping the
//     boundary on the FACTS side only (`Facts.context`'s string branch and the `suppliedFacts`
//     path); the reply side keeps `\b` — a reply's numbers appear in prose, where the
//     conservative boundary is the right call.
//
//  5. `suppliedFacts`'s raw-digit-run retention (alongside the canonical form) was dead code
//     for ordinary numbers — the query side always canonicalizes before checking membership,
//     so nothing was ever looked up by its raw form. Fix 3's magnitude guard makes it
//     load-bearing: past Int64's range, canonicalization is a lossy re-stringification of an
//     imprecise Double, so a reply that echoes a huge lot/batch code's *exact* digits can only
//     be recognized by matching that literal string. `isSafe(_:facts:)` now checks both forms.
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

    /// Not a vacuous rename: this pins down *why* "007" passes, since it turns out raw-string
    /// retention isn't why. `isSafe(_:facts:)` always canonicalizes a reply's numbers before
    /// checking membership, so "007" (canonical "7") matches through canonicalization alone —
    /// a `Facts` set holding only the canonical form, with no raw "007" anywhere, recognizes
    /// the exact same reply. (What the raw form actually gates is numbers too large for
    /// canonicalization to round-trip losslessly — see `hugeNumbersBeyondInt64DoNotCrashAndStillValidate` below.)
    @Test func suppliedFactsMatchOrdinaryLeadingZeroNumbersThroughCanonicalizationAlone() {
        let facts = #"{"code":"007"}"#
        #expect(AIOutputValidator.isSafe("Reference code 007 is on file.", suppliedFacts: facts))

        let canonicalOnly = AIOutputValidator.Facts(
            numericValues: ["7"], groundedText: facts.lowercased(), treatmentReadiness: [:])
        #expect(AIOutputValidator.isSafe("Reference code 007 is on file.", facts: canonicalOnly))
    }

    // MARK: - Fix 3: Int64-overflow crash in `Facts.canonical`

    /// The exact crash scenario: a 19-20+ digit batch/lot code (bigger than Int64.max,
    /// ~9.2e18) appears in both the OCR'd label text and the reply that quotes it verbatim.
    /// `Int(value)` used to trap unconditionally here; the magnitude guard must both avoid the
    /// crash and still recognize the honest, grounded reply as safe.
    @Test func hugeNumbersBeyondInt64DoNotCrashAndStillValidate() {
        let hugeLotCode = "12345678901234567890"   // 20 digits, well past Int64.max
        let label = "Rosemary Mint Scalp Serum. Lot \(hugeLotCode)."
        let reply = "This rosemary scalp oil is Lot \(hugeLotCode)."
        #expect(AIOutputValidator.safeText(reply, suppliedFacts: label) == reply)

        // The guard is a crash fix, not a loosening: an invented huge number the label never
        // stated must still be rejected.
        let invented = "This rosemary scalp oil is Lot 99999999999999999999."
        #expect(AIOutputValidator.safeText(invented, suppliedFacts: label) == AIOutputValidator.replacement)
    }

    // MARK: - Fix 4: ingredient summaries are gated against the label text

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

    /// The exact bug scenario for the word-boundary fix: "10000mcg" glues the number straight
    /// onto its unit, so `\b\d+\b` could never extract "10000" from the label at all — an
    /// honest reply quoting that exact label amount got replaced by the scary fallback text.
    @Test func ingredientSummaryAdmitsAUnitGluedDoseFromTheLabel() {
        let label = "Biotin & Minoxidil Scalp Drops. Active ingredients: Biotin 10000mcg, Minoxidil 5%."
        let reply = "This scalp treatment contains 10000 mcg of biotin at 5% minoxidil."
        #expect(AIOutputValidator.safeText(reply, suppliedFacts: label) == reply)

        // Still not a loosening: a dose the label never stated must still be rejected.
        let invented = "This scalp treatment contains 2500 mcg of biotin."
        #expect(AIOutputValidator.safeText(invented, suppliedFacts: label) == AIOutputValidator.replacement)
    }

    // MARK: - Negative structured facts (shedDirection/scalpDirection can read negative)

    /// A minimal `AIContext` with everything but `dailySeries.shedDirection` empty — enough to
    /// exercise `Facts.context`'s NSNumber branch without pulling in the SwiftData model
    /// fixtures `AIContextTests.swift` builds for the full builder pipeline.
    private func makeMinimalContext(shedDirection: Double?) -> AIContext {
        AIContext(
            generatedAt: "2026-08-21T00:00:00Z",
            profile: .init(condition: "Androgenetic", conditionCode: "AGA", sex: nil,
                          ageBand: nil, familyHistory: nil, baselineStage: nil, tractionRisk: false),
            dailySeries: .init(days: [], shed7d: nil, shedDirection: shedDirection,
                              scalp7d: nil, scalpDirection: nil),
            treatments: [],
            labs: [],
            triggers: [],
            progressCheckIns: [],
            bodySignals: .init(signals: [], rapidWeightLossPercent: nil),
            meta: .init(
                entryCount: 0, streak: 0,
                photos: .init(count: 0, regions: [], firstDate: nil, lastDate: nil),
                longTerm: .init(firstEntryDate: nil, lastEntryDate: nil, averageShed: nil, averageScalpTotal: nil),
                omitted: .init(dailyEntries: 0, treatments: 0, labs: 0, triggers: 0, progressCheckIns: 0, sideEffects: 0)
            )
        )
    }

    /// `shedDirection`/`scalpDirection` are routinely negative (an improving, falling trend).
    /// Before the fix, `Facts.context` only stored the signed canonical form ("-0.5"), while
    /// both number extractions strip the leading "-" — so an honest reply stating the same
    /// fact by magnitude ("declined by 0.5") was rejected as an invented number. The signed
    /// literal must keep working too; only an actually-invented magnitude should fail.
    @Test func structuredContextAdmitsAGroundedNegativeTrendBySignOrByMagnitude() {
        let context = makeMinimalContext(shedDirection: -0.5)
        #expect(AIOutputValidator.isSafe("Shedding declined by 0.5 over this window.", context: context))
        #expect(AIOutputValidator.isSafe("The trend direction reads -0.5.", context: context))
        #expect(!AIOutputValidator.isSafe("Shedding declined by 0.7 over this window.", context: context))
    }
}
