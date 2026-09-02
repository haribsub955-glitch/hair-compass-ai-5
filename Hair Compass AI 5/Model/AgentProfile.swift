import Foundation

/// What the agent is told about the person, and — more importantly — what it is never told.
///
/// The agent runs on a server, so anything in here leaves the device. `AIContextBuilder` already
/// draws that line and states it plainly: *"No direct identifiers: the profile section deliberately
/// has NO name field."* That decision holds here. Sending a name would change the app's App Privacy
/// labels (Contact Info → Name, linked to identity) and widen the PDPL cross-border consent, for a
/// nicety.
///
/// **So the name never travels, and the agent still greets people by name.** The prompt tells the
/// model to write `{{name}}` wherever it would address the user; the client substitutes the real
/// name from the local `Profile` before anything reaches the screen. The model produces a
/// personalised sentence having never seen who it is for.
///
/// Age is different and does travel — as a number, not a birth date. Exact age is load-bearing
/// here: several evidence tiers and treatment cautions turn on it, and `ageBand` ("25-34") is too
/// coarse to gate on. A birth date would be an identifier; an integer is not.
struct AgentProfile: Codable, Equatable, Sendable {

    /// The token the model writes instead of a name. Substituted client-side, never sent up.
    static let nameToken = "{{name}}"

    /// Years. Derived at send time from `birthDate` when present, else parsed from `ageBand`'s
    /// lower bound. Derived rather than stored because a stored age is wrong within a year.
    var age: Int?
    var sex: String?
    var condition: String?
    var familyHistory: String?
    var baselineStage: String?
    var pregnancyStatus: String?

    var wearsTightStyles: Bool = false
    var usesHeat: Bool = false
    var usesChemicalTreatments: Bool = false

    /// Whether the app holds a name to substitute. The model needs to know whether `{{name}}` will
    /// resolve — writing "Hi {{name}}" for someone who never entered one reads as a bug.
    var hasName: Bool = false

    // MARK: - Building

    /// Project a stored `Profile` into what the agent may see.
    ///
    /// Every field here is a deliberate inclusion. `name` and `birthDate` are deliberate
    /// exclusions, and there is a test that fails if either ever appears in the encoded form.
    static func from(_ profile: Profile?, now: Date = .now) -> AgentProfile {
        guard let profile else { return AgentProfile() }
        return AgentProfile(
            age: derivedAge(from: profile, now: now),
            sex: profile.sex.rawValue,
            condition: profile.condition.rawValue,
            familyHistory: profile.familyHistory.rawValue,
            baselineStage: profile.baselineStage.isEmpty ? nil : profile.baselineStage,
            pregnancyStatus: profile.pregnancyStatus == .unspecified
                ? nil : profile.pregnancyStatus.rawValue,
            wearsTightStyles: profile.wearsTightStyles,
            usesHeat: profile.usesHeat,
            usesChemicalTreatments: profile.usesChemicalTreatments,
            hasName: !profile.name.trimmingCharacters(in: .whitespaces).isEmpty
        )
    }

    /// Exact age from a birth date; otherwise the lower bound of the recorded band.
    ///
    /// The band fallback is deliberately conservative — "35-44" yields 35, not 40 — because every
    /// age-gated caution in this app tightens as age rises, so guessing low never loosens a
    /// safeguard.
    static func derivedAge(from profile: Profile, now: Date = .now) -> Int? {
        if let birthDate = profile.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birthDate, to: now).year
            if let years, years >= 0, years < 130 { return years }
        }
        let digits = profile.ageBand.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// The block handed to the agent. Compact on purpose — this rides on every single turn, so
    /// every wasted token is paid for on every request, forever.
    var promptBlock: String {
        var lines: [String] = []
        if let age { lines.append("age: \(age)") }
        if let sex { lines.append("sex: \(sex)") }
        if let condition { lines.append("stated condition: \(condition)") }
        if let familyHistory { lines.append("family history: \(familyHistory)") }
        if let baselineStage { lines.append("baseline: \(baselineStage)") }
        if let pregnancyStatus { lines.append("pregnancy status: \(pregnancyStatus)") }

        let practices = [
            wearsTightStyles ? "tight styles" : nil,
            usesHeat ? "heat" : nil,
            usesChemicalTreatments ? "chemical treatments" : nil,
        ].compactMap { $0 }
        if !practices.isEmpty { lines.append("hair practices: \(practices.joined(separator: ", "))") }

        if lines.isEmpty { return "" }
        let addressing = hasName
            ? "Address them as \(Self.nameToken) — write that token exactly; the app fills in their name."
            : "You do not know their name. Do not ask for it and do not invent one."
        return "[about this person]\n" + lines.joined(separator: "\n") + "\n" + addressing
    }
}

extension AgentProfile {
    /// Replace the token with the real name, on-device, after the answer comes back.
    ///
    /// Trailing punctuation is handled by the caller's own text; this only swaps the token. A model
    /// that forgot the token simply produces an unpersonalised sentence, which is a fine outcome —
    /// far better than the alternative failure of shipping the name to a server.
    static func personalise(_ text: String, name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            // No name to substitute. Strip the token rather than showing it raw to the user.
            return text.replacingOccurrences(of: nameToken, with: "")
                .replacingOccurrences(of: "  ", with: " ")
        }
        return text.replacingOccurrences(of: nameToken, with: trimmed)
    }
}
