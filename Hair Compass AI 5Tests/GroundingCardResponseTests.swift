//
//  GroundingCardResponseTests.swift
//  Hair Compass AI 5Tests
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct GroundingCardResponseTests {
    private let json = """
    {
      "id": "grounding-2026-09-03-user-scope",
      "kind": "grounding",
      "eyebrow": "TODAY'S GROUNDING",
      "headline": "One difficult day is not a conclusion",
      "body": "Yesterday's shedding was above your usual range. One observation is not enough to establish a change.",
      "evidence_anchor": "Next trend review: 18 days",
      "primary_action": { "type": "complete_plan_item", "label": "Mark evening treatment complete", "target_id": "plan-item-id" },
      "secondary_action": { "type": "open_concern_flow", "label": "I'm worried" },
      "closure": "You recorded what happened. Nothing else needs checking today.",
      "tone": "gentle",
      "valid_until": "2099-09-04T00:00:00+04:00",
      "served": true
    }
    """

    private var now: Date { Date(timeIntervalSince1970: 1_788_000_000) }

    private func decode(_ text: String? = nil) throws -> GroundingCardResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GroundingCardResponse.self, from: Data((text ?? json).utf8))
    }

    private func rejection(
        _ response: GroundingCardResponse,
        planIDs: Set<String> = ["plan-item-id"],
        numbers: Set<String> = ["18"],
        percentageAllowed: Bool = true
    ) -> GroundingCardValidator.Rejection? {
        if case .failure(let reason) = GroundingCardValidator.validate(
            response,
            planItemIDs: planIDs,
            allowedNumbers: numbers,
            percentageAllowed: percentageAllowed,
            now: now
        ) { return reason }
        return nil
    }

    @Test func contractExampleDecodesAndBecomesACard() throws {
        let response = try decode()
        #expect(response.primaryAction.targetID == "plan-item-id")
        #expect(response.secondaryAction?.type == "open_concern_flow")
        let result = GroundingCardValidator.validate(
            response,
            planItemIDs: ["plan-item-id"],
            allowedNumbers: ["18"],
            now: now
        )
        let card = try result.get()
        #expect(card.kind == .grounding)
        #expect(card.primary == .completePlanItem(id: "plan-item-id", label: "Mark evening treatment complete"))
        #expect(card.evidenceAnchor == "Next trend review: 18 days")
    }

    @Test func unservedUnknownOrIncompleteShapesAreRejected() throws {
        #expect(rejection(try decode(json.replacingOccurrences(of: "\"served\": true", with: "\"served\": false"))) == .notServed)
        #expect(rejection(try decode(json.replacingOccurrences(of: "\"kind\": \"grounding\"", with: "\"kind\": \"upsell\""))) == .unknownKind)
        #expect(rejection(try decode(json.replacingOccurrences(of: "\"tone\": \"gentle\"", with: "\"tone\": \"alarming\""))) == .unknownTone)
        #expect(rejection(try decode(json.replacingOccurrences(of: "\"id\": \"grounding-2026-09-03-user-scope\"", with: "\"id\": \" \""))) == .incomplete)
    }

    @Test func targetsAndBothActionSlotsAreClosed() throws {
        let response = try decode()
        #expect(rejection(response, planIDs: ["another-item"]) == .badTarget)
        #expect(rejection(try decode(json.replacingOccurrences(of: "complete_plan_item", with: "open_url"))) == .unknownAction)
        #expect(rejection(try decode(json.replacingOccurrences(of: "open_concern_flow", with: "open_url"))) == .unknownAction)
    }

    @Test func limitsExpiryNumbersAndFramingWordsAreEnforced() throws {
        let longHeadline = try decode(json.replacingOccurrences(
            of: "One difficult day is not a conclusion",
            with: "one two three four five six seven eight nine ten eleven"
        ))
        #expect(rejection(longHeadline) == .headlineTooLong)
        let expired = try decode(json.replacingOccurrences(of: "2099-09-04", with: "2020-09-04"))
        #expect(rejection(expired) == .expired)
        #expect(rejection(try decode(), numbers: []) == .unknownNumber("18"))
        let diagnosis = try decode(json.replacingOccurrences(
            of: "One observation is not enough to establish a change.",
            with: "You have androgenetic alopecia."
        ))
        #expect(rejection(diagnosis) == .framingWord("diagnos") || rejection(diagnosis) == .framingWord("you have"))
    }

    @Test func openOnlyConsistencyCannotBePresentedAsZeroPercent() throws {
        let zero = try decode(json.replacingOccurrences(
            of: "One difficult day is not a conclusion",
            with: "Your consistency is 0% today"
        ))
        #expect(rejection(zero, numbers: ["0", "18"], percentageAllowed: false) == .unscoredPercentage)
        #expect(rejection(zero, numbers: ["0", "18"], percentageAllowed: true) == nil)
    }

    @Test func cacheIsBoundToDayFingerprintAndExpiry() throws {
        let defaults = UserDefaults(suiteName: "GroundingCardResponseTests.\(UUID().uuidString)")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Muscat")!
        let response = try decode()
        GroundingCardCache.store(response, fingerprint: "f1", now: now, defaults: defaults)
        #expect(GroundingCardCache.load(fingerprint: "f1", now: now, calendar: calendar, defaults: defaults) == response)
        #expect(GroundingCardCache.load(fingerprint: "f2", now: now, calendar: calendar, defaults: defaults) == nil)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        #expect(GroundingCardCache.load(fingerprint: "f1", now: tomorrow, calendar: calendar, defaults: defaults) == nil)
        GroundingCardCache.clear(defaults: defaults)
        #expect(GroundingCardCache.load(fingerprint: "f1", now: now, calendar: calendar, defaults: defaults) == nil)
    }
}
