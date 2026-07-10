import Foundation

/// The end-of-onboarding "what tracking gets you" model. Deliberately honest:
/// tracking does not grow hair — consistency with an evidence-based plan does, and
/// tracking is how you keep consistency and see whether the plan works. The only
/// quantitative curve shown is the published male-AGA combination-therapy average;
/// every other profile gets qualitative milestones.
struct ProjectionModel {
    struct Milestone: Equatable {
        let week: Int
        let label: String
    }
    struct CurvePoint: Equatable {
        let week: Int
        let hairsPerCm2: Double  // delta vs baseline
    }
    /// A single week's reading on the universal "signal clarity" chart — never hair count.
    /// `withTracking` and `without` are both illustrative 0…1 values, shown for every
    /// condition×sex combination (unlike `evidenceCurve`, which only exists for male AGA).
    struct DifferencePoint: Equatable {
        let week: Int
        let withTracking: Double
        let without: Double
    }

    let headline: String
    let milestones: [Milestone]
    /// Non-nil only when a published average exists for this profile (male androgenetic).
    let evidenceCurve: [CurvePoint]?
    /// Always populated — the honest, universal "tracking vs guessing" illustration.
    let differenceCurve: [DifferencePoint]
    let citation: String
    let disclaimer: String

    static let disclaimerText = "Illustrative — published clinical averages, not a prediction of your results. Individual results vary. Tracking itself doesn't grow hair; it helps you stay consistent and see what works."

    static func make(condition: HairCondition, sex: BiologicalSex) -> ProjectionModel {
        let base: [Milestone] = [
            .init(week: 0, label: "Baseline set — photos, shedding, scalp"),
            .init(week: 6, label: "Where most people quit — reminders keep you going"),
            .init(week: 12, label: "First trend signal is usually readable"),
            .init(week: 24, label: "Published studies measure response here"),
        ]
        let differenceCurve = makeDifferenceCurve()
        switch (condition, sex) {
        case (.androgenetic, .male):
            // Smooth ease-in toward the published 24-week average.
            let target = 29.7
            let curve = [0, 4, 8, 12, 16, 20, 24].map { week in
                CurvePoint(week: week, hairsPerCm2: target * easeIn(Double(week) / 24))
            }
            return .init(
                headline: "Consistency is measurable",
                milestones: base,
                evidenceCurve: curve,
                differenceCurve: differenceCurve,
                citation: "Combination therapy averaged +29.7 hairs/cm² at 24 weeks in men (network meta-analysis; see a clinician about what fits you).",
                disclaimer: disclaimerText
            )
        case (.telogenEffluvium, _):
            return .init(
                headline: "Shedding after a trigger usually recovers",
                milestones: [
                    .init(week: 0, label: "Baseline set — daily shed level"),
                    .init(week: 8, label: "Trigger window — shedding often peaks 2–3 months after"),
                    .init(week: 12, label: "Recovery typically begins once the trigger passes"),
                    .init(week: 24, label: "Your chart shows the full arc"),
                ],
                evidenceCurve: nil,
                differenceCurve: differenceCurve,
                citation: "Telogen effluvium typically follows a trigger by 2–3 months and recovers over the following months.",
                disclaimer: disclaimerText
            )
        default:
            return .init(
                headline: "Seeing clearly beats guessing",
                milestones: base,
                evidenceCurve: nil,
                differenceCurve: differenceCurve,
                citation: "Evidence-based treatments take 3–6 months to show measurable change — objective tracking is how you know.",
                disclaimer: disclaimerText
            )
        }
    }

    private static func easeIn(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return c * c * (3 - 2 * c)  // smoothstep
    }

    /// The universal, explicitly-illustrative "tracking vs guessing" curve. `withTracking` rises
    /// smoothstep 0→1 across 24 weeks (how clearly a plan's effect reads once you're logging
    /// consistently); `without` stays low, flat, and slightly noisy (~0.09–0.15) — never negative,
    /// never a claim about hair count. Same 7 weeks as `evidenceCurve` so the two charts read as
    /// one family.
    private static func makeDifferenceCurve() -> [DifferencePoint] {
        [0, 4, 8, 12, 16, 20, 24].map { week in
            let withTracking = easeIn(Double(week) / 24)
            let without = min(max(0.12 + 0.03 * sin(Double(week)), 0), 0.15)
            return DifferencePoint(week: week, withTracking: withTracking, without: without)
        }
    }
}
