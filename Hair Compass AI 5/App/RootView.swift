import SwiftData
import SwiftUI

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
                case .today: TodayView(profile: profile, onOpenBaseline: { showProfileEdit = true })
                case .trends: TrendsView()
                case .care: CareView()
                case .labs: LabsView()
                case .photos: PhotosView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: $tab)
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
            if !showOnboarding && !suppressRitual {
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
                ritualCoordinator.markBackgrounded()
            case .active:
                // Foreground after >4h in the background → re-roll (never over onboarding/another cover).
                if !showOnboarding, ritualKind == nil, ritualCoordinator.wasBackgroundedLongEnough() {
                    ritualKind = ritualCoordinator.rollOnForeground(hasOnboarded: profile?.hasOnboarded == true)
                    ritualCoordinator.clearBackgrounded()
                }
            default:
                break
            }
        }
        .tint(Clinical.accent)
    }
}

/// Flat bottom tab bar: a hairline top rule, no glass, no gradient.
private struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let on = tab == selection
                Button {
                    selection = tab
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: on ? tab.symbol + ".fill" : tab.symbol)
                            .font(.system(size: 19, weight: on ? .semibold : .regular))
                            .symbolRenderingMode(.monochrome)
                        Text(tab.title)
                            .font(.system(size: 10, weight: on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? Clinical.ink : Clinical.tertiary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            Clinical.surface
                .overlay(alignment: .top) { Clinical.hairline.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
