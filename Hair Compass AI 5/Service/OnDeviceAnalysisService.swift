import Foundation
import CoreFoundation

// App Store Connect product descriptions must NOT claim the AI is on-device-only: DeepSeek
// cloud inference is the primary engine whenever it's configured and consented to (see
// `AIEngine`), and on-device Apple Intelligence is the no-consent path and offline fallback.
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A precise breakdown of *why* on-device AI is (or isn't) usable right now, replacing the single
/// `isAvailable` boolean everywhere the UI needs to explain an unavailable state. Shared by
/// `HairAnalysisService`, `HairChatService`, and `InsightEngine`'s on-device path — all three
/// read the same `SystemLanguageModel.default.availability` and previously collapsed every
/// `UnavailableReason` to the same "your hardware can't do this" copy, which is simply false for a
/// Pro subscriber on eligible hardware who hasn't flipped Apple Intelligence on yet, or whose model
/// is still downloading. Each case carries its own actionable, honest message.
enum OnDeviceAvailability: Equatable {
    /// The on-device model can run right now.
    case available
    /// Eligible hardware, but Apple Intelligence is switched off in Settings — a one-tap fix.
    case notEnabled
    /// Apple Intelligence is on, but the model itself is still downloading/preparing. Transient.
    case modelNotReady
    /// This iPhone or iOS version doesn't support Apple Intelligence at all.
    case deviceNotEligible

    var isAvailable: Bool { self == .available }

    /// Whether the unavailable card should offer an "Open Settings" shortcut for this reason.
    var showsSettingsButton: Bool { self == .notEnabled }

    /// The plain-language, actionable message shown when this status isn't `.available`. Always
    /// closes on the same honest reassurance: the rest of the app still works fully on-device.
    var message: String {
        switch self {
        case .available:
            return ""
        case .notEnabled:
            return "Apple Intelligence is turned off — enable it in Settings > Apple Intelligence & Siri to use on-device AI. Everything else in Hair Compass works fully on this device."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready on this iPhone — try again in a bit. Everything else in Hair Compass works fully on this device."
        case .deviceNotEligible:
            return "On-device AI needs Apple Intelligence (iPhone 15 Pro or newer, iOS 26). Everything else in Hair Compass works fully on this device."
        }
    }

    /// Reads `SystemLanguageModel.default.availability` right now and classifies the specific
    /// `UnavailableReason` so the UI can show something a person can act on instead of one generic
    /// "unsupported hardware" notice. Falls back to `.deviceNotEligible` on iOS < 26 or when
    /// FoundationModels isn't linkable — the same conservative default the app already used.
    static var current: OnDeviceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .modelNotReady
                case .deviceNotEligible: return .deviceNotEligible
                @unknown default: return .deviceNotEligible
                }
            @unknown default:
                return .deviceNotEligible
            }
        }
        #endif
        return .deviceNotEligible
    }
}

/// "Deep analysis" and ingredient identification. Text only: the model reasons over the app's
/// deterministic tracking record (and the on-device OCR of an ingredient label), never over
/// image pixels — photos are never sent anywhere. Record-keeping, never diagnosis.
///
/// Engine order (see `AIEngine`): the cloud model (DeepSeek) leads whenever it is configured
/// and the person has consented — it runs on every iPhone. Apple's on-device FoundationModels
/// is the no-consent path and the offline fallback. Both engines' output passes the same
/// deterministic `AIOutputValidator` gate before the UI shows it.
@MainActor
@Observable
final class HairAnalysisService {
    private(set) var isRunning = false
    private(set) var result: String?
    private(set) var errorMessage: String?
    /// The currently in-flight generation, if any — held so `cancel()` can stop it (and the
    /// billed cloud request underneath it) when a sheet is dismissed mid-run.
    private var currentTask: (any CancellableTask)?

    init() {}

