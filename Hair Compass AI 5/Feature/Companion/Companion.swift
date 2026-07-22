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

/// Wren — the name and personality of the on-device AI. This is the single home of the
/// companion's voice: a pure mapping, no SwiftUI, no state, fully unit-tested (mirrors how
/// `HairChatPrompt` centralizes the chat's scope and `HairInsightCalculator` centralizes stats).
///
/// Wren is *presentation*, never capability: the chat's model contract and guardrails live in
/// `HairChatService` and are untouched. Copy here stays warm, patient, and non-diagnostic.
enum Companion {
    static let name = "Wren"

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

    /// Wren's line for a moment, or `nil` for ambient moments that should stay silent.
    static func line(for moment: CompanionMoment) -> String? {
        switch moment {
        case .greeting:
            return "I'm Wren. I'll help you read what your hair is telling you — a little at a time."
        case .searching:
            return "Nothing here yet. Add something and I'll help you see what changes."
        case .celebrating:
            return "You showed up. That consistency is the part that actually moves hair."
        case .resting, .listening, .thinking:
            return nil
        }
    }
}
