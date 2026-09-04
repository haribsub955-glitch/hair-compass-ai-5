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

    // Hair-care practices — traction/heat/chemical is a genuine, preventable cause (STRONG for
    // traction alopecia). Captured once at baseline; editable.
    var wearsTightStyles: Bool = false
    var usesHeat: Bool = false
    var usesChemicalTreatments: Bool = false

    /// Pregnant / trying / breastfeeding, asked of women in onboarding so the plan can flag the
    /// medications that aren't recommended in or around pregnancy. Defaults to `.unspecified`
    /// (never asked / declined), which raises no caution — schema-safe as a stored String.
    var pregnancyStatusRaw: String = PregnancyStatus.unspecified.rawValue

    /// Optional, asked in onboarding, and it never leaves the device.
    ///
    /// Exact age matters here — several evidence tiers and treatment cautions turn on it, and
    /// `ageBand` ("25-34") is too coarse to gate on. But a birth date is a direct identifier, so
    /// only the *derived integer* is ever projected to the agent (`AgentProfile.derivedAge`).
    /// Optional with no default, which is what keeps lightweight migration safe for anyone who
    /// onboarded before this field existed.
    var birthDate: Date?

    init(
        name: String = "",
        sex: BiologicalSex = .male,
        ageBand: String = "",
        condition: HairCondition = .unsure,
        familyHistory: FamilyHistory = .none,
        baselineStage: String = "",
        createdAt: Date = .now,
        hasOnboarded: Bool = false,
        wearsTightStyles: Bool = false,
        usesHeat: Bool = false,
        usesChemicalTreatments: Bool = false,
        pregnancyStatus: PregnancyStatus = .unspecified,
        birthDate: Date? = nil
    ) {
        self.name = name
        self.sexRaw = sex.rawValue
        self.ageBand = ageBand
        self.conditionRaw = condition.rawValue
        self.familyHistoryRaw = familyHistory.rawValue
        self.baselineStage = baselineStage
        self.createdAt = createdAt
        self.hasOnboarded = hasOnboarded
        self.wearsTightStyles = wearsTightStyles
        self.usesHeat = usesHeat
        self.usesChemicalTreatments = usesChemicalTreatments
        self.pregnancyStatusRaw = pregnancyStatus.rawValue
        self.birthDate = birthDate
    }

    /// True if any mechanical/thermal/chemical stressor is in play — surfaces a traction note.
    var hasTractionRisk: Bool { wearsTightStyles || usesHeat || usesChemicalTreatments }

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
    var pregnancyStatus: PregnancyStatus {
        get { PregnancyStatus(rawValue: pregnancyStatusRaw) ?? .unspecified }
        set { pregnancyStatusRaw = newValue.rawValue }
    }
}

/// Signals that can be explicitly answered in a daily check-in. Values still live in the
/// primitive SwiftData columns below; this set records whether each value was actually supplied.
/// That distinction keeps an untouched default from becoming a false "normal" observation.
enum DailySignal: String, CaseIterable, Codable, Hashable {
    case shedding, washDay, flaking, erythema, itch, oiliness
    case sleepQuality, stress, cigarettes, alcohol
}

@Model
final class DailyEntry {
    var date: Date = Date.now
    var shedRaw: Int = ShedLevel.normal.rawValue
    var flaking: Int = 0       // 0–3 self-report band (scaled to 0–10 in the SD total)
    var erythema: Int = 0      // 0–3
    var itch: Int = 0          // 0–3
    var sleepQuality: Int = 3  // 1–5 (subjective; HealthKit fills objective hours separately)
    var stress: Int = 3        // 1–5
    var cigarettes: Int = 0
    var alcoholDrinks: Int = 0 // WEAK tier — possible modest association, not proven
    var oiliness: Int = 0      // 0–3 self-report; an observation, not a risk driver (WEAK)
    var note: String = ""
    /// Comma-separated `DailySignal` raw values. `nil` means a legacy record created before
    /// answer-presence was tracked; those rows retain their historical all-fields interpretation.
    /// An empty string is an explicitly saved entry with no answered trend signal (for example,
    /// a note-only entry). Optional storage keeps the schema addition lightweight-migration safe.
    var recordedSignalsRaw: String?
    /// Self-reported: hair was washed today. Shed hair is far more visible on wash days, so
    /// this is the confound that lets Trends/ProgressReport/Compare tell an honest "wash days
    /// show more shed" story instead of reading a heavier wash day as a real change. Schema-
    /// safe default `false` — older rows decode as "not a wash day" rather than crashing.
    var washedHair: Bool = false

