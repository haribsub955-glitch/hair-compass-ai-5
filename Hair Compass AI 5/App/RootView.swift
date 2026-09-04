import SwiftData
import SwiftUI
import UIKit

struct ScenePhaseDecision: Equatable {
    var shouldShowPrivacyOverlay: Bool
    var shouldMarkBackgrounded: Bool
    var shouldEndRitualActivity: Bool

    static func reduce(
        phase: ScenePhase,
        isLocked: Bool,
        ritualPresented: Bool
    ) -> ScenePhaseDecision {
        switch phase {
        case .inactive:
            return ScenePhaseDecision(shouldShowPrivacyOverlay: true,
                                      shouldMarkBackgrounded: false,
                                      shouldEndRitualActivity: ritualPresented)
        case .background:
            return ScenePhaseDecision(shouldShowPrivacyOverlay: true,
                                      shouldMarkBackgrounded: true,
                                      shouldEndRitualActivity: ritualPresented)
        case .active:
            return ScenePhaseDecision(shouldShowPrivacyOverlay: false,
                                      shouldMarkBackgrounded: false,
                                      shouldEndRitualActivity: false)
        @unknown default:
            return ScenePhaseDecision(shouldShowPrivacyOverlay: isLocked,
                                      shouldMarkBackgrounded: false,
                                      shouldEndRitualActivity: false)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, trends, care, labs, photos
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .trends: return "Trends"
        case .care: return "Plan"
        case .labs: return "Labs"
        case .photos: return "Photos"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "checkmark.circle"
        case .trends: return "chart.xyaxis.line"
        case .care: return "checklist"
        case .labs: return "testtube.2"
        case .photos: return "camera"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query private var missedDoses: [MissedDoseRecord]
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]

    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = RootView.initialTab
    @State private var didBootstrap = false
    @State private var showOnboarding = false
    @State private var showProfileEdit = false
    @State private var healthKit = HealthKitService()
    @State private var notifications = NotificationService()
    @State private var affiliates = AffiliateStore()
    @State private var appLock = AppLockService()
    @State private var lockPresenter = LockWindowPresenter()
    @State private var privacyPresenter = PrivacyWindowPresenter()
    @State private var owningWindowScene: UIWindowScene?
    @StateObject private var ritualCoordinator = LaunchRitualCoordinator()
    @State private var ritualKind: RitualKind?
    @State private var purchases = PurchaseService()
    @State private var accessWindow = AccessWindow()
    @State private var deepLinks = DeepLinkRouter()
    /// Set by BaselineFlow's "Erase" confirmation; honoured once the Profile sheet has fully
    /// closed so no presented view still holds the profile being deleted.
    @State private var pendingErase = false
    @State private var eraseFailed = false

    // Evening check-in reminder — same AppStorage keys `CareView`'s toggle UI reads/writes.
    // `NotificationService.planEveningCheckIn` only ever schedules 3 non-repeating notifications
    // (today + the next two days), so it must be re-planned at least every ~3 days or the
    // schedule silently runs dry. `CareView` only exists while the Plan tab is on screen, so
    // RootView — always alive — is the surface that actually keeps the horizon rolling forward
    // for someone who lives in Today and never revisits Plan.
    @AppStorage("eveningCheckInEnabled") private var eveningCheckInEnabled = false
    @AppStorage("eveningCheckInMinutes") private var eveningCheckInMinutes = 20 * 60 + 30

    private var profile: Profile? { profiles.first }
    private var launchPresentation: LaunchPresentationState {
        LaunchPresentationState.reduce(.init(
            // Persistence recovery is selected by HairCompassApp before RootView exists.
            persistenceFailed: false,
            isLocked: appLock.isEnabled && appLock.isLocked,
            // Keep the established request flags so bootstrap and dismissal timing stay unchanged.
            hasOnboarded: !showOnboarding,
            hasPendingRoute: deepLinks.hasPendingRoute || IntentHandoff.hasPendingLog,
            ritualDueOrForced: ritualKind != nil,
            appActive: scenePhase == .active
        ))
    }
    private var widgetFingerprint: String {
        let latestEntry = entries.first.map { "\($0.shedRaw)-\($0.flaking)-\($0.erythema)-\($0.itch)" } ?? "none"
        let activeTreatments = treatments.filter(\.isActive).count
        let photoWeek = photos.first.map { "\($0.createdAt.timeIntervalSince1970)" } ?? "nophoto"
        return "\(entries.count)-\(entries.first?.date.timeIntervalSince1970 ?? 0)-\(doses.count)-\(treatments.count)-\(latestEntry)-\(activeTreatments)-\(photoWeek)-\(missedDoses.count)"
    }

    /// The widget records intent in the App Group, never in SwiftData. Drain it through the same
    /// repository as Today, then build from freshly fetched treatments/doses so the optimistic
    /// widget row cannot linger when a request was already complete, invalid, or stale.
    @MainActor
    private func applyPendingCompletionsAndWriteWidget() {
        let liveTreatments = (try? context.fetch(FetchDescriptor<Treatment>())) ?? treatments
        _ = try? PendingCompletionApplier.apply(context: context, treatments: liveTreatments)
        let liveDoses = (try? context.fetch(FetchDescriptor<TreatmentDose>())) ?? doses
        WidgetBridge.write(WidgetSnapshotBuilder.build(
            entries: entries,
            treatments: liveTreatments,
            doses: liveDoses,
            missed: missedDoses,
            photos: photos
        ))
    }

    // MARK: Evening check-in reminder

    /// Whether today already has a logged entry — the "cancel tonight's reminder once today is
    /// logged" honesty rule needs this current even when the user never opens Plan.
    private var hasLoggedToday: Bool { entries.contains { Calendar.current.isDateInToday($0.date) } }
    /// The shielded (displayed) streak — matches the number the Today hero and `CareView`'s own
    /// copy show, so the reminder body ("Day N. Twenty seconds.") never disagrees with the app.
    private var eveningCheckInStreak: Int {
        HairAnalytics.shieldedStreak(entryDates: entries.map(\.date)).streak
    }
    /// Re-plans from whichever surface last ran — idempotent on the notification-service side,
    /// so calling it here as well as from `CareView` is harmless double-planning, not a race.
    private func replanEveningCheckIn() async {
        await notifications.planEveningCheckIn(
            enabled: eveningCheckInEnabled,
            time: NotificationService.eveningCheckInComponents(minutesSinceMidnight: eveningCheckInMinutes),
            hasLoggedToday: hasLoggedToday,
            streak: eveningCheckInStreak
        )
    }
    /// Keys the `.task` below — changes whenever the toggle, the chosen time, today's logged
    /// state, or the most recent entry's day change, so a fresh re-plan runs on all of them
    /// without re-running on every unrelated `entries` mutation.
    private var eveningCheckInPlanKey: String {
        let lastEntryDay = entries.first.map { "\(Calendar.current.startOfDay(for: $0.date).timeIntervalSince1970)" } ?? "none"
        return "\(eveningCheckInEnabled)|\(eveningCheckInMinutes)|\(hasLoggedToday)|\(lastEntryDay)"
    }

    // MARK: - Erase and start over

    /// The wipe, then straight back to the illustrated cover.
    private func eraseAndStartOver() async {
        do {
            try await EraseAndStartOver.perform(context: context)
        } catch {
            // The wipe failed part-way. Roll back what has not been saved, make sure a profile
            // exists again so the app is usable, and say so — a confirmed destructive action
            // must never fail silently or leave the shell empty.
            context.rollback()
            let existing = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
            Seed.bootstrapIfNeeded(context: context, profiles: existing)
            try? context.save()
            eraseFailed = true
            return
        }
        // The domain wipe clears UserDefaults (including the App Lock preference), but this live
        // service instance still has the old value cached in memory — without this, a locked
        // profile's Face ID gate would keep guarding the fresh, un-onboarded app.
        appLock.isEnabled = false
        showOnboarding = true
    }

    private static var initialTab: AppTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "HC_TAB"), i + 1 < args.count,
           let t = AppTab(rawValue: args[i + 1]) { return t }
        #endif
        return .today
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        // Since 1.1 every tab except Plan is part of Pro, unlocked by the 3-day first-install
        // window or a subscription. Plan (medication/treatment logging) stays free forever: a
        // dose schedule is a health-safety surface, and it must never sit behind a paywall.
        case .today:
            ProGate(feature: "Daily Check-ins",
                    symbol: "checkmark.circle",
                    description: "Log shedding, scalp, and treatments in seconds — part of Hair Compass Pro.") {
                TodayView(profile: profile,
                          onOpenBaseline: { showProfileEdit = true },
                          onOpenPlan: { tab = .care },
                          onOpenPhotos: { tab = .photos })
            }
        case .trends:
            ProGate(feature: "Trends & Evidence",
                    symbol: "chart.xyaxis.line",
                    description: "Deterministic charts of your record over time — part of Hair Compass Pro.") {
                TrendsView()
            }
        case .care:
            CareView(
                onLogToday: {
                    tab = .today
                    deepLinks.openLogRequested = true
                },
                onOpenLabs: { tab = .labs },
                onOpenPhotos: { tab = .photos }
            )
        case .labs:
            ProGate(feature: "Lab Results",
                    symbol: "testtube.2",
                    description: "Track ferritin, vitamin D, thyroid and more — part of Hair Compass Pro.") {
                LabsView()
            }
        case .photos:
            ProGate(feature: "Progress Photos",
                    symbol: "camera",
                    description: "Standardized angles for honest comparisons — part of Hair Compass Pro.") {
                PhotosView()
            }
        }
    }

    // The tab canvas plus its layout/overlay chrome. Split out of `body` so the modifier chain
    // type-checks in reasonable time; `body` applies the environment/task/handler modifiers to it.
    private var styledContent: some View {
        ZStack {
            Group { tabContent }
                .transition(tabTransition)
        }
        // Design V2: a quiet crossfade connects destinations while the matched tab pill carries
        // spatial continuity. Reduce Motion keeps only the short fade.
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.22), value: tab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reserve real layout space for navigation. The previous overlay obscured the final
        // card on every tab and made users scroll content underneath an active control.
        // Round-13: the canvas fade that used to live here (behind the tab bar's now-retired
        // ivory capsule) moved onto `FloatingTabBar` itself — the bar owns its own scrim so the
        // frame speaks the same ink grammar wherever it's hosted, not just in RootView.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                // The five destinations use the complete width, so their collective midpoint is
                // the screen midpoint. Wren gets a protected upper berth inside this same safe-area
                // inset: the padding contributes real layout height, so she cannot steal a tap from
                // content, while no invisible trailing spacer can push navigation off-centre.
                FloatingTabBar(selection: $tab)
                WrenChatButton(tab: tab, profile: profile)
                    .padding(.bottom, 64)
            }
            // Charts can establish their own compositing layers. Flatten the complete bar
            // above them so no tab item is painted underneath a scrolling chart card.
            .compositingGroup()
            .zIndex(100)
        }
        .background(Clinical.canvas.ignoresSafeArea())
        .background(WindowSceneReader(scene: $owningWindowScene))
    }

    var body: some View {
        styledContent
        .environment(healthKit)
        .environment(notifications)
        .environment(affiliates)
        .environment(purchases)
        .environment(accessWindow)
        .environment(deepLinks)
        .task {
            // A force-quit can bypass RitualView.onDisappear. Clear any ActivityKit survivors
            // before launch decides whether to present a fresh ritual.
            await RitualActivityService.shared.reconcileOrphans()
            guard !didBootstrap else { return }
            didBootstrap = true
            // Demo seeding is a QA hook, so it stays out of the shipping binary entirely rather
            // than merely being unreachable behind a launch argument a release user can't set.
            #if DEBUG
            let seededDemo = ProcessInfo.processInfo.arguments.contains("HC_SEED_DEMO")
            if seededDemo {
                Seed.demo(context: context, profiles: profiles, entries: entries)
                // HC_NOTODAY: the quiet-day demo for the "Same as yesterday" chip. `Seed.demo`
                // only ever seeds once per install (guarded by `entries.isEmpty`), so a launch
                // that asks for this scenario on an already-seeded install (e.g. a UI test suite
                // reusing one app install across launches) must remove any existing today's entry
                // itself rather than rely on the seed loop, which won't run again.
                if ProcessInfo.processInfo.arguments.contains("HC_NOTODAY") {
                    Seed.ensureNoTodayEntry(context: context)
                }
                if ProcessInfo.processInfo.arguments.contains("HC_PLANOPEN") {
                    Seed.ensureNoDosesToday(context: context)
                }
                // HC_PLANCLOSED (G2 motion amendment M8): the counterpart of HC_PLANOPEN — logs
                // every open occurrence today so a fresh launch can force the closure card, the
                // seven-day constellation and Close the Day. Fetches fresh rather than reading
                // the `treatments` @Query, which has not re-run within this same task yet.
                if ProcessInfo.processInfo.arguments.contains("HC_PLANCLOSED") {
                    let freshTreatments = (try? context.fetch(
                        FetchDescriptor<Treatment>(sortBy: [SortDescriptor(\.startDate)])
                    )) ?? []
                    Seed.ensureDosesToday(context: context, treatments: freshTreatments)
                    // So QA can force the Close the Day sequence to replay on a launch that
                    // reuses an already-closed install, rather than showing the plain closure
                    // card because today was already celebrated in an earlier launch.
                    UserDefaults.standard.removeObject(forKey: "grounding.celebratedDay")
                    UserDefaults.standard.removeObject(forKey: "grounding.enteredCardKey")
                }
            }
            #else
            let seededDemo = false
            #endif
            if !seededDemo {
                Seed.bootstrapIfNeeded(context: context, profiles: profiles)
            }
            try? await Task.sleep(for: .milliseconds(150))
            if profile?.hasOnboarded == false { showOnboarding = true }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_ONBOARD") { showOnboarding = true }
            if ProcessInfo.processInfo.arguments.contains("HC_PROFILE") { showProfileEdit = true }
            // Flags the seeded profile pregnant + female so the pregnancy-caution flow (adding
            // finasteride/minoxidil/etc.) and the female-only onboarding step can be inspected.
            if ProcessInfo.processInfo.arguments.contains("HC_PREGNANT"),
               let p = try? context.fetch(FetchDescriptor<Profile>()).first {
                p.sex = .female
                p.pregnancyStatus = .pregnant
            }
            #endif
            // Launch-ritual roll — only once onboarding is resolved, and never over onboarding.
            var suppressRitual = false
            #if DEBUG
            suppressRitual = ProcessInfo.processInfo.arguments.contains("HC_NORITUAL")
            #endif
            // Lock wins: a locked app never rolls a ritual — the lock screen is the only surface.
            if !showOnboarding && !suppressRitual && !appLock.isLocked {
                ritualKind = ritualCoordinator.rollOnLaunch(hasOnboarded: profile?.hasOnboarded == true)
            }
            // Re-derive notification permission the same way, for the same reason:
            // `NotificationService.authorization` can only ever start at `.notDetermined`, so
            // without this a previously granted user reads as never-asked on every relaunch.
            // Each `plan*`/`reschedule` call below now self-refreshes too (belt-and-suspenders —
            // it's the fix for the 2026-07-21 evening-reminder audit), but doing it once here
            // up front keeps this launch task's intent explicit alongside HealthKit's bootstrap.
            await notifications.refreshAuthorization()
            // Re-derive HealthKit request/query state first — `HealthKitService.init()` can
            // only ever start at `.notRequested`, so without this, a person who answered
            // the request in a prior session would look never-asked on every relaunch and the
            // snapshot refresh below (and the dashboard's manual refresh) would silently stop.
            await healthKit.bootstrap()
            // If the request was previously presented, query today's available samples.
            if healthKit.authorization.isQueryable {
                await healthKit.refreshSnapshot(context: context)
            }
        }
        .task(id: widgetFingerprint) {
            applyPendingCompletionsAndWriteWidget()
        }
        // Keeps the evening check-in's 3-day rolling horizon alive regardless of which tab is on
        // screen — `CareView` (the Plan tab) only exists while it's the selected tab, so without
        // this a user who lives in Today would stop receiving their chosen nudge after ~3 days.
        // Re-runs on the toggle, the chosen time, today's logged state, and the latest entry's
        // day; `planEveningCheckIn` is idempotent, so this and `CareView`'s own re-plan (when
        // Plan happens to be open) never fight — the more recent call always wins.
        .task(id: eveningCheckInPlanKey) {
            await replanEveningCheckIn()
        }
        // Same DeepLinkRouter idiom the widget's haircompass://log URL uses below — routes every
        // reminder's tap to the tab and action it invited, rather than only milestone taps
        // (round 4). Dispatched by identifier prefix, mirroring how NotificationService names
        // its own scheduled requests.
        .task {
            notifications.onNotificationAction = { actionID, identifier, userInfo in
                guard actionID == NotificationService.completeActionID,
                      let slot = userInfo["slot"] as? String,
                      identifier == "treatment.\(slot)"
                else { return }

                // Fetch at action time rather than capturing the treatment query from this
                // render. A notification can be acted on days later, after the plan changed.
                let current = (try? context.fetch(FetchDescriptor<Treatment>())) ?? []
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                for treatment in current where treatment.isActive
                    && PlanAdherence.expectedSlots(treatment, on: today, calendar: calendar).contains(slot) {
                    _ = try? DoseRepository(context: context, calendar: calendar)
                        .log(treatment: treatment, slot: slot)
                }
                // Notification actions may run briefly in the background. Persist now instead of
                // relying on an autosave that suspension could interrupt.
                try? context.save()
            }
            notifications.onNotificationTapped = { identifier in
                if identifier.hasPrefix("milestone.") {
                    tab = .care
                    // Identifier shape is "milestone.<treatmentID>.<week>" (see
                    // NotificationService.planMilestoneReminders) — pull the treatment id back
                    // out so the report that opens is the one THIS milestone was about, not
                    // whichever treatment happens to be earliest.
                    let rest = identifier.dropFirst("milestone.".count)
                    deepLinks.progressReportFocusTreatmentID = rest.split(separator: ".").first.map(String.init)
                    deepLinks.openProgressReportRequested = true
                } else if identifier.hasPrefix("eveningCheckIn.") {
                    tab = .today
                    deepLinks.openLogRequested = true
                } else if identifier == "photoReminder" {
                    tab = .photos
                    deepLinks.openGuidedCaptureRequested = true
                } else if identifier.hasPrefix("refill.") || identifier.hasPrefix("treatment.") {
                    tab = .care
                    deepLinks.openCareRequested = true
                } else if identifier.hasPrefix("procedure.") {
                    tab = .care
                    deepLinks.openProceduresRequested = true
                } else if identifier.hasPrefix("progressCheckIn.") {
                    tab = .care
                    deepLinks.openProgressCheckInRequested = true
                }
            }
        }
        // Owner-controlled affiliate links: pull the remote catalog once per launch. A no-op
        // while RemoteConfig.catalogURLString is unset; failures are silent (bundled links serve).
        .task { await affiliates.refresh() }
        .fullScreenCover(isPresented: Binding(
            // `&& profile != nil` — after "Erase and start over" re-seeds a fresh Profile, the
            // `@Query` that delivers it hasn't necessarily fired yet on this same run loop turn.
            // Without the guard the cover could present before `profile` arrives, and the `if let
            // profile` below would render nothing over a blank cover.
            get: { launchPresentation.surface == .onboarding && profile != nil },
            // Preserve the request when a higher-precedence privacy/lock surface temporarily wins.
            set: { presented in
                if !presented, launchPresentation.surface == .onboarding { showOnboarding = false }
            }
        )) {
            if let profile {
                // Presented covers inherit the environment from where `.fullScreenCover` is
                // attached — here, OUTSIDE the `.environment(healthKit)` / `.environment(purchases)`
                // modifiers below. Without re-injecting directly on the cover's content, onboarding's
                // health step and paywall step would crash reading their `@Environment(...)`.
                OnboardingFlow(profile: profile, onFinish: {
                    showOnboarding = false
                    tab = .care
                })
                .environment(healthKit)
                .environment(purchases)
                .environment(accessWindow)
            }
        }
        // The pure launch reducer makes these cover predicates mutually exclusive. Effect
        // extraction and presenter/window ownership remain intentionally deferred.
        .fullScreenCover(isPresented: Binding(
            get: { launchPresentation.surface == .ritual },
            // Preserve the request when a higher-precedence privacy/lock surface temporarily wins.
            set: { presented in
                if !presented, launchPresentation.surface == .ritual { ritualKind = nil }
            }
        )) {
            if let ritualKind {
                RitualView(kind: ritualKind) { self.ritualKind = nil }
            }
        }
        .sheet(isPresented: $showProfileEdit, onDismiss: {
            guard pendingErase else { return }
            pendingErase = false
            Task { await eraseAndStartOver() }
        }) {
            if let profile {
                // BaselineFlow can replay onboarding from its own cover; inject here so that
                // cover's health + paywall steps can read their services (presented content
                // only inherits the environment of its attachment point).
                BaselineFlow(profile: profile, onEraseRequested: { pendingErase = true })
                    .environment(healthKit)
                    .environment(purchases)
                    .environment(accessWindow)
            }
        }
        .alert("Couldn't erase everything", isPresented: $eraseFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some records may still be on this iPhone. Try again from Profile, or export a backup first and reinstall the app.")
        }
        .onChange(of: scenePhase) { _, phase in
            let decision = ScenePhaseDecision.reduce(
                phase: phase,
                isLocked: appLock.isEnabled && appLock.isLocked,
                ritualPresented: ritualKind != nil
            )
            if decision.shouldShowPrivacyOverlay {
                privacyPresenter.present(in: owningWindowScene)
            } else {
                privacyPresenter.dismiss()
            }
            if decision.shouldEndRitualActivity {
                RitualActivityService.shared.ritualStoppedBeingForeground()
            }
            if decision.shouldMarkBackgrounded {
                appLock.markBackgrounded()
                ritualCoordinator.markBackgrounded()
            }
            switch phase {
            case .background:
                // Both do their own bookkeeping: the lock relocks (if enabled), the ritual
                // coordinator just timestamps for the >4h re-roll.
                break
            case .inactive:
                break
            case .active:
                applyPendingCompletionsAndWriteWidget()
                // Activation may follow suspension/termination where no view teardown ran.
                Task { await RitualActivityService.shared.reconcileOrphans() }
                // A Siri/Shortcuts "Log check-in" hands off through the App Group — honour it on
                // activation. The `&&` short-circuits so the flag is only consumed when we can act
                // (never swallowed behind the lock or onboarding), and it suppresses a ritual roll.
                let wantsLog = !showOnboarding && !(appLock.isEnabled && appLock.isLocked)
                    && IntentHandoff.consumePendingLog()
                if wantsLog {
                    tab = .today
                    deepLinks.openLogRequested = true
                }
                // A day-long-suspended app never re-runs the launch `.task` above, so without
                // this an already-connected user's sleep/HRV/weight facts would only refresh on
                // a cold relaunch. Cheap and idempotent — `refreshSnapshot` only upserts today.
                if healthKit.authorization.isQueryable {
                    Task { await healthKit.refreshSnapshot(context: context) }
                }
                // Same reasoning: `eveningCheckInPlanKey` only changes once the day rolls over,
                // so a foreground that lands before midnight wouldn't otherwise re-trigger the
                // `.task(id:)` above even though the 3-day horizon it scheduled on the *previous*
                // foreground/launch is now a day closer to running dry. Explicit call here rolls
                // it forward on every activation, not just on a day boundary.
                Task { await replanEveningCheckIn() }
                if appLock.isEnabled && appLock.isLocked {
                    // Lock wins: never roll a ritual over the lock screen — go straight to Face ID.
                    lockPresenter.present(appLock)
                    Task { await appLock.unlock() }
                } else if !wantsLog, !showOnboarding, ritualKind == nil, ritualCoordinator.wasBackgroundedLongEnough() {
                    // Foreground after >4h in the background → re-roll (never over onboarding/another cover).
                    ritualKind = ritualCoordinator.rollOnForeground(hasOnboarded: profile?.hasOnboarded == true)
                    ritualCoordinator.clearBackgrounded()
                }
            default:
                break
            }
        }
        // The lock screen lives in its own window above every sheet and cover — a locked app must
        // never show content, no matter what was on screen when it left.
        .onChange(of: appLock.isEnabled && appLock.isLocked, initial: true) { _, locked in
            if locked {
                ritualKind = nil   // lock wins over an in-flight ritual too
                lockPresenter.present(appLock)
            } else {
                lockPresenter.dismiss()
            }
        }
        .onChange(of: launchPresentation.surface, initial: true) { _, surface in
            deepLinks.canConsumeRoutes = surface == .pendingRoute || surface == .normal
        }
        .tint(Clinical.accent)
        .environment(appLock)
        .onOpenURL { url in
            guard let destination = DeepLinkRouter.destination(for: url) else { return }
            tab = .today
            deepLinks.record(destination)
        }
    }

    private var tabTransition: AnyTransition {
        // Pure crossfade — no scale. A centre-anchored scale-in spreads full-width content
        // outward by ~1.5% as it settles; on the chart-dense Trends tab that reads as the plotted
        // line and gridlines drifting "left and right" on every entry. A plain opacity swap keeps
        // every tab's content positionally still.
        .opacity
    }
}

