import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    init() {}

    struct AnalysisError: Error { let message: String }

    /// True when the on-device model is usable on this device (Apple Intelligence available).
    /// The whole feature is unavailable — with a clear message — when this is false.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAnalysis.isAvailable { return true }
        #endif
        return false
    }

    /// The one-line reason shown when `isAvailable` is false.
    static let unavailableMessage = "On-device AI needs Apple Intelligence (iPhone 15 Pro or newer, iOS 26). Everything else in Hair Compass works fully on this device."

    /// Runs one written analysis over the canonical `AIContext` JSON (see AIContextBuilder.swift).
    /// Text only — no photos are read (there is no on-device path for image input); the record's
    /// own photo *metadata* is already inside the context.
    func analyze(context: AIContext) async {
        isRunning = true
        result = nil
        errorMessage = nil
        defer { isRunning = false }
        guard isAvailable else {
            errorMessage = Self.unavailableMessage
            return
        }
        do {
            result = try await generate(instructions: Self.analysisInstructions, prompt: Self.analysisPrompt(context: context))
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
        guard isAvailable else {
            errorMessage = Self.unavailableMessage
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

    private func generate(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let text = await OnDeviceAnalysis.generate(instructions: instructions, prompt: prompt),
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

    /// Generate over `prompt` with the given `instructions`. Returns nil when the model is
    /// unavailable or the request fails, so the caller can surface a clear message.
    static func generate(instructions: String, prompt: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
#endif
