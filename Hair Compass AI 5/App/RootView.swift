import SwiftData
import SwiftUI
import UIKit

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
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \DailyEntry.date, order: .reverse) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]

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
    @StateObject private var ritualCoordinator = LaunchRitualCoordinator()
    @State private var ritualKind: RitualKind?

    private var profile: Profile? { profiles.first }
    private var widgetFingerprint: String {
        "\(entries.count)-\(entries.first?.date.timeIntervalSince1970 ?? 0)-\(doses.count)-\(treatments.count)"
    }

    private static var initialTab: AppTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "HC_TAB"), i + 1 < args.count,
           let t = AppTab(rawValue: args[i + 1]) { return t }
        #endif
        return .today
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .today: TodayView(profile: profile,
                                       onOpenBaseline: { showProfileEdit = true },
                                       onOpenPlan: { tab = .care })
                case .trends: TrendsView()
                case .care: CareView()
                case .labs: LabsView()
                case .photos: PhotosView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selection: $tab)
        }
        .environment(healthKit)
        .environment(notifications)
        .environment(affiliates)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            if ProcessInfo.processInfo.arguments.contains("HC_SEED_DEMO") {
                Seed.demo(context: context, profiles: profiles, entries: entries)
            } else {
                Seed.bootstrapIfNeeded(context: context, profiles: profiles)
            }
            try? await Task.sleep(for: .milliseconds(150))
            if profile?.hasOnboarded == false { showOnboarding = true }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_ONBOARD") { showOnboarding = true }
            if ProcessInfo.processInfo.arguments.contains("HC_PROFILE") { showProfileEdit = true }
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
            // If the user has already granted Health access, refresh today's snapshot on launch.
            if healthKit.authorization.isUsable {
                await healthKit.refreshSnapshot(context: context)
            }
        }
        .task(id: widgetFingerprint) {
            WidgetBridge.write(WidgetSnapshotBuilder.build(entries: entries, treatments: treatments, doses: doses))
        }
        // Owner-controlled affiliate links: pull the remote catalog once per launch. A no-op
        // while RemoteConfig.catalogURLString is unset; failures are silent (bundled links serve).
        .task { await affiliates.refresh() }
        .fullScreenCover(isPresented: $showOnboarding) {
            if let profile {
                OnboardingFlow(profile: profile, onFinish: { showOnboarding = false })
            }
        }
        // Onboarding wins: we only ever set `ritualKind` when not onboarding, so the two covers
        // never contend. Dismissing the ritual reveals the normal Today screen underneath.
        .fullScreenCover(item: $ritualKind) { kind in
            RitualView(kind: kind) { ritualKind = nil }
        }
        .sheet(isPresented: $showProfileEdit) {
            if let profile { BaselineFlow(profile: profile) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Both do their own bookkeeping: the lock relocks (if enabled), the ritual
                // coordinator just timestamps for the >4h re-roll.
                appLock.markBackgrounded()
                ritualCoordinator.markBackgrounded()
            case .active:
                if appLock.isEnabled && appLock.isLocked {
                    // Lock wins: never roll a ritual over the lock screen — go straight to Face ID.
                    lockPresenter.present(appLock)
                    Task { await appLock.unlock() }
                } else if !showOnboarding, ritualKind == nil, ritualCoordinator.wasBackgroundedLongEnough() {
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
        .tint(Clinical.accent)
        .environment(appLock)
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
        window.rootViewController = UIHostingController(rootView: LockScreenView(lock: lock))
        window.isHidden = false
        self.window = window
    }

    func dismiss() {
        window?.isHidden = true
        window = nil
    }
}

/// The warm gouache lock screen: ivory canvas, serif app name, one copper unlock button.
/// Auto-attempts Face ID once when it appears in the foreground.
private struct LockScreenView: View {
    let lock: AppLockService

    var body: some View {
        ZStack {
            Clinical.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Clinical.accent)
                    .frame(width: 88, height: 88)
                    .background(Clinical.accentSoft, in: Circle())
                    .overlay(Circle().strokeBorder(Clinical.hairline, lineWidth: 1))
                Text("Hair Compass")
                    .font(Clinical.headline(30))
                    .foregroundStyle(Clinical.ink)
                    .padding(.top, 22)
                Text("Your hair records are locked.")
                    .font(.system(size: 14))
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Clinical.tertiary)
                    .accessibilityIdentifier("appLockDebugSkip")
                    .padding(.bottom, 16)
                #else
                Spacer().frame(height: 16)
                #endif
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
