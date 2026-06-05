//
//  ContentView.swift
//  Hair Compass AI 5
//
//  Created by Harib Azri on 25/03/2026.
//

import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

enum HapticHelper {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HairProfile.createdAt) private var profiles: [HairProfile]
    @Query(sort: \CheckInEntry.date, order: .reverse) private var entries: [CheckInEntry]
    @Query private var tasks: [RoutineTask]
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photoRecords: [PhotoRecord]
    @Query(sort: \MedicationLog.startedAt, order: .reverse) private var medications: [MedicationLog]
    @Query(sort: \MedicationDoseEntry.loggedAt, order: .reverse) private var medicationDoseEntries: [MedicationDoseEntry]
    @Query(sort: \RoutineCompletionEntry.completedAt, order: .reverse) private var routineCompletionEntries: [RoutineCompletionEntry]
    @Query(sort: \ProcedureEvent.performedAt, order: .reverse) private var procedureEvents: [ProcedureEvent]
    @Query(sort: \LifestyleEntry.loggedAt, order: .reverse) private var lifestyleEntries: [LifestyleEntry]
    @Query(sort: \LabResultEntry.collectedAt, order: .reverse) private var labResults: [LabResultEntry]
    @Query(sort: \HairTriggerEvent.startedAt, order: .reverse) private var triggerEvents: [HairTriggerEvent]

    @State private var selectedTab: AppTab = .today
    @State private var hasSeeded = false
    @State private var healthInsights = HealthInsightsStore()
    @State private var isPresentingDashboardCheckIn = false
    @State private var isPresentingOnboarding = false

    private var isUITestForceOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_FORCE_ONBOARDING")
    }

    private var isUITestResetProfile: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_RESET_PROFILE")
    }

    private var profile: HairProfile? {
        profiles.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainTabContent
            .safeAreaPadding(.bottom, 78)

            FloatingTabBar(selectedTab: $selectedTab)
        }
        .tint(PremiumTheme.forest)
        .onAppear {
            UITabBar.appearance().isHidden = true
        }
        .onOpenURL(perform: handleDeepLink)
        .task {
            guard !hasSeeded else { return }
            hasSeeded = true
            if ProcessInfo.processInfo.arguments.contains("HC_SEED_DEMO") {
                SampleDataSeeder.seedDemoData(
                    modelContext: modelContext,
                    profiles: profiles,
                    entries: entries
                )
            } else {
                SampleDataSeeder.seedIfNeeded(
                    modelContext: modelContext,
                    profiles: profiles,
                    entries: entries,
                    tasks: tasks
                )
            }
            await healthInsights.refresh()
            try? await Task.sleep(for: .milliseconds(200))
            applyUITestProfileResetIfNeeded()
            presentOnboardingIfNeeded()
        }
        .onChange(of: profiles.first?.hasCompletedOnboarding) { _, newValue in
            if newValue == false {
                isPresentingOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $isPresentingOnboarding) {
            if let profile {
                OnboardingSurveyView(profile: profile, mode: .initial)
            }
        }
    }

    private var sortedTasks: [RoutineTask] {
        tasks.sorted {
            if $0.weekday == $1.weekday {
                return $0.timeLabel < $1.timeLabel
            }
            return $0.weekday < $1.weekday
        }
    }

    @ViewBuilder
    private var mainTabContent: some View {
        switch selectedTab {
        case .today:
            NavigationStack {
                DashboardTab(
                    profile: profile,
                    entries: entries,
                    tasks: tasks,
                    photoRecords: photoRecords,
                    medications: medications,
                    routineCompletions: routineCompletionEntries,
                    medicationEntries: medicationDoseEntries,
                    procedureEvents: procedureEvents,
                    lifestyleEntries: lifestyleEntries,
                    healthInsights: healthInsights,
                    labResults: labResults,
                    triggerEvents: triggerEvents,
                    onAddCheckIn: { isPresentingDashboardCheckIn = true },
                    onOpenRoutine: { selectedTab = .plan }
                )
            }
            .sheet(isPresented: $isPresentingDashboardCheckIn) {
                AddCheckInSheet()
            }
        case .chart:
            NavigationStack {
                CheckInsTab(
                    entries: entries,
                    photoRecords: photoRecords,
                    routineCompletions: routineCompletionEntries,
                    medications: medications,
                    medicationEntries: medicationDoseEntries,
                    procedureEvents: procedureEvents,
                    lifestyleEntries: lifestyleEntries,
                    healthMetricsByDay: healthInsights.metricsByDay,
                    triggerEvents: triggerEvents
                )
            }
        case .photo:
            NavigationStack {
                PhotoRecordsTab(photoRecords: photoRecords, profile: profile)
            }
        case .plan:
            NavigationStack {
                RoutineTab(
                    profile: profile,
                    entries: entries,
                    tasks: sortedTasks,
                    medications: medications,
                    doseEntries: medicationDoseEntries,
                    routineCompletions: routineCompletionEntries,
                    procedureEvents: procedureEvents,
                    lifestyleEntries: lifestyleEntries,
                    healthInsights: healthInsights,
                    labResults: labResults,
                    triggerEvents: triggerEvents
                )
            }
        case .you:
            NavigationStack {
                ProfileTab(
                    profile: profile,
                    entries: entries,
                    tasks: tasks,
                    triggerEvents: triggerEvents,
                    medications: medications,
                    procedureEvents: procedureEvents,
                    labResults: labResults,
                    photoRecords: photoRecords
                )
            }
        }
    }

    private func applyUITestProfileResetIfNeeded() {
        guard isUITestResetProfile, let profile else { return }
        profile.hasCompletedOnboarding = false
        profile.name = "User"
        profile.patternDistribution = ""
        profile.familyHistorySummary = ""
        profile.ageRange = ""
        profile.biologicalSex = ""
        profile.hairLossDuration = ""
    }

    private func presentOnboardingIfNeeded() {
        if isUITestForceOnboarding || profile?.hasCompletedOnboarding == false {
            isPresentingOnboarding = true
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "haircompass" else { return }

        let host = url.host ?? ""
        if matchesDeepLink(host: host, path: url.path, route: "checkin") {
            selectedTab = .today
            DispatchQueue.main.async {
                isPresentingDashboardCheckIn = true
            }
            return
        }

        if matchesDeepLink(host: host, path: url.path, route: "routine") {
            selectedTab = .plan
        }
    }

    private func matchesDeepLink(host: String, path: String, route: String) -> Bool {
        host == route || path == "/\(route)"
    }
}