    /// Cancels the in-flight analysis, if any. Cooperative: `URLSession.data(for:)` observes
    /// Swift Concurrency cancellation and tears down the underlying network task when its
    /// enclosing `Task` is cancelled, so this actually stops a billed cloud call in flight
    /// rather than just abandoning the awaiting call site.
    func cancel() {
        currentTask?.cancel()
        // Nothing is still in flight for this handle once cancel() has been asked for it —
        // nil it out so a later `cancel()` (or a stray read) can't act on a stale, already-
        // dead task.
        currentTask = nil
    }

    struct AnalysisError: Error { let message: String }

    /// The specific reason on-device AI is (or isn't) usable right now — read fresh each access,
    /// since Apple Intelligence can be enabled/disabled or finish downloading while the app is open.
    var availability: OnDeviceAvailability { OnDeviceAvailability.current }

    /// Which engine an analysis would use right now — cloud, on-device, a pending consent
    /// question, or nothing. Read fresh each access: consent and Apple Intelligence can both
    /// change while a sheet is open.
    var engine: AIEngine { AIEngine.current }

    /// True when an analysis can actually run right now (cloud or on-device). False while the
    /// consent question is still open and when neither engine exists — the UI shows the consent
    /// card or a clear notice instead of the run button.
    var isAvailable: Bool { engine.canRun }

    /// The one-line reason shown when `isAvailable` is false and no more specific status is on
    /// hand. Prefer `availability.message` where a live `OnDeviceAvailability` is available.
    static let unavailableMessage = "On-device AI needs Apple Intelligence (iPhone 15 Pro or newer, iOS 26). Everything else in Hair Compass works fully on this device."

