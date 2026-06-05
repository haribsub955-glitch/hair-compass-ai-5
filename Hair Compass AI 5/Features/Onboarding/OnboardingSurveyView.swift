import SwiftData
import SwiftUI
import UIKit

struct OnboardingSurveyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var profile: HairProfile
    let mode: Mode

    @State private var response = OnboardingSurveyResponse()
    @State private var step: Step = .welcomeSplash
    @State private var isForward = true
    @State private var iconBounce = false
    @State private var splashAppeared = false
    @State private var showValidationHint = false
    @State private var hasLoggedStart = false
    @State private var hasCompletedOnboardingFlow = false
    @State private var floatingPhase = false
    @FocusState private var focusedField: OnboardingField?

    private let textureOptions = ["Straight 1A-1C", "Wavy 2A-2C", "Wavy 2C / 3A", "Curly 3A-3C", "Coily 4A-4C"]
    private let goalOptions = ["Length retention", "Stronger roots", "Hydration", "Reduce shedding", "Scalp balance"]

    enum Mode {
        case initial
        case update
    }

    private enum OnboardingField: Hashable {
        case name
        case patternDistribution
        case familyHistory
        case patchArea
    }

    // MARK: - Step Enum (consolidated 13-step flow)

    enum Step: Int, CaseIterable {
        case welcomeSplash = 0
        case aboutYou              // combines nameEntry + ageAndSex
        case textureSelection
        case goalSelection
        case hairLossFocus
        case hairLossDuration
        case patternAndHistory     // combines patternDistribution + familyHistory
        case conditionalHairLoss
        case midFlowInsight        // single interstitial replacing 4
        case scalpAndStyling       // combines scalpState + stylingTension
        case washAndHabits         // combines washPreference + photoConsistency + nightProtection
        case medicationStatus
        case summary
    }

    enum OnboardingSection: Int, CaseIterable, Identifiable {
        case profile, hairLoss, scalp, routine, treatment, summary
        var id: Int { rawValue }
    }

    private var currentSection: OnboardingSection {
        switch step {
        case .welcomeSplash, .aboutYou, .textureSelection, .goalSelection:
            return .profile
        case .hairLossFocus, .hairLossDuration, .patternAndHistory, .conditionalHairLoss:
            return .hairLoss
        case .midFlowInsight, .scalpAndStyling:
            return .scalp
        case .washAndHabits:
            return .routine
        case .medicationStatus:
            return .treatment
        case .summary:
            return .summary
        }
    }

    private var isInterstitial: Bool {
        [.welcomeSplash, .midFlowInsight].contains(step)
    }

    private var totalStepCount: Int { Step.allCases.count }

    private var visibleSteps: [Step] {
        Step.allCases.filter { item in
            if item == .conditionalHairLoss {
                return needsConditionalHairLossStep
            }
            return true
        }
    }

    private var currentVisibleStepIndex: Int {
        visibleSteps.firstIndex(of: step) ?? 0
    }

    private var progressRatio: Double {
        guard !visibleSteps.isEmpty else { return 0 }
        return Double(currentVisibleStepIndex + 1) / Double(visibleSteps.count)
    }

    private var canAdvanceFromCurrentStep: Bool {
        switch step {
        case .welcomeSplash, .midFlowInsight, .summary:
            return true
        case .aboutYou:
            let nameValid = response.name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            let ageValid = !response.ageRange.isEmpty
            let sexValid = !response.biologicalSex.isEmpty
            return nameValid && ageValid && sexValid
        case .textureSelection:
            return !response.texture.isEmpty
        case .goalSelection:
            return !response.primaryGoal.isEmpty
        case .hairLossFocus:
            return true
        case .hairLossDuration:
            return !response.hairLossDuration.isEmpty
        case .patternAndHistory:
            let patternValid = response.patternDistribution.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            let familyValid = response.familyHistorySummary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            return patternValid && familyValid
        case .conditionalHairLoss:
            switch response.hairLossFocus {
            case .alopeciaAreata:
                return response.patchAreaSummary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 || response.hasEyebrowOrBeardInvolvement
            case .inflammatoryScarring:
                return response.hasScalpBurningTenderness || response.hasPustulesOrScale
            case .telogenEffluvium:
                return response.recentIllnessTrigger || response.recentSurgeryTrigger || response.postpartumTrigger || response.recentWeightLossTrigger || response.recentMedicationChangeTrigger
            default:
                return true
            }
        case .scalpAndStyling, .washAndHabits, .medicationStatus:
            return true
        }
    }

    private var validationHintText: String {
        switch step {
        case .aboutYou:
            if response.name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                return "Enter at least 2 characters for your name."
            }
            return "Select both age range and biological sex."
        case .hairLossDuration:
            return "Choose when changes first started."
        case .patternAndHistory:
            if response.patternDistribution.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                return "Add a short pattern description (for example temples, part line, crown)."
            }
            return "Add a family-history note (use \"None known\" if unsure)."
        case .conditionalHairLoss:
            switch response.hairLossFocus {
            case .alopeciaAreata:
                return "Describe affected patch areas or enable eyebrow/beard involvement."
            case .inflammatoryScarring:
                return "Select at least one warning-pattern symptom."
            case .telogenEffluvium:
                return "Select at least one possible trigger history item."
            default:
                return "Complete this step to continue."
            }
        default:
            return "Complete this step to continue."
        }
    }

    // MARK: - Body

    private let maxContentWidth: CGFloat = 500

    var body: some View {
        NavigationStack {
            ZStack {
                background

                VStack(spacing: 0) {
                    if step != .welcomeSplash {
                        header
                            .frame(maxWidth: maxContentWidth)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ZStack {
                        stepContent
                            .id(step)
                            .transition(.asymmetric(
                                insertion: .move(edge: isForward ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .move(edge: isForward ? .leading : .trailing)
                                    .combined(with: .opacity)
                            ))
                    }
                    .frame(maxWidth: maxContentWidth)
                    .animation(.spring(response: 0.5, dampingFraction: 0.88), value: step)

                    footer
                        .frame(maxWidth: maxContentWidth)
                }
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if mode == .update {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(mode == .initial)
        .onAppear {
            let launchArguments = ProcessInfo.processInfo.arguments
            response.name = profile.name == "User" ? "" : profile.name
            response.texture = profile.texture
            response.primaryGoal = profile.primaryGoal
            response.hairLossFocus = HairLossFocus(rawValue: profile.hairLossFocus) ?? .notSure
            response.familyHistorySummary = profile.familyHistorySummary
            response.patternDistribution = profile.patternDistribution
            response.ageRange = profile.ageRange
            response.biologicalSex = profile.biologicalSex
            response.hairLossDuration = profile.hairLossDuration
            response.includePhotoReminder = response.wantsMonthlyPhotos
            response.includeNightProtectionTask = response.wantsNightProtection

            if launchArguments.contains("UITEST_REQUIRE_EMPTY_FIELDS") {
                response.name = ""
                response.ageRange = ""
                response.biologicalSex = ""
                response.hairLossDuration = ""
                response.patternDistribution = ""
                response.familyHistorySummary = ""
                response.patchAreaSummary = ""
                response.hairLossFocus = .notSure
            }

            iconBounce = true
            if !hasLoggedStart {
                hasLoggedStart = true
                AnalyticsService.log("onboarding_started", properties: [
                    "mode": mode == .initial ? "initial" : "update"
                ])
                AnalyticsService.log("onboarding_step_viewed", properties: [
                    "step": String(describing: step)
                ])
            }
        }
        .onChange(of: step) { _, newStep in
            showValidationHint = false
            AnalyticsService.log("onboarding_step_viewed", properties: [
                "step": String(describing: newStep)
            ])
        }
        .onDisappear {
            if !hasCompletedOnboardingFlow {
                AnalyticsService.log("onboarding_abandoned", properties: [
                    "mode": mode == .initial ? "initial" : "update",
                    "last_step": String(describing: step)
                ])
            }
        }
    }

    // MARK: - Background (section-adaptive)

    private var background: some View {
        ZStack {
            sectionBackgroundGradient
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: currentSection)

            // Decorative blurred orbs
            Circle()
                .fill(sectionAccentColor.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -100, y: -280)
                .animation(.easeInOut(duration: 0.8), value: currentSection)

            Circle()
                .fill(PremiumTheme.gold.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 140, y: 300)
        }
    }

    private var sectionBackgroundGradient: LinearGradient {
        switch currentSection {
        case .profile:
            return LinearGradient(
                colors: [Color(red: 0.93, green: 0.96, blue: 0.95), Color(red: 0.88, green: 0.93, blue: 0.91), Color(red: 0.95, green: 0.95, blue: 0.93)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .hairLoss:
            return LinearGradient(
                colors: [Color(red: 0.96, green: 0.93, blue: 0.88), Color(red: 0.93, green: 0.90, blue: 0.85), Color(red: 0.95, green: 0.94, blue: 0.91)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .scalp:
            return LinearGradient(
                colors: [Color(red: 0.90, green: 0.95, blue: 0.92), Color(red: 0.87, green: 0.93, blue: 0.89), Color(red: 0.94, green: 0.96, blue: 0.93)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .routine:
            return LinearGradient(
                colors: [Color(red: 0.90, green: 0.93, blue: 0.97), Color(red: 0.87, green: 0.91, blue: 0.96), Color(red: 0.93, green: 0.94, blue: 0.96)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .treatment:
            return LinearGradient(
                colors: [Color(red: 0.94, green: 0.91, blue: 0.96), Color(red: 0.91, green: 0.89, blue: 0.95), Color(red: 0.95, green: 0.93, blue: 0.96)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .summary:
            return LinearGradient(
                colors: [Color(red: 0.91, green: 0.95, blue: 0.93), Color(red: 0.88, green: 0.93, blue: 0.90), Color(red: 0.94, green: 0.96, blue: 0.93)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var sectionAccentColor: Color {
        switch currentSection {
        case .profile: return PremiumTheme.teal
        case .hairLoss: return PremiumTheme.warmAmber
        case .scalp: return Color(red: 0.29, green: 0.56, blue: 0.42)
        case .routine: return Color(red: 0.20, green: 0.47, blue: 0.79)
        case .treatment: return PremiumTheme.softPurple
        case .summary: return PremiumTheme.forest
        }
    }

    // MARK: - Header (step dots + section pill)

    private var header: some View {
        VStack(spacing: 12) {
            // Top row: title + section badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode == .initial ? "Build Your Plan" : "Update Your Plan")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PremiumTheme.secondaryInk)
                        .accessibilityIdentifier("onboardingHeaderTitle")
                    Text("Step \(currentVisibleStepIndex + 1) of \(visibleSteps.count)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PremiumTheme.mutedInk)
                        .accessibilityIdentifier("onboardingStepCounter")
                }
                Spacer()
                Text(sectionLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(sectionAccentColor, in: Capsule())
                    .animation(.easeInOut(duration: 0.3), value: currentSection)
            }

            // Step dot progress indicator
            HStack(spacing: 6) {
                ForEach(Array(visibleSteps.enumerated()), id: \.offset) { index, _ in
                    let isCurrent = index == currentVisibleStepIndex
                    let isCompleted = index < currentVisibleStepIndex

                    Capsule()
                        .fill(
                            isCompleted ? sectionAccentColor :
                            isCurrent ? sectionAccentColor.opacity(0.5) :
                            Color.black.opacity(0.08)
                        )
                        .frame(width: isCurrent ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentVisibleStepIndex)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var sectionLabel: String {
        switch currentSection {
        case .profile: return "Profile"
        case .hairLoss: return "Hair Loss"
        case .scalp: return "Scalp"
        case .routine: return "Routine"
        case .treatment: return "Treatment"
        case .summary: return "Summary"
        }
    }

    private var sectionBoundaryFractions: [Double] {
        let steps = visibleSteps
        let total = Double(steps.count)
        guard total > 0 else { return [] }
        var fractions: [Double] = []
        var prevSection: OnboardingSection? = nil
        for (index, s) in steps.enumerated() {
            let sec = sectionForStep(s)
            if sec != prevSection && prevSection != nil {
                fractions.append(Double(index) / total)
            }
            prevSection = sec
        }
        return fractions
    }

    private func sectionForStep(_ s: Step) -> OnboardingSection {
        switch s {
        case .welcomeSplash, .aboutYou, .textureSelection, .goalSelection:
            return .profile
        case .hairLossFocus, .hairLossDuration, .patternAndHistory, .conditionalHairLoss:
            return .hairLoss
        case .midFlowInsight, .scalpAndStyling:
            return .scalp
        case .washAndHabits:
            return .routine
        case .medicationStatus:
            return .treatment
        case .summary:
            return .summary
        }
    }

    // MARK: - Step Content Router

    @ViewBuilder
    private var stepContent: some View {
        ScrollView(showsIndicators: false) {
            Group {
                switch step {
                case .welcomeSplash: welcomeSplashStep
                case .aboutYou: aboutYouStep
                case .textureSelection: textureSelectionStep
                case .goalSelection: goalSelectionStep
                case .hairLossFocus: hairLossFocusStep
                case .hairLossDuration: hairLossDurationStep
                case .patternAndHistory: patternAndHistoryStep
                case .conditionalHairLoss: conditionalHairLossStep
                case .midFlowInsight: midFlowInsightStep
                case .scalpAndStyling: scalpAndStylingStep
                case .washAndHabits: washAndHabitsStep
                case .medicationStatus: medicationStatusStep
                case .summary: summaryStep
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, step == .welcomeSplash ? 0 : 16)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedField = nil
            }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            // Validation hint above buttons
            if showValidationHint && !canAdvanceFromCurrentStep {
                Text(validationHintText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.82, green: 0.30, blue: 0.24), in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                if step != .welcomeSplash {
                    Button {
                        goBack()
                    } label: {
                        Text("Back")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(PremiumTheme.forest)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Color.white.opacity(0.9),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboardingBackButton")
                }

                Button {
                    advance()
                } label: {
                    HStack(spacing: 8) {
                        Text(footerButtonLabel)
                        Image(systemName: step == .summary ? "checkmark.circle.fill" : "arrow.right")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        sectionAccentColor,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: sectionAccentColor.opacity(0.3), radius: 8, y: 4)
                    .opacity(canAdvanceFromCurrentStep ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.3), value: currentSection)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvanceFromCurrentStep)
                .accessibilityIdentifier("onboardingNextButton")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private var footerButtonLabel: String {
        if step == .summary {
            return mode == .initial ? "Create Plan" : "Update Plan"
        }
        if step == .welcomeSplash {
            return "Get Started"
        }
        if isInterstitial {
            return "Continue"
        }
        return "Next"
    }

    // MARK: - Navigation Logic

    private func advance() {
        if !canAdvanceFromCurrentStep {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            AnalyticsService.log("onboarding_step_blocked", properties: [
                "step": String(describing: step),
                "reason": validationHintText
            ])
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showValidationHint = true
            }
            return
        }

        focusedField = nil

        if step == .summary {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            InitialRoutinePlanner.apply(response: response, to: profile, modelContext: modelContext)
            hasCompletedOnboardingFlow = true
            AnalyticsService.log("onboarding_completed", properties: [
                "mode": mode == .initial ? "initial" : "update",
                "tasks": "\(planPreview.taskTitles.count)",
                "triggers": "\(planPreview.triggerTitles.count)",
                "medications": "\(planPreview.medicationTitles.count)"
            ])
            dismiss()
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard let next = nextValidStep(after: step) else { return }
        isForward = true
        iconBounce = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
            step = next
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                iconBounce = true
            }
        }
    }

    private func goBack() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        focusedField = nil
        guard let prev = previousValidStep(before: step) else { return }
        isForward = false
        iconBounce = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
            step = prev
        }
    }

    private func nextValidStep(after current: Step) -> Step? {
        var raw = current.rawValue + 1
        while raw < totalStepCount {
            guard let candidate = Step(rawValue: raw) else { return nil }
            if candidate == .conditionalHairLoss && !needsConditionalHairLossStep {
                raw += 1
                continue
            }
            return candidate
        }
        return nil
    }

    private func previousValidStep(before current: Step) -> Step? {
        var raw = current.rawValue - 1
        while raw >= 0 {
            guard let candidate = Step(rawValue: raw) else { return nil }
            if candidate == .conditionalHairLoss && !needsConditionalHairLossStep {
                raw -= 1
                continue
            }
            return candidate
        }
        return nil
    }

    private var needsConditionalHairLossStep: Bool {
        [.alopeciaAreata, .inflammatoryScarring, .telogenEffluvium].contains(response.hairLossFocus)
    }

    // MARK: - Section Gradient

    private var sectionGradient: LinearGradient {
        switch currentSection {
        case .profile:
            return LinearGradient(colors: [PremiumTheme.teal, Color(red: 0.34, green: 0.58, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .hairLoss:
            return LinearGradient(colors: [PremiumTheme.warmAmber, Color(red: 0.62, green: 0.38, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .scalp:
            return LinearGradient(colors: [Color(red: 0.29, green: 0.56, blue: 0.42), Color(red: 0.20, green: 0.47, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .routine:
            return LinearGradient(colors: [Color(red: 0.20, green: 0.47, blue: 0.79), Color(red: 0.24, green: 0.55, blue: 0.76)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .treatment:
            return LinearGradient(colors: [PremiumTheme.softPurple, Color(red: 0.64, green: 0.41, blue: 0.70)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .summary:
            return LinearGradient(colors: [PremiumTheme.forest, PremiumTheme.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Welcome Splash

    private var welcomeSplashStep: some View {
        ZStack {
            // Animated background orbs
            floatingCircle(size: 200, color: PremiumTheme.teal.opacity(0.20), xOffset: -80, yOffset: -180, duration: 5.0)
            floatingCircle(size: 150, color: PremiumTheme.gold.opacity(0.15), xOffset: 100, yOffset: -60, duration: 4.0)
            floatingCircle(size: 120, color: PremiumTheme.forest.opacity(0.12), xOffset: -40, yOffset: 200, duration: 6.0)

            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Large icon in gradient circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [PremiumTheme.forest, PremiumTheme.teal],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: PremiumTheme.teal.opacity(0.3), radius: 30, y: 15)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(splashAppeared ? 0 : -20))
                }
                .scaleEffect(splashAppeared ? 1 : 0.3)
                .opacity(splashAppeared ? 1 : 0)
                .padding(.bottom, 32)

                Text("Hair Compass")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(PremiumTheme.ink)
                    .opacity(splashAppeared ? 1 : 0)
                    .offset(y: splashAppeared ? 0 : 20)

                Text("Your personal hair health tracker")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(PremiumTheme.mutedInk)
                    .padding(.top, 6)
                    .opacity(splashAppeared ? 1 : 0)
                    .offset(y: splashAppeared ? 0 : 14)

                Spacer().frame(height: 48)

                // Staggered feature cards
                VStack(spacing: 14) {
                    welcomeFeatureCard(icon: "chart.line.uptrend.xyaxis", title: "Track patterns", detail: "Monitor scalp, shedding, and hydration over time", color: PremiumTheme.teal, delay: 0.2)
                    welcomeFeatureCard(icon: "calendar.badge.clock", title: "Build routines", detail: "Personalized wash, treatment, and photo schedules", color: Color(red: 0.29, green: 0.56, blue: 0.42), delay: 0.35)
                    welcomeFeatureCard(icon: "sparkles", title: "Get insights", detail: "AI-powered readings of your logged data", color: PremiumTheme.warmAmber, delay: 0.5)
                }

                Spacer().frame(height: 28)

                Text(mode == .initial
                     ? "Takes about 2 minutes"
                     : "Let's update your plan")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PremiumTheme.mutedInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.5), in: Capsule())
                    .opacity(splashAppeared ? 1 : 0)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.1)) {
                splashAppeared = true
            }
        }
    }

    private func welcomeFeatureCard(icon: String, title: String, detail: String, color: Color, delay: Double) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: color.opacity(0.3), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PremiumTheme.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PremiumTheme.mutedInk)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        .opacity(splashAppeared ? 1 : 0)
        .offset(y: splashAppeared ? 0 : 30)
        .animation(.spring(response: 0.7, dampingFraction: 0.75).delay(delay), value: splashAppeared)
    }

    private func floatingCircle(size: CGFloat, color: Color, xOffset: CGFloat, yOffset: CGFloat, duration: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size / 4)
            .offset(x: xOffset, y: yOffset + (floatingPhase ? 12 : -12))
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: floatingPhase)
            .onAppear { floatingPhase = true }
    }

    // welcomeFeatureCard is defined after welcomeSplashStep

    // MARK: - Section 1: Profile Questions

    private let ageRangeOptions = ["Under 18", "18–25", "26–35", "36–45", "46–55", "56+"]
    private let biologicalSexOptions = ["Female", "Male", "Prefer not to say"]

    private var aboutYouStep: some View {
        questionPage(
            icon: "person.crop.circle.fill",
            question: "About you",
            subtitle: "Your name, age, and biological sex personalize the plan and affect treatment eligibility."
        ) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("YOUR NAME")
                        .onboardingFieldLabel()
                    TextField("Your name", text: $response.name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .accessibilityIdentifier("onboardingNameField")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Age range")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.30, green: 0.36, blue: 0.33))
                    selectableChips(options: ageRangeOptions, selection: $response.ageRange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Biological sex")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.30, green: 0.36, blue: 0.33))
                    selectableChips(options: biologicalSexOptions, selection: $response.biologicalSex)
                }
            }
        }
    }

    private var textureSelectionStep: some View {
        questionPage(
            icon: "wind",
            question: "What's your hair texture?",
            subtitle: "This helps the app recommend wash frequency and product sensitivity."
        ) {
            selectableChips(options: textureOptions, selection: $response.texture)
        }
    }

    private var goalSelectionStep: some View {
        questionPage(
            icon: "target",
            question: "What's your main goal?",
            subtitle: "This shapes which metrics and reminders the app prioritizes for you."
        ) {
            selectableChips(options: goalOptions, selection: $response.primaryGoal)
        }
    }

    // MARK: - Section 2: Hair-Loss Context

    private var hairLossFocusStep: some View {
        questionPage(
            icon: "point.topleft.down.curvedto.point.bottomright.up",
            question: "Choose a tracking focus",
            subtitle: "This does not diagnose you. It only tells the app what type of reminders to emphasize."
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(HairLossFocus.allCases) { focus in
                    VisualChoiceCard(
                        title: focus.rawValue,
                        subtitle: focusSubtitle(focus),
                        systemImage: focusImage(focus),
                        isSelected: response.hairLossFocus == focus
                    ) {
                        let previousFocus = response.hairLossFocus
                        response.hairLossFocus = focus
                        if focus != previousFocus {
                            response.patchAreaSummary = ""
                            response.hasEyebrowOrBeardInvolvement = false
                            response.hasScalpBurningTenderness = false
                            response.hasPustulesOrScale = false
                            response.recentIllnessTrigger = false
                            response.recentSurgeryTrigger = false
                            response.postpartumTrigger = false
                            response.recentWeightLossTrigger = false
                            response.recentMedicationChangeTrigger = false
                        }
                    }
                }
            }
        }
    }

    private let durationOptions = ["Less than 3 months", "3–6 months", "6–12 months", "1–3 years", "3+ years", "Not sure"]

    private var hairLossDurationStep: some View {
        questionPage(
            icon: "clock.arrow.circlepath",
            question: "When did you first notice changes?",
            subtitle: "Duration helps distinguish sudden shedding from gradual thinning and guides tracking expectations."
        ) {
            selectableChips(options: durationOptions, selection: $response.hairLossDuration)
        }
    }

    private var patternAndHistoryStep: some View {
        questionPage(
            icon: "map",
            question: "Pattern & history",
            subtitle: "Where do you notice changes and who in your family has experienced them?"
        ) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PATTERN DISTRIBUTION")
                        .onboardingFieldLabel()
                    TextField("e.g. temples, part line, crown, diffuse", text: $response.patternDistribution)
                        .focused($focusedField, equals: .patternDistribution)
                        .submitLabel(.next)
                        .accessibilityIdentifier("onboardingPatternField")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 5)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("FAMILY HISTORY")
                        .onboardingFieldLabel()
                    TextField("e.g. father, mother, siblings, none known", text: $response.familyHistorySummary)
                        .focused($focusedField, equals: .familyHistory)
                        .submitLabel(.done)
                        .accessibilityIdentifier("onboardingFamilyHistoryField")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 5)
                }
            }
        }
    }

    @ViewBuilder
    private var conditionalHairLossStep: some View {
        if response.hairLossFocus == .alopeciaAreata {
            questionPage(icon: "circle.grid.2x2.fill", question: "Patch context", subtitle: "Patch-based tracking is more useful when you standardize the zones you watch.") {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Patch areas (scalp, eyebrow, beard, lash)", text: $response.patchAreaSummary)
                        .focused($focusedField, equals: .patchArea)
                        .submitLabel(.done)
                        .accessibilityIdentifier("onboardingPatchAreaField")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    onboardingToggleCard(
                        title: "Eyebrow or beard involvement",
                        detail: "Should the plan account for eyebrow or beard areas?",
                        isOn: $response.hasEyebrowOrBeardInvolvement,
                        tint: Color(red: 0.31, green: 0.53, blue: 0.46)
                    )
                }
            }
        } else if response.hairLossFocus == .inflammatoryScarring {
            questionPage(icon: "flame.fill", question: "Warning-pattern symptoms", subtitle: "These symptoms raise the value of symptom documentation and clinician review reminders.") {
                VStack(spacing: 14) {
                    onboardingToggleCard(
                        title: "Burning or tenderness",
                        detail: "Burning, soreness, or tenderness matters in your current pattern",
                        isOn: $response.hasScalpBurningTenderness,
                        tint: Color(red: 0.78, green: 0.35, blue: 0.26)
                    )
                    onboardingToggleCard(
                        title: "Pustules or heavy scale",
                        detail: "Pustules, heavy scale, or inflammatory flares are part of the picture",
                        isOn: $response.hasPustulesOrScale,
                        tint: Color(red: 0.72, green: 0.42, blue: 0.21)
                    )
                }
            }
        } else if response.hairLossFocus == .telogenEffluvium {
            questionPage(icon: "timeline.selection", question: "Possible trigger history", subtitle: "Diffuse shedding often lags behind the trigger rather than appearing the same day.") {
                VStack(spacing: 12) {
                    onboardingToggleCard(title: "Recent illness or fever", detail: "Febrile illness can cause delayed shedding", isOn: $response.recentIllnessTrigger, tint: PremiumTheme.warmAmber)
                    onboardingToggleCard(title: "Surgery or anesthesia", detail: "Surgical stress can trigger telogen shifts", isOn: $response.recentSurgeryTrigger, tint: PremiumTheme.warmAmber)
                    onboardingToggleCard(title: "Postpartum change", detail: "Hormonal shifts after pregnancy", isOn: $response.postpartumTrigger, tint: PremiumTheme.warmAmber)
                    onboardingToggleCard(title: "Weight loss / calorie restriction", detail: "Nutritional changes affect hair cycle", isOn: $response.recentWeightLossTrigger, tint: PremiumTheme.warmAmber)
                    onboardingToggleCard(title: "New medication", detail: "Some medications affect hair growth", isOn: $response.recentMedicationChangeTrigger, tint: PremiumTheme.warmAmber)
                }
            }
        }
    }

    // MARK: - Mid-Flow Insight (single interstitial)

    private var midFlowInsightStep: some View {
        didYouKnowPage(
            imageName: "intelligence-ambient-soft",
            fact: "Shedding often lags behind stressors by 2\u{2013}4 months. A balanced scalp environment is one of the strongest predictors of healthy growth.",
            context: "The next questions about your scalp and routine help the app create structure around these connections.",
            accentColor: Color(red: 0.29, green: 0.56, blue: 0.42)
        )
    }

    // MARK: - Section 3: Scalp & Styling (combined)

    private var scalpAndStylingStep: some View {
        questionPage(
            icon: "aqi.medium",
            question: "Scalp & styling",
            subtitle: "These choices drive scalp-care tasks and traction-related reminders."
        ) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENT SCALP PATTERN")
                        .onboardingFieldLabel()
                    VStack(spacing: 12) {
                        ForEach(OnboardingScalpState.allCases) { state in
                            VisualChoiceRow(
                                title: state.rawValue,
                                subtitle: scalpSubtitle(state),
                                systemImage: scalpImage(state),
                                isSelected: response.scalpState == state
                            ) {
                                response.scalpState = state
                            }
                        }
                    }
                }

                onboardingToggleCard(
                    title: "Tight styling history",
                    detail: "I often wear tight styles, extensions, or anything that pulls on the hairline",
                    isOn: $response.hasTightStyles,
                    tint: Color(red: 0.78, green: 0.35, blue: 0.26)
                )
            }
        }
    }

    // MARK: - Section 4: Wash & Habits (combined)

    private var washAndHabitsStep: some View {
        questionPage(
            icon: "calendar.badge.clock",
            question: "Wash & habits",
            subtitle: "Set your wash rhythm and choose optional tracking habits."
        ) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WASH RHYTHM")
                        .onboardingFieldLabel()
                    VStack(spacing: 12) {
                        ForEach(OnboardingWashPreference.allCases) { preference in
                            VisualChoiceRow(
                                title: preference.rawValue,
                                subtitle: washSubtitle(preference),
                                systemImage: washImage(preference),
                                isSelected: response.washPreference == preference
                            ) {
                                response.washPreference = preference
                            }
                        }
                    }
                }

                onboardingToggleCard(
                    title: "Monthly photo reminder",
                    detail: "Add a fixed-interval photo protocol for consistent visual tracking",
                    isOn: $response.wantsMonthlyPhotos,
                    tint: Color(red: 0.20, green: 0.47, blue: 0.79)
                )
                .onChange(of: response.wantsMonthlyPhotos) { _, newValue in
                    response.includePhotoReminder = newValue
                }

                onboardingToggleCard(
                    title: "Night protection reminders",
                    detail: "Add nightly reminders for a protective wrap or satin pillowcase routine",
                    isOn: $response.wantsNightProtection,
                    tint: Color(red: 0.29, green: 0.56, blue: 0.42)
                )
                .onChange(of: response.wantsNightProtection) { _, newValue in
                    response.includeNightProtectionTask = newValue
                }
            }
        }
    }

    // MARK: - Section 5: Treatment

    private var medicationStatusStep: some View {
        questionPage(
            icon: "pills.fill",
            question: "Current treatments?",
            subtitle: "The app will only pre-create medication trackers if you are already using something. It is not recommending treatment."
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingMedicationStatus.allCases) { status in
                    VisualChoiceRow(
                        title: status.rawValue,
                        subtitle: medicationSubtitle(status),
                        systemImage: medicationImage(status),
                        isSelected: response.medicationStatus == status
                    ) {
                        response.medicationStatus = status
                    }
                }
            }
        }
    }

    // MARK: - "Did You Know?" Page

    private func didYouKnowPage(imageName: String, fact: String, context: String, accentColor: Color) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 180)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                .shadow(color: accentColor.opacity(0.20), radius: 24, y: 12)
                .scaleEffect(iconBounce ? 1 : 0.85)
                .opacity(iconBounce ? 1 : 0)

            Spacer().frame(height: 32)

            Text("DID YOU KNOW?")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .tracking(2)
                .padding(.bottom, 12)

            Text(fact)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.14))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 20)

            Text(context)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary Step

    private var summaryStep: some View {
        ZStack {
            CelebrationParticlesView()
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                // Hero
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.26, green: 0.56, blue: 0.42), Color(red: 0.20, green: 0.47, blue: 0.79)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(iconBounce ? 1 : 0.7)
                        .opacity(iconBounce ? 1 : 0)

                    Text("Your Plan Is Ready")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumTheme.ink)

                    Text("\(planPreview.totalItems) items tailored to your profile")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(PremiumTheme.mutedInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                // What this plan creates
                OnboardingPanel(title: "What this plan will create", bodyText: "This is a starting structure. You can edit tasks, meds, and triggers later from the app.") {
                    summaryBullet("This plan creates \(planPreview.taskTitles.count) routine items, \(planPreview.triggerTitles.count) trigger context entries, and \(planPreview.medicationTitles.count) treatment trackers.")
                    summaryBullet(response.includeBaselineTracking ? "A repeated check-in cadence and weekly review structure will be added." : "Baseline tracking is turned off.")
                    summaryBullet(response.includeWashRhythm ? "Wash-day structure and post-wash scalp-response tracking will be added." : "Wash rhythm reminder is turned off.")
                    summaryBullet(summaryScalpLine)
                    summaryBullet(response.includePhotoReminder && response.wantsMonthlyPhotos ? "A standardized photo workflow will be added." : "No photo reminder will be added.")
                    summaryBullet(response.includeNightProtectionTask && response.wantsNightProtection ? "A nightly protection habit will be added." : "No night protection task will be added.")
                    summaryBullet(medicationSummaryLine)
                }

                // Preview
                if planPreview.totalItems > 0 {
                    OnboardingPanel(title: "Starter protocol preview", bodyText: "This is the actual structure the app will create.") {
                        if !planPreview.taskTitles.isEmpty {
                            previewSection("Routine items", items: planPreview.taskTitles)
                        }
                        if !planPreview.triggerTitles.isEmpty {
                            previewSection("Trigger context", items: planPreview.triggerTitles)
                        }
                        if !planPreview.medicationTitles.isEmpty {
                            previewSection("Treatment trackers", items: planPreview.medicationTitles)
                        }
                    }
                }

                // Customize toggles
                OnboardingPanel(title: "Adjust the generated plan", bodyText: "Turn individual pieces on or off before they are created.") {
                    planToggle("Baseline tracking", detail: "Creates the repeated check-in cadence and weekly review structure.", isOn: $response.includeBaselineTracking, tint: Color(red: 0.20, green: 0.47, blue: 0.79))
                    planToggle("Wash rhythm", detail: "Creates wash-day and post-wash scalp-response tasks.", isOn: $response.includeWashRhythm, tint: Color(red: 0.23, green: 0.42, blue: 0.68))
                    planToggle("Scalp support", detail: "Creates scalp-state or condition-specific support tasks.", isOn: $response.includeScalpSupport, tint: Color(red: 0.29, green: 0.56, blue: 0.42))
                    planToggle("Trigger logging", detail: "Creates onboarding trigger context when relevant.", isOn: $response.includeTriggerLogging, tint: PremiumTheme.warmAmber)
                    planToggle("Photo reminder", detail: "Creates the fixed-interval photo protocol.", isOn: $response.includePhotoReminder, tint: Color(red: 0.24, green: 0.55, blue: 0.76))
                    planToggle("Night protection", detail: "Creates the wrap or low-friction sleep reminder.", isOn: $response.includeNightProtectionTask, tint: Color(red: 0.34, green: 0.58, blue: 0.47))
                    planToggle("Medication tracker", detail: "Creates medication tracking only if you reported current use.", isOn: $response.includeMedicationTracker, tint: PremiumTheme.softPurple)
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func questionPage<Content: View>(
        icon: String,
        question: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)

            // Icon in colored rounded-rect badge
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(sectionAccentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: sectionAccentColor.opacity(0.35), radius: 12, y: 6)
                .scaleEffect(iconBounce ? 1 : 0.5)
                .opacity(iconBounce ? 1 : 0)
                .padding(.bottom, 18)

            Text(question)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(PremiumTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PremiumTheme.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 24)

            content()
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func onboardingToggleCard(title: String, detail: String, isOn: Binding<Bool>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))
                    Text(detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: tint))
        }
        .padding(18)
        .premiumGlassCard(cornerRadius: 22, fillOpacity: 0.48, shadowOpacity: 0.08)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isOn.wrappedValue ? tint.opacity(0.32) : Color.white.opacity(0.5), lineWidth: 1)
        )
    }

    private func selectableChips(options: [String], selection: Binding<String>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection.wrappedValue == option
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selection.wrappedValue = option
                } label: {
                    HStack(spacing: 8) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(option)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(isSelected ? .white : PremiumTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(
                        isSelected ? AnyShapeStyle(sectionAccentColor) : AnyShapeStyle(Color.white.opacity(0.80)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? Color.clear : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: isSelected ? sectionAccentColor.opacity(0.25) : Color.black.opacity(0.03), radius: isSelected ? 8 : 4, y: isSelected ? 4 : 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Data helpers

    private var summaryScalpLine: String {
        guard response.includeScalpSupport else {
            return "Condition-specific scalp support is turned off."
        }
        switch response.scalpState {
        case .calm: return "The plan stays simple because you selected a mostly calm scalp."
        case .drySensitive: return "Dry/sensitive scalp tasks for barrier-safe wash review and hydration support will be added."
        case .flaky: return "Flake-focused treatment wash and flare-note tasks will be added."
        case .oily: return "An oil-buildup review task will be added."
        }
    }

    private var medicationSummaryLine: String {
        guard response.includeMedicationTracker else {
            return "Medication tracking is turned off."
        }
        switch response.medicationStatus {
        case .none: return "No medication tracker will be pre-created."
        case .minoxidil: return "A minoxidil tracker with twice-daily starter timing will be pre-created."
        case .oralPrescription: return "A clinician-directed oral medication tracker placeholder will be added."
        case .both: return "A minoxidil tracker and an oral prescription tracker placeholder will be added."
        }
    }

    private var planPreview: OnboardingPlanPreview {
        InitialRoutinePlanner.preview(for: response)
    }

    private func focusSubtitle(_ focus: HairLossFocus) -> String {
        switch focus {
        case .androgeneticAlopecia: return "Pattern-focused tracking"
        case .alopeciaAreata: return "Patch-based tracking"
        case .inflammatoryScarring: return "Warning-pattern tracking"
        case .telogenEffluvium: return "Trigger-history tracking"
        case .notSure: return "Start broad and refine later"
        }
    }

    private func focusImage(_ focus: HairLossFocus) -> String {
        switch focus {
        case .androgeneticAlopecia: return "person.crop.circle.badge.exclamationmark"
        case .alopeciaAreata: return "circle.grid.2x2.fill"
        case .inflammatoryScarring: return "flame.fill"
        case .telogenEffluvium: return "timeline.selection"
        case .notSure: return "questionmark.circle.fill"
        }
    }

    private func scalpSubtitle(_ state: OnboardingScalpState) -> String {
        switch state {
        case .calm: return "No major irritation pattern right now."
        case .drySensitive: return "Feels tight, reactive, or easily irritated."
        case .flaky: return "Dandruff-like or seb derm-prone."
        case .oily: return "Gets greasy quickly."
        }
    }

    private func scalpImage(_ state: OnboardingScalpState) -> String {
        switch state {
        case .calm: return "leaf.fill"
        case .drySensitive: return "drop.degreesign.slash.fill"
        case .flaky: return "aqi.low"
        case .oily: return "humidity.fill"
        }
    }

    private func washSubtitle(_ preference: OnboardingWashPreference) -> String {
        switch preference {
        case .daily: return "Best for people who truly need a daily scalp reset."
        case .everyOtherDay: return "Balanced cadence for many users."
        case .twiceWeekly: return "Lower-frequency wash rhythm."
        case .weekly: return "Longer spacing that needs scalp comfort tracking."
        }
    }

    private func washImage(_ preference: OnboardingWashPreference) -> String {
        switch preference {
        case .daily: return "calendar"
        case .everyOtherDay: return "calendar.badge.clock"
        case .twiceWeekly: return "calendar.badge.minus"
        case .weekly: return "calendar.circle"
        }
    }

    private func medicationSubtitle(_ status: OnboardingMedicationStatus) -> String {
        switch status {
        case .none: return "No treatment tracker will be created."
        case .minoxidil: return "Build adherence tracking for minoxidil."
        case .oralPrescription: return "Track a clinician-directed oral treatment."
        case .both: return "Track topical and oral treatment together."
        }
    }

    private func medicationImage(_ status: OnboardingMedicationStatus) -> String {
        switch status {
        case .none: return "minus.circle.fill"
        case .minoxidil: return "drop.circle.fill"
        case .oralPrescription: return "pills.circle.fill"
        case .both: return "cross.case.circle.fill"
        }
    }

    @ViewBuilder
    private func previewSection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.22, green: 0.30, blue: 0.27))
            ForEach(items, id: \.self) { item in
                summaryBullet(item)
            }
        }
        .padding(.top, 4)
    }

    private func summaryBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.26, green: 0.56, blue: 0.42))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.40, blue: 0.37))
        }
    }

    private func planToggle(_ title: String, detail: String, isOn: Binding<Bool>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: tint))
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.50, blue: 0.47))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Supporting Views

