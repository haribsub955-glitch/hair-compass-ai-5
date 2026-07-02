import Foundation
import SwiftData

// SwiftData is the single source of truth. Raw values are stored as primitives and
// bridged to the domain enums in Enums.swift via computed accessors, so a schema stays
// stable even if a case label changes.

@Model
final class Profile {
    var name: String = ""
    var sexRaw: String = BiologicalSex.male.rawValue
    var ageBand: String = ""
    var conditionRaw: String = HairCondition.unsure.rawValue
    var familyHistoryRaw: String = FamilyHistory.none.rawValue
    var baselineStage: String = ""
    var createdAt: Date = Date.now
    var hasOnboarded: Bool = false

    init(
        name: String = "",
        sex: BiologicalSex = .male,
        ageBand: String = "",
        condition: HairCondition = .unsure,
        familyHistory: FamilyHistory = .none,
        baselineStage: String = "",
        createdAt: Date = .now,
        hasOnboarded: Bool = false
    ) {
        self.name = name
        self.sexRaw = sex.rawValue
        self.ageBand = ageBand
        self.conditionRaw = condition.rawValue
        self.familyHistoryRaw = familyHistory.rawValue
        self.baselineStage = baselineStage
        self.createdAt = createdAt
        self.hasOnboarded = hasOnboarded
    }

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }
    var condition: HairCondition {
        get { HairCondition(rawValue: conditionRaw) ?? .unsure }
        set { conditionRaw = newValue.rawValue }
    }
    var familyHistory: FamilyHistory {
        get { FamilyHistory(rawValue: familyHistoryRaw) ?? .none }
        set { familyHistoryRaw = newValue.rawValue }
    }
}

@Model
final class DailyEntry {
    var date: Date = Date.now
    var shedRaw: Int = ShedLevel.normal.rawValue
    var flaking: Int = 0       // 0–3 self-report band (scaled to 0–10 in the SD total)
    var erythema: Int = 0      // 0–3
    var itch: Int = 0          // 0–3
    var sleepQuality: Int = 3  // 1–5
    var stress: Int = 3        // 1–5
    var cigarettes: Int = 0
    var note: String = ""

    init(
        date: Date = .now,
        shed: ShedLevel = .normal,
        flaking: Int = 0,
        erythema: Int = 0,
        itch: Int = 0,
        sleepQuality: Int = 3,
        stress: Int = 3,
        cigarettes: Int = 0,
        note: String = ""
    ) {
        self.date = date
        self.shedRaw = shed.rawValue
        self.flaking = flaking
        self.erythema = erythema
        self.itch = itch
        self.sleepQuality = sleepQuality
        self.stress = stress
        self.cigarettes = cigarettes
        self.note = note
    }

    var shed: ShedLevel {
        get { ShedLevel(rawValue: shedRaw) ?? .normal }
        set { shedRaw = newValue.rawValue }
    }

    /// 16-point scalp seborrheic-dermatitis total (Zhang 2023). Flaking band 0–3 maps to
    /// the validated 0–10 flaking item; erythema and itch are 0–3 each.
    var scalpTotal: Int { HairAnalytics.scalpTotal(flaking: flaking, erythema: erythema, itch: itch) }
    var scalpBand: SeverityBand { HairAnalytics.scalpBand(total: scalpTotal) }
}

@Model
final class Treatment {
    var name: String = ""
    var classRaw: String = TreatmentClass.other.rawValue
    var dose: String = ""
    var scheduleTimes: String = ""   // "08:00,21:00"
    var startDate: Date = Date.now
    var isActive: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \TreatmentDose.treatment)
    var doses: [TreatmentDose] = []

    init(
        name: String = "",
        treatmentClass: TreatmentClass = .other,
        dose: String = "",
        scheduleTimes: String = "",
        startDate: Date = .now,
        isActive: Bool = true
    ) {
        self.name = name
        self.classRaw = treatmentClass.rawValue
        self.dose = dose
        self.scheduleTimes = scheduleTimes
        self.startDate = startDate
        self.isActive = isActive
    }

    var treatmentClass: TreatmentClass {
        get { TreatmentClass(rawValue: classRaw) ?? .other }
        set { classRaw = newValue.rawValue }
    }

    var slots: [String] {
        let parsed = scheduleTimes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !parsed.isEmpty { return parsed }
        // Fall back to a sensible default cadence for daily classes.
        switch treatmentClass.defaultDailyCount {
        case 2: return ["08:00", "21:00"]
        case 1: return ["21:00"]
        default: return []
        }
    }
}

@Model
final class TreatmentDose {
    var treatment: Treatment?
    var loggedAt: Date = Date.now
    var slot: String = ""

    init(treatment: Treatment? = nil, loggedAt: Date = .now, slot: String = "") {
        self.treatment = treatment
        self.loggedAt = loggedAt
        self.slot = slot
    }
}

@Model
final class LabResult {
    var testRaw: String = LabTest.ferritin.rawValue
    var value: Double = 0
    var collectedAt: Date = Date.now
    var note: String = ""

    init(test: LabTest = .ferritin, value: Double = 0, collectedAt: Date = .now, note: String = "") {
        self.testRaw = test.rawValue
        self.value = value
        self.collectedAt = collectedAt
        self.note = note
    }

    var test: LabTest {
        get { LabTest(rawValue: testRaw) ?? .ferritin }
        set { testRaw = newValue.rawValue }
    }

    var flag: LabFlag { HairAnalytics.flag(for: value, test: test) }
}

@Model
final class PhotoRecord {
    var regionRaw: String = PhotoRegion.frontal.rawValue
    var imagePath: String = ""
    var createdAt: Date = Date.now
    var lighting: String = ""
    var distance: String = ""
    var parting: String = ""
    var isWet: Bool = false
    var note: String = ""

    init(
        region: PhotoRegion = .frontal,
        imagePath: String = "",
        createdAt: Date = .now,
        lighting: String = "",
        distance: String = "",
        parting: String = "",
        isWet: Bool = false,
        note: String = ""
    ) {
        self.regionRaw = region.rawValue
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.lighting = lighting
        self.distance = distance
        self.parting = parting
        self.isWet = isWet
        self.note = note
    }

    var region: PhotoRegion {
        get { PhotoRegion(rawValue: regionRaw) ?? .frontal }
        set { regionRaw = newValue.rawValue }
    }
}
