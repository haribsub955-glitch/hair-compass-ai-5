import Foundation
import UIKit

struct RoutineProductAnalysis: Decodable {
    let score: Int
    let summary: String
    let confidence: String
}

struct OpenAIAnalysisService {
    let apiKey: String
    let session: URLSession = .shared

    func analyze(records: [PhotoRecord], profile: HairProfile?) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIAnalysisError.missingAPIKey
        }

        let imageParts: [[String: String]] = records.compactMap { record in
            guard let image = PhotoFileStore.shared.loadImage(at: record.imagePath),
                  let data = image.jpegData(compressionQuality: 0.75) else {
                return nil
            }

            return [
                "type": "input_image",
                "image_url": "data:image/jpeg;base64,\(data.base64EncodedString())"
            ]
        }

        guard !imageParts.isEmpty else {
            throw OpenAIAnalysisError.noImages
        }

        var profileContext = ""
        if let profile {
            var parts: [String] = []
            if !profile.hairLossFocus.isEmpty { parts.append("Tracking focus: \(profile.hairLossFocus)") }
            if !profile.texture.isEmpty { parts.append("Hair texture: \(profile.texture)") }
            if !profile.patternDistribution.isEmpty { parts.append("Pattern: \(profile.patternDistribution)") }
            if !profile.biologicalSex.isEmpty { parts.append("Biological sex: \(profile.biologicalSex)") }
            if !profile.ageRange.isEmpty { parts.append("Age range: \(profile.ageRange)") }
            if !profile.scalpSensitivity.isEmpty { parts.append("Scalp: \(profile.scalpSensitivity)") }
            if !parts.isEmpty {
                profileContext = "\n\nUser profile context:\n\(parts.joined(separator: "\n"))"
            }
        }

        let prompt = """
        You are analyzing a multi-angle hair and scalp tracking session for record keeping only.
        Do not diagnose disease.
        Summarize visible observations by angle, note image quality limitations, and suggest what changes a dermatologist might want documented over time.
        Keep the answer concise and scientifically cautious.\(profileContext)
        """

        var content: [[String: String]] = [
            ["type": "input_text", "text": prompt]
        ]
        content.append(contentsOf: imageParts)

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "store": false,
            "input": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIAnalysisError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw OpenAIAnalysisError.apiFailure(errorText)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsePayload.self, from: data)
        let text = decoded.outputText ?? decoded.output.compactMap(\.content).flatMap { $0 }.compactMap(\.text).joined(separator: "\n")

        guard !text.isEmpty else {
            throw OpenAIAnalysisError.invalidResponse
        }

        return text
    }
}

struct OpenAIIntelligenceService {
    let apiKey: String
    let session: URLSession = .shared

    func analyze(
        report: IntelligenceReport,
        impactPoints: [RoutineImpactPoint],
        entries: [CheckInEntry],
        labResults: [LabResultEntry],
        procedureEvents: [ProcedureEvent],
        profile: HairProfile?,
        medications: [MedicationLog],
        triggerEvents: [HairTriggerEvent]
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIIntelligenceError.missingAPIKey
        }

        let pointSummary = impactPoints.suffix(10).map { point in
            let checkInSummary: String
            if point.hasCheckInData {
                checkInSummary = "shedding \(point.sheddingScore), scalp \(point.scalpScore), hydration \(point.hydrationScore), stress \(point.stressScore)"
            } else {
                checkInSummary = "check-in not logged"
            }

            let healthSummary: String
            if point.hasHealthData {
                var parts = ["sleep \(String(format: "%.1f", point.sleepHours))h", "exercise \(Int(point.exerciseMinutes))min"]
                if point.proteinGrams > 0 { parts.append("protein \(Int(point.proteinGrams))g") }
                if point.waterLiters > 0 { parts.append("water \(String(format: "%.1f", point.waterLiters))L") }
                healthSummary = parts.joined(separator: ", ")
            } else {
                healthSummary = "health data not available"
            }

            return """
            \(point.date.formatted(date: .abbreviated, time: .omitted)): \(checkInSummary), \(healthSummary), minoxidil logs \(point.minoxidilEntries), smoking \(point.smokingCount)
            """
        }.joined(separator: "\n")

