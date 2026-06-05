import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct DashboardTab: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    let profile: HairProfile?
    let entries: [CheckInEntry]
    let tasks: [RoutineTask]
    let photoRecords: [PhotoRecord]
    let medications: [MedicationLog]
    let routineCompletions: [RoutineCompletionEntry]
    let medicationEntries: [MedicationDoseEntry]
    let procedureEvents: [ProcedureEvent]
    let lifestyleEntries: [LifestyleEntry]
    let healthInsights: HealthInsightsStore
    let labResults: [LabResultEntry]
    let triggerEvents: [HairTriggerEvent]
    let onAddCheckIn: () -> Void
    let onOpenRoutine: () -> Void

    @State private var isGeneratingIntelligence = false
    @State private var intelligenceSummary = ""
    @State private var intelligenceErrorMessage = ""
    @State private var intelligenceGeneratedAt: Date?
    @State private var scoreRingAnimationProgress: CGFloat = 0
    @State private var visibleCards: Set<Int> = []
    @State private var isPresentingPremiumPaywall = false
    @State private var selectedDashboardWorkspace: DashboardWorkspace = .overview
    @State private var isShowingLogModal = false
    @State private var cachedMetrics = CachedDashboardMetrics()

    // Lightweight fingerprint used to detect data changes without deep comparison.
    private var dataFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(entries.count)
        hasher.combine(entries.first?.id)
        hasher.combine(tasks.count)
        hasher.combine(routineCompletions.count)
        hasher.combine(medicationEntries.count)
        hasher.combine(medications.count)
        hasher.combine(procedureEvents.count)
        hasher.combine(lifestyleEntries.count)
        hasher.combine(labResults.count)
        hasher.combine(triggerEvents.count)
        hasher.combine(photoRecords.count)
        hasher.combine(healthInsights.dailyMetrics.count)
        return hasher.finalize()
    }

    private struct CachedDashboardMetrics {
        var recent30DayEntries: [CheckInEntry] = []
        var previous30DayEntries: [CheckInEntry] = []
        var averageScalp: Int = 0
        var averageHydration: Int = 0
        var averageShedding30Days: Int = 0
        var averageStress30Days: Int = 0
        var sheddingDeltaVsPreviousMonth: Int = 0
        var completionRate: Int = 0
        var recentMedicationAdherenceRate: Int = 0
        var checkInsThisMonth: Int = 0
        var daysSinceLastCheckIn: Int? = nil
        var currentWeekRoutineActions: Int = 0
        var todayMedicationLogs: Int = 0
        var smokingEventsThisMonth: Int = 0
        var supplementEventsThisMonth: Int = 0
        var impactPoints: [RoutineImpactPoint] = []
        var intelligenceReport: IntelligenceReport = IntelligenceReport.empty
        var clinicalAlerts: [GuidanceAlert] = []
        var todayPlanItems: [DashboardPlanItem] = []
    }

    private func recomputeMetrics() async -> CachedDashboardMetrics {
        var m = CachedDashboardMetrics()
        let cal = Calendar.current
        let now = Date.now
        let recent30Start = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let previous60Start = cal.date(byAdding: .day, value: -60, to: now) ?? now

        m.recent30DayEntries = entries.filter { $0.date >= recent30Start }
        m.previous30DayEntries = entries.filter { $0.date >= previous60Start && $0.date < recent30Start }
        m.averageScalp = HairInsightCalculator.averageScore(for: m.recent30DayEntries, keyPath: \.scalpScore)
        m.averageHydration = HairInsightCalculator.averageScore(for: m.recent30DayEntries, keyPath: \.hydrationScore)
        m.averageShedding30Days = HairInsightCalculator.averageScore(for: m.recent30DayEntries, keyPath: \.sheddingLevel)
        m.averageStress30Days = HairInsightCalculator.averageScore(for: m.recent30DayEntries, keyPath: \.stressLevel)

        let previousShedding = HairInsightCalculator.averageScore(for: m.previous30DayEntries, keyPath: \.sheddingLevel)
        m.sheddingDeltaVsPreviousMonth = previousShedding > 0 ? m.averageShedding30Days - previousShedding : 0

        // Completion rate
        let scheduled = tasks.reduce(0) { partial, task in
            partial + scheduledDashboardOccurrences(for: task, between: recent30Start, and: now)
        }
        if scheduled > 0 {
            let completed = routineCompletions.filter { $0.completedAt >= recent30Start }.count
            m.completionRate = Int((Double(min(completed, scheduled)) / Double(scheduled) * 100).rounded())
        }

        // Medication adherence
        let scheduledSlots = medications
            .filter(\.isActive)
            .reduce(0) { partial, medication in
                let labels = MedicationScheduleFormatter.normalizedLabels(
                    from: medication.scheduledTimes,
                    fallbackFrequency: medication.frequencyPerDay
                )
                guard !labels.isEmpty else { return partial }
                let activeStart = max(cal.startOfDay(for: medication.startedAt), cal.startOfDay(for: recent30Start))
                let activeEnd = cal.startOfDay(for: now)
                guard activeStart <= activeEnd else { return partial }
                let activeDays = (cal.dateComponents([.day], from: activeStart, to: activeEnd).day ?? 0) + 1
                return partial + (labels.count * activeDays)
            }
        if scheduledSlots > 0 {
            let completedMeds = medicationEntries.filter { $0.wasTaken && $0.loggedAt >= recent30Start }.count
            m.recentMedicationAdherenceRate = Int((Double(min(completedMeds, scheduledSlots)) / Double(scheduledSlots) * 100).rounded())
        }

        m.checkInsThisMonth = entries.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.count
        if let latest = entries.first {
            m.daysSinceLastCheckIn = cal.dateComponents([.day], from: cal.startOfDay(for: latest.date), to: cal.startOfDay(for: now)).day
        }
        m.currentWeekRoutineActions = routineCompletions.filter { cal.isDate($0.completedAt, equalTo: now, toGranularity: .weekOfYear) }.count
        m.todayMedicationLogs = medicationEntries.filter { $0.wasTaken && cal.isDateInToday($0.loggedAt) }.count
        m.smokingEventsThisMonth = lifestyleEntries
            .filter { $0.category == LifestyleCategory.smoking.rawValue && cal.isDate($0.loggedAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + Int($1.amount.rounded()) }
        m.supplementEventsThisMonth = lifestyleEntries
            .filter { $0.category == LifestyleCategory.supplement.rawValue && cal.isDate($0.loggedAt, equalTo: now, toGranularity: .month) }
            .count

        // Build a Sendable snapshot on the main actor, then run the heavy day-by-day
        // series computation off the main thread so opening the dashboard stays smooth.
        let impactInput = RoutineImpactInput(
            entries: entries,
            routineCompletions: routineCompletions,
            medications: medications,
            medicationEntries: medicationEntries,
            procedureEvents: procedureEvents,
            healthMetricsByDay: healthInsights.metricsByDay,
            lifestyleEntries: lifestyleEntries,
            triggerEvents: triggerEvents
        )
        m.impactPoints = await Task.detached(priority: .userInitiated) {
            RoutineImpactCalculator.buildPoints(impactInput)
        }.value

        m.intelligenceReport = IntelligenceComposer.build(
            entries: entries,
            impactPoints: m.impactPoints,
            labResults: labResults,
            healthMetrics: healthInsights.dailyMetrics,
            medications: medications,
            procedureEvents: procedureEvents
        )

        m.clinicalAlerts = HairClinicalGuidance.alerts(for: entries)

        // Today plan items
        let today = cal.startOfDay(for: now)
        var planItems: [DashboardPlanItem] = []
        let scheduledTasks = tasks
            .filter { doesDashboardTask($0, occurOn: today) }
            .sorted { $0.timeLabel < $1.timeLabel }
            .prefix(3)
            .map {
                DashboardPlanItem(
                    title: $0.title,
                    subtitle: "\($0.timeLabel) • \($0.category)",
                    tint: dashboardCategoryTint($0.category),
                    isComplete: dashboardTaskCompleted($0, on: today)
                )
            }
        planItems.append(contentsOf: scheduledTasks)
        if let medication = medications.first(where: \.isActive), planItems.count < 3 {
            let slotLabel = MedicationScheduleFormatter
                .normalizedLabels(from: medication.scheduledTimes, fallbackFrequency: medication.frequencyPerDay)
                .first ?? "09:00"
            planItems.append(
                DashboardPlanItem(
                    title: medication.name,
                    subtitle: "\(slotLabel) • Medication",
                    tint: Color(red: 0.37, green: 0.53, blue: 0.76),
                    isComplete: medicationEntries.contains {
                        (($0.medication?.id == medication.id) || ($0.medication == nil && $0.medicationName == medication.name)) &&
                        $0.wasTaken &&
                        cal.isDate($0.loggedAt, inSameDayAs: today)
                    }
                )
            )
        }
        m.todayPlanItems = Array(planItems.prefix(3))

        return m
    }

    // Convenience accessors that read from the cache
    private var averageScalp: Int { cachedMetrics.averageScalp }
    private var averageHydration: Int { cachedMetrics.averageHydration }
    private var completionRate: Int { cachedMetrics.completionRate }
    private var impactPoints: [RoutineImpactPoint] { cachedMetrics.impactPoints }
    private var intelligenceReport: IntelligenceReport { cachedMetrics.intelligenceReport }
    private var recent30DayEntries: [CheckInEntry] { cachedMetrics.recent30DayEntries }
    private var previous30DayEntries: [CheckInEntry] { cachedMetrics.previous30DayEntries }
    private var averageShedding30Days: Int { cachedMetrics.averageShedding30Days }
    private var averageStress30Days: Int { cachedMetrics.averageStress30Days }
    private var sheddingDeltaVsPreviousMonth: Int { cachedMetrics.sheddingDeltaVsPreviousMonth }
    private var checkInsThisMonth: Int { cachedMetrics.checkInsThisMonth }
    private var daysSinceLastCheckIn: Int? { cachedMetrics.daysSinceLastCheckIn }
    private var currentWeekRoutineActions: Int { cachedMetrics.currentWeekRoutineActions }
    private var todayMedicationLogs: Int { cachedMetrics.todayMedicationLogs }
    private var smokingEventsThisMonth: Int { cachedMetrics.smokingEventsThisMonth }
    private var supplementEventsThisMonth: Int { cachedMetrics.supplementEventsThisMonth }
    private var clinicalAlerts: [GuidanceAlert] { cachedMetrics.clinicalAlerts }
    private var recentMedicationAdherenceRate: Int { cachedMetrics.recentMedicationAdherenceRate }

    private var recent30DayStart: Date {
        calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
    }

    private var streak: Int {
        HairInsightCalculator.currentStreak(for: entries)
    }

    private var nextWashDate: Date {
        HairInsightCalculator.nextWashDate(
            from: .now,
            frequencyDays: profile?.washFrequencyDays ?? 4,
            preferredHour: profile?.preferredWashHour ?? 19
        )
    }

    private var recentEntries: [CheckInEntry] {
        Array(entries.prefix(3))
    }

    private var sparklineHeights: [CGFloat] {
        let source = recent30DayEntries.suffix(24)
        if source.isEmpty {
            return (0..<24).map { CGFloat(($0 * 7 + 13) % 22 + 6) }
        }
        return source.map { CGFloat($0.scalpScore) / 100 * 22 + 6 }
    }

    private var upcomingTasks: [RoutineTask] {
        Array(tasks.sorted(by: taskSort).prefix(3))
    }

    private var latestHealthMetric: HealthDailyMetric? {
        healthInsights.dailyMetrics.last
    }

    private var calendar: Calendar {
        .current
    }

    private var labCount: Int {
        labResults.count
    }

    private var latestLabText: String {
        guard let latestLabDate else { return "No labs logged" }
        return "Last lab \(latestLabDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var latestSleepText: String {
        guard let latestHealthMetric, latestHealthMetric.sleepHours > 0 else {
            return "Sleep unavailable"
        }

        return String(format: "Sleep %.1f h", latestHealthMetric.sleepHours)
    }

    private var latestExerciseText: String {
        guard let latestHealthMetric, latestHealthMetric.exerciseMinutes > 0 else {
            return "Exercise unavailable"
        }

        return String(format: "Exercise %.0f min", latestHealthMetric.exerciseMinutes)
    }

    private var latestLabDate: Date? {
        labResults.first?.collectedAt
    }

    private var needsLabPrompt: Bool {
        guard let latestLabDate else { return true }
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: .now) ?? .now
        return latestLabDate < sixMonthsAgo
    }

    private var labPromptTitle: String {
        if labResults.isEmpty {
            return "No hair-related labs logged"
        }
        return "Lab results may be out of date"
    }

    private var labPromptMessage: String {
        if labResults.isEmpty {
            return "If shedding is persistent or supplements are being considered, logging ferritin, vitamin D, thyroid, B12, or other tested results can make the routine more evidence-based."
        }
        return "Your latest logged result is older than six months. If symptoms changed or supplements were started, consider updating ferritin, vitamin D, thyroid, or other clinician-ordered tests."
    }

    private var recentPhotoCount: Int {
        let cutoff = calendar.date(byAdding: .day, value: -60, to: .now) ?? .now
        return photoRecords.filter { $0.createdAt >= cutoff }.count
    }

    private var recentRelevantLabCount: Int {
        let cutoff = calendar.date(byAdding: .month, value: -6, to: .now) ?? .now
        return labResults.filter { $0.collectedAt >= cutoff }.count
    }

    private var hasUnlockedTrackingScore: Bool {
        hasMinimumTrackingInputs
    }

    private var hasMinimumTrackingInputs: Bool {
        recent30DayEntries.count >= 4 && (recentPhotoCount >= 2 || photoRecords.isEmpty)
    }

    private var trackingDepthScore: Int {
        let checkInDepth = min(recent30DayEntries.count * 12, 60)
        let photoDepth = min(recentPhotoCount * 10, 20)
        let labDepth = min(recentRelevantLabCount * 5, 10)
        let routineDepth = min(completionRate / 10, 10)
        return min(checkInDepth + photoDepth + labDepth + routineDepth, 100)
    }

    private var symptomStabilityScore: Int {
        let scalpComfort = Double(averageScalp) * 0.35
        let hydrationComfort = Double(averageHydration) * 0.15
        let sheddingBurdenInverse = Double(max(0, 100 - averageShedding30Days)) * 0.30
        let stressBurdenInverse = Double(max(0, 100 - averageStress30Days)) * 0.20
        return Int((scalpComfort + hydrationComfort + sheddingBurdenInverse + stressBurdenInverse).rounded())
    }

    private var trackingScore: Int {
        guard hasMinimumTrackingInputs else { return 0 }
        let symptomSignal = Double(symptomStabilityScore) * 0.45
        let routineSignal = Double(completionRate) * 0.25
        let dataSignal = Double(trackingDepthScore) * 0.20
        let adherenceSignal = Double(recentMedicationAdherenceRate) * 0.10
        return Int((symptomSignal + routineSignal + dataSignal + adherenceSignal).rounded())
    }

    private var trackingConfidenceLabel: String {
        if recent30DayEntries.count >= 12 && recentPhotoCount >= 3 && recentRelevantLabCount > 0 {
            return "Stronger"
        }
        if recent30DayEntries.count >= 8 && recentPhotoCount >= 2 {
            return "Medium"
        }
        if recent30DayEntries.count >= 4 {
            return "Early"
        }
        return "Low"
    }

    private var trackingConfidenceTint: Color {
        switch trackingConfidenceLabel {
        case "Stronger":
            return Color(red: 0.24, green: 0.52, blue: 0.43)
        case "Medium":
            return Color(red: 0.30, green: 0.45, blue: 0.74)
        case "Early":
            return Color(red: 0.73, green: 0.53, blue: 0.26)
        default:
            return Color(red: 0.66, green: 0.40, blue: 0.25)
        }
    }

    private var scoreMethodNote: String {
        if !hasUnlockedTrackingScore {
            return "Onboarding creates a starting plan and reported context. The numeric score appears only after repeated real logs."
        }
        return "Built from recent symptom stability, recent routine consistency, medication adherence, and repeated data depth."
    }

    private var heroStatusLine: String {
        if !hasUnlockedTrackingScore {
            return "Baseline context comes from what you reported in onboarding. It shapes the plan, but it does not measure severity or progress."
        }
        if trackingConfidenceLabel == "Low" {
            return "Your tracking score is still early because repeated check-ins and comparable photos are limited."
        }
        if averageShedding30Days <= 25 {
            return "Recent symptom signals look calmer, and your tracking picture is becoming more reliable."
        }
        if averageShedding30Days >= 50 {
            return "Recent shedding is elevated. The score helps summarize your logs, but the pattern still needs context."
        }
        return "Your score is mixed. Use routine adherence and repeated check-ins to sharpen the picture."
    }

    private var baselineFocusText: String {
        guard let focus = profile?.hairLossFocus, !focus.isEmpty else { return "Not set yet" }
        return focus
    }

    private var baselinePatternText: String {
        trimmedOrFallback(profile?.patternDistribution, fallback: "No specific distribution reported")
    }

    private var baselineFamilyHistoryText: String {
        trimmedOrFallback(profile?.familyHistorySummary, fallback: "No family history reported")
    }

    private var baselineScalpText: String {
        trimmedOrFallback(profile?.scalpSensitivity, fallback: "Scalp pattern not set")
    }

    private var baselineWashText: String {
        let frequency = profile?.washFrequencyDays ?? 0
        guard frequency > 0 else { return "Wash rhythm not set" }
        return frequency == 1 ? "Daily wash rhythm" : "Every \(frequency) days"
    }

    private var onboardingTriggerSummaries: [String] {
        triggerEvents
            .filter { $0.details.contains(InitialRoutinePlanner.triggerMarker) }
            .prefix(3)
            .map(\.title)
    }

    private var baselineUnlockText: String {
        if hasUnlockedTrackingScore {
            return "Repeated check-ins and recent photo history are strong enough to support measured dashboard tracking."
        }
        if recent30DayEntries.isEmpty {
            return "Log at least 4 recent check-ins and 2 comparable photo sessions to unlock measured tracking."
        }
        return "Keep building repeated check-ins and comparable photos before the dashboard turns onboarding context into measurement."
    }

    private var todayPlanItems: [DashboardPlanItem] {
        cachedMetrics.todayPlanItems
    }

    private var routineCompletionSummary: (completed: Int, total: Int) {
        let total = todayPlanItems.count
        let completed = todayPlanItems.filter(\.isComplete).count
        return (completed, total)
    }

    private var widgetSnapshot: HairCompassWidgetSnapshot {
        HairCompassWidgetSnapshot(
            generatedAt: .now,
            routineHeadline: routineCompletionSummary.total == 0 ? "Build your first routine" : routineCTAHeadline,
            progressLabel: routineCompletionSummary.total == 0 ? "No routine scheduled today" : "\(routineCompletionSummary.completed) of \(routineCompletionSummary.total) complete",
            checkInLabel: lastCheckInText,
            completedCount: routineCompletionSummary.completed,
            totalCount: routineCompletionSummary.total,
            upcomingTitles: todayPlanItems.prefix(3).map(\.title)
        )
    }

    private var routineProgressValue: Double {
        guard routineCompletionSummary.total > 0 else { return 0 }
        return Double(routineCompletionSummary.completed) / Double(routineCompletionSummary.total)
    }

    private func publishWidgetSnapshot() {
        guard let defaults = UserDefaults(suiteName: HairCompassWidgetStore.appGroup),
              let data = try? JSONEncoder().encode(widgetSnapshot) else {
            return
        }
        defaults.set(data, forKey: HairCompassWidgetStore.snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "HairCompassCheckInWidget")
    }

    private func saveQuickLog(sheddingValue: Int, triggers: Set<String>) {
        let entry = CheckInEntry(
            date: .now,
            scalpScore: averageScalp > 0 ? averageScalp : 70,
            hydrationScore: averageHydration > 0 ? averageHydration : 70,
            sheddingLevel: sheddingValue,
            stressLevel: triggers.contains("High stress") ? 80 : averageStress30Days,
            hasItch: false,
            hasFlaking: false,
            hasScalpPain: false,
            hasPatchyHairLoss: false,
            hasTightStyleTension: triggers.contains("Tight style"),
            isWashDay: true,
            note: triggers.isEmpty ? "Quick log" : "Triggers: \(triggers.sorted().joined(separator: ", "))"
        )
        modelContext.insert(entry)
        HapticHelper.success()
        AnalyticsService.log("quick_log_saved", properties: [
            "shedding": String(sheddingValue),
            "triggers": triggers.sorted().joined(separator: ",")
        ])
    }

    private var routineCTAHeadline: String {
        if routineCompletionSummary.total == 0 {
            return "Set up your first routine"
        }
        if routineCompletionSummary.completed == routineCompletionSummary.total {
            return "Routine complete today"
        }
        return "\(routineCompletionSummary.total - routineCompletionSummary.completed) actions waiting today"
    }

    private var routineCTASubtitle: String {
        if let firstPending = todayPlanItems.first(where: { !$0.isComplete }) {
            return "Next: \(firstPending.title) • \(firstPending.subtitle)"
        }
        if routineCompletionSummary.total == 0 {
            return "Build a routine so the app can guide your next step."
        }
        return "You have completed every planned action for today."
    }

    private var latestJourneyRecord: PhotoRecord? {
        photoRecords.first
    }

    private var journeyCaption: String {
        if let latestJourneyRecord {
            return "\(latestJourneyRecord.angle) • \(latestJourneyRecord.createdAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return "No progress photo yet"
    }

    private var greetingName: String {
        guard let name = profile?.name, !name.isEmpty else { return "there" }
        return name
    }

    private func trimmedOrFallback(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    var body: some View {
        ZStack {
            appBackground
            dashboardAtmosphere

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DashboardSpacing.section) {
                    animatedCard(0) { dashboardRevampHeader }
                    // The Strand Compass score is the app's signature metric, so on the
                    // default Overview landing it now leads the hierarchy directly under
                    // the greeting instead of sitting below the stats/picker/pulse cards.
                    if selectedDashboardWorkspace == .overview {
                        animatedCard(1) { heroCard }
                    }
                    animatedCard(2) { dashboardCommandCenter }
                    animatedCard(3) { dashboardWorkspacePicker }
                    animatedCard(4) { dashboardPulseStrip }
                    dashboardWorkspaceDeck
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DashboardSpacing.horizontalPadding)
                .padding(.top, DashboardSpacing.topPadding)
                .padding(.bottom, DashboardSpacing.bottomPadding)
            }
            .safeAreaPadding(.top, 12)
            .safeAreaPadding(.horizontal, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isPresentingPremiumPaywall) {
            PremiumPaywallView()
        }
        .sheet(isPresented: $isShowingLogModal) {
            LogSheddingModal(
                averageShedding: averageShedding30Days,
                onSave: { sheddingValue, triggers in
                    saveQuickLog(sheddingValue: sheddingValue, triggers: triggers)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(36)
            .presentationBackground(.clear)
        }
        .task(id: widgetSnapshot) {
            publishWidgetSnapshot()
        }
        .onAppear {
            AnalyticsService.log("dashboard_viewed")
        }
        // `.task(id:)` already fires once on first appearance and again whenever the
        // data fingerprint changes, so the previous `.onAppear` recompute was redundant
        // double work on open. A single source of truth keeps the Today tab snappier.
        .task(id: dataFingerprint) {
            cachedMetrics = await recomputeMetrics()
        }
        .onChange(of: selectedDashboardWorkspace) { _, newValue in
            AnalyticsService.log("dashboard_workspace_changed", properties: [
                "workspace": newValue.rawValue
            ])
        }
    }

    private enum DashboardSpacing {
        static let section: CGFloat = 18
        static let card: CGFloat = 12
        static let row: CGFloat = 10
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 12
        static let bottomPadding: CGFloat = 40
    }

    private enum DashboardTypography {
        static let display = Font.system(size: 34, weight: .black, design: .rounded)
        static let heading = Font.system(size: 17, weight: .bold, design: .rounded)
        static let body = Font.system(size: 14, weight: .medium, design: .rounded)
        static let label = Font.system(size: 12, weight: .bold, design: .rounded)
        static let value = Font.system(size: 18, weight: .bold, design: .rounded)
        static let micro = Font.system(size: 10, weight: .bold, design: .rounded)
    }

    private enum DashboardWorkspace: String, CaseIterable, Identifiable {
        case overview
        case today
        case intelligence
        case clinical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .today: return "Today"
            case .intelligence: return "Intelligence"
            case .clinical: return "Clinical"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2.fill"
            case .today: return "calendar.badge.clock"
            case .intelligence: return "sparkles.rectangle.stack"
            case .clinical: return "cross.case.fill"
            }
        }
    }

    private var dashboardRevampHeader: some View {
        VStack(alignment: .leading, spacing: DashboardSpacing.card) {
            // Monospace eyebrow date
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(PremiumTheme.mutedInk)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text("Morning, ")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(PremiumTheme.ink)
                        Text(greetingName)
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .italic()
                            .foregroundStyle(PremiumTheme.forest)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }

                Spacer()

                // Avatar circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [PremiumTheme.sand, PremiumTheme.gold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(String((profile?.name ?? "A").prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(PremiumTheme.ink)
                }
                .frame(width: 44, height: 44)
                .shadow(color: PremiumTheme.gold.opacity(0.3), radius: 8, y: 2)
            }
        }
        .cardStyle()
    }

    private var dashboardCommandCenter: some View {
        VStack(alignment: .leading, spacing: DashboardSpacing.card) {
            HStack(spacing: DashboardSpacing.row) {
                dashboardCommandChip(title: "Tracking", value: "\(trackingScore)%", tint: PremiumTheme.forest)
                dashboardCommandChip(title: "Routine", value: "\(completionRate)%", tint: PremiumTheme.teal)
                dashboardCommandChip(title: "Shedding", value: "\(averageShedding30Days)%", tint: PremiumTheme.gold)
            }

            // CTA buttons row
            HStack(spacing: 10) {
                // Quick Log button (opens Log modal)
                Button {
                    HapticHelper.medium()
                    isShowingLogModal = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Quick Log")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(PremiumTheme.forest)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        PremiumTheme.forest.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PremiumTheme.forest.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Full Check-In button
                Button {
                    HapticHelper.medium()
                    onAddCheckIn()
                } label: {
                    HStack(spacing: 6) {
                        Text("Full Check-In")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(PremiumTheme.forestTealGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: PremiumTheme.forest.opacity(0.2), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private func dashboardCommandChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(PremiumTheme.mutedInk)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dashboardWorkspacePicker: some View {
        VStack(alignment: .leading, spacing: DashboardSpacing.card) {
            Text("Workspace")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 0.44, green: 0.50, blue: 0.47))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DashboardWorkspace.allCases) { workspace in
                        let isSelected = selectedDashboardWorkspace == workspace
                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                                selectedDashboardWorkspace = workspace
                            }
                            HapticHelper.selection()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: workspace.icon)
                                    .font(.system(size: 12, weight: .bold))
                                Text(workspace.title)
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                if isSelected {
                                    Text(workspaceBadgeValue(for: workspace))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.28), in: Capsule())
                                }
                            }
                            .foregroundStyle(isSelected ? .white : Color(red: 0.20, green: 0.24, blue: 0.22))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                isSelected
                                ? Color(red: 0.22, green: 0.50, blue: 0.43)
                                : Color.white.opacity(0.85),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
                            )
                            .scaleEffect(isSelected ? 1.04 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dashboardWorkspace_\(workspace.rawValue)")
                    }
                }
            }
        }
        .cardStyle()
    }

    private func workspaceBadgeValue(for workspace: DashboardWorkspace) -> String {
        switch workspace {
        case .overview:
            return "\(checkInsThisMonth)"
        case .today:
            return "\(routineCompletionSummary.completed)/\(max(routineCompletionSummary.total, 1))"
        case .intelligence:
            return intelligenceSummary.isEmpty ? "New" : "Ready"
        case .clinical:
            return "\(clinicalAlerts.count)"
        }
    }

    private var dashboardPulseStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DashboardSpacing.row) {
                pulseTile(
                    title: "Last Check-In",
                    value: daysSinceLastCheckIn.map { "\($0)d ago" } ?? "No data",
                    tint: Color(red: 0.34, green: 0.56, blue: 0.72)
                )
                pulseTile(
                    title: "Medication",
                    value: "\(recentMedicationAdherenceRate)%",
                    tint: Color(red: 0.32, green: 0.48, blue: 0.78)
                )
                pulseTile(
                    title: "Photos 60D",
                    value: "\(recentPhotoCount)",
                    tint: Color(red: 0.63, green: 0.45, blue: 0.73)
                )
                pulseTile(
                    title: "Latest Sleep",
                    value: latestSleepText,
                    tint: Color(red: 0.28, green: 0.53, blue: 0.56)
                )
                pulseTile(
                    title: "Latest Exercise",
                    value: latestExerciseText,
                    tint: Color(red: 0.34, green: 0.59, blue: 0.43)
                )
            }
        }
    }

    private func pulseTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.47, green: 0.53, blue: 0.50))
            Text(value)
                .font(DashboardTypography.body.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 150, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var dashboardWorkspaceDeck: some View {
        VStack(alignment: .leading, spacing: DashboardSpacing.section) {
            dashboardWorkspaceContent(selectedDashboardWorkspace)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedDashboardWorkspace)
    }

    @ViewBuilder
    private func dashboardWorkspaceContent(_ workspace: DashboardWorkspace) -> some View {
        switch workspace {
        case .overview:
            // heroCard is now promoted above the fold (see body); the Overview deck
            // continues with the trend chart and supporting detail.
            animatedCard(5) { dashboardChartCard }
            animatedCard(6) { metricGrid }
            animatedCard(7) { healthLifestyleCard }
            animatedCard(8) { journeyCard }
        case .today:
            animatedCard(4) { routinePromptCard }
            animatedCard(5) { dailyPlanCard }
            animatedCard(6) { upcomingRoutineCard }
            animatedCard(7) { recentCheckInsCard }
            animatedCard(8) { metricGrid }
        case .intelligence:
            animatedCard(4) { intelligenceCard }
            animatedCard(5) { summaryCard }
            if profile?.hasCompletedOnboarding == true {
                animatedCard(6) { baselineContextCard }
            }
            animatedCard(7) { dashboardChartCard }
            if needsLabPrompt {
                animatedCard(8) { labPromptCard }
            }
        case .clinical:
            if !clinicalAlerts.isEmpty {
                animatedCard(4) { alertCard }
            }
            if needsLabPrompt {
                animatedCard(5) { labPromptCard }
            }
            animatedCard(6) { healthLifestyleCard }
            animatedCard(7) { dashboardChartCard }
            animatedCard(8) { recentCheckInsCard }
        }
    }



    private func animatedCard<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(visibleCards.contains(index) ? 1 : 0)
            .offset(y: visibleCards.contains(index) ? 0 : 24)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.82)
                    .delay(Double(index) * 0.06),
                value: visibleCards.contains(index)
            )
            .onAppear {
                visibleCards.insert(index)
            }
    }

    private var dashboardAtmosphere: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PremiumTheme.teal.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 200
                    )
                )
                .frame(width: 380, height: 380)
                .blur(radius: 40)
                .offset(x: -100, y: -280)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [PremiumTheme.gold.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 160
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 30)
                .offset(x: 140, y: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Dark forest compass card
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PremiumTheme.compassHeroGradient)

                // Compass SVG motif (simplified)
                Circle()
                    .stroke(PremiumTheme.gold.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 120, height: 120)
                    .offset(x: 80, y: -10)

                Circle()
                    .stroke(PremiumTheme.gold.opacity(0.12), lineWidth: 1)
                    .frame(width: 180, height: 180)
                    .offset(x: 80, y: -10)

                // Compass needle
                Image(systemName: "safari")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(PremiumTheme.gold.opacity(0.4))
                    .offset(x: 80, y: -10)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("STRAND COMPASS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(PremiumTheme.gold.opacity(0.7))

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(trackingScore)")
                                    .font(.system(size: 48, weight: .bold, design: .serif))
                                    .foregroundStyle(PremiumTheme.gold)
                                Text("/100")
                                    .font(.system(size: 18, weight: .medium, design: .serif))
                                    .foregroundStyle(PremiumTheme.gold.opacity(0.6))
                            }

                            if sheddingDeltaVsPreviousMonth != 0 {
                                Text("\(sheddingDeltaVsPreviousMonth > 0 ? "↑" : "↓") \(abs(sheddingDeltaVsPreviousMonth)) this month")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(PremiumTheme.goldSoft.opacity(0.8))
                            }
                        }
                        Spacer()
                    }

                    // Mini sparkline bar chart
                    HStack(spacing: 2) {
                        ForEach(Array(sparklineHeights.enumerated()), id: \.offset) { _, height in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [PremiumTheme.teal, PremiumTheme.gold],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: 6, height: height)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(0.7)
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: PremiumTheme.forest.opacity(0.3), radius: 20, y: 10)

            // Today's rituals section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Today · \(todayPlanItems.count) rituals")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(PremiumTheme.ink)
                    Spacer()
                }

                ForEach(todayPlanItems) { item in
                    HStack(spacing: 12) {
                        // Colored left accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.tint)
                            .frame(width: 4, height: 36)

                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(item.isComplete ? PremiumTheme.forest : PremiumTheme.mutedInk)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PremiumTheme.ink)
                                .strikethrough(item.isComplete)
                            Text(item.subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PremiumTheme.mutedInk)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }

            // Metric grid 2x2
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                compassMetricTile(label: "SCALP", value: averageScalp, tint: PremiumTheme.forest)
                compassMetricTile(label: "SHED", value: averageShedding30Days, tint: PremiumTheme.teal)
                compassMetricTile(label: "HYDRATION", value: averageHydration, tint: PremiumTheme.teal)
                compassMetricTile(label: "STRESS", value: averageStress30Days, tint: PremiumTheme.gold)
            }
        }
        .heroCardStyle()
    }

    private func compassMetricTile(label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(PremiumTheme.mutedInk)
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(PremiumTheme.ink)
            // Delta indicator dots
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < (value / 34) ? tint : tint.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PremiumTheme.forest.opacity(0.06), lineWidth: 1)
        )
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            dashboardSectionHeader(
                title: "Hair Compass",
                subtitle: "Current conditions for your hair, routine, and progress.",
                badge: Date.now.formatted(.dateTime.weekday(.abbreviated).day()),
                titleSize: 30,
                subtitleSize: 15,
                accessibilityIdentifier: "hairHealthTrackerTitle"
            )

            HStack(spacing: 12) {
                dashboardHeaderMetric(title: "Check-Ins", value: "\(checkInsThisMonth) this month")
                dashboardHeaderMetric(title: "Streak", value: streak > 0 ? "\(streak)d" : "—")
                dashboardHeaderMetric(title: "Routine", value: "\(completionRate)%")
            }
        }
        .cardStyle()
    }

    private func dashboardHeaderMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.47, green: 0.53, blue: 0.50))
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var heroTopSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    heroTitleBlock
                    Spacer(minLength: 12)
                    heroBellButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    heroTitleBlock
                    heroBellButton
                }
            }

            Button {
                HapticHelper.medium()
                onAddCheckIn()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Check-In")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.38, green: 0.53, blue: 0.76), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var heroTitleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.46, green: 0.57, blue: 0.53))
                .textCase(.uppercase)

            Text(profile?.name.isEmpty == false ? "Hi, \(profile?.name ?? "there")" : "Hi there")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(heroSubtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.39, green: 0.45, blue: 0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroBellButton: some View {
        Image(systemName: "bell.badge")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color(red: 0.46, green: 0.57, blue: 0.53))
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(0.8), in: Circle())
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            MetricTile(
                title: "Shedding 30D",
                value: "\(averageShedding30Days)%",
                caption: sheddingDeltaText,
                icon: "wind",
                tint: Color(red: 0.84, green: 0.56, blue: 0.28)
            )

            MetricTile(
                title: "Check-Ins",
                value: "\(checkInsThisMonth)",
                caption: lastCheckInText,
                icon: "calendar.badge.clock",
                tint: Color(red: 0.44, green: 0.41, blue: 0.70)
            )

            MetricTile(
                title: "Routine Activity",
                value: "\(currentWeekRoutineActions)",
                caption: "\(todayMedicationLogs) medication logs today",
                icon: "checkmark.circle.badge.questionmark",
                tint: Color(red: 0.19, green: 0.35, blue: 0.56)
            )

            MetricTile(
                title: "Lab Coverage",
                value: "\(labCount)",
                caption: latestLabText,
                icon: "testtube.2",
                tint: Color(red: 0.55, green: 0.33, blue: 0.30)
            )
        }
    }

    private var routinePromptCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            dashboardSectionHeader(
                title: "Today’s Routine",
                subtitle: [routineCTAHeadline, routineCTASubtitle].joined(separator: "\n"),
                badge: routineCompletionSummary.total == 0 ? "Ready" : "\(routineCompletionSummary.completed)/\(routineCompletionSummary.total)"
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(routineCompletionSummary.completed) of \(max(routineCompletionSummary.total, 1)) done")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.39, green: 0.45, blue: 0.42))
                    Spacer()
                    Text("\(Int((routineProgressValue * 100).rounded()))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.17, green: 0.34, blue: 0.30))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 0.89, green: 0.92, blue: 0.90))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.44, green: 0.67, blue: 0.62),
                                        Color(red: 0.26, green: 0.47, blue: 0.41)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(proxy.size.width * routineProgressValue, routineProgressValue > 0 ? 18 : 0))
                    }
                }
                .frame(height: 10)
            }

            if !todayPlanItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(todayPlanItems.prefix(2))) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(item.isComplete ? item.tint : item.tint.opacity(0.18))
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(item.subtitle)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button {
                onOpenRoutine()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .frame(width: 18)
                    Text(routineCompletionSummary.total == 0 ? "Open Routine Setup" : "Open Routine")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .frame(width: 18)
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.42, blue: 0.39),
                            Color(red: 0.16, green: 0.30, blue: 0.28)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .heroCardStyle()
    }

    private var routinePromptHeaderText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today’s Routine")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
            Text(routineCTAHeadline)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.31, green: 0.45, blue: 0.40))
            Text(routineCTASubtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routinePromptBadge: some View {
        Text(routineCompletionSummary.total == 0 ? "Ready" : "\(routineCompletionSummary.completed)/\(routineCompletionSummary.total)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.17, green: 0.34, blue: 0.30))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.78), in: Capsule())
    }

    private var dailyPlanCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today’s Plan")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                    Text("A calmer view of what matters today.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                }
                Spacer(minLength: 0)

                Image("routine-lifestyle-soft")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 8)
            }

            if todayPlanItems.isEmpty {
                Text("No tasks are scheduled for today yet. Add a routine item or medication to start building your day plan.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
            } else {
                ForEach(todayPlanItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(item.isComplete ? item.tint : Color.gray.opacity(0.6))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
                            Text(item.subtitle)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .cardStyle()
    }

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hair Journey")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                    Text("Photo tracking and recent progress in one place.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                }
                Spacer(minLength: 8)
                Text(journeyCaption)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.33, green: 0.47, blue: 0.44))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.85), in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    weatherModuleFrame {
                        journeyImagePanel
                    }
                    journeyStatsColumn
                }

                VStack(alignment: .leading, spacing: 14) {
                    weatherModuleFrame {
                        journeyImagePanel
                    }
                    journeyStatsGrid
                }
            }
        }
        .cardStyle()
    }

    private var baselineContextCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            dashboardSectionHeader(
                title: "Baseline Context",
                subtitle: "Reported onboarding context that shapes your starting plan. It is not a measured severity score.",
                badge: "Reported"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                baselineContextTile(title: "Tracking Focus", value: baselineFocusText, tint: Color(red: 0.83, green: 0.92, blue: 0.98))
                baselineContextTile(title: "Pattern", value: baselinePatternText, tint: Color(red: 0.95, green: 0.92, blue: 0.85))
                baselineContextTile(title: "Family History", value: baselineFamilyHistoryText, tint: Color(red: 0.92, green: 0.89, blue: 0.96))
                baselineContextTile(title: "Starting Assumption", value: "\(baselineScalpText) • \(baselineWashText)", tint: Color(red: 0.89, green: 0.95, blue: 0.91))
            }

            if !onboardingTriggerSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reported Trigger Context")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.48, green: 0.55, blue: 0.51))
                        .textCase(.uppercase)

                    ForEach(onboardingTriggerSummaries, id: \.self) { title in
                        Text(title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.82), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                    }
                }
            }

            Text(baselineUnlockText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func baselineContextTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.48, green: 0.55, blue: 0.51))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var dashboardScoreRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: 12)
            Circle()
                .trim(from: 0, to: scoreRingAnimationProgress * CGFloat(trackingScore) / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.57, green: 0.74, blue: 0.92),
                            Color(red: 0.59, green: 0.78, blue: 0.67),
                            Color(red: 0.57, green: 0.74, blue: 0.92)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 3) {
                Text("\(Int(Double(trackingScore) * scoreRingAnimationProgress))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
                    .contentTransition(.numericText())
                Text("Tracking Score")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.46, green: 0.57, blue: 0.53))
                    .textCase(.uppercase)
            }
        }
        .frame(width: 132, height: 132)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                scoreRingAnimationProgress = 1.0
            }
        }
    }

    private var dashboardPrimaryVisual: some View {
        Group {
            if hasUnlockedTrackingScore {
                dashboardScoreRing
            } else {
                trackingReadinessPanel
            }
        }
    }

    private func dashboardSectionHeader(
        title: String,
        subtitle: String,
        badge: String,
        titleSize: CGFloat = 22,
        subtitleSize: CGFloat = 14,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                dashboardSectionHeaderText(
                    title: title,
                    subtitle: subtitle,
                    titleSize: titleSize,
                    subtitleSize: subtitleSize,
                    accessibilityIdentifier: accessibilityIdentifier
                )
                Spacer(minLength: 12)
                dashboardSectionBadge(badge)
            }

            VStack(alignment: .leading, spacing: 12) {
                dashboardSectionHeaderText(
                    title: title,
                    subtitle: subtitle,
                    titleSize: titleSize,
                    subtitleSize: subtitleSize,
                    accessibilityIdentifier: accessibilityIdentifier
                )
                dashboardSectionBadge(badge)
            }
        }
    }

    @ViewBuilder
    private func dashboardSectionHeaderText(
        title: String,
        subtitle: String,
        titleSize: CGFloat,
        subtitleSize: CGFloat,
        accessibilityIdentifier: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let accessibilityIdentifier {
                Text(title)
                    .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.14))
                    .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                Text(title)
                    .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.14))
            }
            Text(subtitle)
                .font(.system(size: subtitleSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardSectionBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.18, green: 0.27, blue: 0.24))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.85), in: Capsule())
    }

    private var trackingReadinessPanel: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.27, green: 0.47, blue: 0.73))

            Text("Tracking score locked")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))

            Text("It unlocks after repeated check-ins and comparable history.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                softMetricBadge(title: "Check-Ins", value: "\(recent30DayEntries.count)/4")
                softMetricBadge(title: "Photos", value: "\(min(recentPhotoCount, 2))/2")
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func softMetricBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.48, green: 0.55, blue: 0.51))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func miniJourneyStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.47, green: 0.53, blue: 0.50))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
    }

    private func weatherModuleFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.36), lineWidth: 1)
            )
    }

    private var intelligenceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topLeading) {
                Image("intelligence-ambient-soft")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.52),
                                Color.white.opacity(0.88)
                            ],
                            startPoint: .top,
                            endPoint: .bottomLeading
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        intelligenceHeaderText

                        Spacer(minLength: 12)

                        intelligenceGenerateButton
                    }
                    .padding(18)

                    VStack(alignment: .leading, spacing: 14) {
                        intelligenceHeaderText
                        intelligenceGenerateButton
                    }
                    .padding(18)
                }
            }
            .buttonStyle(.plain)
            .disabled(purchaseManager.hasPremiumAccess && (isGeneratingIntelligence || openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            intelligencePanel(
                title: intelligenceReport.headline,
                tint: Color(red: 0.17, green: 0.34, blue: 0.30),
                bodyText: "Confidence: \(intelligenceReport.confidenceLabel)",
                emphasized: true
            )

            if !intelligenceReport.observations.isEmpty {
                intelligenceGroup(title: "Observed Patterns", tint: Color(red: 0.22, green: 0.49, blue: 0.43), items: intelligenceReport.observations)
            }

            if !intelligenceReport.suggestions.isEmpty {
                intelligenceGroup(title: "Useful Next Steps", tint: Color(red: 0.73, green: 0.53, blue: 0.26), items: intelligenceReport.suggestions)
            }

            if !intelligenceReport.dataGaps.isEmpty {
                intelligenceGroup(title: "Missing Context", tint: Color(red: 0.48, green: 0.47, blue: 0.65), items: intelligenceReport.dataGaps)
            }

            intelligenceEvidencePanel

            if !intelligenceReport.reviewFlags.isEmpty {
                intelligenceGroup(title: "Clinical Review Flags", tint: Color(red: 0.68, green: 0.31, blue: 0.25), items: intelligenceReport.reviewFlags)
            }

            if purchaseManager.hasPremiumAccess {
                if openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SecureField("OpenAI API Key", text: $openAIAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.80), lineWidth: 1)
                        )

                    Text("Add your API key here to enable AI-generated Intelligence. When you use this feature, relevant logs, labs, medication history, procedures, triggers, and related summaries may be sent directly from the app to OpenAI. Do not use this feature as medical advice or diagnosis.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.40, green: 0.45, blue: 0.42))
                } else if let intelligenceGeneratedAt, !intelligenceSummary.isEmpty {
                    Text("AI-generated \(intelligenceGeneratedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.41, green: 0.46, blue: 0.43))
                        .textCase(.uppercase)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.85), in: Capsule())
                }

                if !intelligenceSummary.isEmpty {
                    intelligencePanel(
                        title: "AI-generated reading",
                        tint: Color(red: 0.14, green: 0.37, blue: 0.54),
                        bodyText: intelligenceSummary,
                        emphasized: true
                    )
                }

                if !intelligenceErrorMessage.isEmpty {
                    Text(intelligenceErrorMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.62, green: 0.17, blue: 0.13))
                }
            } else {
                PremiumLockedCallout(
                    title: "Hair Compass Pro",
                    detail: "Upgrade to unlock AI-generated Intelligence based on your own logs. Rule-based safety prompts stay available for all users.",
                    actionTitle: "View Pro"
                ) {
                    isPresentingPremiumPaywall = true
                }
            }
        }
        .heroCardStyle()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Last 30 Days")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))

            Text(weeklySummary)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.33, green: 0.39, blue: 0.35))
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    dashboardBadge(label: scalpSignalBadge, tint: Color(red: 0.27, green: 0.48, blue: 0.42))
                    dashboardBadge(label: stressSignalBadge, tint: Color(red: 0.80, green: 0.56, blue: 0.34))
                }

                VStack(alignment: .leading, spacing: 8) {
                    dashboardBadge(label: scalpSignalBadge, tint: Color(red: 0.27, green: 0.48, blue: 0.42))
                    dashboardBadge(label: stressSignalBadge, tint: Color(red: 0.80, green: 0.56, blue: 0.34))
                }
            }
        }
        .secondaryCardStyle()
    }

    private func intelligencePanel(title: String, tint: Color, bodyText: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
            Text(bodyText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.37, green: 0.43, blue: 0.40))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(emphasized ? Color.white.opacity(0.80) : tint.opacity(0.08))
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(emphasized ? tint.opacity(0.22) : tint.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: emphasized ? tint.opacity(0.10) : .clear, radius: 12, y: 8)
    }

    private func intelligenceGroup(title: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.20))
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint)
                            .padding(.top, 3)
                        Text(item)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.36, green: 0.41, blue: 0.39))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var intelligenceEvidencePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.24, green: 0.42, blue: 0.60))
                    .frame(width: 8, height: 8)
                Text("How Intelligence built this")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.20))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(intelligenceDataRows, id: \.title) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.46, green: 0.52, blue: 0.49))
                        Text(row.value)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(intelligenceReasonRows, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.24, green: 0.42, blue: 0.60))
                            .padding(.top, 3)
                        Text(item)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.36, green: 0.41, blue: 0.39))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 1)
        )
    }

    private var intelligenceDataRows: [(title: String, value: String)] {
        [
            ("Check-ins used", "\(min(entries.count, 12)) recent"),
            ("Chart days", "\(impactPoints.count) points"),
            ("Labs", "\(labResults.count) logged"),
            ("Procedures", "\(procedureEvents.count) logged"),
            ("Health sync", healthInsights.lastSyncDate == nil ? "Not synced" : "Available"),
            ("Photos", "\(photoRecords.count) records")
        ]
    }

    private var intelligenceReasonRows: [String] {
        var rows: [String] = []

        if !intelligenceReport.observations.isEmpty {
            rows.append("Observed patterns come from your recent check-ins plus the lag-aware trend points shown in charts.")
        }

        if !intelligenceReport.suggestions.isEmpty {
            rows.append("Useful next steps are generated from what is already logged versus what is still missing, such as labs, photos, or adherence density.")
        }

        if !intelligenceReport.dataGaps.isEmpty {
            rows.append("Missing context appears when the app sees thin data, older labs, or too few repeated logs to support a stable pattern read.")
        }

        if !intelligenceReport.reviewFlags.isEmpty {
            rows.append("Clinical review flags are rule-based safety prompts from symptoms and hair-loss patterns, not an AI diagnosis.")
        }

        if rows.isEmpty {
            rows.append("Intelligence is waiting for more repeated check-ins, routine logs, and comparable photos before it can explain meaningful trends.")
        }

        return rows
    }

    @MainActor
    private func generateIntelligenceSummary() async {
        guard purchaseManager.hasPremiumAccess else {
            intelligenceErrorMessage = "Hair Compass Pro is required for AI-generated Intelligence."
            return
        }

        let trimmedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        isGeneratingIntelligence = true
        intelligenceErrorMessage = ""

        do {
            intelligenceSummary = try await OpenAIIntelligenceService(apiKey: trimmedKey).analyze(
                report: intelligenceReport,
                impactPoints: impactPoints,
                entries: Array(entries.prefix(12)),
                labResults: Array(labResults.prefix(8)),
                procedureEvents: Array(procedureEvents.prefix(6)),
                profile: profile,
                medications: medications,
                triggerEvents: triggerEvents
            )
            intelligenceGeneratedAt = .now
        } catch {
            intelligenceErrorMessage = error.localizedDescription
        }

        isGeneratingIntelligence = false
    }

    private var dashboardChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Results Trend")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                    Text("See whether routine and medication consistency line up with stronger check-ins.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                }

                Spacer(minLength: 8)

                Text("Live")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.39, blue: 0.37))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.85), in: Capsule())
            }

            // RoutineImpactChart renders its own preview state when there is no data,
            // so we no longer stack a separate placeholder image behind it (which caused
            // an overlapping double-preview).
            RoutineImpactChart(points: impactPoints)
            .padding(10)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.40), lineWidth: 1)
            )
        }
        .heroCardStyle()
    }

    private var heroInsightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heroStatusLine)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.19, green: 0.25, blue: 0.23))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(hasUnlockedTrackingScore ? "Confidence \(trackingConfidenceLabel)" : "Reported Context")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(hasUnlockedTrackingScore ? trackingConfidenceTint : Color(red: 0.18, green: 0.27, blue: 0.24))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        hasUnlockedTrackingScore ? trackingConfidenceTint.opacity(0.12) : Color(red: 0.84, green: 0.93, blue: 0.88),
                        in: Capsule()
                    )

                Text(hasUnlockedTrackingScore ? "\(recent30DayEntries.count) recent check-ins" : "Starting assumptions")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.45))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.88), in: Capsule())
            }

            if hasUnlockedTrackingScore {
                HStack(spacing: 10) {
                    softMetricBadge(title: "Symptoms", value: "\(symptomStabilityScore)%")
                    softMetricBadge(title: "Routine", value: "\(completionRate)%")
                }

                HStack(spacing: 10) {
                    softMetricBadge(title: "Data Depth", value: "\(trackingDepthScore)%")
                    softMetricBadge(title: "Meds", value: "\(recentMedicationAdherenceRate)%")
                }
            } else {
                HStack(spacing: 10) {
                    softMetricBadge(title: "Focus", value: baselineFocusShort)
                    softMetricBadge(title: "Wash", value: baselineWashShort)
                }

                if !onboardingTriggerSummaries.isEmpty {
                    Text("Reported trigger context: \(onboardingTriggerSummaries.joined(separator: " • "))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(scoreMethodNote)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var baselineFocusShort: String {
        if baselineFocusText.count <= 14 { return baselineFocusText }
        return String(baselineFocusText.prefix(14)) + "…"
    }

    private var baselineWashShort: String {
        if baselineWashText.count <= 14 { return baselineWashText }
        return String(baselineWashText.prefix(14)) + "…"
    }

    private var journeyImagePanel: some View {
        Group {
            if let latestJourneyRecord,
               let image = PhotoFileStore.shared.loadImage(at: latestJourneyRecord.imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("journey-photo-soft")
                    .resizable()
                    .scaledToFill()
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.macro")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                            Text("No progress photo yet")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.24))
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var journeyStatsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            miniJourneyStat(title: "Photos", value: "\(photoRecords.count)", tint: Color(red: 0.38, green: 0.53, blue: 0.76))
            miniJourneyStat(title: "Procedures", value: "\(procedureEvents.count)", tint: Color(red: 0.73, green: 0.53, blue: 0.26))
            miniJourneyStat(title: "Trend points", value: "\(impactPoints.count)", tint: Color(red: 0.46, green: 0.62, blue: 0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var journeyStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            miniJourneyStat(title: "Photos", value: "\(photoRecords.count)", tint: Color(red: 0.38, green: 0.53, blue: 0.76))
            miniJourneyStat(title: "Procedures", value: "\(procedureEvents.count)", tint: Color(red: 0.73, green: 0.53, blue: 0.26))
            miniJourneyStat(title: "Trend points", value: "\(impactPoints.count)", tint: Color(red: 0.46, green: 0.62, blue: 0.52))
        }
    }

    private var intelligenceHeaderText: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Intelligence")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("AI")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.27, blue: 0.24))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.84, green: 0.93, blue: 0.88), in: Capsule())
            }

            Text("AI pattern reading for your own logs. It summarizes trends, uncertainty, and gaps. It does not diagnose.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var intelligenceGenerateButton: some View {
        Button {
            if purchaseManager.hasPremiumAccess {
                Task {
                    await generateIntelligenceSummary()
                }
            } else {
                isPresentingPremiumPaywall = true
            }
        } label: {
            HStack(spacing: 8) {
                if purchaseManager.hasPremiumAccess && isGeneratingIntelligence {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else if purchaseManager.hasPremiumAccess {
                    Image(systemName: "sparkles.rectangle.stack")
                } else {
                    Image(systemName: "lock.fill")
                }
                Text(purchaseManager.hasPremiumAccess ? (intelligenceSummary.isEmpty ? "Generate" : "Refresh") : "Unlock Pro")
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.17, green: 0.34, blue: 0.30), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var healthLifestyleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lifestyle Signals")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                    Text("Compare shedding and scalp trends against sleep, exercise, nutrition, and smoking patterns.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                }

                Spacer(minLength: 0)

                Button(healthInsights.authorizationState == .authorized ? "Refresh" : "Connect") {
                    Task {
                        if healthInsights.authorizationState == .authorized {
                            await healthInsights.refresh()
                        } else {
                            await healthInsights.requestAccessAndRefresh()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    dashboardBadge(label: latestSleepText, tint: Color(red: 0.24, green: 0.49, blue: 0.78))
                    dashboardBadge(label: latestExerciseText, tint: Color(red: 0.29, green: 0.56, blue: 0.42))
                }

                VStack(alignment: .leading, spacing: 8) {
                    dashboardBadge(label: latestSleepText, tint: Color(red: 0.24, green: 0.49, blue: 0.78))
                    dashboardBadge(label: latestExerciseText, tint: Color(red: 0.29, green: 0.56, blue: 0.42))
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    dashboardBadge(label: "Supplements \(supplementEventsThisMonth)", tint: Color(red: 0.80, green: 0.56, blue: 0.34))
                    dashboardBadge(label: "Smoking \(smokingEventsThisMonth)", tint: Color(red: 0.64, green: 0.36, blue: 0.28))
                }

                VStack(alignment: .leading, spacing: 8) {
                    dashboardBadge(label: "Supplements \(supplementEventsThisMonth)", tint: Color(red: 0.80, green: 0.56, blue: 0.34))
                    dashboardBadge(label: "Smoking \(smokingEventsThisMonth)", tint: Color(red: 0.64, green: 0.36, blue: 0.28))
                }
            }

            if let lastSyncDate = healthInsights.lastSyncDate {
                Text("Last synced \(lastSyncDate.formatted(date: .abbreviated, time: .shortened)). Health data is read-only, and smoking stays manual.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.33, green: 0.39, blue: 0.35))
            } else {
                Text("Apple Health can supply sleep, exercise, protein, and water trends. Smoking and supplement events stay manual so the relationship data remains explicit.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.33, green: 0.39, blue: 0.35))
            }

            if let errorMessage = healthInsights.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.62, green: 0.17, blue: 0.13))
            }
        }
        .secondaryCardStyle()
    }

    private var labPromptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lab Signals")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                    Text(labPromptTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.62, green: 0.41, blue: 0.15))
                }
                Spacer(minLength: 0)
                Image(systemName: "testtube.2")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.62, green: 0.41, blue: 0.15))
            }

            Text(labPromptMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.39, green: 0.43, blue: 0.40))

            Text("Most relevant logs: ferritin, CBC/hemoglobin, 25-OH vitamin D, TSH, B12, folate, and sometimes zinc.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.26, green: 0.56, blue: 0.42))
        }
        .secondaryCardStyle()
    }

    private var alertCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Safety Flags")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.40, green: 0.16, blue: 0.12))

            Text("This app tracks observations. It does not diagnose hair or scalp disease.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.24, blue: 0.20))

            ForEach(clinicalAlerts) { alert in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(alert.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Spacer()
                        Text(alert.severity.rawValue.capitalized)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(alertTint(for: alert.severity).opacity(0.14), in: Capsule())
                            .foregroundStyle(alertTint(for: alert.severity))
                    }

                    Text(alert.message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.24, blue: 0.20))
                }
                .padding(14)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(20)
        .background(Color(red: 0.99, green: 0.92, blue: 0.88), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(red: 0.93, green: 0.74, blue: 0.66), lineWidth: 1)
        )
    }

    private var recentCheckInsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Check-Ins")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))

            if recentEntries.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color(red: 0.38, green: 0.53, blue: 0.76).opacity(0.6))

                    Text("No entries yet")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))

                    Text("Log your first check-in to start building trends for scalp health, hydration, and shedding.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                        .multilineTextAlignment(.center)

                    Button {
                        HapticHelper.light()
                        onAddCheckIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add First Check-In")
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.38, green: 0.53, blue: 0.76), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(recentEntries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.date, format: .dateTime.weekday(.wide).month().day())
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 8)
                            Text("Scalp \(entry.scalpScore)%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.27, green: 0.48, blue: 0.42))
                        }

                        Text(entry.note)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))

                        HStack(spacing: 12) {
                            miniMetric(label: "Hydration", value: entry.hydrationScore)
                            miniMetric(label: "Shedding", value: entry.sheddingLevel)
                            miniMetric(label: "Stress", value: entry.stressLevel)
                        }

                        let symptoms = symptomSummary(for: entry)
                        if !symptoms.isEmpty {
                            Text(symptoms.joined(separator: "  •  "))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.71, green: 0.42, blue: 0.25))
                        }
                    }

                    if entry.id != recentEntries.last?.id {
                        Divider()
                    }
                }
            }
        }
        .secondaryCardStyle()
    }

    private var upcomingRoutineCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upcoming Routine")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))

            ForEach(upcomingTasks) { task in
                HStack(alignment: .center, spacing: 14) {
                    Text(weekdaySymbol(for: task.weekday))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.34, green: 0.42, blue: 0.37))
                        .frame(width: 46, height: 46)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
                            .lineLimit(1)
                        Text("\(task.timeLabel)  •  \(task.category)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(task.isCompleted ? Color.green : Color.gray.opacity(0.7))
                }
            }
        }
        .secondaryCardStyle()
    }

    private var heroSubtitle: String {
        if !hasUnlockedTrackingScore {
            return "Your starting plan is built from reported onboarding context. Add repeated check-ins and comparable photos to unlock measured tracking."
        }
        if let profile {
            return "\(profile.name), your current focus is \(profile.primaryGoal.lowercased()). \(checkInsThisMonth) check-ins logged this month with \(currentWeekRoutineActions) routine actions this week."
        }

        return "Track growth, scalp balance, wash cadence, routine actions, and check-in trends in one place."
    }

    private var weeklySummary: String {
        guard let latest = entries.first, !recent30DayEntries.isEmpty else {
            return "Add a check-in to start measuring your weekly scalp and hydration trends."
        }

        return "In the last 30 days, average scalp score was \(averageScalp)% and average shedding was \(averageShedding30Days)%. Your latest check-in logged \(latest.hydrationScore)% hydration and \(latest.stressLevel)% stress."
    }

    private var sheddingDeltaText: String {
        if recent30DayEntries.isEmpty {
            return "No 30-day data yet"
        }

        if sheddingDeltaVsPreviousMonth == 0 {
            return "Stable vs previous 30 days"
        }

        if sheddingDeltaVsPreviousMonth < 0 {
            return "\(abs(sheddingDeltaVsPreviousMonth)) pts lower than previous 30 days"
        }

        return "\(sheddingDeltaVsPreviousMonth) pts higher than previous 30 days"
    }

    private var lastCheckInText: String {
        guard let daysSinceLastCheckIn else { return "No entries yet" }
        if daysSinceLastCheckIn == 0 { return "Last check-in today" }
        if daysSinceLastCheckIn == 1 { return "Last check-in yesterday" }
        return "Last check-in \(daysSinceLastCheckIn)d ago"
    }

    private var scalpSignalBadge: String {
        if averageScalp >= 80 { return "Scalp trending strong" }
        if averageScalp >= 60 { return "Scalp mixed lately" }
        return "Scalp needs attention"
    }

    private var stressSignalBadge: String {
        if averageStress30Days >= 70 { return "Stress running high" }
        if averageStress30Days >= 40 { return "Stress moderate" }
        return "Stress relatively low"
    }

    private func dashboardBadge(label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func miniMetric(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
            Text("\(value)%")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardTaskCompleted(_ task: RoutineTask, on date: Date) -> Bool {
        routineCompletions.contains {
            (($0.task?.persistentModelID == task.persistentModelID) || ($0.task == nil && $0.taskTitle == task.title))
                && calendar.isDate($0.completedAt, inSameDayAs: date)
        }
    }

    private func doesDashboardTask(_ task: RoutineTask, occurOn date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: task.startDate)
        let endDay = task.endDate.map { calendar.startOfDay(for: $0) }

        guard day >= startDay else { return false }
        if let endDay, day > endDay { return false }

        let recurrence = RoutineRecurrenceType(rawValue: task.recurrenceType) ?? .weekly
        switch recurrence {
        case .daily:
            return true
        case .weekly:
            let weekdays = dashboardRecurrenceWeekdays(for: task)
            return weekdays.contains(calendar.component(.weekday, from: day))
        case .everyNDays:
            let offset = calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
            return offset.isMultiple(of: max(1, task.recurrenceInterval))
        case .monthly:
            return calendar.component(.day, from: startDay) == calendar.component(.day, from: day)
        }
    }

    private func doesDashboardTask(_ task: RoutineTask, occurBetween startDate: Date, and endDate: Date) -> Bool {
        var cursor = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        while cursor <= end {
            if doesDashboardTask(task, occurOn: cursor) {
                return true
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return false
    }

    private func scheduledDashboardOccurrences(for task: RoutineTask, between startDate: Date, and endDate: Date) -> Int {
        var cursor = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        var count = 0

        while cursor <= end {
            if doesDashboardTask(task, occurOn: cursor) {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return count
    }

    private func dashboardRecurrenceWeekdays(for task: RoutineTask) -> [Int] {
        let configured = task.recurrenceWeekdays
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1 ... 7).contains($0) }
        return configured.isEmpty ? [task.weekday] : configured
    }

    private func dashboardCategoryTint(_ category: String) -> Color {
        switch category.lowercased() {
        case "wash":
            return Color(red: 0.73, green: 0.53, blue: 0.26)
        case "scalp":
            return Color(red: 0.46, green: 0.62, blue: 0.52)
        case "hydration":
            return Color(red: 0.38, green: 0.53, blue: 0.76)
        case "protection":
            return Color(red: 0.60, green: 0.46, blue: 0.72)
        default:
            return Color(red: 0.43, green: 0.50, blue: 0.46)
        }
    }

    private func weekdaySymbol(for weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = min(max(weekday - 1, 0), symbols.count - 1)
        return symbols[index]
    }

    private func taskSort(lhs: RoutineTask, rhs: RoutineTask) -> Bool {
        if lhs.weekday == rhs.weekday {
            return lhs.timeLabel < rhs.timeLabel
        }
        return lhs.weekday < rhs.weekday
    }

    private func alertTint(for severity: GuidanceSeverity) -> Color {
        switch severity {
        case .routine:
            return Color(red: 0.69, green: 0.43, blue: 0.20)
        case .soon:
            return Color(red: 0.72, green: 0.38, blue: 0.16)
        case .prompt:
            return Color(red: 0.62, green: 0.17, blue: 0.13)
        }
    }

    private func symptomSummary(for entry: CheckInEntry) -> [String] {
        var symptoms: [String] = []
        if entry.hasItch { symptoms.append("Itch") }
        if entry.hasFlaking { symptoms.append("Flaking") }
        if entry.hasScalpPain { symptoms.append("Pain") }
        if entry.hasPatchyHairLoss { symptoms.append("Patchy loss") }
        if entry.hasTightStyleTension { symptoms.append("Tension") }
        if entry.isWashDay { symptoms.append("Wash day") }
        return symptoms
    }
}

