//
//  GroundingCardProvider.swift
//  Hair Compass AI 5
//
//  Who supplies today's grounding card. The deterministic provider always answers and is the
//  exact fallback the spec requires (§10); a validated server card (G5) can sit in front of it.
//

import Foundation

@MainActor
protocol GroundingCardProvider {
    func card(input: GroundingInput, now: Date) async -> GroundingCard?
}

struct DeterministicGroundingProvider: GroundingCardProvider {
    func card(input: GroundingInput, now: Date) async -> GroundingCard? {
        GroundingCards.select(input)
    }
}

/// The exact state sent to the server and the numeric facts a response may quote. Both originate
/// from the same `GroundingInput`, preventing a generated card from introducing a plausible but
/// unrecorded percentage, date, or count.
enum GroundingState {
    static func fingerprint(_ input: GroundingInput) -> String {
        let plan = input.plan.occurrences
            .map { "\($0.id):\($0.state.rawValue)" }
            .joined(separator: ",")
        let flags = input.flags.map(\.id).joined(separator: ",")
        let phase = input.phase.map {
            "\($0.dayNumber)/\($0.week)/\($0.nextReviewWeek)/\($0.daysToReview)"
        } ?? "-"
        let photo: String
        switch input.photo {
        case .noBaseline: photo = "none"
        case .due(let days): photo = "due:\(days)"
        case .upcoming(let days): photo = "upcoming:\(days)"
        }
        let consistency = input.consistency30.map {
            "\($0.completed)/\($0.planned)/\($0.scored)"
        } ?? "-"
        return [
            plan, flags, phase, photo,
            "\(input.photoWithinTwoWeeks)",
            "\(input.missedYesterday)",
            "\(input.sheddingAboveUsual)",
            "\(input.loggedToday)",
            consistency,
            input.concern?.kind.rawValue ?? "no-concern"
        ].joined(separator: "|")
    }

    static func allowedNumbers(_ input: GroundingInput) -> Set<String> {
        var values: Set<String> = ["4", "12", "24", "28", "30"]
        values.formUnion([
            "\(input.plan.occurrences.count)",
            "\(input.plan.completedCount)",
            "\(input.plan.openCount)",
            "\(input.missedYesterday)"
        ])
        for occurrence in input.plan.occurrences {
            let name = occurrence.treatment.name.isEmpty
                ? occurrence.treatment.treatmentClass.title
                : occurrence.treatment.name
            values.formUnion(GroundingCardValidator.numbers(in: name))
            values.formUnion(GroundingCardValidator.numbers(in: occurrence.slot))
        }
        if let phase = input.phase {
            values.formUnion([
                "\(phase.dayNumber)", "\(phase.week)",
                "\(phase.nextReviewWeek)", "\(phase.daysToReview)"
            ])
        }
        if let consistency = input.consistency30 {
            values.formUnion([
                "\(consistency.completed)", "\(consistency.planned)", "\(consistency.scored)"
            ])
            if consistency.scored > 0 { values.insert("\(consistency.percent)") }
        }
        switch input.photo {
        case .due(let days):
            values.formUnion(["\(days)", "\(PhotoCadence.intervalDays + days)"])
        case .upcoming(let days):
            values.insert("\(days)")
        case .noBaseline:
            break
        }
        return values
    }

    static func payload(_ input: GroundingInput) -> [String: Any] {
        var state: [String: Any] = [
            "flags": input.flags.map(\.id),
            "plan_items": input.plan.occurrences.map { occurrence in
                [
                    "id": occurrence.id,
                    "state": occurrence.state.rawValue,
                    "slot": occurrence.slot,
                    "treatment": occurrence.treatment.name.isEmpty
                        ? occurrence.treatment.treatmentClass.title
                        : occurrence.treatment.name
                ]
            },
            "plan_complete": input.plan.isComplete,
            "plan_counts": [
                "total": input.plan.occurrences.count,
                "completed": input.plan.completedCount,
                "open": input.plan.openCount
            ],
            "missed_yesterday": input.missedYesterday,
            "shedding_above_usual": input.sheddingAboveUsual,
            "logged_today": input.loggedToday,
            "photo_within_two_weeks": input.photoWithinTwoWeeks,
            "policy": [
                "review_weeks": [4, 12, 24],
                "photo_interval_days": PhotoCadence.intervalDays,
                "consistency_window_days": 30
            ]
        ]
        if let phase = input.phase {
            state["phase"] = [
                "day": phase.dayNumber,
                "week": phase.week,
                "label": phase.label,
                "next_review_week": phase.nextReviewWeek,
                "days_to_review": phase.daysToReview
            ]
        }
        if let consistency = input.consistency30 {
            var value: [String: Any] = [
                "completed": consistency.completed,
                "planned": consistency.planned,
                "scored": consistency.scored
            ]
            if consistency.scored > 0 { value["percent"] = consistency.percent }
            state["consistency_30d"] = value
        }
        switch input.photo {
        case .noBaseline:
            state["photo"] = ["status": "no_baseline"]
        case .due(let days):
            state["photo"] = ["status": "due", "days_overdue": days]
        case .upcoming(let days):
            state["photo"] = ["status": "upcoming", "days_until": days]
        }
        if let concern = input.concern {
            state["concern"] = concern.kind.rawValue
        }
        return state
    }
}

#if DEBUG
/// The optional server path. It is reachable only with `HC_AGENT`, then only after the session
/// advertises `daily_grounding`. Decode, feature, transport, and validation failures all return
/// nil so Today keeps its deterministic card without flashing an error.
struct ServerGroundingProvider: GroundingCardProvider {
    let client: AgentClient

    init?() {
        guard AgentBridge.isEnabled else { return nil }
        client = AgentBridge.shared()
    }

    func card(input: GroundingInput, now: Date) async -> GroundingCard? {
        let fingerprint = GroundingState.fingerprint(input)
        let planIDs = Set(input.plan.occurrences.map(\.id))
        let allowedNumbers = GroundingState.allowedNumbers(input)
        let percentageAllowed = (input.consistency30?.scored ?? 0) > 0

        if let cached = GroundingCardCache.load(fingerprint: fingerprint, now: now),
           case .success(let card) = GroundingCardValidator.validate(
               cached,
               planItemIDs: planIDs,
               allowedNumbers: allowedNumbers,
               percentageAllowed: percentageAllowed,
               now: now
           ),
           card.kind != .safety {
            return card
        }
        guard let session = try? await client.startSession(),
              session.features.contains("daily_grounding"),
              let data = try? await client.fetchGroundingCard(state: GroundingState.payload(input))
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let response = try? decoder.decode(GroundingCardResponse.self, from: data),
              case .success(let card) = GroundingCardValidator.validate(
                  response,
                  planItemIDs: planIDs,
                  allowedNumbers: allowedNumbers,
                  percentageAllowed: percentageAllowed,
                  now: now
              ),
              card.kind != .safety
        else { return nil }

        GroundingCardCache.store(response, fingerprint: fingerprint, now: now)
        return card
    }
}
#endif