        let checkInSummary = entries.map { entry in
            var flags: [String] = []
            if entry.hasItch { flags.append("itch") }
            if entry.hasFlaking { flags.append("flaking") }
            if entry.hasScalpPain { flags.append("scalp pain") }
            if entry.hasPatchyHairLoss { flags.append("patchy loss") }
            if entry.hasTightStyleTension { flags.append("traction tension") }
            if entry.isWashDay { flags.append("wash day") }
            let flagStr = flags.isEmpty ? "" : " [flags: \(flags.joined(separator: ", "))]"
            return """
            \(entry.date.formatted(date: .abbreviated, time: .omitted)): scalp \(entry.scalpScore), hydration \(entry.hydrationScore), shedding \(entry.sheddingLevel), stress \(entry.stressLevel)\(flagStr), note: \(entry.note)
            """
        }.joined(separator: "\n")

        let labSummary = labResults.map { result in
            "\(result.testName) \(result.valueText) \(result.unit) (\(result.status)) on \(result.collectedAt.formatted(date: .abbreviated, time: .omitted))"
        }.joined(separator: "\n")

        let procedureSummary = procedureEvents.map { event in
            "\(event.title) on \(event.performedAt.formatted(date: .abbreviated, time: .omitted))"
        }.joined(separator: "\n")

        var profileSection = "Not available."
        if let profile {
            var parts: [String] = []
            if !profile.hairLossFocus.isEmpty { parts.append("Tracking focus: \(profile.hairLossFocus)") }
            if !profile.texture.isEmpty { parts.append("Hair texture: \(profile.texture)") }
            if !profile.primaryGoal.isEmpty { parts.append("Primary goal: \(profile.primaryGoal)") }
            if !profile.biologicalSex.isEmpty { parts.append("Biological sex: \(profile.biologicalSex)") }
            if !profile.ageRange.isEmpty { parts.append("Age range: \(profile.ageRange)") }
            if !profile.hairLossDuration.isEmpty { parts.append("Duration of hair loss: \(profile.hairLossDuration)") }
            if !profile.patternDistribution.isEmpty { parts.append("Pattern: \(profile.patternDistribution)") }
            if !profile.familyHistorySummary.isEmpty { parts.append("Family history: \(profile.familyHistorySummary)") }
            if !profile.scalpSensitivity.isEmpty { parts.append("Scalp: \(profile.scalpSensitivity)") }
            parts.append("Wash frequency: every \(profile.washFrequencyDays) day(s)")
            if !parts.isEmpty { profileSection = parts.joined(separator: "\n") }
        }

        let medicationSummary = medications.filter(\.isActive).map { med in
            "\(med.name) (\(med.form), \(med.dosage), \(med.schedule))\(med.prescribedByClinician ? " [clinician-prescribed]" : "")"
        }.joined(separator: "\n")

        let triggerSummary = triggerEvents.prefix(8).map { event in
            "\(event.title) (\(event.category), severity: \(event.severity), started \(event.startedAt.formatted(date: .abbreviated, time: .omitted)))\(event.affectsSheddingRisk ? " [affects shedding risk]" : "")"
        }.joined(separator: "\n")

        let prompt = """
        You are Hair Compass Intelligence, an AI feature inside a hair tracking app.
        Your job is to summarize the user's own data conservatively.
        Do not diagnose disease.
        Do not claim causation from correlation.
        Clearly mention uncertainty when the data is sparse.
        Focus on practical tracking insights and low-risk next steps.
        Keep the output concise with 5 short sections titled:
        1. What data this used
        2. AI pattern read
        3. What might be worth tracking
        4. Missing context
        5. When clinician review matters

        User profile:
        \(profileSection)

        Local summary:
        \(report.compactPromptSummary)

        Recent chart points:
        \(pointSummary.isEmpty ? "No chart points available." : pointSummary)

        Recent check-ins:
        \(checkInSummary.isEmpty ? "No recent check-ins available." : checkInSummary)

        Active medications:
        \(medicationSummary.isEmpty ? "No active medications logged." : medicationSummary)

        Trigger events:
        \(triggerSummary.isEmpty ? "No trigger events logged." : triggerSummary)

        Labs:
        \(labSummary.isEmpty ? "No labs logged." : labSummary)

        Procedures:
        \(procedureSummary.isEmpty ? "No procedures logged." : procedureSummary)
        """

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "store": false,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIIntelligenceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw OpenAIIntelligenceError.apiFailure(errorText)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsePayload.self, from: data)
        let text = decoded.outputText ?? decoded.output.compactMap(\.content).flatMap { $0 }.compactMap(\.text).joined(separator: "\n")

        guard !text.isEmpty else {
            throw OpenAIIntelligenceError.invalidResponse
        }

        return text
    }
}