    init(
        date: Date = .now,
        shed: ShedLevel = .normal,
        flaking: Int = 0,
        erythema: Int = 0,
        itch: Int = 0,
        sleepQuality: Int = 3,
        stress: Int = 3,
        cigarettes: Int = 0,
        alcoholDrinks: Int = 0,
        oiliness: Int = 0,
        note: String = "",
        washedHair: Bool = false,
        recordedSignals: Set<DailySignal> = Set(DailySignal.allCases)
    ) {
        self.date = date
        self.shedRaw = shed.rawValue
        self.flaking = flaking
        self.erythema = erythema
        self.itch = itch
        self.sleepQuality = sleepQuality
        self.stress = stress
        self.cigarettes = cigarettes
        self.alcoholDrinks = alcoholDrinks
        self.oiliness = oiliness
        self.note = note
        self.washedHair = washedHair
        self.recordedSignalsRaw = Self.encode(recordedSignals)
    }

    var shed: ShedLevel {
        get { ShedLevel(rawValue: shedRaw) ?? .normal }
        set { shedRaw = newValue.rawValue }
    }

    /// Legacy rows (`nil`) are intentionally treated as answered so an app update does not erase
    /// an existing user's history. Every newly saved check-in writes an explicit set.
    var recordedSignals: Set<DailySignal> {
        get {
            guard let recordedSignalsRaw else { return Set(DailySignal.allCases) }
            return Set(recordedSignalsRaw.split(separator: ",").compactMap {
                DailySignal(rawValue: String($0))
            })
        }
        set { recordedSignalsRaw = Self.encode(newValue) }
    }

    func hasRecorded(_ signal: DailySignal) -> Bool { recordedSignals.contains(signal) }

    var hasCompleteScalpRecording: Bool {
        hasRecorded(.flaking) && hasRecorded(.erythema) && hasRecorded(.itch)
    }

    private static func encode(_ signals: Set<DailySignal>) -> String {
        signals.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Self-reported 16-point scalp symptom total, adapted from Zhang 2023. Flaking band 0–3
    /// is mapped to 0–10; this is not the clinician-administered validated instrument itself.
    var scalpTotal: Int { HairAnalytics.scalpTotal(flaking: flaking, erythema: erythema, itch: itch) }
    var scalpBand: SeverityBand { HairAnalytics.scalpBand(total: scalpTotal) }
}

@Model
final class Treatment {
    var name: String = ""
    var classRaw: String = TreatmentClass.other.rawValue
    var dose: String = ""
    var scheduleTimes: String = ""   // "08:00,21:00"
    /// Which weekdays a care product is used (Calendar weekday numbers 1=Sun…7=Sat),
    /// comma-separated; empty = every day. Meaningful for periodic care products (shampoo/oil) so
    /// they only appear in the day's routine on their days; medications keep it empty and run
    /// daily. Schema-safe (String default).
    var scheduledWeekdaysRaw: String = ""
    var startDate: Date = Date.now
    var isActive: Bool = true
    /// When the current supply is expected to run out. Optional — unset means "not tracked".
    /// Running low is the most common reason a regimen lapses, so it gets a first-class date.
    var refillBy: Date? = nil
    /// Set the moment `isActive` flips to false (and cleared on reactivation). Stopping a
    /// treatment — often because of a side effect — is one of the most informative dated events
    /// in the whole record: shedding changes can lag a stop by 2–3 months, the same delay the
    /// app teaches for triggers. Schema-safe optional, so existing rows just read nil.
    var endDate: Date? = nil

    /// A custom item can carry a photo of its ingredient label (path on disk via PhotoStore)
    /// and a short AI-produced summary of what it is. Empty means "not provided".
    var ingredientPhotoPath: String = ""
    var aiIngredientSummary: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TreatmentDose.treatment)
    var doses: [TreatmentDose] = []

    @Relationship(deleteRule: .cascade, inverse: \SideEffectLog.treatment)
    var sideEffects: [SideEffectLog] = []

    @Relationship(deleteRule: .cascade, inverse: \MissedDoseRecord.treatment)
    var missedDoses: [MissedDoseRecord] = []

