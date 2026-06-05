import Foundation

@MainActor
enum ClinicianExportService {
    static func buildText(
        profile: HairProfile,
        entries: [CheckInEntry],
        tasks: [RoutineTask],
        medications: [MedicationLog],
        procedures: [ProcedureEvent],
        labs: [LabResultEntry],
        triggers: [HairTriggerEvent],
        photoRecords: [PhotoRecord]
    ) -> String {
        let recentEntries = entries
            .sorted { $0.date > $1.date }
            .prefix(8)
            .map(entryLine)
            .joined(separator: "\n")

        let activeTasks = tasks
            .sorted { lhs, rhs in
                if lhs.weekday == rhs.weekday {
                    return lhs.timeLabel < rhs.timeLabel
                }
                return lhs.weekday < rhs.weekday
            }
            .prefix(10)
            .map { "- \($0.title) (\($0.category), \($0.timeLabel))" }
            .joined(separator: "\n")

        let activeMedications = medications
            .filter(\.isActive)
            .sorted { $0.startedAt > $1.startedAt }
            .map { "- \($0.name), \($0.form), \($0.dosage), \($0.schedule)" }
            .joined(separator: "\n")

        let recentProcedures = procedures
            .sorted { $0.performedAt > $1.performedAt }
            .prefix(8)
            .map { "- \($0.performedAt.formatted(date: .abbreviated, time: .omitted)): \($0.title) (\($0.category))" }
            .joined(separator: "\n")

        let recentLabs = labs
            .sorted { $0.collectedAt > $1.collectedAt }
            .prefix(10)
            .map { "- \($0.collectedAt.formatted(date: .abbreviated, time: .omitted)): \($0.testName) \($0.valueText) \($0.unit) [\($0.status)]" }
            .joined(separator: "\n")

        let recentTriggers = triggers
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(10)
            .map { trigger in
                if let endedAt = trigger.endedAt {
                    return "- \(trigger.title): \(trigger.startedAt.formatted(date: .abbreviated, time: .omitted)) to \(endedAt.formatted(date: .abbreviated, time: .omitted))"
                }
                return "- \(trigger.title): \(trigger.startedAt.formatted(date: .abbreviated, time: .omitted))"
            }
            .joined(separator: "\n")

        let recentPhotos = photoRecords
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { "- \($0.createdAt.formatted(date: .abbreviated, time: .omitted)): \($0.angle) • \($0.notes.isEmpty ? "No note" : $0.notes)" }
            .joined(separator: "\n")

        return """
        Hair Compass Clinician Summary
        Generated: \(Date.now.formatted(date: .abbreviated, time: .shortened))

        Profile
        - Name: \(profile.name)
        - Texture: \(profile.texture)
        - Primary goal: \(profile.primaryGoal)
        - Tracking focus: \(profile.hairLossFocus)
        - Pattern distribution: \(profile.patternDistribution.isEmpty ? "Not entered" : profile.patternDistribution)
        - Family history: \(profile.familyHistorySummary.isEmpty ? "Not entered" : profile.familyHistorySummary)
        - Scalp sensitivity: \(profile.scalpSensitivity)
        - Wash frequency: every \(profile.washFrequencyDays) day(s)
        - Notes: \(profile.notes.isEmpty ? "None" : profile.notes)

        Recent Check-Ins
        \(recentEntries.isEmpty ? "- No check-ins logged" : recentEntries)

        Current Routine
        \(activeTasks.isEmpty ? "- No routine tasks" : activeTasks)

        Active Medications
        \(activeMedications.isEmpty ? "- No active medications" : activeMedications)

        Procedure History
        \(recentProcedures.isEmpty ? "- No procedures logged" : recentProcedures)

        Trigger History
        \(recentTriggers.isEmpty ? "- No trigger history logged" : recentTriggers)

        Lab Results
        \(recentLabs.isEmpty ? "- No labs logged" : recentLabs)

        Photo Notes
        \(recentPhotos.isEmpty ? "- No photos logged" : recentPhotos)
        """
    }

    private static func entryLine(_ entry: CheckInEntry) -> String {
        var symptoms: [String] = []
        if entry.hasItch { symptoms.append("itch") }
        if entry.hasFlaking { symptoms.append("flaking") }
        if entry.hasScalpPain { symptoms.append("pain/burning") }
        if entry.hasPatchyHairLoss { symptoms.append("patchy loss") }
        if entry.hasTightStyleTension { symptoms.append("tight tension") }

        let symptomText = symptoms.isEmpty ? "no symptom flags" : symptoms.joined(separator: ", ")
        return "- \(entry.date.formatted(date: .abbreviated, time: .omitted)): scalp \(entry.scalpScore), hydration \(entry.hydrationScore), shedding \(entry.sheddingLevel), stress \(entry.stressLevel) • \(symptomText)"
    }
}