// MARK: - App Lock overlay

/// Hosts the lock screen in its own UIWindow at `.alert + 1`, which sits above the main window's
/// entire presentation stack (sheets, full-screen covers, popovers). A plain `.overlay` or a
/// `fullScreenCover` can be out-presented by an open sheet; a higher window can't.
@MainActor
private final class LockWindowPresenter {
    private var window: UIWindow?

    func present(_ lock: AppLockService) {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(
            rootView: LockScreenView(lock: lock)
        )
        window.isHidden = false
        self.window = window
    }

    func dismiss() {
        window?.isHidden = true
        window = nil
    }
}

/// Covers every presentation layer before iOS captures the app-switcher snapshot. Snapshot
/// privacy is always active, independently of the optional Face ID app lock.
@MainActor
private final class PrivacyWindowPresenter {
    private var window: UIWindow?

    func present(in scene: UIWindowScene?) {
        guard window == nil else { return }
        guard let scene else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 2
        window.rootViewController = UIHostingController(rootView: PrivacySnapshotView())
        window.isHidden = false
        self.window = window
    }

    func dismiss() {
        window?.isHidden = true
        window = nil
    }
}

private struct WindowSceneReader: UIViewRepresentable {
    @Binding var scene: UIWindowScene?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        DispatchQueue.main.async { scene = view.window?.windowScene }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { scene = view.window?.windowScene }
    }
}