struct OpenAIRoutineProductAnalysisService {
    let apiKey: String
    let session: URLSession = .shared

    func analyze(
        title: String,
        itemType: String,
        category: String,
        notes: String,
        image: UIImage?,
        profile: HairProfile?
    ) async throws -> RoutineProductAnalysis {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIAnalysisError.missingAPIKey
        }

        var profileContext = ""
        if let profile {
            var parts: [String] = []
            if !profile.hairLossFocus.isEmpty { parts.append("Tracking focus: \(profile.hairLossFocus)") }
            if !profile.texture.isEmpty { parts.append("Hair texture: \(profile.texture)") }
            if !profile.scalpSensitivity.isEmpty { parts.append("Scalp: \(profile.scalpSensitivity)") }
            if !profile.biologicalSex.isEmpty { parts.append("Biological sex: \(profile.biologicalSex)") }
            if !parts.isEmpty { profileContext = "\n\nUser profile:\n\(parts.joined(separator: "\n"))" }
        }

        var content: [[String: String]] = [[
            "type": "input_text",
            "text": """
            You are Hair Compass Intelligence.
            Assess whether this hair routine item is likely to add real value for hair or scalp tracking.
            Be conservative and scientifically honest.
            Do not diagnose disease.
            Do not overclaim cosmetic or marketing benefits.
            Return strict JSON with keys:
            score: integer from 0 to 100
            summary: short plain-language explanation under 40 words
            confidence: one of low, medium, high

            Item title: \(title)
            Item type: \(itemType)
            Category: \(category)
            Notes: \(notes.isEmpty ? "No notes provided." : notes)\(profileContext)
            """
        ]]

        if let image, let data = image.jpegData(compressionQuality: 0.75) {
            content.append([
                "type": "input_image",
                "image_url": "data:image/jpeg;base64,\(data.base64EncodedString())"
            ])
        }

        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "routine_product_analysis",
                    "schema": [
                        "type": "object",
                        "properties": [
                            "score": [
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 100
                            ],
                            "summary": [
                                "type": "string"
                            ],
                            "confidence": [
                                "type": "string",
                                "enum": ["low", "medium", "high"]
                            ]
                        ],
                        "required": ["score", "summary", "confidence"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "input": [[
                "role": "user",
                "content": content
            ]]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIAnalysisError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw OpenAIAnalysisError.apiFailure(errorText)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsePayload.self, from: data)
        let text = decoded.outputText ?? decoded.output.compactMap(\.content).flatMap { $0 }.compactMap(\.text).joined(separator: "\n")
        guard let jsonData = text.data(using: .utf8) else {
            throw OpenAIAnalysisError.invalidResponse
        }
        let result = try JSONDecoder().decode(RoutineProductAnalysis.self, from: jsonData)
        return RoutineProductAnalysis(
            score: min(max(result.score, 0), 100),
            summary: result.summary,
            confidence: result.confidence
        )
    }
}

enum OpenAIAnalysisError: LocalizedError {
    case missingAPIKey
    case noImages
    case invalidResponse
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Enter an OpenAI API key before requesting analysis."
        case .noImages:
            return "There are no valid images in this session."
        case .invalidResponse:
            return "OpenAI returned an unreadable response."
        case .apiFailure(let message):
            return message
        }
    }
}

enum OpenAIIntelligenceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Enter an OpenAI API key before generating Intelligence."
        case .invalidResponse:
            return "The AI response could not be read."
        case .apiFailure(let message):
            return message
        }
    }
}

struct OpenAIResponsePayload: Decodable {
    let output: [OpenAIOutputItem]

    enum CodingKeys: String, CodingKey {
        case output
        case outputText = "output_text"
    }

    let outputText: String?
}

struct OpenAIOutputItem: Decodable {
    let content: [OpenAIOutputContent]?
}

struct OpenAIOutputContent: Decodable {
    let text: String?
}

final class PhotoFileStore {
    static let shared = PhotoFileStore()

    private init() {}

    func save(image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = directoryURL.appendingPathComponent("\(UUID().uuidString).jpg")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: url, options: .atomic)
        return url.path
    }

    func loadImage(at path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    private var directoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("HairPhotoRecords", isDirectory: true)
    }
}
