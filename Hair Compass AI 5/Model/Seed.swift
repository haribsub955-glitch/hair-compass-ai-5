import Foundation
import SwiftData

enum Seed {
    /// First-run: create an empty, un-onboarded profile so the app has a subject.
    static func bootstrapIfNeeded(context: ModelContext, profiles: [Profile]) {
        guard profiles.isEmpty else { return }
        context.insert(Profile())
    }

    /// Debug-only demo dataset (gated by the HC_SEED_DEMO launch argument): a completed
    /// profile plus ~120 days of entries and adherence so charts and gates are populated.
    static func demo(context: ModelContext, profiles: [Profile], entries: [DailyEntry]) {
        guard entries.isEmpty else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let span = 120

        if let existing = profiles.first {
            existing.name = "Demo"
            existing.sex = .male
            existing.ageBand = "26–35"
            existing.condition = .androgenetic
            existing.familyHistory = .oneParent
            existing.baselineStage = "Norwood III"
            existing.hasOnboarded = true
            existing.usesHeat = true
        } else {
            context.insert(Profile(
                name: "Demo", sex: .male, ageBand: "26–35",
                condition: .androgenetic, familyHistory: .oneParent,
                baselineStage: "Norwood III", hasOnboarded: true,
                usesHeat: true
            ))
        }

        // Treatment started ~20 weeks ago so the 24-week gate is nearly (not yet) reached.
        let start = calendar.date(byAdding: .day, value: -140, to: today) ?? today
        let minox = Treatment(
            name: "Minoxidil 5%", treatmentClass: .minoxidil, dose: "1 mL",
            scheduleTimes: "08:00,21:00", startDate: start, isActive: true,
            refillBy: calendar.date(byAdding: .day, value: 6, to: today)   // inside the urgent band
        )
        let fin = Treatment(
            name: "Finasteride 1mg", treatmentClass: .finasteride, dose: "1 mg",
            scheduleTimes: "21:00", startDate: start, isActive: true
        )
        context.insert(minox)
        context.insert(fin)

        // Tolerability history: a mild transient shedding flare early on, and a moderate
        // irritation more recently — enough for chips and the detail list, no severe banner.
        context.insert(SideEffectLog(
            treatment: minox, type: .shedding, severity: 1,
            date: calendar.date(byAdding: .day, value: -110, to: today) ?? today,
            note: "Week 3–4 flare, settled on its own"
        ))
        context.insert(SideEffectLog(
            treatment: minox, type: .scalpIrritation, severity: 2,
            date: calendar.date(byAdding: .day, value: -9, to: today) ?? today,
            note: "Stinging after the evening application"
        ))

        for offset in stride(from: span, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if offset % 4 == 1 { continue } // realistic gaps

            let progress = Double(span - offset) / Double(span) // 0 → 1
            let noise = Double((offset * 7) % 9) - 4

            func clampBand(_ v: Double) -> Int { min(3, max(0, Int(v.rounded()))) }
            let entry = DailyEntry(
                date: day,
                shed: ShedLevel(rawValue: clampBand(2.4 - progress * 1.6 + noise * 0.15)) ?? .normal,
                flaking: clampBand(1.6 - progress * 1.0 + noise * 0.1),
                erythema: clampBand(1.3 - progress * 0.9),
                itch: clampBand(1.4 - progress * 0.9 + noise * 0.1),
                sleepQuality: min(5, max(1, Int((3.2 + progress * 1.2 + noise * 0.1).rounded()))),
                stress: min(5, max(1, Int((3.6 - progress * 1.1).rounded()))),
                cigarettes: 0,
                alcoholDrinks: offset % 6 == 0 ? 2 : 0,
                oiliness: clampBand(1.4 - progress * 0.6),
                note: ""
            )
            context.insert(entry)

            // A weekly HealthKit-style snapshot so Trends/AI have auto data to work with.
            if offset % 7 == 0 {
                context.insert(HealthSnapshot(
                    date: day,
                    sleepHours: 6.4 + progress * 1.0 + noise * 0.05,
                    hrvSDNN: 42 + progress * 12 + noise,
                    restingHR: 64 - progress * 4,
                    bodyMassKg: 78 - progress * 1.5,
                    bmi: 24.1 - progress * 0.4,
                    dietaryProteinG: 90 + progress * 20
                ))
            }

            // Log doses with realistic ~85% adherence.
            if offset % 7 != 3 {
                for slot in minox.slots where !(offset % 5 == 2 && slot == "08:00") {
                    context.insert(TreatmentDose(treatment: minox, loggedAt: day, slot: slot))
                }
                for slot in fin.slots {
                    context.insert(TreatmentDose(treatment: fin, loggedAt: day, slot: slot))
                }
            }
        }

        context.insert(LabResult(test: .ferritin, value: 38, collectedAt: start, note: "Baseline"))
        context.insert(LabResult(test: .tsh, value: 2.1, collectedAt: start))
        context.insert(LabResult(test: .vitaminD, value: 24, collectedAt: start, note: "Flagged low"))

        // A one-off procedure ~7 weeks back — a periodic (non-daily) treatment, so it reads as a
        // point event on the journey timeline rather than a daily med.
        let prpDate = calendar.date(byAdding: .day, value: -50, to: today) ?? today
        context.insert(Treatment(
            name: "PRP session", treatmentClass: .prp, dose: "3 injections",
            scheduleTimes: "", startDate: prpDate, isActive: true
        ))

        // A dated shedding trigger ~10 weeks back, so the TE-lag readout has something to show.
        let triggerDate = calendar.date(byAdding: .day, value: -70, to: today) ?? today
        context.insert(TriggerEvent(type: .illness, date: triggerDate, note: "Flu, ran a fever for several days"))
    }
}
