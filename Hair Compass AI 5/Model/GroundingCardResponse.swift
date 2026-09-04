//
//  GroundingCardResponse.swift
//  Hair Compass AI 5
//
//  The server card's wire shape, the gate it must pass before rendering, and a one-card cache.
//  The server chooses the message; the app only enforces shape, provenance, and safety.
//

import Foundation

struct GroundingCardResponse: Codable, Equatable {
    struct ActionPayload: Codable, Equatable {
        let type: String
        let label: String
        let targetID: String?

        enum CodingKeys: String, CodingKey {
            case type, label
            case targetID = "target_id"
        }
    }

    let id: String
    let kind: String
    let eyebrow: String
    let headline: String
    let body: String
    let evidenceAnchor: String?
    let primaryAction: ActionPayload
    let secondaryAction: ActionPayload?
    let closure: String
    let tone: String
    let validUntil: Date
    let served: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, eyebrow, headline, body, closure, tone, served
        case evidenceAnchor = "evidence_anchor"
        case primaryAction = "primary_action"
        case secondaryAction = "secondary_action"
        case validUntil = "valid_until"
    }
}

enum GroundingCardValidator {
    enum Rejection: Error, Equatable {
        case notServed
        case incomplete
        case unknownKind
        case unknownTone
        case headlineTooLong
        case bodyTooLong
        case missingClosure
        case unknownAction
        case badTarget
        case expired
        case unknownNumber(String)
        case unscoredPercentage
        case framingWord(String)
    }

    static let bannedWords = [
        "diagnos", "cure", "you have", "prescrib", "you should", "you must",
        "start taking", "stop taking", "double", "anxious", "anxiety", "disorder",
        "getting worse", "!"
    ]

    private static let kinds: [String: GroundingCard.Kind] = [
        "safety": .safety,
        "concern": .concern,
        "grounding": .grounding,
        "continuation": .continuation,
        "preparation": .preparation,
        "closure": .closure,
        "settled": .settled,
        "recovery": .recovery,
        "celebration": .celebration,
        "education": .education,
        "quiet": .quiet
    ]
    private static let tones: Set<String> = ["gentle", "direct", "scientific", "minimal"]
    private static let primaryActions: Set<String> = [
        "complete_plan_item", "log_checkin", "open_photos", "open_plan", "prepare_visit", "none"
    ]

    static func validate(
        _ response: GroundingCardResponse,
        planItemIDs: Set<String>,
        allowedNumbers: Set<String>,
        percentageAllowed: Bool = true,
        now: Date
    ) -> Result<GroundingCard, Rejection> {
        guard response.served else { return .failure(.notServed) }
        guard !response.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.eyebrow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failure(.incomplete) }
        guard let kind = kinds[response.kind] else { return .failure(.unknownKind) }
        guard tones.contains(response.tone) else { return .failure(.unknownTone) }
        guard wordCount(response.headline) <= 10 else { return .failure(.headlineTooLong) }
        guard wordCount(response.body) <= 55 else { return .failure(.bodyTooLong) }
        guard !response.closure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingClosure)
        }
        guard response.validUntil > now else { return .failure(.expired) }
        guard primaryActions.contains(response.primaryAction.type) else { return .failure(.unknownAction) }
        guard response.primaryAction.type == "none"
                || !response.primaryAction.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failure(.incomplete) }

        // The view owns the local concern affordance. A server may request only that one known
        // secondary action; all other secondary payloads are rejected instead of ignored.
        if let secondary = response.secondaryAction {
            guard secondary.type == "open_concern_flow",
                  !secondary.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  secondary.targetID == nil
            else { return .failure(.unknownAction) }
        }

        let primary: GroundingCard.Action
        switch response.primaryAction.type {
        case "complete_plan_item":
            guard let target = response.primaryAction.targetID, planItemIDs.contains(target) else {
                return .failure(.badTarget)
            }
            primary = .completePlanItem(id: target, label: response.primaryAction.label)
        case "log_checkin": primary = .logCheckIn
        case "open_photos": primary = .openPhotos
        case "open_plan": primary = .openPlan
        case "prepare_visit": primary = .prepareVisit
        case "none": primary = .none
        default: return .failure(.unknownAction)
        }

        let renderedText = [
            response.eyebrow, response.headline, response.body,
            response.evidenceAnchor ?? "", response.closure,
            response.primaryAction.label, response.secondaryAction?.label ?? ""
        ]
        for text in renderedText {
            let lower = text.lowercased()
            for word in bannedWords where lower.contains(word) {
                return .failure(.framingWord(word))
            }
        }
        if !percentageAllowed,
           [response.headline, response.body, response.evidenceAnchor ?? "", response.closure]
            .contains(where: { $0.range(of: #"\b0\s*%"#, options: .regularExpression) != nil }) {
            return .failure(.unscoredPercentage)
        }
        // Provenance applies to every user-visible string, not only the large type. Otherwise an
        // invented date could slip through the evidence anchor or an action label.
        for text in renderedText {
            for number in numbers(in: text) where !allowedNumbers.contains(number) {
                return .failure(.unknownNumber(number))
            }
        }

        return .success(GroundingCard(
            kind: kind,
            eyebrow: response.eyebrow,
            headline: response.headline,
            body: response.body,
            evidenceAnchor: response.evidenceAnchor,
            primary: primary,
            closure: response.closure,
            reason: "Chosen from your record for today's \(response.kind) state."
        ))
    }

    static func numbers(in text: String) -> [String] {
        var values: [String] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                values.append(current)
                current = ""
            }
        }
        if !current.isEmpty { values.append(current) }
        return values
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

enum GroundingCardCache {
    static let key = "grounding.card.cache"

    private struct Entry: Codable {
        let response: GroundingCardResponse
        let fingerprint: String
        let storedAt: Date
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func store(
        _ response: GroundingCardResponse,
        fingerprint: String,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) {
        let entry = Entry(response: response, fingerprint: fingerprint, storedAt: now)
        if let data = try? encoder.encode(entry) {
            defaults.set(data, forKey: key)
        }
    }

    static func load(
        fingerprint: String,
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> GroundingCardResponse? {
        guard let data = defaults.data(forKey: key),
              let entry = try? decoder.decode(Entry.self, from: data),
              entry.fingerprint == fingerprint,
              calendar.isDate(entry.storedAt, inSameDayAs: now),
              entry.response.validUntil > now
        else { return nil }
        return entry.response
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
