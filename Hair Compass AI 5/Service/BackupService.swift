import Foundation
import ImageIO
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

    nonisolated static let currentVersion = 1

    /// Auditable contract: every SwiftData model is represented, and treatment ownership is
    /// preserved by nesting. Unattached relationship records have dedicated arrays below.
    static let manifest = [
        "Profile", "DailyEntry", "Treatment", "TreatmentDose → Treatment?", "MissedDoseRecord → Treatment?",
        "SideEffectLog → Treatment?", "LabResult", "PhotoRecord", "HealthSnapshot",
        "TriggerEvent", "ProcedureAppointment", "ProgressCheckIn", "AgentMemory"
    ]

    // MARK: - Errors

    nonisolated enum BackupError: LocalizedError, Equatable, Sendable {
        case unsupportedVersion(Int)
        case unreadableFile
        case missingPhotoFiles([String])
        case invalidPhotoData

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "This backup uses a newer format (v\(v)) than this app understands. Update Hair Compass, then try again."
            case .unreadableFile:
                return "That file doesn't look like a Hair Compass backup."
            case .missingPhotoFiles(let paths):
                return "Backup stopped because \(paths.count) photo file(s) are missing. No incomplete backup was created."
            case .invalidPhotoData:
                return "A photo in this backup is not valid image data. Nothing from that photo was written."
            }
        }
    }

    // MARK: - The archive envelope (version 1)

    /// Codable mirror of the whole store. Enum raw values are stored as-is; dates are
    /// ISO8601 (whole seconds). Doses and side effects are nested inside their treatment
    /// so relationships survive the round trip.
    nonisolated struct Envelope: Codable, Sendable {
        var version: Int = currentVersion
        var createdAt: Date = .now
        var appVersion: String = AppInfo.version
        var profile: ProfileDTO?
        var entries: [EntryDTO] = []
        var treatments: [TreatmentDTO] = []
        var unattachedDoses: [DoseDTO]?
        var unattachedMissedDoses: [MissedDoseDTO]?
        var unattachedSideEffects: [SideEffectDTO]?
        var labs: [LabDTO] = []
        var photos: [PhotoDTO] = []
        var snapshots: [SnapshotDTO] = []
        var triggers: [TriggerDTO] = []
        // Added after v1 shipped — Codable arrays default to empty, so older backup files
        // (which never wrote these keys) still decode cleanly with no procedures/check-ins,
        // rather than failing the whole restore.
        var procedures: [ProcedureDTO] = []
        var progressCheckIns: [ProgressCheckInDTO] = []
        var agentMemories: [AgentMemoryDTO] = []
    }

    /// What the agent has learned about the person. Included in the archive because it is the
    /// user's own data and lives only on the device — omitting it makes "restore your backup"
    /// quietly lossy. `forgottenAt` travels with it: a tombstone that didn't survive the round
    /// trip would resurrect something the person explicitly asked the agent to forget.
    nonisolated struct AgentMemoryDTO: Codable, Sendable {
        var scopeRaw = AgentMemoryScope.session.rawValue
        var sessionID = ""
        var text = ""
        var kindRaw = AgentMemoryKind.fact.rawValue
        var createdAt = Date.now
        var lastRecalledAt: Date?
        var recallCount = 0
        var forgottenAt: Date?
    }

    nonisolated struct ProfileDTO: Codable, Sendable {
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

    nonisolated struct EntryDTO: Codable, Sendable {
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
        /// Optional by design: nil keeps the legacy all-fields interpretation when importing an
        /// older backup; a present empty string preserves a note-only/explicitly skipped log.
        var recordedSignalsRaw: String?
    }

    nonisolated struct TreatmentDTO: Codable, Sendable {
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
        /// Added to v1 after launch. Missing keys in older archives decode as nil.
        var ingredientImageBase64: String?
        var aiIngredientSummary: String?
        var doses: [DoseDTO] = []
        var missedDoses: [MissedDoseDTO]?
        var sideEffects: [SideEffectDTO] = []
    }

    nonisolated struct DoseDTO: Codable, Sendable {
        var loggedAt = Date.now
        var slot = ""
    }

    nonisolated struct MissedDoseDTO: Codable, Sendable {
        var date = Date.now
        var slot = ""
        var reasonRaw = MissedDoseReason.forgot.rawValue
    }

    nonisolated struct SideEffectDTO: Codable, Sendable {
        var date = Date.now
        var severity = 1
        var typeRaw = ""
        var note = ""
    }

    nonisolated struct LabDTO: Codable, Sendable {
        var testRaw = ""
        var value = 0.0
        var collectedAt = Date.now
        var note = ""
        // Defaulted so older backups (without the field) still decode to "no override" — the
        // built-in default range applies, exactly as before this existed.
        var refLow: Double?
        var refHigh: Double?
    }

    nonisolated struct PhotoDTO: Codable, Sendable {
        var regionRaw = ""
        var createdAt = Date.now
        var lighting = ""
        var distance = ""
        var parting = ""
        var isWet = false
        var note = ""
        var patchSeriesLabel: String?
        var babyHairsNoticed: Bool?
        /// The JPEG bytes, base64. nil when the original file was already missing on disk.
        var imageBase64: String?
    }

    nonisolated struct SnapshotDTO: Codable, Sendable {
        var date = Date.now
        var sleepHours: Double?
        var hrvSDNN: Double?
        var restingHR: Double?
        var bodyMassKg: Double?
        var bmi: Double?
        var dietaryProteinG: Double?
        var updatedAt = Date.now
    }

    nonisolated struct TriggerDTO: Codable, Sendable {
        var typeRaw = ""
        var date = Date.now
        var note = ""
    }

    /// In-office / clinic events (transplant, PRP, LLLT session, etc.) — the dated,
    /// irreplaceable records a lost-phone restore must not silently drop.
    nonisolated struct ProcedureDTO: Codable, Sendable {
        var typeRaw = ""
        var date = Date.now
        var location = ""
        var isCompleted = false
        var completedAt: Date?
        var note = ""
        var createdAt = Date.now
        var agendaMainConcern: String?
        var agendaChangedWhen: String?
        var agendaTreatmentsToReview: String?
        var agendaSafetyConcerns: String?
        var agendaQuestionsRaw: String?
    }

    /// Monthly self-reported regrowth/density/shedding/hairline/overall check-in, including
    /// the scalp-pain red flag.
    nonisolated struct ProgressCheckInDTO: Codable, Sendable {
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
        var hairFeelingRaw: Int?
        var hairFeelingNote: String?
    }

    private struct VersionProbe: Codable { let version: Int }

    // MARK: - Export

    /// Snapshot the fetched records into an envelope. `photoData` supplies the raw stored
    /// JPEG bytes for a relative path (injected so tests never touch the real photo store).
    static func makeEnvelope(
        profile: Profile?,
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        sideEffects: [SideEffectLog],
        labs: [LabResult],
        photos: [PhotoRecord],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        procedures: [ProcedureAppointment],
        progressCheckIns: [ProgressCheckIn],
        missedDoses: [MissedDoseRecord] = [],
        agentMemories: [AgentMemory] = [],
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
                     washedHair: $0.washedHair, recordedSignalsRaw: $0.recordedSignalsRaw)
        }

        envelope.treatments = treatments.map { t in
            TreatmentDTO(
                name: t.name, classRaw: t.classRaw, dose: t.dose,
                scheduleTimes: t.scheduleTimes, scheduledWeekdaysRaw: t.scheduledWeekdaysRaw,
                startDate: t.startDate,
                isActive: t.isActive, refillBy: t.refillBy, endDate: t.endDate,
                ingredientImageBase64: t.ingredientPhotoPath.isEmpty
                    ? nil
                    : photoData(t.ingredientPhotoPath)?.base64EncodedString(),
                aiIngredientSummary: t.aiIngredientSummary,
                doses: t.doses
                    .sorted { $0.loggedAt < $1.loggedAt }
                    .map { DoseDTO(loggedAt: $0.loggedAt, slot: $0.slot) },
                missedDoses: t.missedDoses
                    .sorted { $0.date < $1.date }
                    .map { MissedDoseDTO(date: $0.date, slot: $0.slot, reasonRaw: $0.reasonRaw) },
                sideEffects: t.sideEffects
                    .sorted { $0.date < $1.date }
                    .map { SideEffectDTO(date: $0.date, severity: $0.severity, typeRaw: $0.typeRaw, note: $0.note) }
            )
        }
        envelope.unattachedDoses = doses.filter { $0.treatment == nil }
            .map { DoseDTO(loggedAt: $0.loggedAt, slot: $0.slot) }
        envelope.unattachedMissedDoses = missedDoses.filter { $0.treatment == nil }
            .map { MissedDoseDTO(date: $0.date, slot: $0.slot, reasonRaw: $0.reasonRaw) }
        envelope.unattachedSideEffects = sideEffects.filter { $0.treatment == nil }
            .map { SideEffectDTO(date: $0.date, severity: $0.severity, typeRaw: $0.typeRaw, note: $0.note) }

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
                    patchSeriesLabel: record.region == .patch ? record.normalizedPatchSeriesLabel : nil,
                    babyHairsNoticed: record.babyHairsNoticed,
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
                         note: $0.note, createdAt: $0.createdAt,
                         agendaMainConcern: $0.agendaMainConcern,
                         agendaChangedWhen: $0.agendaChangedWhen,
                         agendaTreatmentsToReview: $0.agendaTreatmentsToReview,
                         agendaSafetyConcerns: $0.agendaSafetyConcerns,
                         agendaQuestionsRaw: $0.agendaQuestionsRaw)
        }

        envelope.progressCheckIns = progressCheckIns.map {
            ProgressCheckInDTO(
                date: $0.date, regrowthRaw: $0.regrowthRaw, densityRaw: $0.densityRaw,
                sheddingRaw: $0.sheddingRaw, hairlineRaw: $0.hairlineRaw, overallRaw: $0.overallRaw,
                patchTrendRaw: $0.patchTrendRaw,
                scalpPain: $0.scalpPain, scalpPainNote: $0.scalpPainNote, note: $0.note,
                createdAt: $0.createdAt, hairFeelingRaw: $0.hairFeelingRaw,
                hairFeelingNote: $0.hairFeelingNote
            )
        }

        envelope.agentMemories = agentMemories.map {
            AgentMemoryDTO(
                scopeRaw: $0.scopeRaw, sessionID: $0.sessionID, text: $0.text,
                kindRaw: $0.kindRaw, createdAt: $0.createdAt,
                lastRecalledAt: $0.lastRecalledAt, recallCount: $0.recallCount,
                forgottenAt: $0.forgottenAt
            )
        }

        return envelope
    }

    // `nonisolated` (this module defaults unannotated declarations to the main actor) so
    // `exportBackupAsync`'s background task can JSON-encode without hopping back to whichever
    // actor called it — encoding the full archive is itself non-trivial once photos are in it.
    nonisolated static func encode(_ envelope: Envelope) throws -> Data {
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
        doses: [TreatmentDose],
        sideEffects: [SideEffectLog],
        labs: [LabResult],
        photos: [PhotoRecord],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        procedures: [ProcedureAppointment],
        progressCheckIns: [ProgressCheckIn],
        missedDoses: [MissedDoseRecord] = [],
        agentMemories: [AgentMemory] = [],
        now: Date = .now,
        photoData: (String) -> Data? = { PhotoStore.shared.loadData($0) }
    ) throws -> URL {
        let envelope = makeEnvelope(
            profile: profile, entries: entries, treatments: treatments, doses: doses,
            sideEffects: sideEffects, labs: labs,
            photos: photos, snapshots: snapshots, triggers: triggers,
            procedures: procedures, progressCheckIns: progressCheckIns,
            missedDoses: missedDoses, agentMemories: agentMemories,
            createdAt: now, photoData: photoData
        )
        var missingPhotos = zip(photos, envelope.photos).compactMap { record, dto in
            !record.imagePath.isEmpty && dto.imageBase64 == nil ? record.imagePath : nil
        }
        missingPhotos += zip(treatments, envelope.treatments).compactMap { treatment, dto in
            !treatment.ingredientPhotoPath.isEmpty && dto.ingredientImageBase64 == nil
                ? treatment.ingredientPhotoPath : nil
        }
        guard missingPhotos.isEmpty else { throw BackupError.missingPhotoFiles(missingPhotos) }
        let data = try encode(envelope)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HairCompass-Backup-\(formatter.string(from: now)).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Off-main variant of `exportBackup`. A year of 5-region photos base64-encoded into one
    /// JSON string is genuinely hundreds of MB of string building — real work, not just a
    /// long-running call — so unlike `exportBackup` this never runs it on the caller's actor.
    ///
    /// `makeEnvelope` still runs here, on the caller's actor, but with `photoData: { _ in nil }`
    /// so it never touches a photo's bytes — it's cheap even with hundreds of records because
    /// it only reads SwiftData model properties, which is exactly the part that must stay on
    /// the caller's actor (`Profile`/`DailyEntry`/etc. are not `Sendable` and can't cross the
    /// hop). Only the plain `imagePath` strings are extracted for the background task; the
    /// `Envelope` and its DTOs are plain `Sendable` value types, so nothing SwiftData-owned
    /// crosses the actor boundary.
    static func exportBackupAsync(
        profile: Profile?,
        entries: [DailyEntry],
        treatments: [Treatment],
        doses: [TreatmentDose],
        sideEffects: [SideEffectLog],
        labs: [LabResult],
        photos: [PhotoRecord],
        snapshots: [HealthSnapshot],
        triggers: [TriggerEvent],
        procedures: [ProcedureAppointment],
        progressCheckIns: [ProgressCheckIn],
        missedDoses: [MissedDoseRecord] = [],
        agentMemories: [AgentMemory] = [],
        now: Date = .now,
        photoData: @Sendable @escaping (String) -> Data? = { PhotoStore.shared.loadData($0) }
    ) async throws -> URL {
        let envelope = makeEnvelope(
            profile: profile, entries: entries, treatments: treatments, doses: doses,
            sideEffects: sideEffects, labs: labs,
            photos: photos, snapshots: snapshots, triggers: triggers,
            procedures: procedures, progressCheckIns: progressCheckIns,
            missedDoses: missedDoses, agentMemories: agentMemories,
            createdAt: now, photoData: { _ in nil }
        )
        // Same order as `envelope.photos` (both come from mapping `photos` in order), so the
        // background task can splice byte-loaded base64 back into the right DTO by index
        // without needing the `PhotoRecord`s themselves.
        let imagePaths = photos.map(\.imagePath)
        let ingredientImagePaths = treatments.map(\.ingredientPhotoPath)

        return try await Task.detached(priority: .userInitiated) {
            try finishExportOffMain(envelope: envelope, imagePaths: imagePaths,
                                    ingredientImagePaths: ingredientImagePaths,
                                    now: now, photoData: photoData)
        }.value
    }

    /// The actual expensive work: read every photo's JPEG bytes off disk, base64-encode them
    /// into the envelope, JSON-encode the whole archive and write the temp file. `nonisolated`
    /// so it genuinely runs on the detached task's background thread instead of hopping back to
    /// the main actor (this module defaults unannotated declarations to the main actor).
    /// `photoData` is injected (defaulting to the real `PhotoStore`) so tests never touch disk,
    /// same reasoning as `makeEnvelope`'s own `photoData` parameter.
    nonisolated private static func finishExportOffMain(
        envelope: Envelope, imagePaths: [String], ingredientImagePaths: [String],
        now: Date, photoData: (String) -> Data?
    ) throws -> URL {
        var envelope = envelope
        var missingPhotos: [String] = []
        // One photo at a time inside an autorelease pool, so the transient JPEG buffers are
        // reclaimed between iterations instead of piling up (same reasoning as `makeEnvelope`).
        for (index, path) in imagePaths.enumerated() {
            guard !path.isEmpty else { continue }
            autoreleasepool {
                if let data = photoData(path) {
                    envelope.photos[index].imageBase64 = data.base64EncodedString()
                } else {
                    missingPhotos.append(path)
                }
            }
        }
        for (index, path) in ingredientImagePaths.enumerated() {
            guard !path.isEmpty else { continue }
            autoreleasepool {
                if let data = photoData(path) {
                    envelope.treatments[index].ingredientImageBase64 = data.base64EncodedString()
                } else {
                    missingPhotos.append(path)
                }
            }
        }
        guard missingPhotos.isEmpty else { throw BackupError.missingPhotoFiles(missingPhotos) }
        let data = try encode(envelope)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HairCompass-Backup-\(formatter.string(from: now)).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
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
        return try restore(envelope, into: context,
                           photoWriter: { PhotoStore.shared.stageData($0) },
                           photoRemover: { PhotoStore.shared.deleteStagedData($0) },
                           photoCommitter: { try PhotoStore.shared.commitStagedData($0) },
                           finalizedPhotoRemover: { PhotoStore.shared.delete($0) })
    }

    /// Merge-safe upsert of a decoded envelope. Nothing is ever deleted; records that
    /// already exist (matched by natural key) are skipped and counted.
    ///
    /// Natural keys:
    /// - DailyEntry: calendar day (`HairAnalytics.dayBounds` — one entry per day)
    /// - Treatment: (name, startDate); its doses by (calendar day, slot), missed doses by
    ///   (treatment, calendar day, reason), and side effects by (type, date)
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
        photoWriter: (Data) -> String?,
        photoRemover: (String) -> Void = { _ in },
        photoCommitter: (String) throws -> Void = { _ in },
        finalizedPhotoRemover: (String) -> Void = { _ in },
        databaseSaver: (() throws -> Void)? = nil
    ) throws -> RestoreSummary {
        // Intentionally remains outside the repositories in this pass. Restore already owns an
        // atomic staged-file/database rollback; it is the last planned persistence migration.
        // Decode and validate the complete payload before touching either persistence layer.
        // In particular, a corrupt image at the end cannot arrive after earlier files/rows.
        let preparedTreatmentImages = try envelope.treatments.map {
            try validatedImageData($0.ingredientImageBase64)
        }
        let preparedPhotos = try envelope.photos.map { try validatedImageData($0.imageBase64) }
        try validateRawValues(in: envelope)

        // The injected writer is the file-store staging boundary. Keep every returned path so
        // any later writer/database failure can remove the whole staged set. Bytes are only
        // written for records that are actually being inserted — staging happens lazily at each
        // insert site so re-restoring the same payload never rewrites files for skipped duplicates.
        var stagedPaths: [String] = []
        func stage(_ data: Data?) throws -> String {
            guard let data else { return "" }
            guard let path = photoWriter(data) else { throw BackupError.invalidPhotoData }
            stagedPaths.append(path)
            return path
        }

        do {
        var summary = RestoreSummary()
        var committedPaths = Set<String>()
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
            e.recordedSignalsRaw = dto.recordedSignalsRaw
            context.insert(e)
            summary.inserted += 1
        }

        // Treatments — matched by (name, startDate); nested doses and side effects are
        // merged into the matched (or newly created) treatment.
        var treatmentsByKey: [String: Treatment] = [:]
        for t in try context.fetch(FetchDescriptor<Treatment>()) {
            treatmentsByKey[treatmentKey(name: t.name, startDate: t.startDate)] = t
        }
        for (treatmentIndex, dto) in envelope.treatments.enumerated() {
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
                t.ingredientPhotoPath = try stage(preparedTreatmentImages[treatmentIndex])
                if !t.ingredientPhotoPath.isEmpty { committedPaths.insert(t.ingredientPhotoPath) }
                t.aiIngredientSummary = dto.aiIngredientSummary ?? ""
                context.insert(t)
                treatmentsByKey[key] = t
                target = t
                summary.inserted += 1
            }

            var doseKeys = Set(target.doses.map {
                doseKey(loggedAt: $0.loggedAt, slot: $0.slot, calendar: calendar)
            })
            for d in dto.doses {
                let k = doseKey(loggedAt: d.loggedAt, slot: d.slot, calendar: calendar)
                guard !doseKeys.contains(k) else { summary.skipped += 1; continue }
                doseKeys.insert(k)
                context.insert(TreatmentDose(treatment: target, loggedAt: d.loggedAt, slot: d.slot))
                summary.inserted += 1
            }

            var missedKeys = Set(target.missedDoses.map {
                missedDoseKey(date: $0.date, reasonRaw: $0.reasonRaw, calendar: calendar)
            })
            for missed in dto.missedDoses ?? [] {
                let key = missedDoseKey(date: missed.date, reasonRaw: missed.reasonRaw, calendar: calendar)
                guard !missedKeys.contains(key) else { summary.skipped += 1; continue }
                missedKeys.insert(key)
                let record = MissedDoseRecord(treatment: target, date: missed.date, slot: missed.slot)
                record.reasonRaw = missed.reasonRaw
                context.insert(record)
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

        var unattachedDoseKeys = Set(
            try context.fetch(FetchDescriptor<TreatmentDose>())
                .filter { $0.treatment == nil }
                .map { doseKey(loggedAt: $0.loggedAt, slot: $0.slot, calendar: calendar) }
        )
        for dto in envelope.unattachedDoses ?? [] {
            let key = doseKey(loggedAt: dto.loggedAt, slot: dto.slot, calendar: calendar)
            guard !unattachedDoseKeys.contains(key) else { summary.skipped += 1; continue }
            unattachedDoseKeys.insert(key)
            context.insert(TreatmentDose(loggedAt: dto.loggedAt, slot: dto.slot))
            summary.inserted += 1
        }
        for dto in envelope.unattachedSideEffects ?? [] {
            let log = SideEffectLog(severity: dto.severity, date: dto.date, note: dto.note)
            log.typeRaw = dto.typeRaw
            context.insert(log)
            summary.inserted += 1
        }
        var unattachedMissedKeys = Set(
            try context.fetch(FetchDescriptor<MissedDoseRecord>())
                .filter { $0.treatment == nil }
                .map { missedDoseKey(date: $0.date, reasonRaw: $0.reasonRaw, calendar: calendar) }
        )
        for dto in envelope.unattachedMissedDoses ?? [] {
            let key = missedDoseKey(date: dto.date, reasonRaw: dto.reasonRaw, calendar: calendar)
            guard !unattachedMissedKeys.contains(key) else { summary.skipped += 1; continue }
            unattachedMissedKeys.insert(key)
            let record = MissedDoseRecord(date: dto.date, slot: dto.slot)
            record.reasonRaw = dto.reasonRaw
            context.insert(record)
            summary.inserted += 1
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
        for (photoIndex, dto) in envelope.photos.enumerated() {
            let k = photoKey(createdAt: dto.createdAt, regionRaw: dto.regionRaw)
            guard !photoKeys.contains(k) else { summary.skipped += 1; continue }
            photoKeys.insert(k)
            let path = try stage(preparedPhotos[photoIndex])
            if !path.isEmpty { committedPaths.insert(path) }
            if !path.isEmpty { summary.photosRestored += 1 }
            let record = PhotoRecord(imagePath: path, createdAt: dto.createdAt,
                                     lighting: dto.lighting, distance: dto.distance,
                                     parting: dto.parting, isWet: dto.isWet, note: dto.note,
                                     patchSeriesLabel: dto.patchSeriesLabel ?? "",
                                     babyHairsNoticed: dto.babyHairsNoticed ?? false)
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
                completedAt: dto.completedAt, note: dto.note, createdAt: dto.createdAt,
                agendaMainConcern: dto.agendaMainConcern ?? "",
                agendaChangedWhen: dto.agendaChangedWhen ?? "",
                agendaTreatmentsToReview: dto.agendaTreatmentsToReview ?? "",
                agendaSafetyConcerns: dto.agendaSafetyConcerns ?? "",
                agendaQuestions: (dto.agendaQuestionsRaw ?? "").split(separator: "\n").map(String.init)
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
                note: dto.note, createdAt: dto.createdAt,
                hairFeeling: dto.hairFeelingRaw.flatMap(HairFeeling.init(rawValue:)) ?? .unspecified,
                hairFeelingNote: dto.hairFeelingNote ?? ""
            ))
            summary.inserted += 1
        }

        var memoryKeys = Set(
            try context.fetch(FetchDescriptor<AgentMemory>())
                .map { agentMemoryKey(sessionID: $0.sessionID, text: $0.text, createdAt: $0.createdAt) }
        )
        for dto in envelope.agentMemories {
            let key = agentMemoryKey(sessionID: dto.sessionID, text: dto.text, createdAt: dto.createdAt)
            guard !memoryKeys.contains(key) else { summary.skipped += 1; continue }
            memoryKeys.insert(key)
            let memory = AgentMemory(
                scope: AgentMemoryScope(rawValue: dto.scopeRaw) ?? .session,
                sessionID: dto.sessionID,
                text: dto.text,
                kind: AgentMemoryKind(rawValue: dto.kindRaw) ?? .fact,
                createdAt: dto.createdAt
            )
            // Recall history and the forget tombstone are restored rather than reset: they are
            // what consolidation ranks by, and what keeps a forgotten memory forgotten.
            memory.lastRecalledAt = dto.lastRecalledAt
            memory.recallCount = dto.recallCount
            memory.forgottenAt = dto.forgottenAt
            context.insert(memory)
            summary.inserted += 1
        }

        let pathsToCommit = stagedPaths.filter { committedPaths.contains($0) }
        stagedPaths.filter { !committedPaths.contains($0) }.forEach(photoRemover)
        var finalizedPaths: [String] = []
        do {
            for path in pathsToCommit {
                try photoCommitter(path)
                finalizedPaths.append(path)
            }
        } catch {
            finalizedPaths.forEach(finalizedPhotoRemover)
            pathsToCommit.dropFirst(finalizedPaths.count).forEach(photoRemover)
            throw error
        }
        do {
            if let databaseSaver { try databaseSaver() } else { try context.save() }
        } catch {
            finalizedPaths.forEach(finalizedPhotoRemover)
            throw error
        }
        return summary
        } catch {
            context.rollback()
            stagedPaths.forEach(photoRemover)
            throw error
        }
    }

    private static func validatedImageData(_ base64: String?) throws -> Data? {
        guard let base64 else { return nil }
        guard let bytes = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw BackupError.invalidPhotoData
        }
        return bytes
    }

    /// Reject unknown enum encodings up front rather than silently coercing a partial restore.
    private static func validateRawValues(in envelope: Envelope) throws {
        let valid =
            envelope.profile.map {
                BiologicalSex(rawValue: $0.sexRaw) != nil
                    && HairCondition(rawValue: $0.conditionRaw) != nil
                    && FamilyHistory(rawValue: $0.familyHistoryRaw) != nil
                    && PregnancyStatus(rawValue: $0.pregnancyStatusRaw) != nil
            } ?? true
            && envelope.entries.allSatisfy { ShedLevel(rawValue: $0.shedRaw) != nil }
            && envelope.treatments.allSatisfy {
                TreatmentClass(rawValue: $0.classRaw) != nil
                    && ($0.missedDoses ?? []).allSatisfy { MissedDoseReason(rawValue: $0.reasonRaw) != nil }
                    && $0.sideEffects.allSatisfy { SideEffectType(rawValue: $0.typeRaw) != nil }
            }
            && (envelope.unattachedMissedDoses ?? []).allSatisfy {
                MissedDoseReason(rawValue: $0.reasonRaw) != nil
            }
            && (envelope.unattachedSideEffects ?? []).allSatisfy {
                SideEffectType(rawValue: $0.typeRaw) != nil
            }
            && envelope.labs.allSatisfy { LabTest(rawValue: $0.testRaw) != nil }
            && envelope.photos.allSatisfy { PhotoRegion(rawValue: $0.regionRaw) != nil }
            && envelope.triggers.allSatisfy { TriggerType(rawValue: $0.typeRaw) != nil }
            && envelope.procedures.allSatisfy { ProcedureType(rawValue: $0.typeRaw) != nil }
            && envelope.progressCheckIns.allSatisfy {
                RegrowthLevel(rawValue: $0.regrowthRaw) != nil
                    && ProgressTrend(rawValue: $0.densityRaw) != nil
                    && ProgressTrend(rawValue: $0.sheddingRaw) != nil
                    && ProgressTrend(rawValue: $0.hairlineRaw) != nil
                    && ProgressTrend(rawValue: $0.overallRaw) != nil
                    && ($0.patchTrendRaw == nil || ProgressTrend(rawValue: $0.patchTrendRaw!) != nil)
                    && ($0.hairFeelingRaw == nil || HairFeeling(rawValue: $0.hairFeelingRaw!) != nil)
            }
            && envelope.agentMemories.allSatisfy {
                AgentMemoryScope(rawValue: $0.scopeRaw) != nil
                    && AgentMemoryKind(rawValue: $0.kindRaw) != nil
            }
        guard valid else { throw BackupError.unreadableFile }
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

    static func doseKey(
        loggedAt: Date,
        slot: String,
        calendar: Calendar = .current
    ) -> String {
        let day = HairAnalytics.dayBounds(for: loggedAt, calendar: calendar).lowerBound
        return "\(secondKey(day))|\(slot)"
    }

    static func sideEffectKey(typeRaw: String, date: Date) -> String {
        "\(typeRaw)|\(secondKey(date))"
    }

    static func missedDoseKey(date: Date, reasonRaw: String, calendar: Calendar) -> String {
        "\(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate)|\(reasonRaw)"
    }

    /// Natural key for a memory: which conversation wrote it, its exact words, and when. Two
    /// memories with the same text in the same conversation a second apart are genuinely two
    /// memories; the same one restored twice is not.
    static func agentMemoryKey(sessionID: String, text: String, createdAt: Date) -> String {
        "\(sessionID)|\(text)|\(secondKey(createdAt))"
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
