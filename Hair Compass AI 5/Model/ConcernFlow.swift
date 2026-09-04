//
//  ConcernFlow.swift
//  Hair Compass AI 5
//
//  "I'm worried", as deterministic data. The flow asks no more than two things the record
//  cannot know, then separates observation, uncertainty, next step, and safety. Generative chat
//  is deliberately downstream of this response, never upstream of urgent-care copy.
//

import Foundation

enum ConcernKind: String, CaseIterable, Identifiable, Codable {
    case moreShedding, looksDifferent, sideEffect, scalpSymptom, doubt, keepChecking, somethingElse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moreShedding: return "More shedding"
        case .looksDifferent: return "My hair looks different"
        case .sideEffect: return "A possible side effect"
        case .scalpSymptom: return "A scalp symptom"
        case .doubt: return "Doubt about treatment"
        case .keepChecking: return "I keep checking"
        case .somethingElse: return "Something else"
        }
    }

    var symbol: String {
        switch self {
        case .moreShedding: return "wind"
        case .looksDifferent: return "eye"
        case .sideEffect: return "exclamationmark.circle"
        case .scalpSymptom: return "hand.raised"
        case .doubt: return "questionmark.circle"
        case .keepChecking: return "arrow.triangle.2.circlepath"
        case .somethingElse: return "ellipsis.bubble"
        }
    }
}

struct ConcernQuestion: Equatable {
    let prompt: String
    let options: [String]
}

/// A read-only snapshot assembled from Today's existing queries. The responder itself never
/// reaches into SwiftData, so its safety and wording are reproducible in tests.
struct ConcernRecord {
    struct TreatmentSummary: Equatable {
        let name: String
        let treatmentClass: TreatmentClass
        let weeks: Int
        let sideEffectCount: Int
    }

    var recentShed: [Int]
    var washDaysLast7: Int
    var sheddingAboveUsual: Bool
    var scalpAverage: Double?
    var phase: EvidencePhase?
    var consistency30: PlanAdherence.Consistency?
    var photo: PhotoCadence.Status
    var flagIDs: [String]
    var treatments: [TreatmentSummary]
    var pregnancy: PregnancyStatus
    var keepCheckingCount14d: Int
}

enum ConcernAction: Equatable {
    case done
    case openPhotos
    case openPlan
    case logCheckIn
    case openTreatment(name: String)
}

struct ConcernResponse: Equatable {
    let headline: String
    let recordShows: String
    let cannotConclude: String
    let nextStep: String
    let seekHelp: String?
    let primary: ConcernAction
    let primaryLabel: String
    let closure: String
    let offersFewerChecks: Bool
}

enum ConcernResponder {
    static let urgentLine = "If you notice swelling of the face or lips, trouble breathing, chest pain or fainting, seek urgent care now."

    static func questions(for kind: ConcernKind, record: ConcernRecord) -> [ConcernQuestion] {
        switch kind {
        case .moreShedding, .somethingElse:
            return []
        case .looksDifferent:
            return [ConcernQuestion(
                prompt: "What looks different?",
                options: ["Thinner at the parting", "More scalp showing", "Texture or shine", "Not sure"]
            )]
        case .sideEffect:
            var questions: [ConcernQuestion] = []
            if record.treatments.count > 1 {
                questions.append(ConcernQuestion(
                    prompt: "Which treatment?",
                    options: record.treatments.map(\.name)
                ))
            }
            questions.append(ConcernQuestion(
                prompt: "How strong is it right now?",
                options: ["Mild", "Noticeable", "Severe"]
            ))
            return questions
        case .scalpSymptom:
            return [
                ConcernQuestion(
                    prompt: "Which is closest?",
                    options: ["Itch", "Flaking", "Redness", "Pain or tenderness", "Burning"]
                ),
                ConcernQuestion(
                    prompt: "How long has it been there?",
                    options: ["Today", "A few days", "Weeks"]
                )
            ]
        case .doubt:
            return [ConcernQuestion(
                prompt: "What is behind the doubt?",
                options: ["No visible change yet", "Shedding has not dropped", "A side effect", "The cost or effort"]
            )]
        case .keepChecking:
            return [ConcernQuestion(
                prompt: "How many times today, roughly?",
                options: ["Once or twice", "Several", "Lost count"]
            )]
        }
    }

    static func respond(kind: ConcernKind, answers: [String], record: ConcernRecord) -> ConcernResponse {
        switch kind {
        case .moreShedding: return moreShedding(record)
        case .looksDifferent: return looksDifferent(record)
        case .sideEffect: return sideEffect(answers: answers, record: record)
        case .scalpSymptom: return scalpSymptom(answers: answers, record: record)
        case .doubt:
            if answers.contains("A side effect") {
                return sideEffect(answers: ["Mild"], record: record)
            }
            return doubt(record)
        case .keepChecking: return keepChecking(record)
        case .somethingElse: return somethingElse()
        }
    }

