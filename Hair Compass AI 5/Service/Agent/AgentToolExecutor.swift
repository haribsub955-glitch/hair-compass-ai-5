import Foundation
import SwiftData

/// Runs the agent's tool calls against this device's own data.
///
/// This is the `ClientIntegration` half of the platform split: the server knows a tool is called
/// `read_lab_results` and that its output is untrusted; only this file knows that means a
/// `FetchDescriptor<LabResult>` and how to shape the answer.
///
/// **The field names here are a contract with the server's prompt pack.** Rename one and nothing
/// fails — no test, no gate, no crash. The model simply starts answering with less information,
/// and the regression stays invisible until someone reads a bad answer. Keep the shapes in step,
/// and bump the envelope schema version when one has to change.
///
/// **Every value the agent sees is computed by `HairAnalytics`, never by the model.** The scalp
/// total, the lab flag, the rapid-weight-loss threshold — the app decides all of them, and the
/// agent's job is to explain a finding the app already made. That is the standing rule from the
/// project's own stance, and it is what keeps the AI from inventing numbers.
@MainActor
struct AgentToolExecutor: AgentClient.ToolExecutor {

    let context: ModelContext
    /// Conversation identity, so session-scoped memories stay inside the conversation that wrote
    /// them. Provenance, not visibility — see `AgentMemory`.
    let sessionID: String
    var calendar: Calendar = .current
    var now: () -> Date = { .now }

    /// Guards the effects a mutation would otherwise repeat after a lost acknowledgement.
    let idempotency: IdempotencyLog

    var healthAvailable: Bool = true

    /// What this build can do. Subtractive only — the server intersects it with what it would
    /// offer anyway, so naming something extra gains nothing and guarantees a timeout when the
    /// server dispatches it.
    var implementedTools: [String] {
        var tools = ["recall_memory", "read_recent_entries", "read_lab_results", "log_entry",
                     "read_hair_science", "read_treatments", "read_procedures", "read_triggers",
                     "read_progress_checkins", "read_photo_history", "read_profile"]
        if healthAvailable { tools.append("read_health_signals") }
        return tools
    }

    enum ExecutorError: Error {
        case unknownTool(String)
        case missingIdempotencyKey(String)
    }

    func run(tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch tool {
        // `await` on synchronous calls: `ToolExecutor.run` is a nonisolated protocol requirement,
        // so this body runs off the main actor even though the type is `@MainActor`. Each hop
        // below is what gets these reads back onto the actor that owns the `ModelContext`.
        case "recall_memory":       return try await recallMemory(arguments)
        case "read_recent_entries": return try await readRecentEntries(arguments)
        case "read_lab_results":    return try await readLabResults(arguments)
        case "read_health_signals": return try await readHealthSignals(arguments)
        case "read_hair_science":   return await readHairScience(arguments)
        case "read_treatments":     return try await readTreatments(arguments)
        case "read_procedures":     return try await readProcedures(arguments)
        case "read_triggers":       return try await readTriggers(arguments)
        case "read_progress_checkins": return try await readProgressCheckIns(arguments)
        case "read_photo_history":  return try await readPhotoHistory(arguments)
        case "read_profile":        return try await readProfile(arguments)
        case "log_entry":           return try await logEntry(arguments)
        default:
            // Unreachable while `implementedTools` and this switch agree. Reaching it means they
            // drifted, which deserves an error rather than a silent empty result.
            throw ExecutorError.unknownTool(tool)
        }
    }

    // MARK: - Reads

    private func recallMemory(_ arguments: [String: Any]) throws -> [String: Any] {
        let query = (arguments["query"] as? String) ?? ""
        let limit = min((arguments["limit"] as? Int) ?? AgentMemoryStore.defaultLimit, 20)
        let scope = (arguments["scope"] as? String).flatMap(AgentMemoryScope.init(rawValue:))

        let all = try context.fetch(FetchDescriptor<AgentMemory>())
        let hits = AgentMemoryStore.recall(
            all, scope: scope, sessionID: sessionID, query: query, limit: limit
        )
        AgentMemoryStore.markRecalled(hits, at: now())

        return [
            "hits": hits.map { hit in
                ["text": hit.text, "kind": hit.kind.rawValue, "recorded": iso(hit.createdAt)]
            },
            "total_stored": all.filter { !$0.isForgotten }.count,
        ]
    }