    init(
        name: String = "",
        treatmentClass: TreatmentClass = .other,
        dose: String = "",
        scheduleTimes: String = "",
        scheduledWeekdays: Set<Int> = [],
        startDate: Date = .now,
        isActive: Bool = true,
        refillBy: Date? = nil,
        ingredientPhotoPath: String = "",
        aiIngredientSummary: String = ""
    ) {
        self.name = name
        self.classRaw = treatmentClass.rawValue
        self.dose = dose
        self.scheduleTimes = scheduleTimes
        self.scheduledWeekdaysRaw = Self.encodeWeekdays(scheduledWeekdays)
        self.startDate = startDate
        self.isActive = isActive
        self.refillBy = refillBy
        self.ingredientPhotoPath = ingredientPhotoPath
        self.aiIngredientSummary = aiIngredientSummary
    }

    var treatmentClass: TreatmentClass {
        get { TreatmentClass(rawValue: classRaw) ?? .other }
        set { classRaw = newValue.rawValue }
    }

    /// The weekdays this item is scheduled for (Calendar weekday numbers 1=Sun…7=Sat).
    /// Empty = every day.
    var scheduledWeekdays: Set<Int> {
        get { Set(scheduledWeekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { scheduledWeekdaysRaw = Self.encodeWeekdays(newValue) }
    }

    static func encodeWeekdays(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }

    /// True when this item is due on `now`'s weekday — today's weekday is in the schedule, or the
    /// schedule is empty (every day). Medications (empty schedule) are always due; a shampoo set
    /// to Mon/Thu is due only on those days.
    func isDueToday(now: Date = .now, calendar: Calendar = .current) -> Bool {
        let days = scheduledWeekdays
        guard !days.isEmpty else { return true }
        return days.contains(calendar.component(.weekday, from: now))
    }

    /// Whole days from today until `refillBy` (start-of-day to start-of-day). nil when unset;
    /// 0 = due today; negative = overdue.
    var daysUntilRefill: Int? { HairAnalytics.daysUntilRefill(refillBy) }

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

/// One clock-format boundary for treatment schedules. SwiftUI edits `Date` values, while the
/// model, reminders, widget, and adherence engine continue to share stable `HH:mm` strings.
enum TreatmentSchedule {
    static func encode(_ dates: [Date], calendar: Calendar = .current) -> String {
        let minutes = Set(dates.map { date in
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        })
        return minutes.sorted().map { value in
            String(format: "%02d:%02d", value / 60, value % 60)
        }.joined(separator: ",")
    }

    static func dates(from raw: String, anchor: Date = .now, calendar: Calendar = .current) -> [Date] {
        let anchorDay = calendar.dateComponents([.year, .month, .day], from: anchor)
        return raw.split(separator: ",").compactMap { token in
            let pieces = token.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
                  (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
            var components = anchorDay
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components)
        }.sorted()
    }
}

/// A scheduled (or already-done) in-clinic procedure — PRP, microneedling, a transplant, LLLT.
/// Unlike a daily `Treatment`, a procedure is a dated event the user books, gets reminded about,
/// and marks done (from its detail view or the daily check-in).
@Model
final class ProcedureAppointment {
    var typeRaw: String = ProcedureType.prp.rawValue
    var date: Date = Date.now
    var location: String = ""
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var note: String = ""
    var createdAt: Date = Date.now
    var agendaMainConcern: String = ""
    var agendaChangedWhen: String = ""
    var agendaTreatmentsToReview: String = ""
    var agendaSafetyConcerns: String = ""
    /// Newline-delimited editable questions. Plain text keeps the migration additive and makes
    /// the user's agenda portable in backups and reports without introducing opaque blobs.
    var agendaQuestionsRaw: String = ""

    init(
        type: ProcedureType = .prp,
        date: Date = .now,
        location: String = "",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        note: String = "",
        createdAt: Date = .now,
        agendaMainConcern: String = "",
        agendaChangedWhen: String = "",
        agendaTreatmentsToReview: String = "",
        agendaSafetyConcerns: String = "",
        agendaQuestions: [String] = []
    ) {
        self.typeRaw = type.rawValue
        self.date = date
        self.location = location
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.note = note
        self.createdAt = createdAt
        self.agendaMainConcern = agendaMainConcern
        self.agendaChangedWhen = agendaChangedWhen
        self.agendaTreatmentsToReview = agendaTreatmentsToReview
        self.agendaSafetyConcerns = agendaSafetyConcerns
        self.agendaQuestionsRaw = agendaQuestions.joined(separator: "\n")
    }

    var type: ProcedureType {
        get { ProcedureType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// True for a future, not-yet-done appointment (the ones worth reminding about).
    var isUpcoming: Bool { !isCompleted && date >= Calendar.current.startOfDay(for: .now) }

    var agendaQuestions: [String] {
        get { agendaQuestionsRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
        set { agendaQuestionsRaw = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n") }
    }

    var hasVisitAgenda: Bool {
        !agendaMainConcern.isEmpty || !agendaChangedWhen.isEmpty || !agendaTreatmentsToReview.isEmpty
            || !agendaSafetyConcerns.isEmpty || !agendaQuestions.isEmpty
    }
}

/// A periodic (≈monthly) answer to the between-visit questions a dermatologist asks — new
/// regrowth, density/shedding/hairline trend, scalp symptoms, overall. Slow-moving, self-
/// reported *context* (never measurement or diagnosis); surfaced in the clinician export + AI.
@Model
final class ProgressCheckIn {
    var date: Date = Date.now
    var regrowthRaw: Int = RegrowthLevel.none.rawValue
    var densityRaw: Int = ProgressTrend.same.rawValue
    var sheddingRaw: Int = ProgressTrend.same.rawValue
    var hairlineRaw: Int = ProgressTrend.same.rawValue
    var overallRaw: Int = ProgressTrend.same.rawValue
    /// Alopecia areata-only: are patches new/larger, unchanged, or fewer/smaller since last
    /// time? `nil` means "not asked" (every non-AA check-in, and every check-in recorded before
    /// this field existed) — distinct from `.same`, which is an actual answer.
    var patchTrendRaw: Int?
    var scalpPain: Bool = false          // a genuine red flag — persistent pain can mean scarring alopecia
    var scalpPainNote: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    /// Optional, unscored emotional context. Zero means the question was not answered.
    var hairFeelingRaw: Int = HairFeeling.unspecified.rawValue
    var hairFeelingNote: String = ""

    init(
        date: Date = .now,
        regrowth: RegrowthLevel = .none,
        density: ProgressTrend = .same,
        shedding: ProgressTrend = .same,
        hairline: ProgressTrend = .same,
        overall: ProgressTrend = .same,
        patchTrend: ProgressTrend? = nil,
        scalpPain: Bool = false,
        scalpPainNote: String = "",
        note: String = "",
        createdAt: Date = .now,
        hairFeeling: HairFeeling = .unspecified,
        hairFeelingNote: String = ""
    ) {
        self.date = date
        self.regrowthRaw = regrowth.rawValue
        self.densityRaw = density.rawValue
        self.sheddingRaw = shedding.rawValue
        self.hairlineRaw = hairline.rawValue
        self.overallRaw = overall.rawValue
        self.patchTrendRaw = patchTrend?.rawValue
        self.scalpPain = scalpPain
        self.scalpPainNote = scalpPainNote
        self.note = note
        self.createdAt = createdAt
        self.hairFeelingRaw = hairFeeling.rawValue
        self.hairFeelingNote = hairFeelingNote
    }

    var regrowth: RegrowthLevel {
        get { RegrowthLevel(rawValue: regrowthRaw) ?? .none }
        set { regrowthRaw = newValue.rawValue }
    }
    var hairFeeling: HairFeeling {
        get { HairFeeling(rawValue: hairFeelingRaw) ?? .unspecified }
        set { hairFeelingRaw = newValue.rawValue }
    }
    var density: ProgressTrend {
        get { ProgressTrend(rawValue: densityRaw) ?? .same }
        set { densityRaw = newValue.rawValue }
    }
    var shedding: ProgressTrend {
        get { ProgressTrend(rawValue: sheddingRaw) ?? .same }
        set { sheddingRaw = newValue.rawValue }
    }
    var hairline: ProgressTrend {
        get { ProgressTrend(rawValue: hairlineRaw) ?? .same }
        set { hairlineRaw = newValue.rawValue }
    }
    var overall: ProgressTrend {
        get { ProgressTrend(rawValue: overallRaw) ?? .same }
        set { overallRaw = newValue.rawValue }
    }
    /// `nil` when never asked (non-AA profiles, or check-ins recorded before this field
    /// existed) — distinct from an explicit `.same` answer.
    var patchTrend: ProgressTrend? {
        get { patchTrendRaw.flatMap(ProgressTrend.init(rawValue:)) }
        set { patchTrendRaw = newValue?.rawValue }
    }

    /// Plain, clinician-readable lines for the export. The scalp-pain line is a safety flag,
    /// not a diagnosis.
    func clinicianSummary() -> [String] {
        var lines: [String] = [
            "New regrowth (baby hairs): \(regrowth.title)",
            "Density: \(density.clinicianPhrase(for: .density))",
            "Shedding: \(shedding.clinicianPhrase(for: .shedding))",
            "Hairline/part: \(hairline.clinicianPhrase(for: .hairline))",
            "Overall: \(overall.clinicianPhrase(for: .overall))"
        ]
        if let patchTrend {
            lines.append("Patches: \(patchTrend.clinicianPhrase(for: .patches))")
        }
        if scalpPain {
            lines.append("⚠ Reports scalp pain/tenderness\(scalpPainNote.isEmpty ? "" : " — \(scalpPainNote)"). Worth prompt dermatology review.")
        }
        if !note.isEmpty { lines.append("Note: \(note)") }
        if hairFeeling != .unspecified {
            lines.append("Feeling about hair: \(hairFeeling.title)\(hairFeelingNote.isEmpty ? "" : " — \(hairFeelingNote)")")
        }
        return lines
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

enum MissedDoseReason: String, CaseIterable, Identifiable, Sendable {
    case forgot, supply, irritation, travel, clinicianDirectedPause
    var id: String { rawValue }
    var title: String {
        switch self {
        case .forgot: return "Forgot"
        case .supply: return "Ran out / supply"
        case .irritation: return "Discomfort or irritation"
        case .travel: return "Travel or routine change"
        case .clinicianDirectedPause: return "Clinician-directed pause"
        }
    }
    var summaryLabel: String {
        switch self {
        case .forgot: return "forgot"
        case .supply: return "supply"
        case .irritation: return "irritation"
        case .travel: return "travel"
        case .clinicianDirectedPause: return "clinician-directed pause"
        }
    }
}

/// A scheduled application that did not happen. This is distinct from a completed dose and is
/// neutral record-keeping; in particular, clinician-directed pauses are never scored as failure.
@Model
final class MissedDoseRecord {
    var treatment: Treatment?
    var date: Date = Date.now
    var slot: String = ""
    var reasonRaw: String = MissedDoseReason.forgot.rawValue

    init(treatment: Treatment? = nil, date: Date = .now, slot: String = "", reason: MissedDoseReason = .forgot) {
        self.treatment = treatment
        self.date = date
        self.slot = slot
        self.reasonRaw = reason.rawValue
    }

    var reason: MissedDoseReason {
        get { MissedDoseReason(rawValue: reasonRaw) ?? .forgot }
        set { reasonRaw = newValue.rawValue }
    }
}

/// One dated tolerability observation for a treatment. Side effects are why people quit
/// finasteride/minoxidil or need their prescriber — a record, never medical advice.
@Model
final class SideEffectLog {
    var treatment: Treatment?
    var date: Date = Date.now
    var severity: Int = 1   // 1 mild · 2 moderate · 3 severe
    var typeRaw: String = SideEffectType.other.rawValue
    var note: String = ""

    init(
        treatment: Treatment? = nil,
        type: SideEffectType = .other,
        severity: Int = 1,
        date: Date = .now,
        note: String = ""
    ) {
        self.treatment = treatment
        self.typeRaw = type.rawValue
        self.severity = min(max(severity, 1), 3)
        self.date = date
        self.note = note
    }

    var type: SideEffectType {
        get { SideEffectType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }
}

@Model
final class LabResult {
    var testRaw: String = LabTest.ferritin.rawValue
    /// Always stored in `test.unit` (the canonical unit) — any alternate-unit entry (e.g.
    /// vitamin D in nmol/L) is converted at entry time in AddLabSheet, never at read time.
    var value: Double = 0
    var collectedAt: Date = Date.now
    var note: String = ""
    /// Optional "use the range printed on your report" override — a UK/EU lab's own printed
    /// interval, or a sex-specific ferritin range, takes precedence over the app's generic
    /// adult default whenever both are set with `refLow < refHigh`. Schema-safe: nil means
    /// "use the built-in default," matching every backup/restore made before this existed.
    var refLow: Double?
    var refHigh: Double?

    init(
        test: LabTest = .ferritin, value: Double = 0, collectedAt: Date = .now, note: String = "",
        refLow: Double? = nil, refHigh: Double? = nil
    ) {
        self.testRaw = test.rawValue
        self.value = value
        self.collectedAt = collectedAt
        self.note = note
        self.refLow = refLow
        self.refHigh = refHigh
    }

    var test: LabTest {
        get { LabTest(rawValue: testRaw) ?? .ferritin }
        set { testRaw = newValue.rawValue }
    }

    /// The range flags/gauges actually judge this result against — the user's own override
    /// when it's a valid interval, otherwise the built-in default.
    var effectiveRange: ClosedRange<Double> {
        if let refLow, let refHigh, refLow < refHigh { return refLow...refHigh }
        return test.referenceRange
    }

    /// Whether `effectiveRange` differs from the built-in default — drives the "range from
    /// your lab report" caption instead of a silent, unexplained band shift.
    var hasCustomRange: Bool {
        if let refLow, let refHigh, refLow < refHigh {
            return refLow != test.referenceRange.lowerBound || refHigh != test.referenceRange.upperBound
        }
        return false
    }

    var flag: LabFlag { HairAnalytics.flag(for: value, range: effectiveRange) }
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
    var patchSeriesLabel: String = ""
    /// User-observed milestone, dated to this photo; never inferred from image analysis.
    var babyHairsNoticed: Bool = false

    init(
        region: PhotoRegion = .frontal,
        imagePath: String = "",
        createdAt: Date = .now,
        lighting: String = "",
        distance: String = "",
        parting: String = "",
        isWet: Bool = false,
        note: String = "",
        patchSeriesLabel: String = "",
        babyHairsNoticed: Bool = false
    ) {
        self.regionRaw = region.rawValue
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.lighting = lighting
        self.distance = distance
        self.parting = parting
        self.isWet = isWet
        self.note = note
        self.patchSeriesLabel = patchSeriesLabel
        self.babyHairsNoticed = babyHairsNoticed
    }

    var region: PhotoRegion {
        get { PhotoRegion(rawValue: regionRaw) ?? .frontal }
        set { regionRaw = newValue.rawValue }
    }

    var normalizedPatchSeriesLabel: String {
        patchSeriesLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func belongsToSameSeries(as other: PhotoRecord) -> Bool {
        guard region == other.region else { return false }
        return region != .patch || normalizedPatchSeriesLabel == other.normalizedPatchSeriesLabel
    }
}

/// A daily cache of the evidence-defensible HealthKit metrics. Written by the sync service so
/// Trends, the widget, offline use, and the AI can read them without re-querying HealthKit.
/// All values are optional — "not available" is first-class, never a zero.
@Model
final class HealthSnapshot {
    var date: Date = Date.now
    var sleepHours: Double?
    var hrvSDNN: Double?
    var restingHR: Double?
    var bodyMassKg: Double?
    var bmi: Double?
    var dietaryProteinG: Double?
    var updatedAt: Date = Date.now

    init(
        date: Date = .now,
        sleepHours: Double? = nil,
        hrvSDNN: Double? = nil,
        restingHR: Double? = nil,
        bodyMassKg: Double? = nil,
        bmi: Double? = nil,
        dietaryProteinG: Double? = nil,
        updatedAt: Date = .now
    ) {
        self.date = date
        self.sleepHours = sleepHours
        self.hrvSDNN = hrvSDNN
        self.restingHR = restingHR
        self.bodyMassKg = bodyMassKg
        self.bmi = bmi
        self.dietaryProteinG = dietaryProteinG
        self.updatedAt = updatedAt
    }

    var hasAnyValue: Bool {
        [sleepHours, hrvSDNN, restingHR, bodyMassKg, bmi, dietaryProteinG].contains { $0 != nil }
    }
}

/// A dated telogen-effluvium trigger (crash diet, illness, major stress, childbirth, new med).
/// The ~2–3 month lag to shedding is what makes the date worth recording.
@Model
final class TriggerEvent {
    var typeRaw: String = TriggerType.other.rawValue
    var date: Date = Date.now
    var note: String = ""

    init(type: TriggerType = .other, date: Date = .now, note: String = "") {
        self.typeRaw = type.rawValue
        self.date = date
        self.note = note
    }

    var type: TriggerType {
        get { TriggerType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// Weeks elapsed since the trigger — used to show progress toward the ~8–12 week TE window.
    func weeksElapsed(now: Date = .now, calendar: Calendar = .current) -> Int {
        HairAnalytics.weeksElapsed(since: date, now: now, calendar: calendar)
    }
}