    /// Runs one written analysis over the canonical `AIContext` JSON (see AIContextBuilder.swift).
    /// Text only — no photos are read (there is no on-device path for image input); the record's
    /// own photo *metadata* is already inside the context.
    func analyze(context: AIContext) async {
        // A double-tap on the run button (or the sheet re-appearing mid-request) must not fire
        // a second billed cloud call on top of the first. The guard and the flag it guards
        // have to happen together, synchronously, right here — setting `isRunning` from
        // inside the enqueued Task body left a window where two rapid calls could both pass
        // the guard before either body had actually run (reproduced: two billed calls).
        guard !isRunning else { return }
        isRunning = true
        result = nil
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            // Also clears `currentTask`: a stale handle left behind after this Task finishes
            // could otherwise be cancelled or read by a later, unrelated run.
            defer { self.isRunning = false; self.currentTask = nil }
            do {
                self.result = try await self.generate(
                    instructions: Self.analysisInstructions,
                    prompt: Self.analysisPrompt(context: context),
                    validationContext: context,
                    maxTokens: 700
                )
            } catch is CancellationError {
                // The sheet is gone — nothing to show, and no fallback: cancellation means
                // the person no longer wants an answer, not that the call failed.
            } catch let e as AnalysisError {
                self.errorMessage = e.message
            } catch {
                self.errorMessage = "The analysis couldn't be completed. Please try again."
            }
        }
        currentTask = task
        await task.value
    }

    /// Summarize a product from the text read off its ingredient label (on-device OCR — see
    /// `TextScanner`). Returns a short summary, or nil on error. Record-keeping, not medical advice.
    func analyzeIngredients(labelText: String) async -> String? {
        // Same synchronous guard-then-flag ordering as `analyze` above, and for the same
        // reason: `isRunning` must be set before this function returns control to the caller,
        // not from inside the Task it hands off to.
        guard !isRunning else { return nil }
        isRunning = true
        errorMessage = nil
        let task = Task { [weak self] () -> String? in
            guard let self else { return nil }
            defer { self.isRunning = false; self.currentTask = nil }
            let trimmed = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.errorMessage = "No label text was read from this photo. Try a clearer photo of the ingredients."
                return nil
            }
            do {
                // The label text IS the fact set here — there's no AIContext for a product
                // summary, so the OCR'd text is what grounds the validator against invented
                // dosages/claims (see fix for the bypass this used to have: `generate` was
                // called with no validation source at all, and `validated(_:context:)` returns
                // unvalidated text when there's no context — cloud output rendered verbatim on
                // exactly the surface that invites dosage language).
                return try await self.generate(
                    instructions: Self.ingredientInstructions, prompt: trimmed,
                    validationFacts: trimmed, maxTokens: 300
                )
            } catch is CancellationError {
                return nil
            } catch let e as AnalysisError {
                self.errorMessage = e.message
                return nil
            } catch {
                self.errorMessage = "Couldn't summarize this label. Please try again."
                return nil
            }
        }
        currentTask = task
        return await task.value
    }

    // MARK: - Generation (engine order lives here)

    /// `validationContext` is the deep-analysis path's fact source; `validationFacts` is the
    /// ingredient path's (the raw OCR'd label text). Exactly one is non-nil per caller today,
    /// but nothing here assumes that — `validated` below just checks whichever it's handed.
    private func generate(
        instructions: String,
        prompt: String,
        validationContext: AIContext? = nil,
        validationFacts: String? = nil,
        maxTokens: Int = 600
    ) async throws -> String {
        switch engine {
        case .cloud:
            do {
                let reply = try await CloudAI.reply(
                    system: instructions,
                    turns: [CloudAI.Turn(role: "user", text: prompt)],
                    maxTokens: maxTokens
                )
                return validated(reply, context: validationContext, suppliedFacts: validationFacts)
            } catch let cloudError as CloudAI.ServiceError {
                // A failed cloud call falls back to the on-device model when this hardware has
                // one; otherwise the honest transport error is the result.
                guard OnDeviceAvailability.current.isAvailable else {
                    throw AnalysisError(message: cloudError.message)
                }
                // A cancellation landing in the gap between the cloud call failing and the
                // fallback starting (the sheet dismissed right as the cloud request errored
                // out) must not kick off a second, on-device generation nobody is waiting for
                // anymore.
                try Task.checkCancellation()
                do {
                    return try await onDeviceGenerate(
                        instructions: instructions, prompt: prompt,
                        validationContext: validationContext, validationFacts: validationFacts
                    )
                } catch {
                    // Both engines failed. When the cloud call failed for a network reason,
                    // that message ("check your connection") is the actionable diagnosis —
                    // don't let the on-device fallback's generic failure mask why cloud didn't
                    // answer either. When cloud failed for a non-network reason, the on-device
                    // error is at least as informative, so let it through unchanged.
                    if cloudError.isNetwork { throw AnalysisError(message: cloudError.message) }
                    throw error
                }
            }
        case .onDevice:
            return try await onDeviceGenerate(
                instructions: instructions, prompt: prompt,
                validationContext: validationContext, validationFacts: validationFacts
            )
        case .needsCloudConsent:
            // The sheets gate their run buttons behind the consent card, so reaching this is a
            // logic error — answer with the honest next step rather than trapping.
            throw AnalysisError(message: "Choose whether to use cloud AI first.")
        case .unavailable(let message):
            throw AnalysisError(message: message)
        }
    }

    private func onDeviceGenerate(
        instructions: String,
        prompt: String,
        validationContext: AIContext?,
        validationFacts: String?
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAvailability.current.isAvailable {
            // No `onPartial` passed: nothing reads partial prose (the deterministic gate below
            // is the sole publication boundary), so there's nothing to feed it — the function
            // keeps its own no-op default for callers that ever do want progress.
            guard let text = await OnDeviceAnalysis.generate(instructions: instructions, prompt: prompt),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // A cancelled generation (the sheet dismissed mid-run) surfaces here as the
                // same nil/empty result as a genuine on-device failure — check cancellation
                // first so a walked-away person gets silence (the `catch is CancellationError`
                // in `analyze`/`analyzeIngredients` above), not an error card for a request
                // they didn't actually ask to fail.
                if Task.isCancelled { throw CancellationError() }
                throw AnalysisError(message: "The analysis came back empty. Please try again.")
            }
            return validated(text.trimmingCharacters(in: .whitespacesAndNewlines), context: validationContext, suppliedFacts: validationFacts)
        }
        #endif
        throw AnalysisError(message: OnDeviceAvailability.current.message)
    }

    /// The one publication gate both engines share — deterministic, gated against whichever
    /// fact source the caller has: the full `AIContext` for deep analysis, or the raw label
    /// text for ingredient summaries. Every `generate()` caller in this file supplies one or
    /// the other; text reaches the UI unvalidated only if a future caller passes neither.
    private func validated(_ text: String, context: AIContext?, suppliedFacts: String? = nil) -> String {
        if let context { return AIOutputValidator.safeText(text, context: context) }
        if let suppliedFacts { return AIOutputValidator.safeText(text, suppliedFacts: suppliedFacts) }
        return text
    }

    // MARK: - Prompts

    static let analysisInstructions = """
    You are a careful hair-health companion inside a documentation app — NOT a diagnostic tool. \
    You will receive one person's tracking record as a JSON object. Write a plain-language, warm \
    written summary (about 6–10 sentences) that prioritizes what matters most and notes honest \
    uncertainty. Rules: never invent numbers or facts beyond the JSON; never diagnose or name a \
    condition the person didn't state; only discuss whether a treatment is 'working' if it is past \
    its 24-week judging point; correlation is a pattern worth watching, not proof. Frame everything \
    as record-keeping. End with one gentle, evidence-aligned suggestion. No lists or headings.
    """

    static func analysisPrompt(context: AIContext) -> String {
        """
        Facts: the JSON object below is this person's tracking record (schemaVersion \(context.schemaVersion) of the app's AI context; dates are yyyy-MM-dd; all statistics are precomputed on-device). Absent fields were simply not tracked — never guess them.
        \(context.jsonString())
        """
    }

    static let ingredientInstructions = """
    You are given the text read off a hair or scalp product's ingredient label. Identify what the \
    product is and summarize its key active ingredients and their evidence tier for hair. Note if \
    it's largely inactive or a marketing myth. Be brief (2–4 sentences). This is record-keeping, \
    not medical advice; do not diagnose.
    """
}

