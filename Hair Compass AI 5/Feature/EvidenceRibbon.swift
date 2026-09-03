//
//  EvidenceRibbon.swift
//  Hair Compass AI 5
//
//  Four quiet lines of supporting evidence — this week, the last thirty days, the next photo,
//  the next review. Numbers here are subordinate to the decision above them; none is a score.
//

import SwiftUI

/// The ribbon's copy, pure functions of the record so they are testable without a view.
/// G2-R8 (owner QA, 2026-09-04): `monthLine` never shows a percentage — not even "0%" — when
/// nothing has settled yet (`scored == 0`), because an open-only window is not a rhythm to grade.
enum EvidenceRibbonCopy {
    static func weekLine(_ weekSummary: PlanAdherence.Consistency?) -> String {
        weekSummary.map { "\($0.completed) of \($0.planned) planned actions" } ?? "No planned actions"
    }

    static func monthLine(_ consistency30: PlanAdherence.Consistency?) -> String {
        guard let consistency30 else { return "Not enough planned actions yet" }
        guard consistency30.scored > 0 else { return "Not enough due actions yet" }
        return "\(consistency30.percent)% · \(consistency30.completed) of \(consistency30.planned)"
    }

    static func photoLine(_ photo: PhotoCadence.Status) -> String {
        switch photo {
        case .noBaseline: return "Baseline pending"
        case .due: return "Due now"
        case .upcoming(let days): return days == 1 ? "Tomorrow" : "In \(days) days"
        }
    }

    static func reviewLine(_ phase: EvidencePhase?) -> String {
        guard let phase else { return "—" }
        switch phase.daysToReview {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(phase.daysToReview) days"
        }
    }
}

struct EvidenceRibbon: View {
    let weekSummary: PlanAdherence.Consistency?
    let consistency30: PlanAdherence.Consistency?
    let photo: PhotoCadence.Status
    let phase: EvidencePhase?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Your evidence")
            VStack(spacing: 0) {
                row("This week", EvidenceRibbonCopy.weekLine(weekSummary))
                Divider().overlay(Clinical.hairline)
                row("Last 30 days", EvidenceRibbonCopy.monthLine(consistency30))
                Divider().overlay(Clinical.hairline)
                row("Next photo", EvidenceRibbonCopy.photoLine(photo))
                Divider().overlay(Clinical.hairline)
                row("Next review", EvidenceRibbonCopy.reviewLine(phase))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evidenceRibbon")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Clinical.caption(12.5))
                .foregroundStyle(Clinical.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Clinical.body(13, weight: .medium))
                .foregroundStyle(Clinical.ink)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
