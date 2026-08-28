import SwiftData
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

/// One-time baseline capture — the highest-value fields (family history, condition) up front.
/// Also reused as the editable profile from the Today header.
struct BaselineFlow: View {
    @Bindable var profile: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLockService.self) private var appLock
    /// Owned here rather than injected app-wide: nothing else reads it yet, because nothing acts
    /// on it yet. Promote to an `@Environment` service when a contribution pipeline actually exists.
    @State private var researchConsent = ResearchConsent()
    // Read only to build the contribution preview, so the person sees their real numbers rather
    // than a mock-up of them.
    @Query(sort: \DailyEntry.date) private var researchEntries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var researchTreatments: [Treatment]
    @Query private var researchLabs: [LabResult]
    @Query private var researchTriggers: [TriggerEvent]
    @Environment(PurchaseService.self) private var purchases
    @State private var replayOnboarding = false
    @State private var showManageSubscriptions = false

    private let ageBands = ["Under 25", "26–35", "36–45", "46–55", "56+"]

    /// Built with `consentGiven: true` regardless of the live toggle — this is the *preview*, and
    /// someone deciding whether to opt in has to be able to see what they'd be agreeing to before
    /// they agree. Nothing is transmitted either way; the real pipeline, when it exists, must read
    /// the actual consent state.
    private var researchPayload: ResearchPayload? {
        ResearchAggregator.build(
            consentGiven: true,
            consentTermsVersion: ResearchConsent.currentTermsVersion,
            profile: profile,
            entries: researchEntries,
            treatments: researchTreatments,
            hasLabs: !researchLabs.isEmpty,
            hasTriggers: !researchTriggers.isEmpty
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    intro

                    replayRow

                    field("Your name") {
                        TextField("Name", text: $profile.name)
                            .textFieldStyle(.plain)
                            .font(Clinical.caption(16))
                            .padding(12)
                            .background(Clinical.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                            .accessibilityIdentifier("baselineName")
                    }

                    field("Biological sex") {
                        ClinicalSegmented(options: BiologicalSex.allCases, label: { $0.title }, selection: $profile.sex)
                        Text("Sets the staging scale: \(profile.sex.stagingScaleName).")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Age") {
                        chips(ageBands, selected: profile.ageBand) { profile.ageBand = $0 }
                    }

                    if profile.sex == .female {
                        field("Pregnancy") {
                            let opts: [PregnancyStatus] = [.no, .pregnant, .tryingToConceive, .breastfeeding, .unspecified]
                            chips(opts.map(\.title), selected: profile.pregnancyStatus.title) { title in
                                if let match = opts.first(where: { $0.title == title }) { profile.pregnancyStatus = match }
                            }
                            Text("Lets the plan flag medications usually avoided in or around pregnancy. Stays private to your device.")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        }
                    }

                    field("What are you tracking?") {
                        VStack(spacing: 8) {
                            ForEach(HairCondition.allCases) { c in
                                conditionRow(c)
                            }
                        }
                    }

                    field("Family history of hair loss") {
                        chips(FamilyHistory.allCases.map(\.title), selected: profile.familyHistory.title) { title in
                            if let match = FamilyHistory.allCases.first(where: { $0.title == title }) {
                                profile.familyHistory = match
                            }
                        }
                        Text("The single strongest measured risk factor for pattern loss.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Hair-care practices") {
                        VStack(spacing: 10) {
                            practiceToggle("Tight styles (braids, ponytails, extensions)", isOn: $profile.wearsTightStyles)
                            practiceToggle("Regular heat styling", isOn: $profile.usesHeat)
                            practiceToggle("Chemical treatments (relaxers, dyes, perms)", isOn: $profile.usesChemicalTreatments)
                        }
                        Text("Sustained tension, heat and chemicals cause traction alopecia — preventable and reversible early.")
                            .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Baseline stage (optional)") {
                        TextField("e.g. \(profile.sex.stagingScaleName) III", text: $profile.baselineStage)
                            .textFieldStyle(.plain)
                            .font(Clinical.caption(16))
                            .padding(12)
                            .background(Clinical.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                    }

                    Button("Save baseline", action: complete)
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(profile.name.trimmingCharacters(in: .whitespaces).count < 2)
                        .opacity(profile.name.trimmingCharacters(in: .whitespaces).count < 2 ? 0.5 : 1)
                        .accessibilityIdentifier("baselineSave")

                    privacySection

                    ResearchConsentSection(consent: researchConsent, payload: researchPayload)

                    if purchases.hasPro {
                        subscriptionSection
                    }

                    StrandDivider()

                    BackupRestoreSection()

                    FeedbackSection()

                    aboutFooter
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .clinicalScreen()
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .navigationTitle("Baseline")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $replayOnboarding) {
                OnboardingFlow(profile: profile,
                               onFinish: { replayOnboarding = false },
                               onDismiss: { replayOnboarding = false })
            }
            .toolbar {
                if profile.hasOnboarded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { complete() }
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(BrandArt.baselineHero)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Set up once")
                Text("A few facts that shape everything")
                    .font(Clinical.headline(26))
                    .foregroundStyle(Clinical.ink)
                Text("These are the signals a dermatologist weighs first. You'll only set them once.")
                    .font(Clinical.caption(14))
                    .foregroundStyle(Clinical.secondary)
            }
        }
    }

    /// This row was already the medallion-and-chevron shape by hand; `BrandNavRow` is that shape
    /// named, so the two stay in step instead of drifting. It stays a *card* — unlike Plan's
    /// ledger headers, which Round-9 deliberately de-chromed — because this is a standalone
    /// destination inside a form, not a section heading in a ledger.
    private var replayRow: some View {
        BrandNavRow(
            symbol: "sparkles",
            title: "Replay the walkthrough",
            line: "Revisit the animated intro anytime"
        ) { replayOnboarding = true }
        .accessibilityIdentifier("replayOnboarding")
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            content()
        }
    }

    private func conditionRow(_ c: HairCondition) -> some View {
        let on = profile.condition == c
        return Button {
            profile.condition = c
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(Clinical.caption(20))
                    .foregroundStyle(on ? Clinical.accent : Clinical.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(Clinical.body(15, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text(c.summary).font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(on ? Clinical.accentSoft : Clinical.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Clinical.accent.opacity(0.4) : Clinical.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("condition_\(c.rawValue)")
    }

    private func chips(_ items: [String], selected: String, onPick: @escaping (String) -> Void) -> some View {
        FlowChips(items: items, selected: selected, onPick: onPick)
    }

    /// Privacy controls: App Lock (Face ID / passcode). All AI runs on-device now, so there is no
    /// off-device data consent to manage — the app simply keeps everything on the phone.
    private var privacySection: some View {
        @Bindable var appLock = appLock
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Privacy")

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $appLock.isEnabled) {
                    Text("Require Face ID to open")
                        .font(Clinical.body(15, weight: .medium))
                        .foregroundStyle(appLock.canUseLock ? Clinical.ink : Clinical.tertiary)
                }
                .tint(Clinical.accent)
                .disabled(!appLock.canUseLock)
                .accessibilityIdentifier("appLockToggle")
                Text(appLock.canUseLock
                     ? "Locks Hair Compass when you leave it. Uses your device's Face ID or passcode."
                     : "Unavailable — this device has no Face ID, Touch ID or passcode set up.")
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)

                Divider().overlay(Clinical.hairline)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.iphone")
                        .font(Clinical.caption(14)).foregroundStyle(Clinical.accent)
                        .frame(width: 20)
                    Text("Everything stays on your device. Your records, photos and the AI features all run on-device — nothing is uploaded to any server.")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                }
            }
            .padding(14)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Hair Compass Pro")
            Button {
                showManageSubscriptions = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(Clinical.caption(15))
                        .foregroundStyle(Clinical.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage subscription")
                            .font(Clinical.body(15, weight: .semibold))
                            .foregroundStyle(Clinical.ink)
                        Text("View your plan or change and cancel it in the App Store.")
                            .font(Clinical.caption(12))
                            .foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                }
                .padding(14)
                .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Clinical.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manageSubscription")
        }
    }

    private var aboutFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Clinical.hairline)
            Text(AppInfo.medicalDisclaimer)
                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
            HStack(spacing: 16) {
                if let url = AppInfo.privacyPolicyURL {
                    Link("Privacy", destination: url).font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
                }
                if let url = AppInfo.supportURL {
                    Link("Support", destination: url).font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
                }
                Spacer()
                Text("v\(AppInfo.version)").font(Clinical.eyebrow(10)).foregroundStyle(Clinical.tertiary)
            }
        }
        .padding(.top, 8)
        // A quiet mirrored sprig bleeding off the bottom-left behind the footer — pushed down
        // so most of the foliage exits the screen edge rather than sitting behind the small print.
        .background(alignment: .bottomLeading) {
            CornerSprig(corner: .topLeading, width: 150, opacity: 0.35)
                .offset(y: 56)
        }
    }

    private func practiceToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
        }
        .tint(Clinical.accent)
    }

    private func complete() {
        profile.hasOnboarded = true
        dismiss()
    }
}

