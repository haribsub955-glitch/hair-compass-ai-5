import Foundation
import SwiftData

/// Full-fidelity backup and merge-safe restore of every record the app owns, photos included.
///
/// The archive is one versioned JSON file with photos embedded as base64 JPEG — no zip
/// container, so it shares, AirDrops and saves to Files/iCloud Drive as-is. Photos dominate
/// the size (~100–500 KB each); past ~50 MB the file is large but still written — a
/// phone-loss-proof copy matters more than a small file.
///
/// Restore is an upsert by natural keys, never a wipe: existing records are kept, missing
/// ones are inserted, and nothing is deleted.
enum BackupService {

    static let currentVersion = 1

    // MARK: - Errors

    enum BackupError: LocalizedError, Equatable {
        case unsupportedVersion(Int)
        case unreadableFile

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "This backup uses a newer format (v\(v)) than this app understands. Update Hair Compass, then try again."
            case .unreadableFile:
                return "That file doesn't look like a Hair Compass backup."
            }
        }
    }

    // MARK: - The archive envelope (version 1)

    /// Codable mirror of the whole store. Enum raw values are stored as-is; dates are
    /// ISO8601 (whole seconds). Doses and side effects are nested inside their treatment
    /// so relationships survive the round trip.
    struct Envelope: Codable {
        var version: Int = currentVersion
        var createdAt: Date = .now
        var appVersion: String = AppInfo.version
        var profile: ProfileDTO?
        var entries: [EntryDTO] = []
        var treatments: [TreatmentDTO] = []
        var labs: [LabDTO] = []
        var photos: [PhotoDTO] = []
        var snapshots: [SnapshotDTO] = []
        var triggers: [TriggerDTO] = []
        // Added after v1 shipped — Codable arrays default to empty, so older backup files
        // (which never wrote these keys) still decode cleanly with no procedures/check-ins,
        // rather than failing the whole restore.
        var procedures: [ProcedureDTO] = []
        var progressCheckIns: [ProgressCheckInDTO] = []
    }

    struct ProfileDTO: Codable {
        var name = ""
        var sexRaw = ""
        var ageBand = ""
        var conditionRaw = ""
        var familyHistoryRaw = ""
        var baselineStage = ""
        var createdAt = Date.now
        var hasOnboarded = false
        var wearsTightStyles = false
        var usesHeat = false
        var usesChemicalTreatments = false
        // Defaulted so older backups (without the field) still decode to `.unspecified`.
        var pregnancyStatusRaw = PregnancyStatus.unspecified.rawValue
    }

    struct EntryDTO: Codable {
        var date = Date.now
        var shedRaw = 0
        var flaking = 0
        var erythema = 0
        var itch = 0
        var sleepQuality = 3
        var stress = 3
        var cigarettes = 0
        var alcoholDrinks = 0
        var oiliness = 0
        var note = ""
        // Defaulted so older backups (without the field) still decode to "not a wash day".
        var washedHair = false
    }

    struct TreatmentDTO: Codable {
        var name = ""
        var classRaw = ""
        var dose = ""
        var scheduleTimes = ""
        // Defaulted so older backups (without the field) restore to "every day".
        var scheduledWeekdaysRaw = ""
        var startDate = Date.now
        var isActive = true
        var refillBy: Date?
        var endDate: Date?
        var doses: [DoseDTO] = []
        var sideEffects: [SideEffectDTO] = []
    }

    struct DoseDTO: Codable {
        var loggedAt = Date.now
        var slot = ""
    }

    struct SideEffectDTO: Codable {
        var date = Date.now
        var severity = 1
        var typeRaw = ""
        var note = ""
    }

    struct LabDTO: Codable {
        var testRaw = ""
        var value = 0.0
        var collectedAt = Date.now
        var note = ""
        // Defaulted so older backups (without the field) still decode to "no override" — the
        // built-in default range applies, exactly as before this existed.
        var refLow: Double?
        var refHigh: Double?
    }

    struct PhotoDTO: Codable {
        var regionRaw = ""
        var createdAt = Date.now
        var lighting = ""
        var distance = ""
        var parting = ""
        var isWet = false
        var note = ""
        /// The JPEG bytes, base64. nil when the original file was already missing on disk.
        var imageBase64: String?
    }

    struct SnapshotDTO: Codable {
        var date = Date.now
        var sleepHours: Double?
        var hrvSDNN: Double?
        var restingHR: Double?
        var bodyMassKg: Double?
        var bmi: Double?
        var dietaryProteinG: Double?
        var updatedAt = Date.now
    }

    struct TriggerDTO: Codable {
        var typeRaw = ""
        var date = Date.now
        var note = ""
    }

    /// In-office / clinic events (transplant, PRP, LLLT session, etc.) — the dated,
    /// irreplaceable records a lost-phone restore must not silently drop.
    struct ProcedureDTO: Codable {
        var typeRaw = ""
        var date = Date.now
        var location = ""
        var isCompleted = false
        var completedAt: Date?
        var note = ""
        var createdAt = Date.now
    }

    /// Monthly self-reported regrowth/density/shedding/hairline/overall check-in, including
    /// the scalp-pain red flag.
    struct ProgressCheckInDTO: Codable {
        var date = Date.now
        var regrowthRaw = 0
        var densityRaw = 0
        var sheddingRaw = 0
        var hairlineRaw = 0
        var overallRaw = 0
        /// Alopecia areata-only "patches" answer; `nil` for every backup made before this
        /// question existed, decoded via `Codable`'s default-on-missing-key behavior.
        var patchTrendRaw: Int?
        var scalpPain = false
        var scalpPainNote = ""
        var note = ""
        var createdAt = Date.now
    }

    private struct VersionProbe: Codable { let version: Int }

    // MARK: - Export

    /// Snapshot the fetched records into an envelope. `photoData` supplies the raw stored
    /// JPEG bytes for a relative path (injected so tests never touch the real photo store).
    static func makeEnvelope(
        profile: Profile?,
        entries: [DailyEntry],
        treatments: [Treatment],
        labs: [LabResult],
        photos: [PhotoRecord],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        procedures: [ProcedureAppointment] = [],
        progressCheckIns: [ProgressCheckIn] = [],
        createdAt: Date = .now,
        photoData: (String) -> Data?
    ) -> Envelope {
        var envelope = Envelope(createdAt: createdAt)

        if let p = profile {
            envelope.profile = ProfileDTO(
                name: p.name, sexRaw: p.sexRaw, ageBand: p.ageBand,
                conditionRaw: p.conditionRaw, familyHistoryRaw: p.familyHistoryRaw,
                baselineStage: p.baselineStage, createdAt: p.createdAt,
                hasOnboarded: p.hasOnboarded, wearsTightStyles: p.wearsTightStyles,
                usesHeat: p.usesHeat, usesChemicalTreatments: p.usesChemicalTreatments,
                pregnancyStatusRaw: p.pregnancyStatusRaw
            )
        }

        envelope.entries = entries.map {
            EntryDTO(date: $0.date, shedRaw: $0.shedRaw, flaking: $0.flaking,
                     erythema: $0.erythema, itch: $0.itch, sleepQuality: $0.sleepQuality,
                     stress: $0.stress, cigarettes: $0.cigarettes,
                     alcoholDrinks: $0.alcoholDrinks, oiliness: $0.oiliness, note: $0.note,
                     washedHair: $0.washedHair)
        }

        envelope.treatments = treatments.map { t in
            TreatmentDTO(
                name: t.name, classRaw: t.classRaw, dose: t.dose,
                scheduleTimes: t.scheduleTimes, scheduledWeekdaysRaw: t.scheduledWeekdaysRaw,
                startDate: t.startDate,
                isActive: t.isActive, refillBy: t.refillBy, endDate: t.endDate,
                doses: t.doses
                    .sorted { $0.loggedAt < $1.loggedAt }
                    .map { DoseDTO(loggedAt: $0.loggedAt, slot: $0.slot) },
                sideEffects: t.sideEffects
                    .sorted { $0.date < $1.date }
                    .map { SideEffectDTO(date: $0.date, severity: $0.severity, typeRaw: $0.typeRaw, note: $0.note) }
            )
        }

        envelope.labs = labs.map {
            LabDTO(testRaw: $0.testRaw, value: $0.value, collectedAt: $0.collectedAt, note: $0.note,
                   refLow: $0.refLow, refHigh: $0.refHigh)
        }

        // One photo at a time inside an autorelease pool, so the transient JPEG buffers
        // are reclaimed between iterations instead of piling up.
        envelope.photos = photos.map { record in
            autoreleasepool {
                PhotoDTO(
                    regionRaw: record.regionRaw, createdAt: record.createdAt,
                    lighting: record.lighting, distance: record.distance,
                    parting: record.parting, isWet: record.isWet, note: record.note,
                    imageBase64: record.imagePath.isEmpty
                        ? nil
                        : photoData(record.imagePath)?.base64EncodedString()
                )
            }
        }

        envelope.snapshots = snapshots.map {
            SnapshotDTO(date: $0.date, sleepHours: $0.sleepHours, hrvSDNN: $0.hrvSDNN,
                        restingHR: $0.restingHR, bodyMassKg: $0.bodyMassKg, bmi: $0.bmi,
                        dietaryProteinG: $0.dietaryProteinG, updatedAt: $0.updatedAt)
        }

        envelope.triggers = triggers.map {
            TriggerDTO(typeRaw: $0.typeRaw, date: $0.date, note: $0.note)
        }

        envelope.procedures = procedures.map {
            ProcedureDTO(typeRaw: $0.typeRaw, date: $0.date, location: $0.location,
                         isCompleted: $0.isCompleted, completedAt: $0.completedAt,
                         note: $0.note, createdAt: $0.createdAt)
        }

        envelope.progressCheckIns = progressCheckIns.map {
            ProgressCheckInDTO(
                date: $0.date, regrowthRaw: $0.regrowthRaw, densityRaw: $0.densityRaw,
                sheddingRaw: $0.sheddingRaw, hairlineRaw: $0.hairlineRaw, overallRaw: $0.overallRaw,
                patchTrendRaw: $0.patchTrendRaw,
                scalpPain: $0.scalpPain, scalpPainNote: $0.scalpPainNote, note: $0.note,
                createdAt: $0.createdAt
            )
        }

        return envelope
    }

    static func encode(_ envelope: Envelope) throws -> Data {
        let encoder = JSONEncoder()
        // Whole-second ISO8601 (no fractional seconds) — stable across encode/decode.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> Envelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            throw BackupError.unreadableFile
        }
        guard probe.version == currentVersion else {
            throw BackupError.unsupportedVersion(probe.version)
        }
        do {
            return try decoder.decode(Envelope.self, from: data)
        } catch {
            throw BackupError.unreadableFile
        }
    }

    /// Build the archive from the fetched arrays and write it to a shareable temp file
    /// named `HairCompass-Backup-YYYY-MM-DD.json`.
    static func exportBackup(
        profile: Profile?,
        entries: [DailyEntry],
        treatments: [Treatment],
        labs: [LabResult],
        photos: [PhotoRecord],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        procedures: [ProcedureAppointment] = [],
        progressCheckIns: [ProgressCheckIn] = [],
        now: Date = .now,
        photoData: (String) -> Data? = { PhotoStore.shared.loadData($0) }
    ) throws -> URL {
        let envelope = makeEnvelope(
            profile: profile, entries: entries, treatments: treatments, labs: labs,
            photos: photos, snapshots: snapshots, triggers: triggers,
            procedures: procedures, progressCheckIns: progressCheckIns,
            createdAt: now, photoData: photoData
        )
        let data = try encode(envelope)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HairCompass-Backup-\(formatter.string(from: now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Restore

    struct RestoreSummary: Equatable {
        var inserted = 0
        var skipped = 0
        var photosRestored = 0
    }

    /// Read a backup file (handles security-scoped URLs from `.fileImporter`), decode it,
    /// and merge it into the live store.
    static func restore(from url: URL, into context: ModelContext) throws -> RestoreSummary {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.unreadableFile
        }
        let envelope = try decode(data)
        return try restore(envelope, into: context, photoWriter: { PhotoStore.shared.saveData($0) })
    }

    /// Merge-safe upsert of a decoded envelope. Nothing is ever deleted; records that
    /// already exist (matched by natural key) are skipped and counted.
    ///
    /// Natural keys:
    /// - DailyEntry: calendar day (`HairAnalytics.dayBounds` — one entry per day)
    /// - Treatment: (name, startDate); its doses by (loggedAt, slot); side effects by (type, date)
    /// - LabResult: (test, collectedAt)
    /// - PhotoRecord: (createdAt, region) — image bytes written back through `photoWriter`
    /// - HealthSnapshot: calendar day
    /// - TriggerEvent: (type, date)
    /// - ProcedureAppointment: (type, date)
    /// - ProgressCheckIn: calendar day
    /// - Profile: overwritten only while the local profile is still untouched (default)
    static func restore(
        _ envelope: Envelope,
        into context: ModelContext,
        photoWriter: (Data) -> String?
    ) throws -> RestoreSummary {
        var summary = RestoreSummary()
        let calendar = Calendar.current

        // Profile — keep local edits; only a still-default profile takes the backup's fields.
        if let incoming = envelope.profile {
            if let local = try context.fetch(FetchDescriptor<Profile>()).first {
                if isDefaultProfile(local) {
                    local.name = incoming.name
                    local.sexRaw = incoming.sexRaw
                    local.ageBand = incoming.ageBand
                    local.conditionRaw = incoming.conditionRaw
                    local.familyHistoryRaw = incoming.familyHistoryRaw
                    local.baselineStage = incoming.baselineStage
                    local.createdAt = incoming.createdAt
                    local.hasOnboarded = incoming.hasOnboarded
                    local.wearsTightStyles = incoming.wearsTightStyles
                    local.usesHeat = incoming.usesHeat
                    local.usesChemicalTreatments = incoming.usesChemicalTreatments
                    local.pregnancyStatusRaw = incoming.pregnancyStatusRaw
                    summary.inserted += 1
                } else {
                    summary.skipped += 1
                }
            } else {
                let p = Profile()
                p.name = incoming.name
                p.sexRaw = incoming.sexRaw
                p.ageBand = incoming.ageBand
                p.conditionRaw = incoming.conditionRaw
                p.familyHistoryRaw = incoming.familyHistoryRaw
                p.baselineStage = incoming.baselineStage
                p.createdAt = incoming.createdAt
                p.hasOnboarded = incoming.hasOnboarded
                p.wearsTightStyles = incoming.wearsTightStyles
                p.usesHeat = incoming.usesHeat
                p.usesChemicalTreatments = incoming.usesChemicalTreatments
                p.pregnancyStatusRaw = incoming.pregnancyStatusRaw
                context.insert(p)
                summary.inserted += 1
            }
        }

        // Daily entries — one per calendar day (same rule as the in-app upsert).
        var entryDays = Set(
            try context.fetch(FetchDescriptor<DailyEntry>())
                .map { HairAnalytics.dayBounds(for: $0.date, calendar: calendar).lowerBound }
        )
        for dto in envelope.entries {
            let day = HairAnalytics.dayBounds(for: dto.date, calendar: calendar).lowerBound
            guard !entryDays.contains(day) else { summary.skipped += 1; continue }
            entryDays.insert(day)
            let e = DailyEntry(date: dto.date)
            e.shedRaw = dto.shedRaw
            e.flaking = dto.flaking
            e.erythema = dto.erythema
            e.itch = dto.itch
            e.sleepQuality = dto.sleepQuality
            e.stress = dto.stress
            e.cigarettes = dto.cigarettes
            e.alcoholDrinks = dto.alcoholDrinks
            e.oiliness = dto.oiliness
            e.note = dto.note
            e.washedHair = dto.washedHair
            context.insert(e)
            summary.inserted += 1
        }

        // Treatments — matched by (name, startDate); nested doses and side effects are
        // merged into the matched (or newly created) treatment.
        var treatmentsByKey: [String: Treatment] = [:]
        for t in try context.fetch(FetchDescriptor<Treatment>()) {
            treatmentsByKey[treatmentKey(name: t.name, startDate: t.startDate)] = t
        }
        for dto in envelope.treatments {
            let key = treatmentKey(name: dto.name, startDate: dto.startDate)
            let target: Treatment
            if let existing = treatmentsByKey[key] {
                target = existing
                summary.skipped += 1
            } else {
                let t = Treatment()
                t.name = dto.name
                t.classRaw = dto.classRaw
                t.dose = dto.dose
                t.scheduleTimes = dto.scheduleTimes
                t.scheduledWeekdaysRaw = dto.scheduledWeekdaysRaw
                t.startDate = dto.startDate
                t.isActive = dto.isActive
                t.refillBy = dto.refillBy
                t.endDate = dto.endDate
                context.insert(t)
                treatmentsByKey[key] = t
                target = t
                summary.inserted += 1
            }

            var doseKeys = Set(target.doses.map { doseKey(loggedAt: $0.loggedAt, slot: $0.slot) })
            for d in dto.doses {
                let k = doseKey(loggedAt: d.loggedAt, slot: d.slot)
                guard !doseKeys.contains(k) else { summary.skipped += 1; continue }
                doseKeys.insert(k)
                context.insert(TreatmentDose(treatment: target, loggedAt: d.loggedAt, slot: d.slot))
                summary.inserted += 1
            }

            var effectKeys = Set(target.sideEffects.map { sideEffectKey(typeRaw: $0.typeRaw, date: $0.date) })
            for s in dto.sideEffects {
                let k = sideEffectKey(typeRaw: s.typeRaw, date: s.date)
                guard !effectKeys.contains(k) else { summary.skipped += 1; continue }
                effectKeys.insert(k)
                let log = SideEffectLog(treatment: target, severity: s.severity, date: s.date, note: s.note)
                log.typeRaw = s.typeRaw
                context.insert(log)
                summary.inserted += 1
            }
        }

        // Labs — (test, collectedAt).
        var labKeys = Set(
            try context.fetch(FetchDescriptor<LabResult>())
                .map { labKey(testRaw: $0.testRaw, collectedAt: $0.collectedAt) }
        )
        for dto in envelope.labs {
            let k = labKey(testRaw: dto.testRaw, collectedAt: dto.collectedAt)
            guard !labKeys.contains(k) else { summary.skipped += 1; continue }
            labKeys.insert(k)
            let lab = LabResult(value: dto.value, collectedAt: dto.collectedAt, note: dto.note,
                               refLow: dto.refLow, refHigh: dto.refHigh)
            lab.testRaw = dto.testRaw
            context.insert(lab)
            summary.inserted += 1
        }

        // Photos — (createdAt, region); the JPEG bytes go back through the photo store.
        var photoKeys = Set(
            try context.fetch(FetchDescriptor<PhotoRecord>())
                .map { photoKey(createdAt: $0.createdAt, regionRaw: $0.regionRaw) }
        )
        for dto in envelope.photos {
            let k = photoKey(createdAt: dto.createdAt, regionRaw: dto.regionRaw)
            guard !photoKeys.contains(k) else { summary.skipped += 1; continue }
            photoKeys.insert(k)
            var path = ""
            autoreleasepool {
                if let base64 = dto.imageBase64,
                   let bytes = Data(base64Encoded: base64),
                   let saved = photoWriter(bytes) {
                    path = saved
                }
            }
            if !path.isEmpty { summary.photosRestored += 1 }
            let record = PhotoRecord(imagePath: path, createdAt: dto.createdAt,
                                     lighting: dto.lighting, distance: dto.distance,
                                     parting: dto.parting, isWet: dto.isWet, note: dto.note)
            record.regionRaw = dto.regionRaw
            context.insert(record)
            summary.inserted += 1
        }

        // Health snapshots — one per calendar day.
        var snapshotDays = Set(
            try context.fetch(FetchDescriptor<HealthSnapshot>())
                .map { HairAnalytics.dayBounds(for: $0.date, calendar: calendar).lowerBound }
        )
        for dto in envelope.snapshots {
            let day = HairAnalytics.dayBounds(for: dto.date, calendar: calendar).lowerBound
            guard !snapshotDays.contains(day) else { summary.skipped += 1; continue }
            snapshotDays.insert(day)
            context.insert(HealthSnapshot(
                date: dto.date, sleepHours: dto.sleepHours, hrvSDNN: dto.hrvSDNN,
                restingHR: dto.restingHR, bodyMassKg: dto.bodyMassKg, bmi: dto.bmi,
                dietaryProteinG: dto.dietaryProteinG, updatedAt: dto.updatedAt
            ))
            summary.inserted += 1
        }

        // Triggers — (type, date).
        var triggerKeys = Set(
            try context.fetch(FetchDescriptor<TriggerEvent>())
                .map { triggerKey(typeRaw: $0.typeRaw, date: $0.date) }
        )
        for dto in envelope.triggers {
            let k = triggerKey(typeRaw: dto.typeRaw, date: dto.date)
            guard !triggerKeys.contains(k) else { summary.skipped += 1; continue }
            triggerKeys.insert(k)
            let event = TriggerEvent(date: dto.date, note: dto.note)
            event.typeRaw = dto.typeRaw
            context.insert(event)
            summary.inserted += 1
        }

        // Procedures — (type, date). The dated, irreplaceable clinic events (transplant, PRP,
        // LLLT session, etc.) a phone-loss restore must not silently drop.
        var procedureKeys = Set(
            try context.fetch(FetchDescriptor<ProcedureAppointment>())
                .map { procedureKey(typeRaw: $0.typeRaw, date: $0.date) }
        )
        for dto in envelope.procedures {
            let k = procedureKey(typeRaw: dto.typeRaw, date: dto.date)
            guard !procedureKeys.contains(k) else { summary.skipped += 1; continue }
            procedureKeys.insert(k)
            context.insert(ProcedureAppointment(
                type: ProcedureType(rawValue: dto.typeRaw) ?? .other,
                date: dto.date, location: dto.location, isCompleted: dto.isCompleted,
                completedAt: dto.completedAt, note: dto.note, createdAt: dto.createdAt
            ))
            summary.inserted += 1
        }

        // Monthly progress check-ins — one per calendar day (same rule as daily entries and
        // health snapshots).
        var checkInDays = Set(
            try context.fetch(FetchDescriptor<ProgressCheckIn>())
                .map { HairAnalytics.dayBounds(for: $0.date, calendar: calendar).lowerBound }
        )
        for dto in envelope.progressCheckIns {
            let day = HairAnalytics.dayBounds(for: dto.date, calendar: calendar).lowerBound
            guard !checkInDays.contains(day) else { summary.skipped += 1; continue }
            checkInDays.insert(day)
            context.insert(ProgressCheckIn(
                date: dto.date,
                regrowth: RegrowthLevel(rawValue: dto.regrowthRaw) ?? .none,
                density: ProgressTrend(rawValue: dto.densityRaw) ?? .same,
                shedding: ProgressTrend(rawValue: dto.sheddingRaw) ?? .same,
                hairline: ProgressTrend(rawValue: dto.hairlineRaw) ?? .same,
                overall: ProgressTrend(rawValue: dto.overallRaw) ?? .same,
                patchTrend: dto.patchTrendRaw.flatMap(ProgressTrend.init(rawValue:)),
                scalpPain: dto.scalpPain, scalpPainNote: dto.scalpPainNote,
                note: dto.note, createdAt: dto.createdAt
            ))
            summary.inserted += 1
        }

        try context.save()
        return summary
    }

    // MARK: - Natural keys (pure, unit-tested)

    /// Whole-second timestamp. The archive stores ISO8601 without fractional seconds, so
    /// matching at second granularity keeps a restored record equal to its on-device
    /// original (whose `Date` may carry sub-second precision).
    static func secondKey(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    static func treatmentKey(name: String, startDate: Date) -> String {
        "\(name)|\(secondKey(startDate))"
    }

    static func doseKey(loggedAt: Date, slot: String) -> String {
        "\(secondKey(loggedAt))|\(slot)"
    }

    static func sideEffectKey(typeRaw: String, date: Date) -> String {
        "\(typeRaw)|\(secondKey(date))"
    }

    static func labKey(testRaw: String, collectedAt: Date) -> String {
        "\(testRaw)|\(secondKey(collectedAt))"
    }

    static func photoKey(createdAt: Date, regionRaw: String) -> String {
        "\(secondKey(createdAt))|\(regionRaw)"
    }

    static func triggerKey(typeRaw: String, date: Date) -> String {
        "\(typeRaw)|\(secondKey(date))"
    }

    static func procedureKey(typeRaw: String, date: Date) -> String {
        "\(typeRaw)|\(secondKey(date))"
    }

    /// A profile that has never been filled in: no name, never onboarded. Only such a
    /// profile takes the backup's fields; anything the user has touched is kept.
    static func isDefaultProfile(_ profile: Profile) -> Bool {
        profile.name.trimmingCharacters(in: .whitespaces).isEmpty && !profile.hasOnboarded
    }
}
