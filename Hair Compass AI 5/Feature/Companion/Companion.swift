import Foundation

/// Asset-catalog names for Wren's gouache poses. One consistent painterly style; transparent
/// backgrounds so poses bleed like `brand-sprig`. See the plan's "Asset Generation" appendix
/// for the art brief. Kept beside the model (not in BrandArt) so the companion is one isolated unit.
enum CompanionArt {
    static let resting     = "wren-resting"
    static let greeting    = "wren-greeting"
    static let listening   = "wren-listening"
    static let thinking    = "wren-thinking"
    static let searching   = "wren-searching"
    static let celebrating = "wren-celebrate"
    static let avatar      = "wren-avatar"
}

/// The contexts Wren can appear in. Drives which pose renders and which line (if any) she says.
enum CompanionMoment: CaseIterable {
    case resting       // ambient / default presence
    case greeting      // onboarding welcome, chat empty state
    case listening     // chat: waiting for / reading the person
    case thinking      // chat: generating a reply
    case searching     // empty states (replaces a flat empty icon)
    case celebrating   // milestone / streak celebration
}

/// The three pieces of the app Wren teaches during the first week. These are navigation
/// destinations, not treatment recommendations: Wren asks the person to record what is already
/// true, then gives slow-moving hair data enough time to become useful.
enum CompanionGuideAction: String, CaseIterable {
    case checkIn
    case routine
    case baselinePhoto

    var title: String {
        switch self {
        case .checkIn: return "Check in once, then leave it"
        case .routine: return "Mirror your real routine"
        case .baselinePhoto: return "Make one honest baseline"
        }
    }

    var instruction: String {
        switch self {
        case .checkIn:
            return "A rough shedding and scalp check is enough. Consistent beats perfectly counted."
        case .routine:
            return "Add only care you already use. You never need to start something for the app."
        case .baselinePhoto:
            return "Use the guided angles once, then compare on schedule — not every anxious day."
        }
    }

    var buttonTitle: String {
        switch self {
        case .checkIn: return "Log today"
        case .routine: return "Open Plan"
        case .baselinePhoto: return "Take baseline"
        }
    }

    var symbol: String {
        switch self {
        case .checkIn: return "checkmark.circle"
        case .routine: return "checklist"
        case .baselinePhoto: return "camera.viewfinder"
        }
    }
}

struct CompanionGuideStep: Identifiable, Equatable {
    let action: CompanionGuideAction
    let isComplete: Bool

    var id: CompanionGuideAction { action }
}

/// A short-lived, deterministic guide for the first seven calendar days after the first entry.
/// It deliberately expires: Wren should become a quiet companion once the person knows the app,
/// not keep treating a returning user like a beginner. Completion comes from the record itself,
/// so there is no second checklist that can drift out of sync.
struct CompanionNewcomerGuide: Equatable {
    let dayNumber: Int
    let steps: [CompanionGuideStep]

    var invitation: String {
        "New here? I’ll keep your first week to three small steps."
    }

    var completedCount: Int { steps.filter(\.isComplete).count }
}

/// Wren — the name and personality of the AI companion (engine varies: cloud once consented,
/// on-device otherwise). This is the single home of the
/// companion's voice: a pure mapping, no SwiftUI, no state, fully unit-tested (mirrors how
/// `HairChatPrompt` centralizes the chat's scope and `HairInsightCalculator` centralizes stats).
///
/// Wren is *presentation*, never capability: the chat's model contract and guardrails live in
/// `HairChatService` and are untouched. Copy here stays warm, patient, and non-diagnostic.
enum Companion {
    static let name = "Wren"
    static let role = "Your calm tracking companion"
    static let introduction = "I watch the pattern, not one alarming day. I’ll be honest about what your record can — and cannot — show, then point to one useful next step."
    static let newcomerReassurance = "Nothing is judged in your first week. You’re building a baseline, not a verdict."

    /// The pose asset for a moment.
    static func pose(for moment: CompanionMoment) -> String {
        switch moment {
        case .resting:     return CompanionArt.resting
        case .greeting:    return CompanionArt.greeting
        case .listening:   return CompanionArt.listening
        case .thinking:    return CompanionArt.thinking
        case .searching:   return CompanionArt.searching
        case .celebrating: return CompanionArt.celebrating
        }
    }

    /// What Wren offers from the floating chat button, phrased for the screen the person is
    /// actually on. Lives here rather than in the view because this file is the single home of the
    /// companion's voice — same reason `line(for:)` does — and because a pure mapping is
    /// unit-testable.
    ///
    /// Each line names something the chat can genuinely do with the person's own record. None of
    /// them promise an outcome or imply a diagnosis; the chat's real limits still live in
    /// `HairChatPrompt.system`.
    static func openingLine(for tab: AppTab) -> String {
        switch tab {
        case .today:
            return "Logged today? I can tell you how this week compares to your last one."
        case .trends:
            return "See a dip or a climb here? Ask me what else moved at the same time."
        case .care:
            return "Ask me whether your routine is actually landing — and where it slips."
        case .labs:
            return "Ask me what a result means in the context of everything else you've logged."
        case .photos:
            return "Ask me what's changed since your baseline photo — and what hasn't."
        }
    }

    /// The focus line handed to `HairChatSheet` so answers land on the screen the chat was opened
    /// from. Deliberately terse — it's read by the model, not the person.
    static func chatFocus(for tab: AppTab) -> String {
        switch tab {
        case .today:  return "The person's whole tracked record, opened from the Today screen."
        case .trends: return "The person's trends over time, opened from the Trends screen."
        case .care:   return "The person's routine and treatment adherence, opened from the Plan screen."
        case .labs:   return "The person's lab results in the context of their record, opened from the Labs screen."
        case .photos: return "The person's progress photos over time, opened from the Photos screen."
        }
    }

    /// Builds Wren's first-week instructions from facts the app already owns. `firstEntryDate`
    /// normally marks the end of onboarding more accurately than `profileCreatedAt`; the latter
    /// remains a safe fallback for profiles created before a first entry existed.
    static func newcomerGuide(
        profileCreatedAt: Date,
        firstEntryDate: Date?,
        hasOnboarded: Bool,
        hasLoggedToday: Bool,
        hasRoutine: Bool,
        hasBaselinePhoto: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CompanionNewcomerGuide? {
        guard hasOnboarded else { return nil }

        let start = calendar.startOfDay(for: firstEntryDate ?? profileCreatedAt)
        let today = calendar.startOfDay(for: now)
        let rawOffset = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let dayOffset = max(0, rawOffset)
        guard dayOffset < 7 else { return nil }

        return CompanionNewcomerGuide(
            dayNumber: dayOffset + 1,
            steps: [
                CompanionGuideStep(action: .checkIn, isComplete: hasLoggedToday),
                CompanionGuideStep(action: .routine, isComplete: hasRoutine),
                CompanionGuideStep(action: .baselinePhoto, isComplete: hasBaselinePhoto),
            ]
        )
    }

    /// Wren's line for a moment, or `nil` for ambient moments that should stay silent.
    static func line(for moment: CompanionMoment) -> String? {
        switch moment {
        case .greeting:
            return "I’m Wren. I help you step back from one scary hair day and read the slower pattern."
        case .searching:
            return "Nothing here yet. Add something and I'll help you see what changes."
        case .celebrating:
            return "You showed up. That consistency is the part that actually moves hair."
        case .resting, .listening, .thinking:
            return nil
        }
    }
}