    private static func reviewWord(_ record: ConcernRecord) -> String {
        record.phase.map { GroundingCards.daysWord($0.daysToReview) } ?? "at the next review"
    }

    private static func moreShedding(_ record: ConcernRecord) -> ConcernResponse {
        let shows: String
        if record.sheddingAboveUsual {
            shows = "You recorded higher shedding yesterday. The entries before it stayed within your usual range."
        } else if let last = record.recentShed.last, last >= 2 {
            let similar = record.recentShed.dropLast().filter { $0 >= 2 }.count
            shows = "Your latest entry records heavier shedding. Of the entries before it, \(similar) were at that level."
        } else {
            shows = "Your recent entries record shedding inside your usual range."
        }
        let washContext = " \(record.washDaysLast7) of the last seven logged days were wash days; shedding can look higher on those days."
        return ConcernResponse(
            headline: "Let's separate one moment from the pattern",
            recordShows: shows + washContext,
            cannotConclude: "One day, or one wash day, cannot show whether a treatment is working or whether hair loss has changed pace. That takes repeated entries over weeks.",
            nextStep: "Record the next two wash days and follow the plan already agreed with your clinician. Hair Compass watches for repetition.",
            seekHelp: record.flagIDs.contains("heavyShed")
                ? "Heavy shedding on most days for two weeks is worth a clinician's look; your record already shows that pattern."
                : nil,
            primary: .done,
            primaryLabel: "Close for today",
            closure: "You recorded what happened. No photo is needed today.",
            offersFewerChecks: false
        )
    }

    private static func looksDifferent(_ record: ConcernRecord) -> ConcernResponse {
        let shows: String
        let primary: ConcernAction
        let label: String
        switch record.photo {
        case .noBaseline:
            shows = "There is no baseline photo yet, so there is nothing comparable to set today against."
            primary = .openPhotos
            label = "Take a baseline photo"
        case .due(let overdue):
            shows = "Your last comparable photo is \(PhotoCadence.intervalDays + overdue) days old; the next one is due now."
            primary = .openPhotos
            label = "Take the next photo"
        case .upcoming(let days):
            shows = "Your last comparable photo is \(PhotoCadence.intervalDays - days) days old; the next is due \(GroundingCards.daysWord(days))."
            primary = .done
            label = "Wait for the photo date"
        }
        return ConcernResponse(
            headline: "A mirror cannot tell a real change from a different morning",
            recordShows: shows,
            cannotConclude: "Appearance changes from day to day with light, styling, wetness and angle. Only photos taken the same way, weeks apart, can show a direction.",
            nextStep: primary == .openPhotos
                ? "Use the same light, parting and distance as before, then let the pair speak."
                : "Nothing needs photographing today. The next photo date is the next honest look.",
            seekHelp: nil,
            primary: primary,
            primaryLabel: label,
            closure: "The record is doing the watching.",
            offersFewerChecks: false
        )
    }

    private static func sideEffect(answers: [String], record: ConcernRecord) -> ConcernResponse {
        let treatment: ConcernRecord.TreatmentSummary?
        if record.treatments.count > 1,
           let chosen = answers.first,
           let selected = record.treatments.first(where: { $0.name == chosen }) {
            treatment = selected
        } else {
            treatment = record.treatments.first
        }
        let severity = answers.last ?? "Mild"
        let name = treatment?.name ?? "this treatment"
        var shows = "\(name) has been in your plan for \(treatment?.weeks ?? 0) weeks."
        if let count = treatment?.sideEffectCount, count > 0 {
            shows += " \(count) side effect \(count == 1 ? "entry is" : "entries are") already on its record."
        }
        var help: String
        if severity == "Severe" {
            help = "A severe side effect is worth contacting your prescriber promptly. \(urgentLine)"
        } else {
            help = "If it worsens or persists, contact your prescriber. Do not change the dose on your own. \(urgentLine)"
        }
        if let treatment,
           let caution = PregnancyCaution.info(
               treatmentClass: treatment.treatmentClass,
               name: treatment.name,
               status: record.pregnancy
           ) {
            help += " \(caution.message)"
        }
        return ConcernResponse(
            headline: "Record it with a date",
            recordShows: shows,
            cannotConclude: "Hair Compass cannot tell whether a symptom is caused by a treatment. It can preserve the date and strength for a clinician to weigh.",
            nextStep: "Add it to \(name)'s side-effect record with today's date and how strong it feels.",
            seekHelp: help,
            primary: .openTreatment(name: name),
            primaryLabel: "Open \(name)'s record",
            closure: "Once it is recorded, nothing else is needed from you today.",
            offersFewerChecks: false
        )
    }