/// Deterministic safety boundary after generation. Model instructions are defense-in-depth; this
/// validator is the final gate on the two risks it's built for — clinical-safety overreach
/// (diagnosis, dosing language, waving off a red-flag symptom) and ungrounded output (numbers or
/// high-impact facts the supplied record never stated). Scope, honestly: it is not a general
/// content-safety or prompt-injection filter — injected instructions and phishing-style text are
/// out of scope. That's a deliberate line, not an oversight: everywhere this validator's output
/// lands renders as inert plain `Text` (no links, no markup, nothing executable), so there is
/// nothing downstream for injected text to actually do.
enum AIOutputValidator {
    static let replacement = "I couldn't safely summarize that output. Keep using the tracked record for documentation, and discuss medical decisions or concerning symptoms with a qualified clinician. This is record-keeping, not diagnosis."

    struct Facts: Sendable {
        var numericValues: Set<String>
        var groundedText: String
        var treatmentReadiness: [String: Bool]

        static func context(_ context: AIContext) -> Facts {
            let data = (try? JSONEncoder().encode(context)) ?? Data()
            let object = try? JSONSerialization.jsonObject(with: data)
            var numbers = Set<String>()
            func collect(_ value: Any) {
                if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                    let signed = canonical(number.doubleValue)
                    numbers.insert(signed)
                    // A structured field can be legitimately negative (`shedDirection` /
                    // `scalpDirection` read negative for an improving trend) while an honest
                    // reply states the same fact by magnitude ("declined by 0.5") rather than
                    // echoing the sign. The reply-side extraction below never captures a
                    // leading "-" — a blanket `-?\d+` would also eat into "2026-08-05" and mint
                    // fake negative dates — so the unsigned counterpart has to be supplied from
                    // here instead. Sign semantics are otherwise out of this gate's scope
                    // entirely: it only checks that the generated *magnitude* was actually
                    // present somewhere in the record.
                    if signed.hasPrefix("-") { numbers.insert(canonical(abs(number.doubleValue))) }
                } else if let string = value as? String {
                    // No `\b`: label/JSON text glues digits straight onto units or suffixes
                    // ("Biotin 10000mcg"), and `\b` can never match between two `\w`
                    // characters, so it would silently fail to extract those numbers at all.
                    // The reply-side extraction below keeps `\b` — a reply's numbers appear in
                    // prose, where the conservative boundary is the right call.
                    string.matches(of: /\d+(?:\.\d+)?/).forEach {
                        if let number = Double($0.output) { numbers.insert(canonical(number)) }
                    }
                } else if let array = value as? [Any] { array.forEach(collect) }
                else if let dictionary = value as? [String: Any] { dictionary.values.forEach(collect) }
            }
            if let object { collect(object) }
            return Facts(
                numericValues: numbers,
                groundedText: String(data: data, encoding: .utf8)?.lowercased() ?? "",
                treatmentReadiness: Dictionary(
                    context.treatments.map { ($0.name.lowercased(), $0.outcomeReady) },
                    uniquingKeysWith: { $0 && $1 })
            )
        }