private struct OnboardingPanel<Content: View>: View {
    let title: String
    let bodyText: String
    @ViewBuilder var content: Content

    init(title: String, bodyText: String, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.title = title
        self.bodyText = bodyText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(PremiumTheme.ink)
            Text(bodyText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PremiumTheme.mutedInk)
                .lineSpacing(2)
            content
        }
        .padding(18)
        .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 5)
    }
}

private struct VisualChoiceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? .white : PremiumTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? Color.white.opacity(0.22) : Color.black.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : PremiumTheme.ink)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : PremiumTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(16)
            .background(
                isSelected
                ? AnyShapeStyle(PremiumTheme.accentGradient)
                : AnyShapeStyle(Color.white.opacity(0.85)),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: isSelected ? PremiumTheme.forest.opacity(0.25) : Color.black.opacity(0.04), radius: isSelected ? 12 : 6, y: isSelected ? 6 : 3)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboardingChoice_\(sanitizedIdentifier(title))")
    }
}

private struct VisualChoiceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? .white : PremiumTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? Color.white.opacity(0.22) : Color.black.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : PremiumTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : PremiumTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14)
            .background(
                isSelected
                ? AnyShapeStyle(PremiumTheme.accentGradient)
                : AnyShapeStyle(Color.white.opacity(0.85)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: isSelected ? PremiumTheme.forest.opacity(0.2) : Color.black.opacity(0.03), radius: isSelected ? 10 : 4, y: isSelected ? 5 : 2)
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboardingChoice_\(sanitizedIdentifier(title))")
    }
}

