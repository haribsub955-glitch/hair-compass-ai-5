//
//  StarterPlanSnapshot.swift
//  Hair Compass AI 5
//
//  The two places the starting plan is shown build their snapshot here, so they cannot drift:
//  the onboarding finale from the freshly filled profile (`fresh`), and the Plan tab from the
//  live record (`make`). `StarterPlanDismissals` is the codec for the one piece of stored state.
//

import Foundation

extension StarterPlan.Snapshot {

    /// The finale's view of the record: profile answers, nothing recorded yet. `loggedToday` is
    /// true because `OnboardingFlow.finish()` seeds today's entry the moment the finale closes.
    static func fresh(profile: Profile) -> StarterPlan.Snapshot {
        StarterPlan.Snapshot(
            condition: profile.condition, sex: profile.sex, pregnancy: profile.pregnancyStatus,
            labTests: [], treatmentClasses: [],
            hasAnyTreatment: false, hasAnyLab: false, hasBaselinePhoto: false,
            procedureTypes: [], remindersEnabled: false, loggedToday: true, dismissed: []
        )
    }

    /// The Plan tab's view of the record, derived on every body evaluation.
    static func make(
        profile: Profile,
        labs: [LabResult],
        treatments: [Treatment],
        photos: [PhotoRecord],
        procedures: [ProcedureAppointment],
        entries: [DailyEntry],
        remindersEnabled: Bool,
        dismissed: Set<String>,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> StarterPlan.Snapshot {
        StarterPlan.Snapshot(
            condition: profile.condition, sex: profile.sex, pregnancy: profile.pregnancyStatus,
            labTests: Set(labs.map(\.test)),
            treatmentClasses: Set(treatments.map(\.treatmentClass)),
            hasAnyTreatment: !treatments.isEmpty,
            hasAnyLab: !labs.isEmpty,
            hasBaselinePhoto: !photos.isEmpty,
            procedureTypes: Set(procedures.map(\.type)),
            remindersEnabled: remindersEnabled,
            loggedToday: entries.contains { calendar.isDate($0.date, inSameDayAs: today) },
            dismissed: dismissed
        )
    }
}

/// "Not for me" is the only stored state of the starting plan: a JSON array of item ids in
/// `UserDefaults`, read and written through `@AppStorage(StarterPlanDismissals.key)`.
enum StarterPlanDismissals {
    static let key = "starterPlan.dismissed"

    static func decode(_ json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    static func encode(_ ids: Set<String>) -> String {
        let data = (try? JSONEncoder().encode(ids.sorted())) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