        // `fileprivate`, not `private`: `isSafe(_:suppliedFacts:allTreatmentsOutcomeReady:)`
        // and `isSafe(_:facts:)` below both need the exact same canonical form when they build
        // or canonicalize numbers by hand instead of through `.context(_:)`, so no two call
        // sites ever drift into two different notions of "the same number".
        fileprivate static func canonical(_ value: Double) -> String {
            // `Int(value)` traps once `value` exceeds Int64's range (~±9.2e18) — reachable
            // from 19-20+ digit batch/lot codes in OCR'd label text, and symmetrically from a
            // reply that echoes one back. Guard the magnitude and fall back to the Double's
            // own string form instead; every call site shares this one function, so the crash
            // can't reappear somewhere the guard was forgotten, and both sides always agree on
            // what a given huge number's canonical string looks like.
            value.rounded() == value && value.magnitude < 9e18 ? String(Int(value)) : String(value)
        }
    }

    static func safeText(_ text: String, context: AIContext) -> String {
        isSafe(text, facts: .context(context)) ? text : replacement
    }

    static func isSafe(_ text: String, context: AIContext) -> Bool {
        isSafe(text, facts: .context(context))
    }

    static func safeText(_ text: String, suppliedFacts: String, allTreatmentsOutcomeReady: Bool? = nil) -> String {
        isSafe(text, suppliedFacts: suppliedFacts, allTreatmentsOutcomeReady: allTreatmentsOutcomeReady)
            ? text : replacement
    }

    static func isSafe(_ text: String, suppliedFacts: String, allTreatmentsOutcomeReady: Bool? = nil) -> Bool {
        // Canonicalize each supplied number the same way `Facts.context` canonicalizes the
        // reply-side numbers below (Double → trimmed integer-or-decimal string) — AND keep the
        // raw matched string too. Without the canonical form, a date component like "08" or
        // "05" in a JSON fact string could never match a reply's canonicalized "8", so an
        // honest reply ("shedding rose in month 8") would fail against a fact set that plainly
        // contains that same date. Keeping the raw string is a pure superset for ordinary
        // numbers — but it stops being a no-op once a number is too large for `canonical` to
        // round-trip losslessly: the fallback there is a lossy re-stringification of an
        // imprecise Double, so a reply that echoes a huge lot/batch code's exact digits
        // verbatim can only be recognized by matching that literal string. `isSafe(_:facts:)`
        // below checks both forms for exactly this reason.
        //
        // No `\b` either: see the matching comment on `Facts.context`'s string branch — a
        // label like "Biotin 10000mcg" glues its number straight onto the unit.
        var numbers = Set<String>()
        for match in suppliedFacts.matches(of: /\d+(?:\.\d+)?/) {
            let raw = String(match.output)
            numbers.insert(raw)
            if let value = Double(raw) { numbers.insert(Facts.canonical(value)) }
        }
        let readiness = allTreatmentsOutcomeReady
            ?? (suppliedFacts.lowercased().contains("\"outcomeready\":false") ? false : nil)
        return isSafe(text, facts: Facts(numericValues: numbers,
                                        groundedText: suppliedFacts.lowercased(),
                                        treatmentReadiness: readiness.map { ["treatment": $0] } ?? [:]))
    }

    static func isSafe(_ text: String, facts: Facts) -> Bool {
        let value = text.lowercased()
        let safeNegations = [
            #"\b(do not|don't|never) (stop|discontinue|change|increase|decrease)\b[^.!?]{0,80}\b(without|unless)\b[^.!?]{0,80}\b(clinician|doctor|prescriber|medical professional)\b"#,
            #"\b(talk|speak|check|consult) (to|with) (your )?(clinician|doctor|prescriber) before\b[^.!?]{0,50}\b(stop|discontinue|change|increase|decrease)\b"#
        ]
        var gatedValue = value
        for pattern in safeNegations {
            gatedValue = gatedValue.replacingOccurrences(of: pattern, with: " safe-medication-caution ", options: .regularExpression)
        }
        let forbidden = [
            #"\b(you|your scalp|this|it)\s+(clearly |definitely |certainly |probably |likely )?(have|has|is|looks? like|appears? to be|suggests?|indicates?|shows?)\s+(an? )?(alopecia(?: areata| totalis| universalis)?|androgenetic alopecia|pattern hair loss|telogen effluvium|dermatitis|psoriasis|folliculitis|tinea capitis|ringworm|infection|scarring alopecia|lichen planopilaris|frontal fibrosing alopecia)\b"#,
            #"\b(you|your scalp|this|it)\s+(could|should|would|may|might)\s+be\s+(an? )?(alopecia(?: areata| totalis| universalis)?|androgenetic alopecia|pattern hair loss|telogen effluvium|dermatitis|psoriasis|folliculitis|tinea capitis|ringworm|infection|scarring alopecia|lichen planopilaris|frontal fibrosing alopecia)\b"#,
            #"\b(this|that|the pattern|the photo|your symptoms?) (proves|confirms|establishes|means|is diagnostic of|points to)\b"#,
            #"\b(start|stop|discontinue|quit|increase|decrease|reduce|raise|lower|double|halve|skip|switch) (taking |using |applying )?(your )?(medication|medicine|dose|dosage|treatment|minoxidil|finasteride)\b"#,
            #"\b(you should|i recommend|you need to) (start|stop|discontinue|increase|decrease|switch|change|take|use|apply)\b"#,
            #"\b(medication|medicine|dose|dosage|treatment|minoxidil|finasteride)\s+(should|could|would|may|might)\s+be\s+(started|stopped|discontinued|increased|decreased|changed|switched|doubled|halved|skipped)\b"#,
            #"\b(safe|okay|ok|advisable|appropriate)\s+to\s+(start|stop|discontinue|quit|increase|decrease|change|switch|take|use|apply)\b[^.!?]{0,60}\b(medication|medicine|dose|dosage|treatment|minoxidil|finasteride)\b"#,
            #"\b(i recommend|you should|you need to)\s+(starting|stopping|discontinuing|increasing|decreasing|changing|switching|taking|using|applying)\b"#,
            #"\b(take|use|apply)\s+(one|two|three|half|a)\s*(mg|ml|tablet|capsule|pill|drop|pump|times?)\b"#,
            #"\b(take|use|apply) \d+(\.\d+)?\s*(mg|mcg|g|ml|tablet|capsule|pill|drop|pump|times? (a|per) day)\b"#,
            #"\b(no need|do not need|don't need|not necessary) to (seek|get|call|contact).*(urgent|emergency|medical|clinician|doctor)\b"#,
            #"\b(ignore|nothing to worry about|not serious|harmless|definitely safe|cannot be serious)\b.*\b(chest pain|faint|severe|swelling|trouble breathing|shortness of breath|suicid|sudden|bleeding)\b"#
        ]
        if forbidden.contains(where: { gatedValue.range(of: $0, options: .regularExpression) != nil }) { return false }

        let efficacy = value.range(
            of: #"\b(treatment|medication|minoxidil|finasteride|it) (is |has |isn't |hasn't )?(working|effective|ineffective|failed|improving regrowth)\b"#,
            options: .regularExpression) != nil
        if efficacy {
            let mentioned = facts.treatmentReadiness.filter { value.contains($0.key) }
            if mentioned.isEmpty {
                if facts.treatmentReadiness.values.contains(false) { return false }
            } else if mentioned.values.contains(false) { return false }
        }

        // Reject invented numeric measurements. Calendar dates and the app's fixed 24-week
        // policy are allowed; every other generated number must occur in the supplied facts.
        //
        // No `\b` here either — a reply can glue an invented number straight onto a unit
        // ("contains 5000mcg of biotin"), and `\b\d+\b` can never match between two `\w`
        // characters, so a unit-glued invented dose used to contribute NO number to this check
        // at all and sailed through ungated on exactly the surface that invites dosage
        // language. The facts side (`Facts.context`'s string branch and the `suppliedFacts`
        // path above) is already boundary-less for the same reason, so a legitimately-quoted,
        // unit-glued dose from the label/context still matches and still passes.
        let numbers = value.matches(of: /\d+(?:\.\d+)?/).map { String($0.output) }
        for number in numbers where number != "24" {
            // A closure literal here, not a bare `Facts.canonical` function reference: the
            // latter converts the MainActor-isolated method into a plain function value with
            // no isolation of its own, which the compiler flags even though this call site
            // runs on the same actor. The closure inherits this context's isolation instead.
            let canonical = Double(number).map { Facts.canonical($0) } ?? number
            // Check the literal digits too, not just the canonical form — see the comment on
            // `suppliedFacts`'s raw-string retention above for why this stops being redundant
            // once a number is too large to round-trip through a Double exactly.
            if !facts.numericValues.contains(canonical) && !facts.numericValues.contains(number) {
                return false
            }
        }

        // High-impact clinical facts must be present in the supplied record before generated
        // prose may assert them. This deliberately stays small and deterministic; the model is
        // free to summarize recorded observations, never to invent a new clinical premise.
        let groundedTerms = ["pregnant", "pregnancy", "ferritin", "vitamin d", "thyroid",
                             "infection", "alopecia areata", "telogen effluvium"]
        for term in groundedTerms where value.contains(term) && !facts.groundedText.contains(term) {
            return false
        }
        return true
    }
}

#if canImport(FoundationModels)
/// On-device analysis via Apple's FoundationModels (Apple Intelligence). Everything stays on the
/// device — no network, no key, no consent. Mirrors `OnDeviceChat` / `OnDeviceInsight`.
@available(iOS 26.0, *)
enum OnDeviceAnalysis {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Generate over `prompt` with the given `instructions`. The underlying session always
    /// streams internally (`streamResponse`), and `onPartial`, if a caller supplies one, fires
    /// on the main actor with the cumulative text after every new snapshot — but nothing in the
    /// app does today: generated prose is never shown before `AIOutputValidator` passes the
    /// finished text, so every caller here keeps the no-op default and reads only the return
    /// value. Returns nil when the model is unavailable or the request fails, so the caller can
    /// surface a clear message.
    static func generate(
        instructions: String,
        prompt: String,
        onPartial: @MainActor (String) -> Void = { _ in }
    ) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let stream = session.streamResponse(to: prompt)
            var latest = ""
            for try await snapshot in stream {
                latest = snapshot.content
                let trimmed = latest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { await onPartial(trimmed) }
            }
            let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
#endif