    private static func scalpSymptom(answers: [String], record: ConcernRecord) -> ConcernResponse {
        let symptom = answers.first ?? "Itch"
        let duration = answers.dropFirst().first ?? "Today"
        let shows = record.scalpAverage.map {
            "Your scalp score over recent entries averaged \(String(format: "%.1f", $0)) of 16, in the \(HairAnalytics.scalpBand(total: Int($0.rounded())).title.lowercased()) band."
        } ?? "Your recent entries carry no scalp score yet."
        let persistentPain = (symptom == "Pain or tenderness" || symptom == "Burning") && duration == "Weeks"
        return ConcernResponse(
            headline: "Give it a line in the record",
            recordShows: shows,
            cannotConclude: "A scalp symptom on its own does not identify a cause. The record can show whether it is new and whether it persists.",
            nextStep: "Add it to today's check-in so its date and pattern are available for review.",
            seekHelp: persistentPain
                ? "Persistent scalp pain, tenderness or burning is worth a prompt clinical review because some causes are best assessed early."
                : nil,
            primary: .logCheckIn,
            primaryLabel: "Log today's check-in",
            closure: "Logged is enough for today.",
            offersFewerChecks: false
        )
    }

    private static func doubt(_ record: ConcernRecord) -> ConcernResponse {
        var shows = record.treatments.first.map {
            "\($0.name) is at week \($0.weeks) of the 24-week review window."
        } ?? "There is no active treatment on the record."
        if let consistency = record.consistency30 {
            if consistency.scored > 0 {
                shows += " Over 30 days, \(consistency.completed) of \(consistency.scored) due actions were completed; \(consistency.planned) were planned through today."
            } else {
                shows += " The current consistency window has no due actions to score yet."
            }
        }
        return ConcernResponse(
            headline: "The record cannot answer this yet, by design",
            recordShows: shows,
            cannotConclude: "Before week 24 the record cannot say whether a treatment is working. Earlier changes are not a reliable verdict.",
            nextStep: "Keep the current record until the next review \(reviewWord(record)). The review reads consistency and comparable photos together.",
            seekHelp: nil,
            primary: .openPlan,
            primaryLabel: "See the evidence path",
            closure: "Doubt is reasonable this early. The review date holds the question for you.",
            offersFewerChecks: false
        )
    }

    private static func keepChecking(_ record: ConcernRecord) -> ConcernResponse {
        let photoLine: String
        switch record.photo {
        case .noBaseline:
            photoLine = "There is no baseline photo yet; a first one in good light is the only check the record can use."
        case .due:
            photoLine = "Your next comparable photo is due now; that is the useful check."
        case .upcoming(let days):
            photoLine = "Your next comparable photo is \(GroundingCards.daysWord(days)); checking earlier cannot show a change the record can use."
        }
        // The live answer is produced before this choice is appended to the log, so two prior
        // choices plus the current one are the third occurrence.
        let repeated = record.keepCheckingCount14d >= 2
        let next = repeated
            ? "You have chosen this a few times recently. Leave the shedding scene alone until the photo date and let the reminder do the remembering. If worry is getting in the way of daily life, support from a professional can help; that is a normal thing to ask for."
            : "Give yourself permission to stop checking until the photo date. The record is doing the watching."
        return ConcernResponse(
            headline: "The next useful look has a date",
            recordShows: photoLine,
            cannotConclude: "Repeated mirror checks cannot show a reliable change; they can only make an ordinary day feel longer.",
            nextStep: next,
            seekHelp: nil,
            primary: .done,
            primaryLabel: "Close for today",
            closure: "Nothing needs checking today.",
            offersFewerChecks: repeated
        )
    }

    private static func somethingElse() -> ConcernResponse {
        ConcernResponse(
            headline: "Ask in your own words",
            recordShows: "Wren can answer from the record in plain language.",
            cannotConclude: "It stays record-keeping: no diagnosis and no change to any treatment.",
            nextStep: "Ask Wren about it below.",
            seekHelp: nil,
            primary: .done,
            primaryLabel: "Close",
            closure: "You can come back to this any time.",
            offersFewerChecks: false
        )
    }
}

enum ConcernLog {
    static let key = "concern.log"
    private static let cap = 30

    private struct Entry: Codable {
        let kind: ConcernKind
        let day: Date
    }

    private static func entries(in defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func record(
        _ kind: ConcernKind,
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        var values = entries(in: defaults)
        values.append(Entry(kind: kind, day: calendar.startOfDay(for: now)))
        if values.count > cap { values.removeFirst(values.count - cap) }
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key)
        }
    }

    static func today(
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> ConcernKind? {
        let today = calendar.startOfDay(for: now)
        return entries(in: defaults).last { calendar.isDate($0.day, inSameDayAs: today) }?.kind
    }

    static func count(
        _ kind: ConcernKind,
        withinDays days: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Int {
        guard days > 0,
              let first = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
        else { return 0 }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return entries(in: defaults).filter { $0.kind == kind && $0.day >= first && $0.day < end }.count
    }
}