/// "Your data": a full backup (every record + photos, one JSON file) and a merge-safe
/// restore. The store is local-only, so this file is the durability story until iCloud
/// sync is switched on.
private struct BackupRestoreSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \DailyEntry.date) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query(sort: \TreatmentDose.loggedAt) private var doses: [TreatmentDose]
    @Query(sort: \MissedDoseRecord.date) private var missedDoses: [MissedDoseRecord]
    @Query(sort: \SideEffectLog.date) private var sideEffects: [SideEffectLog]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date) private var triggers: [TriggerEvent]
    @Query(sort: \ProcedureAppointment.date) private var procedureAppointments: [ProcedureAppointment]
    @Query(sort: \AgentMemory.createdAt) private var agentMemories: [AgentMemory]
    @Query(sort: \ProgressCheckIn.date) private var progressCheckIns: [ProgressCheckIn]

    @State private var backupURL: URL?
    @State private var isBackingUp = false
    @State private var showImporter = false
    @State private var pendingRestoreURL: URL?
    @State private var showRestoreConfirm = false
    @State private var restoreSummary: BackupService.RestoreSummary?
    @State private var errorMessage: String?
    @State private var showSensitiveWarning = false
    @State private var sensitiveWarningAcknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Your data")

            VStack(alignment: .leading, spacing: 12) {
                if let backupURL, sensitiveWarningAcknowledged {
                    ShareLink(item: backupURL) {
                        Label("Share \(backupURL.lastPathComponent)\(backupSizeSuffix(backupURL))",
                              systemImage: "square.and.arrow.up")
                            .font(Clinical.body(15, weight: .semibold))
                            .foregroundStyle(Clinical.surface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Clinical.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityIdentifier("backupShare")
                } else if let backupURL {
                    Button("Review before sharing") { showSensitiveWarning = true }
                        .buttonStyle(ClinicalButtonStyle(filled: true))
                } else {
                    Button { Task { await generateBackup() } } label: {
                        Label(isBackingUp ? "Preparing backup…" : "Back up everything",
                              systemImage: "arrow.down.doc")
                            .font(Clinical.body(15, weight: .semibold))
                            .foregroundStyle(Clinical.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBackingUp)
                    .accessibilityIdentifier("backupCreate")
                }

                Button {
                    showImporter = true
                } label: {
                    Label("Restore from backup", systemImage: "arrow.counterclockwise")
                        .font(Clinical.body(15, weight: .semibold))
                        .foregroundStyle(Clinical.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backupRestore")

                Text("Backups include your photos. Store the file somewhere safe (Files/iCloud Drive). Automatic iCloud sync isn't on yet.")
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
            }
            .padding(14)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingRestoreURL = url
                showRestoreConfirm = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Sensitive health information", isPresented: $showSensitiveWarning,
                            titleVisibility: .visible) {
            Button("I understand — show sharing options") { sensitiveWarningAcknowledged = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This backup contains sensitive health records, treatment history, notes, and scalp photos. Share it only with people and services you trust.")
        }
        .confirmationDialog("Restore from backup?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Restore") { runRestore() }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("Merges with what's on this phone — nothing is deleted.")
        }
        .alert("Restore complete", isPresented: Binding(
            get: { restoreSummary != nil },
            set: { if !$0 { restoreSummary = nil } }
        )) {
            Button("OK") { restoreSummary = nil }
        } message: {
            if let s = restoreSummary {
                Text("\(s.inserted) records added, \(s.skipped) already on this phone, \(s.photosRestored) photos restored.")
            }
        }
        .alert("Couldn't restore", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    /// `isBackingUp` now actually gets to render a frame — `exportBackupAsync` does the base64
    /// encoding of every stored photo off the main actor, so setting the flag and awaiting the
    /// call are two separate SwiftUI update cycles instead of one blocking call in between.
    private func generateBackup() async {
        isBackingUp = true
        do {
            backupURL = try await BackupService.exportBackupAsync(
                profile: profiles.first, entries: entries, treatments: treatments,
                doses: doses, sideEffects: sideEffects,
                labs: labs, photos: photos, snapshots: snapshots, triggers: triggers,
                procedures: procedureAppointments, progressCheckIns: progressCheckIns,
                missedDoses: missedDoses, agentMemories: agentMemories
            )
            sensitiveWarningAcknowledged = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isBackingUp = false
    }

    private func runRestore() {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil
        do {
            restoreSummary = try BackupService.restore(from: url, into: modelContext)
            backupURL = nil   // the store changed — a shared backup should be regenerated
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func backupSizeSuffix(_ url: URL) -> String {
        guard let bytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return ""
        }
        return " (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
    }
}

/// Horizontally scrolling chip row — robust across label widths, no layout math.
private struct FlowChips: View {
    let items: [String]
    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = item == selected
                    Button {
                        onPick(item)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(item)
                            .font(Clinical.body(14, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(on ? Clinical.ink : Clinical.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}