    private func readRecentEntries(_ arguments: [String: Any]) throws -> [String: Any] {
        let days = min(max((arguments["days"] as? Int) ?? 30, 1), 365)
        let since = calendar.date(byAdding: .day, value: -days, to: now()) ?? now()
        let entries = try context.fetch(
            FetchDescriptor<DailyEntry>(
                predicate: #Predicate { $0.date >= since },
                sortBy: [SortDescriptor(\DailyEntry.date, order: .reverse)]
            )
        )

        var facts: [String: Any] = [
            "days_requested": days,
            "entry_count": entries.count,
            "streak_days": HairAnalytics.loggingStreak(
                entryDates: entries.map(\.date), now: now(), calendar: calendar
            ),
        ]
        guard !entries.isEmpty else { return facts }

        // Two windows, so the model can state a direction rather than one number it has to
        // interpret. A trend is the thing a person actually asked about.
        let midpoint = calendar.date(byAdding: .day, value: -days / 2, to: now()) ?? now()
        let recent = entries.filter { $0.date >= midpoint }
        let previous = entries.filter { $0.date < midpoint }

        // Shed is a self-reported BAND (`ShedLevel`), not a hair count. Reporting it as a number
        // would invite the model to say "42 hairs a day", which this app never claims to measure.
        if let band = modalShed(recent) { facts["shed_band_recent"] = band }
        if let band = modalShed(previous) { facts["shed_band_previous"] = band }

        // `scalpTotal` is HairAnalytics' 16-point scale, computed by the app.
        if let average = mean(recent.map { Double($0.scalpTotal) }) {
            facts["scalp_score_16pt_recent"] = Int(average.rounded())
        }
        if let average = mean(previous.map { Double($0.scalpTotal) }) {
            facts["scalp_score_16pt_previous"] = Int(average.rounded())
        }
        facts["scalp_scale_max"] = 16

        // Wash days show more shed. Handing the model the count without the confound is how it
        // reads a heavy wash week as a real change.
        facts["wash_days_recent"] = recent.filter(\.washedHair).count
        return facts
    }

    /// The person's plan: what they are actually taking or applying, and how it is going.
    ///
    /// The single most-asked thing about a hair record — "is minoxidil in my plan", "how long
    /// have I been on this", "am I keeping up with it" — and until this existed the agent had no
    /// way to answer any of it and would say it couldn't verify.
    ///
    /// Every derived number comes from `HairAnalytics`, never from the model. `outcome_ready` is
    /// the 24-week judging gate the whole app is built around: the agent must not call a
    /// treatment working or not working before it, and it can only respect that rule if it is
    /// told which side of the line each treatment sits on.
    private func readTreatments(_ arguments: [String: Any]) throws -> [String: Any] {
        let includeStopped = (arguments["include_stopped"] as? Bool) ?? true
        let all = try context.fetch(FetchDescriptor<Treatment>(
            sortBy: [SortDescriptor(\Treatment.startDate, order: .reverse)]
        ))
        let treatments = includeStopped ? all : all.filter(\.isActive)

        return [
            "count": treatments.count,
            "treatments": treatments.map { t -> [String: Any] in
                let weeks = HairAnalytics.weeksElapsed(since: t.startDate)
                let doseDates = t.doses.map(\.loggedAt)
                var row: [String: Any] = [
                    "name": t.name.isEmpty ? t.treatmentClass.title : t.name,
                    "class": t.treatmentClass.title,
                    "dose": t.dose,
                    "active": t.isActive,
                    "started": iso(t.startDate),
                    "weeks_elapsed": weeks,
                    // The 24-week gate, stated rather than implied.
                    "outcome_ready": HairAnalytics.outcomeReady(weeksElapsed: weeks),
                    "times_per_day": t.slots.count,
                    "doses_logged": t.doses.count,
                    "side_effects_logged": t.sideEffects.count,
                    "missed_doses_logged": t.missedDoses.count,
                ]
                if !t.scheduleTimes.isEmpty {
                    row["schedule"] = t.scheduleTimes
                    // Both clock forms, deliberately. A model handed "21:00" will write "9pm" —
                    // that is a correct, helpful rendering, but "9" then appears in prose while
                    // only "21" appears in the facts, and `AIOutputValidator` rejects the whole
                    // answer as containing an invented number. Publishing both readings keeps
                    // the gate strict about genuinely invented figures without punishing the
                    // model for converting a clock properly.
                    row["schedule_12h"] = Self.twelveHour(t.scheduleTimes)
                }
                if let adherence = HairAnalytics.adherence(doseDates: doseDates, expectedPerDay: t.slots.count) {
                    row["adherence_percent"] = Int((adherence * 100).rounded())
                }
                if let end = t.endDate { row["stopped"] = iso(end) }
                if let refill = t.refillBy { row["refill_by"] = iso(refill) }
                if !t.aiIngredientSummary.isEmpty { row["ingredient_summary"] = t.aiIngredientSummary }
                return row
            },
        ]
    }