// MARK: - Celebration Particles

private struct CelebrationParticlesView: View {
    @State private var particles: [CelebrationParticle] = (0..<20).map { _ in CelebrationParticle() }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let age = timeline.date.timeIntervalSince(particle.createdAt)
                    let y = (particle.startY + age * particle.speed) * size.height
                    let x = (particle.startX + sin(age * particle.wobbleFreq) * particle.wobbleAmp) * size.width
                    let opacity = max(0, 1.0 - age / particle.lifetime)

                    guard opacity > 0 else { continue }

                    context.opacity = opacity
                    context.fill(
                        Circle().path(in: CGRect(x: x, y: y, width: particle.size, height: particle.size)),
                        with: .color(particle.color)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct CelebrationParticle {
    let startX: Double = .random(in: 0.05...0.95)
    let startY: Double = .random(in: -0.3...0)
    let speed: Double = .random(in: 0.03...0.10)
    let size: CGFloat = .random(in: 4...8)
    let color: Color = [
        PremiumTheme.teal,
        PremiumTheme.gold,
        PremiumTheme.forest,
        PremiumTheme.softPurple
    ].randomElement()!
    let lifetime: Double = .random(in: 4...8)
    let wobbleFreq: Double = .random(in: 1...3)
    let wobbleAmp: Double = .random(in: 0.01...0.04)
    let createdAt = Date()
}

// MARK: - Helpers

private func sanitizedIdentifier(_ raw: String) -> String {
    raw
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: ",", with: "")
}

private extension Text {
    func onboardingFieldLabel() -> some View {
        self
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.41, green: 0.46, blue: 0.43))
            .textCase(.uppercase)
    }
}

private extension View {
    func onboardingTextField() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 0.96, green: 0.97, blue: 0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