private struct PrivacySnapshotView: View {
    var body: some View {
        ZStack {
            Clinical.canvas.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(Clinical.body(30, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                Text("Hair Compass")
                    .font(Clinical.headline(28))
                    .foregroundStyle(Clinical.ink)
                Text("Your records are concealed.")
                    .font(Clinical.caption(14))
                    .foregroundStyle(Clinical.secondary)
            }
        }
    }
}

/// The warm gouache lock screen: ivory canvas, serif app name, one copper unlock button.
/// Auto-attempts Face ID once when it appears in the foreground.
private struct LockScreenView: View {
    let lock: AppLockService

    var body: some View {
        ZStack {
            Clinical.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    Image(systemName: "lock.fill")
                    .font(Clinical.body(32, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                    .frame(width: 88, height: 88)
                    .background(Clinical.accentSoft, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
                Text("Hair Compass")
                    .font(Clinical.headline(30))
                    .foregroundStyle(Clinical.ink)
                    .padding(.top, 22)
                Text("Your hair records are locked.")
                    .font(Clinical.caption(14))
                    .foregroundStyle(Clinical.secondary)
                    .padding(.top, 6)
                Spacer()
                Button("Unlock with Face ID") {
                    Task { await lock.unlock() }
                }
                .buttonStyle(ClinicalButtonStyle())
                .accessibilityIdentifier("appLockUnlock")
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                #if DEBUG
                // Debug builds only — simulators without enrolled Face ID would otherwise strand
                // a test run behind the lock. Compiled out of release.
                Button("Skip (debug build)") { lock.debugBypass() }
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .accessibilityIdentifier("appLockDebugSkip")
                    .padding(.bottom, 16)
                #else
                Spacer().frame(height: 16)
                #endif
                }
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height)
            }
        }
        .task {
            // One automatic attempt on appear — but only in the foreground (locking happens on
            // backgrounding, and Face ID can't run from the background).
            if UIApplication.shared.applicationState == .active {
                await lock.unlock()
            }
        }
    }
}
