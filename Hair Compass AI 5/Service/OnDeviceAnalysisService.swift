import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A precise breakdown of *why* on-device AI is (or isn't) usable right now, replacing the single
/// `isAvailable` boolean everywhere the UI needs to explain an unavailable state. Shared by
/// `OnDeviceAnalysisService`, `HairChatService`, and `InsightEngine`'s on-device path — all three
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

/// On-device "deep analysis" and ingredient identification via Apple's **FoundationModels**
/// (Apple Intelligence). Everything stays on the device — no network, no API key, no off-device
/// consent. Text only: the model reasons over the app's deterministic tracking record (and the
/// on-device OCR of an ingredient label), never over image pixels — Foundation Models has no
/// image input, so scalp *photos* are not interpreted. Record-keeping, never diagnosis.
///
/// Mirrors `OnDeviceChat` / `OnDeviceInsight`: availability-gated, and it returns a clear,
/// user-facing message on unsupported hardware rather than reaching for a cloud fallback.
@MainActor
@Observable
final class OnDeviceAnalysisService {
    private(set) var isRunning = false
    private(set) var result: String?
    private(set) var errorMessage: String?
    /// The written summary as it streams in token-by-token, cumulative from an empty string.
    /// Nil until the first token arrives, and cleared back to nil once the finished text lands
    /// in `result` — the UI shows this growing inside the Summary card instead of a blind wait.
    private(set) var streamingText: String?

    init() {}

    struct AnalysisError: Error { let message: String }

    /// The specific reason on-device AI is (or isn't) usable right now — read fresh each access,
    /// since Apple Intelligence can be enabled/disabled or finish downloading while the app is open.
    var availability: OnDeviceAvailability { OnDeviceAvailability.current }

    /// True when the on-device model is usable on this device (Apple Intelligence available).
    /// The whole feature is unavailable — with a clear, reason-specific message — when this is
    /// false; see `availability` for which of the three reasons applies.
    var isAvailable: Bool { availability.isAvailable }

    /// The one-line reason shown when `isAvailable` is false and no more specific status is on
    /// hand. Prefer `availability.message` where a live `OnDeviceAvailability` is available.
    static let unavailableMessage = "On-device AI needs Apple Intelligence (iPhone 15 Pro or newer, iOS 26). Everything else in Hair Compass works fully on this device."

    /// Runs one written analysis over the canonical `AIContext` JSON (see AIContextBuilder.swift).
    /// Text only — no photos are read (there is no on-device path for image input); the record's
    /// own photo *metadata* is already inside the context.
    func analyze(context: AIContext) async {
        isRunning = true
        result = nil
        streamingText = nil
        errorMessage = nil
        defer { isRunning = false; streamingText = nil }
        let status = availability
        guard status.isAvailable else {
            errorMessage = status.message
            return
        }
        do {
            result = try await generate(
                instructions: Self.analysisInstructions,
                prompt: Self.analysisPrompt(context: context),
                onPartial: { [weak self] partial in self?.streamingText = partial }
            )
        } catch let e as AnalysisError {
            errorMessage = e.message
        } catch {
            errorMessage = "The analysis couldn't be completed. Please try again."
        }
    }

    /// Summarize a product from the text read off its ingredient label (on-device OCR — see
    /// `TextScanner`). Returns a short summary, or nil on error. Record-keeping, not medical advice.
    func analyzeIngredients(labelText: String) async -> String? {
        let trimmed = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        let status = availability
        guard status.isAvailable else {
            errorMessage = status.message
            return nil
        }
        guard !trimmed.isEmpty else {
            errorMessage = "No label text was read from this photo. Try a clearer photo of the ingredients."
            return nil
        }
        do {
            return try await generate(instructions: Self.ingredientInstructions, prompt: trimmed)
        } catch {
            errorMessage = "Couldn't summarize this label. Please try again."
            return nil
        }
    }

    // MARK: - On-device generation

    private func generate(
        instructions: String,
        prompt: String,
        onPartial: @MainActor (String) -> Void = { _ in }
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let text = await OnDeviceAnalysis.generate(instructions: instructions, prompt: prompt, onPartial: onPartial),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AnalysisError(message: "The analysis came back empty. Please try again.")
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw AnalysisError(message: Self.unavailableMessage)
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

#if canImport(FoundationModels)
/// On-device analysis via Apple's FoundationModels (Apple Intelligence). Everything stays on the
/// device — no network, no key, no consent. Mirrors `OnDeviceChat` / `OnDeviceInsight`.
@available(iOS 26.0, *)
enum OnDeviceAnalysis {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Generate over `prompt` with the given `instructions`, streaming as it writes. `onPartial`
    /// fires on the main actor with the cumulative text so far after every new snapshot, so the
    /// UI can show the summary as it's written instead of a blind wait. Returns nil when the
    /// model is unavailable or the request fails, so the caller can surface a clear message.
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