enum AppSubmissionLinks {
    // Replace these before App Store submission.
    static let privacyPolicyURL = URL(string: "")
    static let supportURL = URL(string: "")
}

struct DashboardPlanItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let tint: Color
    let isComplete: Bool
}

enum HairCompassWidgetStore {
    static let appGroup = "group.harib.Hair-Compass-AI-5"
    static let snapshotKey = "dashboardSnapshot"
}

struct HairCompassWidgetSnapshot: Codable, Equatable {
    let generatedAt: Date
    let routineHeadline: String
    let progressLabel: String
    let checkInLabel: String
    let completedCount: Int
    let totalCount: Int
    let upcomingTitles: [String]
}

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case chart
    case photo
    case plan
    case you

    var id: String { rawValue }

    // Legacy mapping
    static var dashboard: AppTab { .today }
    static var checkIns: AppTab { .chart }
    static var routine: AppTab { .plan }
    static var profile: AppTab { .you }
    static var guidance: AppTab { .you }
    static var photos: AppTab { .photo }

    var label: String {
        switch self {
        case .today: return "Today"
        case .chart: return "Chart"
        case .photo: return "Photo"
        case .plan: return "Plan"
        case .you: return "You"
        }
    }

    var icon: String {
        switch self {
        case .today: return "list.bullet"
        case .chart: return "chart.xyaxis.line"
        case .photo: return "camera"
        case .plan: return "checklist"
        case .you: return "person"
        }
    }
}

// MARK: - Floating Glass Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                    HapticHelper.selection()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? PremiumTheme.forest : PremiumTheme.mutedInk)

                        Text(tab.label)
                            .font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? PremiumTheme.forest : PremiumTheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? PremiumTheme.teal.opacity(0.18)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: PremiumTheme.forest.opacity(0.12), radius: 24, y: 8)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 28)
    }
}

// MARK: - Dashboard Tab