    /// In-clinic work: PRP, transplants, laser and the rest, booked or done.
    private func readProcedures(_ arguments: [String: Any]) throws -> [String: Any] {
        let limit = min((arguments["limit"] as? Int) ?? 20, 50)
        var descriptor = FetchDescriptor<ProcedureAppointment>(
            sortBy: [SortDescriptor(\ProcedureAppointment.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let procedures = try context.fetch(descriptor)

        return [
            "count": procedures.count,
            "procedures": procedures.map { p -> [String: Any] in
                var row: [String: Any] = [
                    "type": p.type.title,
                    "date": iso(p.date),
                    "completed": p.isCompleted,
                ]
                if !p.location.isEmpty { row["location"] = p.location }
                if !p.note.isEmpty { row["note"] = p.note }
                if !p.agendaMainConcern.isEmpty { row["main_concern"] = p.agendaMainConcern }
                return row
            },
        ]
    }

    /// Life events the person marked as possible triggers. Shedding lags a trigger by 2–3
    /// months, so `weeks_ago` is the number that makes one worth mentioning at all.
    private func readTriggers(_ arguments: [String: Any]) throws -> [String: Any] {
        let limit = min((arguments["limit"] as? Int) ?? 10, 30)
        var descriptor = FetchDescriptor<TriggerEvent>(
            sortBy: [SortDescriptor(\TriggerEvent.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let triggers = try context.fetch(descriptor)

        return [
            "count": triggers.count,
            "triggers": triggers.map { t -> [String: Any] in
                var row: [String: Any] = [
                    "type": t.type.title,
                    "date": iso(t.date),
                    "weeks_ago": t.weeksElapsed(),
                ]
                if !t.note.isEmpty { row["note"] = t.note }
                return row
            },
        ]
    }

    /// The periodic self-assessment — the person's own read on regrowth, density and hairline.
    ///
    /// `scalp_pain` travels with every row it appears in. Persistent scalp pain is one of the
    /// few genuine red flags in this app (it can mean scarring alopecia, which is irreversible
    /// once missed), so it must reach the agent rather than being averaged away.
    private func readProgressCheckIns(_ arguments: [String: Any]) throws -> [String: Any] {
        let limit = min((arguments["limit"] as? Int) ?? 6, 20)
        var descriptor = FetchDescriptor<ProgressCheckIn>(
            sortBy: [SortDescriptor(\ProgressCheckIn.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let checkIns = try context.fetch(descriptor)

        return [
            "count": checkIns.count,
            "check_ins": checkIns.map { c -> [String: Any] in
                var row: [String: Any] = [
                    "date": iso(c.date),
                    "regrowth": c.regrowth.title,
                    // Each answer is phrased for the question it answers — "More scalp shows"
                    // rather than a bare "worse" — so the agent quotes the person's own wording
                    // back instead of re-inventing a direction word.
                    "density": c.density.label(for: .density),
                    "shedding": c.shedding.label(for: .shedding),
                    "hairline": c.hairline.label(for: .hairline),
                    "overall": c.overall.label(for: .overall),
                    "scalp_pain": c.scalpPain,
                ]
                if c.scalpPain && !c.scalpPainNote.isEmpty { row["scalp_pain_note"] = c.scalpPainNote }
                if !c.note.isEmpty { row["note"] = c.note }
                return row
            },
        ]
    }

    /// Photo *metadata* only — how many, which regions, over what span.
    ///
    /// Deliberately never the images. Foundation Models has no image input and this agent has no
    /// attachment transport (handover §6), so sending pixels would be impossible as well as
    /// wrong. What the agent can usefully say is whether a comparison is even possible yet.
    private func readPhotoHistory(_ arguments: [String: Any]) throws -> [String: Any] {
        let photos = try context.fetch(FetchDescriptor<PhotoRecord>(
            sortBy: [SortDescriptor(\PhotoRecord.createdAt)]
        ))
        var byRegion: [String: Int] = [:]
        for photo in photos { byRegion[photo.region.title, default: 0] += 1 }

        var facts: [String: Any] = [
            "count": photos.count,
            "by_region": byRegion,
            "images_are_never_sent": true,
        ]
        if let first = photos.first, let last = photos.last {
            facts["first"] = iso(first.createdAt)
            facts["latest"] = iso(last.createdAt)
            facts["span_weeks"] = HairAnalytics.weeksElapsed(since: first.createdAt)
        }
        return facts
    }

    /// Who this person is, as far as the agent is allowed to know.
    ///
    /// Routed through `AgentProfile`, which is the existing projection that strips the name and
    /// the exact birth date and passes only a derived age. That boundary is the reason this
    /// doesn't just read `Profile` directly.
    private func readProfile(_ arguments: [String: Any]) throws -> [String: Any] {
        let profile = try context.fetch(FetchDescriptor<Profile>(
            sortBy: [SortDescriptor(\Profile.createdAt)]
        )).first
        let projected = AgentProfile.from(profile, now: now())

        var facts: [String: Any] = [:]
        if let age = projected.age { facts["age"] = age }
        if let condition = projected.condition { facts["condition"] = condition }
        if let history = projected.familyHistory { facts["family_history"] = history }
        if let stage = projected.baselineStage, !stage.isEmpty { facts["baseline_stage"] = stage }
        if let sex = projected.sex { facts["sex"] = sex }
        // Pregnancy gates real advice in this app (finasteride is contraindicated), so it has to
        // reach the agent rather than being something it guesses around.
        if let pregnancy = projected.pregnancyStatus { facts["pregnancy_status"] = pregnancy }
        facts["wears_tight_styles"] = projected.wearsTightStyles
        facts["uses_heat"] = projected.usesHeat
        facts["uses_chemical_treatments"] = projected.usesChemicalTreatments
        facts["identifiers_are_never_sent"] = true
        return facts
    }

    /// The app's own hair-science library — what lets the agent answer a general question
    /// ("how fast does hair grow?") instead of only questions about this person's record.
    ///
    /// It reads `LearnLibrary`, the same evidence-tiered, myth-flagged content the Learn screen
    /// shows, rather than letting the model answer from its own training. Two reasons, and the
    /// second is the load-bearing one:
    ///
    /// 1. **Consistency.** The app already took positions — water intake and dietary caffeine are
    ///    named as myths, blanket biotin is rejected. An agent contradicting the Learn screen in
    ///    the same app is worse than an agent that cannot answer.
    /// 2. **The output gate.** `AIOutputValidator` rejects any number in generated prose that is
    ///    absent from the facts the model was given. General hair science is full of numbers —
    ///    "1 cm a month", "50-100 hairs a day", "2-6 years" — so without this tool a correct
    ///    general answer is silently replaced by the "couldn't safely summarize" text. Returning
    ///    the library's own wording puts those figures into the fact set, where the gate can see
    ///    them. The model is still never free to invent one.
    ///
    /// Scored the same way `AgentMemoryStore.recall` scores memories: term overlap, so a short
    /// query still finds the card a person actually meant.
    private func readHairScience(_ arguments: [String: Any]) async -> [String: Any] {
        let query = (arguments["query"] as? String) ?? ""
        let limit = min((arguments["limit"] as? Int) ?? 4, 8)
        let requested = (arguments["category"] as? String)
            .flatMap(LearnCategory.init(rawValue:))

        let pool = requested.map(LearnLibrary.cards(in:)) ?? LearnLibrary.cards
        let terms = Set(
            query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )

        let ranked: [FlashCard]
        if terms.isEmpty {
            ranked = Array(pool.prefix(limit))
        } else {
            ranked = pool
                .map { card -> (FlashCard, Int) in
                    let text = (card.question + " " + card.answer).lowercased()
                    return (card, terms.filter { text.contains($0) }.count)
                }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map(\.0)
        }

        return [
            "query": query,
            "cards": ranked.map { card in
                [
                    "question": card.question,
                    "answer": card.answer,
                    "category": card.category.rawValue,
                    // Myths read as a verdict, not an evidence tier — the library's own rule, and
                    // the difference between "weak evidence" and "this is a myth" matters.
                    "verdict": card.isMyth ? "MYTH" : card.tier.title,
                ]
            },
        ]
    }

    private func readLabResults(_ arguments: [String: Any]) throws -> [String: Any] {
        let limit = min((arguments["limit"] as? Int) ?? 20, 50)
        var descriptor = FetchDescriptor<LabResult>(
            sortBy: [SortDescriptor(\LabResult.collectedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let results = try context.fetch(descriptor)

        return [
            "results": results.map { result -> [String: Any] in
                var row: [String: Any] = [
                    "test": result.test.rawValue,
                    "name": result.test.title,
                    "unit": result.test.unit,
                    "value": result.value,
                    "collected": iso(result.collectedAt),
                    // The app's own clinical note for this test, and it does two jobs.
                    //
                    // It frames the result the way the rest of the app frames it, so chat and the
                    // Labs screen cannot drift apart. And it supplies the vocabulary the model
                    // will legitimately reach for: asked about TSH, any competent answer says
                    // "thyroid", but "thyroid" is one of `AIOutputValidator`'s grounded terms and
                    // a fact set containing only the string "TSH" gets that answer thrown away.
                    // The note says "Thyroid function", so the gate and the model finally agree.
                    "note": result.test.note,
                ]
                // The flag comes from HairAnalytics against the test's own reference range — or
                // the user's recorded range when they entered one, which is the more honest
                // comparison since reference ranges differ by lab.
                if let low = result.refLow, let high = result.refHigh, low < high {
                    row["flag"] = String(describing: HairAnalytics.flag(for: result.value, range: low...high))
                    row["ref_low"] = low
                    row["ref_high"] = high
                } else {
                    row["flag"] = String(describing: HairAnalytics.flag(for: result.value, test: result.test))
                }
                return row
            }
        ]
    }

    private func readHealthSignals(_ arguments: [String: Any]) throws -> [String: Any] {
        let days = min(max((arguments["days"] as? Int) ?? 30, 1), 365)
        let since = calendar.date(byAdding: .day, value: -days, to: now()) ?? now()
        let snapshots = try context.fetch(
            FetchDescriptor<HealthSnapshot>(
                predicate: #Predicate { $0.date >= since },
                sortBy: [SortDescriptor(\HealthSnapshot.date, order: .reverse)]
            )
        )
        guard !snapshots.isEmpty else { return ["available": false] }

        var facts: [String: Any] = ["available": true, "days_requested": days]
        if let sleep = mean(snapshots.compactMap(\.sleepHours)) {
            facts["sleep_hours_avg"] = (sleep * 10).rounded() / 10
        }
        if let hrv = mean(snapshots.compactMap(\.hrvSDNN)) {
            facts["hrv_sdnn_avg"] = Int(hrv.rounded())
        }
        // Rapid loss is a documented telogen-effluvium trigger. The threshold is the app's.
        let masses = snapshots.compactMap { snapshot -> (date: Date, massKg: Double)? in
            snapshot.bodyMassKg.map { (date: snapshot.date, massKg: $0) }
        }
        if let percent = HairAnalytics.rapidWeightLossPercent(samples: masses) {
            facts["weight_change_percent"] = (percent * 10).rounded() / 10
        }
        return facts
    }

    // MARK: - Mutations

    private func logEntry(_ arguments: [String: Any]) async throws -> [String: Any] {
        // The server refuses to dispatch a mutation without a key, so its absence means something
        // upstream is broken. Failing beats performing an effect a retry would repeat.
        guard let key = arguments["idempotency_key"] as? String, !key.isEmpty else {
            throw ExecutorError.missingIdempotencyKey("log_entry")
        }
        guard await idempotency.claim(key) else {
            // Already performed. Reporting success is correct — the effect the caller wanted has
            // happened; it simply happened on an earlier attempt.
            return ["logged": true, "duplicate": true]
        }

        let day = (arguments["date"] as? String).flatMap(parseDay) ?? now()
        let repository = DailyEntryRepository(context: context, calendar: calendar, now: now)
        let entry = try repository.upsert(day: day) { entry in
            // Shed arrives as a band name, never a count — the app does not measure hair counts.
            if let name = arguments["shed_band"] as? String, let level = Self.shedLevel(named: name) {
                entry.shed = level
            }
            if let note = arguments["note"] as? String, !note.isEmpty { entry.note = note }
        }
        return ["logged": true, "duplicate": false, "date": iso(entry.date)]
    }

    // MARK: - Helpers

    /// Most common band, not a mean — averaging ordinal self-report bands invents a precision the
    /// data does not have.
    private func modalShed(_ entries: [DailyEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let counts = Dictionary(grouping: entries, by: { $0.shed.rawValue }).mapValues(\.count)
        guard let raw = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return ShedLevel(rawValue: raw).map { String(describing: $0) }
    }

    /// `ShedLevel` is Int-backed, but the wire carries the band's NAME — an integer on the wire
    /// would silently break the day someone reorders the cases.
    /// "08:00,21:00" → "8am, 9pm". Locale-independent on purpose: this is grounding material for
    /// a model, not display text, and it has to match what the model will write.
    nonisolated static func twelveHour(_ times: String) -> String {
        times.split(separator: ",").compactMap { slot -> String? in
            let parts = slot.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard let hour = Int(parts.first ?? "") else { return nil }
            let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            let suffix = hour < 12 ? "am" : "pm"
            let display = hour % 12 == 0 ? 12 : hour % 12
            return minute == 0 ? "\(display)\(suffix)" : "\(display):\(String(format: "%02d", minute))\(suffix)"
        }
        .joined(separator: ", ")
    }

    static func shedLevel(named name: String) -> ShedLevel? {
        ShedLevel.allCases.first { String(describing: $0).lowercased() == name.lowercased() }
    }

    /// Rounded to one decimal, and that rounding is load-bearing in two ways.
    ///
    /// It is honest: a mean of 13 sleep readings is not known to sixteen significant figures, and
    /// `7.400000000000000355` claims a precision the data does not have.
    ///
    /// It also keeps generated prose publishable. `AIOutputValidator` rejects any number in an
    /// answer that does not appear in the facts the model was given; a model handed
    /// `7.400000000000000355` will sensibly write "7.4", the two do not match, and a correct
    /// answer gets replaced by the "couldn't safely summarize" text. Emitting the number the way
    /// it should be quoted is what makes the gate agree with reality.
    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return ((values.reduce(0, +) / Double(values.count)) * 10).rounded() / 10
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}

/// Remembers which mutating calls this device has already performed.
///
/// The second half of the duplicate-effect defence: the server declines to retry a mutation whose
/// result never came back, and this declines to *repeat* one whose key it has already seen. Even a
/// retry arriving through some path nobody anticipated does nothing twice.
///
/// `UserDefaults` because it must survive a relaunch — the failure mode is a dropped
/// acknowledgement, and the app being killed is one way that happens.
actor IdempotencyLog {
    private let defaults: UserDefaults
    private let storageKey = "agent.performed_idempotency_keys"
    /// Bounded so it cannot grow forever. Ageing keys out is safe: the retry window is seconds, so
    /// a key this old belongs to a turn that ended long ago.
    private let limit = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True if this effect is new (and records it). False means it already happened — skip.
    func claim(_ key: String) -> Bool {
        var seen = defaults.stringArray(forKey: storageKey) ?? []
        guard !seen.contains(key) else { return false }
        seen.append(key)
        if seen.count > limit { seen.removeFirst(seen.count - limit) }
        defaults.set(seen, forKey: storageKey)
        return true
    }
}
