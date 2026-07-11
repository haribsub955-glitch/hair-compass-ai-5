import SwiftData
import SwiftUI

/// The cinematic first-run. 14 screens that demonstrate rather than ask; each writes the same
/// `Profile`/`DailyEntry`/`TriggerEvent` fields as the plain BaselineFlow (which stays as the
/// editable profile). The answer drives the physics — the shedding dial *is* the falling-hair
/// simulation.
struct OnboardingFlow: View {
    @Bindable var profile: Profile
    var onFinish: () -> Void
    /// Non-nil only when replayed from the profile — shows a close button so it can be exited early.
    /// First-run leaves this nil so the walkthrough must be completed.
    var onDismiss: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(HealthKitService.self) private var healthKit
    @State private var step = OnboardingFlow.initialStep
    @State private var shedIntensity: CGFloat = 0.34

    // Status questions (steps 6–8) — feed the day-one seed and the paywall's personalized line.
    // Scalp/wellbeing fields are `LivingGauge` intensities (0…1); `finish()` converts them to the
    // discrete bands `OnboardingSeed.dayOneEntry` takes via `GaugeBand.index`.
    @State private var oilI: CGFloat = 0
    @State private var flakeI: CGFloat = 0
    @State private var itchI: CGFloat = 0
    @State private var sleepI: CGFloat = 0.5
    @State private var stressI: CGFloat = 0.5
    @State private var selectedTriggers = Set<TriggerType>()

    @FocusState private var nameFocused: Bool

    private let total = 14   // 0 welcome … 13 finale

    private static var initialStep: Int {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "HC_ONBOARD_STEP"), i + 1 < a.count, let n = Int(a[i + 1]) { return max(0, min(13, n)) }
        #endif
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                content
                    .id(step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Clinical.canvas.ignoresSafeArea())
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            // The paywall (12) is a forward-or-through screen — no back button, "Continue free"
            // is the honest exit.
            if step > 0 && step < total - 1 && step != 12 {
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(Clinical.ink)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Clinical.hairline)
                    Capsule().fill(Clinical.accent)
                        .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(total))
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
                }
            }
            .frame(height: 4)
            if let onDismiss {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Clinical.tertiary)
                }
                .accessibilityLabel("Close walkthrough")
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: nameStep
        case 2: sexStep
        case 3: ageStep
        case 4: concernStep
        case 5: sheddingStep
        case 6: scalpFeelStep
        case 7: stressSleepStep
        case 8: triggersStep
        case 9: familyStep
        case 10: habitsStep
        case 11: healthConnectStep
        case 12: OnboardingPlanStep(profile: profile) { next() }
        default: finale
        }
    }

    // MARK: Navigation

    private func next() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        nameFocused = false
        withAnimation(.easeInOut(duration: 0.35)) { step = min(total - 1, step + 1) }
    }
    private func back() {
        nameFocused = false
        withAnimation(.easeInOut(duration: 0.3)) { step = max(0, step - 1) }
    }

    private func finish() {
        // Seed today's full status (shedding + scalp + stress/sleep) so day one has data, plus
        // one TriggerEvent per recent trigger the user flagged.
        let today = Calendar.current.startOfDay(for: .now)
        let hasToday = (try? context.fetch(FetchDescriptor<DailyEntry>(predicate: #Predicate { $0.date >= today })))?.isEmpty == false
        if !hasToday {
            context.insert(OnboardingSeed.dayOneEntry(
                shedIntensity: shedIntensity,
                oiliness: GaugeBand.index(oilI, count: 4),
                flaking: GaugeBand.index(flakeI, count: 4),
                itch: GaugeBand.index(itchI, count: 4),
                stress: GaugeBand.index(stressI, count: 5) + 1,
                sleepQuality: GaugeBand.index(sleepI, count: 5) + 1
            ))
        }
        for event in OnboardingSeed.triggerEvents(selectedTriggers) {
            context.insert(event)
        }
        profile.hasOnboarded = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onFinish()
    }

    private func primary(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ClinicalButtonStyle())
            .disabled(!enabled).opacity(enabled ? 1 : 0.5)
            .padding(.horizontal, 20).padding(.bottom, 28)
    }

    private func head(_ eyebrow: String, _ title: String, _ sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow)
            Text(title).font(Clinical.headline(30)).foregroundStyle(Clinical.ink).fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(Clinical.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 12)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            BrandBanner(art: BrandArt.baselineHero, height: 260).padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Welcome")
                Text("Let's set your\ncompass").font(Clinical.headline(34)).foregroundStyle(Clinical.ink)
                Text("A few questions — each one shows you something true about hair. It takes about a minute.")
                    .font(.system(size: 15)).foregroundStyle(Clinical.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Spacer()
            primary("Begin") { next() }
        }
    }

    private var nameValid: Bool { profile.name.trimmingCharacters(in: .whitespaces).count >= 2 }

    private var nameStep: some View {
        VStack(spacing: 0) {
            head("About you", "What should we call you?")
            Spacer()
            TextField("Your name", text: $profile.name)
                .textFieldStyle(.plain).font(Clinical.headline(26)).foregroundStyle(Clinical.ink)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
                .focused($nameFocused)
                .submitLabel(.continue)
                .onSubmit { if nameValid { next() } }
                .accessibilityIdentifier("onboardName")
            Spacer(); Spacer()
            primary("Continue", enabled: nameValid) { next() }
        }
        .onAppear {
            // Delay lets the step transition settle before the keyboard animates in.
            Task { try? await Task.sleep(for: .milliseconds(450)); nameFocused = true }
        }
    }

    private var sexStep: some View {
        VStack(spacing: 0) {
            head("About you", "Your biological sex", "Men and women thin in different patterns — this picks the right map for yours.")
            StagingScalePreview(sex: profile.sex)
                .padding(.horizontal, 20).padding(.top, 8)
            Spacer()
            VStack(spacing: 12) {
                ForEach(BiologicalSex.allCases) { s in
                    let on = profile.sex == s
                    Button { profile.sex = s; UISelectionFeedbackGenerator().selectionChanged() } label: {
                        HStack {
                            Text(s.title).font(.system(size: 17, weight: .medium)).foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            Spacer()
                            if on { Text(s.stagingScaleName).font(Clinical.eyebrow(10)).foregroundStyle(Clinical.surface.opacity(0.8)) }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 18)
                        .background(on ? Clinical.accent : Clinical.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }.padding(.horizontal, 20)
            Spacer()
            primary("Continue") { next() }
        }
    }

    private var ageStep: some View {
        let bands = ["Under 25", "26–35", "36–45", "46–55", "56+"]
        return VStack(spacing: 0) {
            head("About you", "How old are you?")
            Spacer()
            VStack(spacing: 10) {
                ForEach(bands, id: \.self) { b in
                    let on = profile.ageBand == b
                    Button { profile.ageBand = b; UISelectionFeedbackGenerator().selectionChanged() } label: {
                        Text(b).font(.system(size: 16, weight: on ? .semibold : .regular)).foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(on ? Clinical.ink : Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20)
            Spacer()
            primary("Continue", enabled: !profile.ageBand.isEmpty) { next() }
        }
    }

    private var concernStep: some View {
        VStack(spacing: 0) {
            head("What are you noticing?", "Pick the closest match", "Plain words — the clinical name is underneath. You can change this anytime.")
            ConditionDemo(condition: profile.condition)
                .frame(height: 190).frame(maxWidth: .infinity)
                .background(Clinical.surface).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                .padding(.horizontal, 20).padding(.top, 12)
            Text(profile.condition.demoCaption)
                .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                .contentTransition(.opacity)
                .padding(.horizontal, 20).padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(HairCondition.allCases) { c in
                        let on = profile.condition == c
                        Button { withAnimation(.easeInOut(duration: 0.3)) { profile.condition = c }; UISelectionFeedbackGenerator().selectionChanged() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(c.plainTitle).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                                    Text(c.title.uppercased()).font(Clinical.eyebrow(10)).tracking(1.0).foregroundStyle(Clinical.tertiary)
                                    Text(c.plainSummary).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                                }
                                Spacer()
                                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Clinical.accent : Clinical.tertiary)
                            }
                            .padding(12)
                            .background(on ? Clinical.accentSoft : Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Clinical.accent.opacity(0.4) : Clinical.hairline, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20).padding(.top, 12)
            }
            primary("Continue") { next() }
        }
    }

    private var sheddingStep: some View {
        let cap = SheddingDial.bandCaption(shedIntensity)
        return ZStack {
            FallingHairView(intensity: shedIntensity)
            VStack(alignment: .leading, spacing: 0) {
                head("Daily shedding", "How much are you\nshedding?", "Drag the dial — what you set is what falls.")
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text(cap.0).font(Clinical.headline(30)).foregroundStyle(Clinical.accent)
                    Text(cap.1).font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                }.padding(.horizontal, 20)
                primary("Continue") { next() }
            }
            HStack {
                Spacer()
                SheddingDial(intensity: $shedIntensity)
                    .frame(width: 74).frame(maxHeight: 380)
                    .padding(.trailing, 18)
            }
        }
    }

    private var scalpFeelStep: some View {
        VStack(spacing: 0) {
            head("Your scalp", "How does your scalp feel?", "Drag each — the preview reacts as you go.")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    LivingGauge(title: "Oiliness", intensity: $oilI, bandCount: 4,
                                tint: Clinical.accent, zones: ["NORMAL", "SLIGHT", "OILY", "VERY"], ends: nil,
                                caption: { i in Self.scalpCaption(i, count: 4,
                                    titles: ["Balanced", "Slightly oily", "Oily", "Very oily"],
                                    subs: ["comfortable", "a little greasy", "greasy by midday", "greasy fast"]) }) { i in OilMotif(intensity: i) }
                    LivingGauge(title: "Flaking", intensity: $flakeI, bandCount: 4,
                                tint: Clinical.accent, zones: ["NONE", "POWDERY", "VISIBLE", "ADHERENT"], ends: nil,
                                caption: { i in Self.scalpCaption(i, count: 4,
                                    titles: ["No flaking", "Powdery", "Visible flakes", "Sticky flakes"],
                                    subs: ["clear", "fine dust", "you can see it", "clings to the scalp"]) }) { i in FlakeMotif(intensity: i) }
                    LivingGauge(title: "Itch", intensity: $itchI, bandCount: 4,
                                tint: Clinical.accent, zones: ["NONE", "MILD", "COMES & GOES", "CONSTANT"], ends: nil,
                                caption: { i in Self.scalpCaption(i, count: 4,
                                    titles: ["No itch", "Mild", "Comes and goes", "Constant"],
                                    subs: ["clear", "barely there", "on and off", "hard to ignore"]) }) { i in ItchMotif(intensity: i) }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            }
            primary("Continue") { next() }
        }
    }

    /// Shared caption builder: band index → (title, subtitle) from parallel arrays.
    private static func scalpCaption(_ i: CGFloat, count: Int, titles: [String], subs: [String]) -> (String, String) {
        let b = GaugeBand.index(i, count: count)
        return (titles[b], subs[b])
    }

    private var stressSleepStep: some View {
        VStack(spacing: 0) {
            head("Lifestyle", "Stress and sleep lately?", "Both can show up in your hair 2–3 months later.")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    LivingGauge(title: "Sleep quality", intensity: $sleepI, bandCount: 5,
                                tint: Clinical.sage, zones: nil, ends: ("POOR", "DEEP"),
                                caption: { i in Self.fiveCaption(i,
                                    titles: ["Poor", "Fair", "OK", "Good", "Great"],
                                    subs: ["restless nights", "broken sleep", "average", "mostly solid", "deeply rested"]) }) { i in SleepMotif(intensity: i) }
                    LivingGauge(title: "Stress", intensity: $stressI, bandCount: 5,
                                tint: Clinical.accent, zones: nil, ends: ("CALM", "HIGH"),
                                caption: { i in Self.fiveCaption(i,
                                    titles: ["Very low", "Low", "Medium", "High", "Very high"],
                                    subs: ["calm", "steady", "some pressure", "stretched", "overwhelmed"]) }) { i in StressMotif(intensity: i) }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            }
            primary("Continue") { next() }
        }
    }

    /// Shared caption builder for the 5-band wellbeing gauges — analogous to `scalpCaption`.
    private static func fiveCaption(_ i: CGFloat, titles: [String], subs: [String]) -> (String, String) {
        let b = GaugeBand.index(i, count: 5)
        return (titles[b], subs[b])
    }

    private var triggersStep: some View {
        VStack(spacing: 0) {
            head("The last 3 months", "Did any of these happen?", "Shedding often follows a trigger by 2–3 months. Knowing the date makes your chart make sense.")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(TriggerType.allCases) { t in
                        let on = selectedTriggers.contains(t)
                        Button {
                            if on { selectedTriggers.remove(t) } else { selectedTriggers.insert(t) }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: t.symbol).font(.system(size: 16)).foregroundStyle(on ? Clinical.accent : Clinical.secondary).frame(width: 22)
                                Text(t.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Clinical.accent : Clinical.tertiary)
                            }
                            .padding(14)
                            .background(on ? Clinical.accentSoft : Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Clinical.accent.opacity(0.4) : Clinical.hairline, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    Button {
                        selectedTriggers.removeAll()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack {
                            Text("None of these").font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Image(systemName: selectedTriggers.isEmpty ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selectedTriggers.isEmpty ? Clinical.accent : Clinical.tertiary)
                        }
                        .padding(14)
                        .background(selectedTriggers.isEmpty ? Clinical.accentSoft : Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selectedTriggers.isEmpty ? Clinical.accent.opacity(0.4) : Clinical.hairline, lineWidth: 1))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.top, 12)
            }
            primary("Continue") { next() }
        }
    }

    private var familyStep: some View {
        VStack(spacing: 0) {
            head("Risk", "Does hair loss run\nin your family?", "The single strongest measured factor — context, not a prediction.")
            Spacer()
            RiskGauge(value: riskValue)
            Text(familyContextLine)
                .font(.system(size: 12))
                .foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 10)
            VStack(spacing: 8) {
                ForEach(FamilyHistory.allCases) { f in
                    let on = profile.familyHistory == f
                    Button { withAnimation { profile.familyHistory = f }; UISelectionFeedbackGenerator().selectionChanged() } label: {
                        Text(f.title).font(.system(size: 15, weight: on ? .semibold : .regular)).foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(on ? Clinical.accent : Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20)
            Spacer()
            primary("Continue") { next() }
        }
    }
    private var riskValue: Double {
        switch profile.familyHistory { case .none: return 0.05; case .extended: return 0.35; case .oneParent: return 0.6; case .bothParents: return 0.9 }
    }
    /// Switches with the selection — honest, never predictive; each ends "context, not a
    /// prediction." except the baseline (no-signal) line.
    private var familyContextLine: String {
        switch profile.familyHistory {
        case .none: return "Baseline odds — no measured family signal."
        case .extended: return "Somewhat raised odds in studies — context, not a prediction."
        case .oneParent: return "Meaningfully raised odds (~2.7× in a 2026 meta-analysis) — context, not a prediction."
        case .bothParents: return "The strongest measured signal (~2.7× odds, both sides) — still context, not a prediction."
        }
    }

    private var habitsStep: some View {
        VStack(spacing: 0) {
            head("Habits", "How do you treat\nyour hair?", "Watch what each does to a single strand.")
            // UX audit #8: fills the dead lower half between the headline and the toggles with
            // the gouache habits vignette — the trailing Spacer (before "Continue") shrinks to
            // absorb the added height on its own since it only ever claims leftover space.
            Image("onboard-habits")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .accessibilityHidden(true)
            StressStrandView(tight: profile.wearsTightStyles, heat: profile.usesHeat, chemical: profile.usesChemicalTreatments)
                .frame(height: 170)
                .padding(.top, 8)
            VStack(spacing: 10) {
                habitToggle("Tight styles (braids, ponytails)", $profile.wearsTightStyles)
                habitToggle("Regular heat styling", $profile.usesHeat)
                habitToggle("Chemical treatments (dyes, relaxers)", $profile.usesChemicalTreatments)
            }.padding(.horizontal, 20).padding(.top, 8)
            Spacer()
            primary("Continue") { next() }
        }
    }
    private func habitToggle(_ title: String, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: b) { Text(title).font(.system(size: 14)).foregroundStyle(Clinical.ink) }
            .tint(Clinical.accent)
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private var healthConnectStep: some View {
        VStack(spacing: 0) {
            head("Automatic signals", "Connect Apple Health?", "Sleep, body weight, and recovery fill in automatically — no typing. You control exactly what's shared, and you can change it anytime in Settings.")
            Spacer()
            VStack(spacing: 10) {
                healthBenefitRow(symbol: "bed.double.fill", text: "Sleep hours, every night")
                healthBenefitRow(symbol: "figure", text: "Body weight and BMI")
                healthBenefitRow(symbol: "heart.fill", text: "Recovery (HRV) as a stress signal")
            }.padding(.horizontal, 20)
            Spacer()
            healthConnectCTA
        }
    }

    @ViewBuilder private var healthConnectCTA: some View {
        switch healthKit.authorization {
        case .authorized:
            Text("Health is connected ✓")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Clinical.sage)
                .padding(.bottom, 8)
            primary("Continue") { next() }
                .accessibilityIdentifier("onboardHealthConnect")
        case .unavailable:
            Text("Health isn't available on this device")
                .font(.system(size: 13)).foregroundStyle(Clinical.tertiary)
                .padding(.bottom, 8)
            primary("Continue") { next() }
                .accessibilityIdentifier("onboardHealthConnect")
        default:
            primary("Connect Apple Health") {
                Task {
                    await healthKit.requestAuthorization()
                    if healthKit.authorization.isUsable { await healthKit.refreshSnapshot(context: context) }
                    next()
                }
            }
            .accessibilityIdentifier("onboardHealthConnect")
            Button("Not now") { next() }
                .font(.system(size: 13)).foregroundStyle(Clinical.tertiary)
                .padding(.bottom, 24)
        }
    }

    private func healthBenefitRow(symbol: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Clinical.accent).frame(width: 28)
            Text(text).font(.system(size: 14)).foregroundStyle(Clinical.ink)
            Spacer()
        }
        .padding(14)
        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private var finale: some View {
        ZStack {
            FallingHairView(intensity: 0.25)
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Clinical.accent)
                    .padding(.bottom, 16)
                Text(profile.name.isEmpty ? "You're all set" : "You're all set, \(profile.name)")
                    .font(Clinical.headline(30)).foregroundStyle(Clinical.ink).multilineTextAlignment(.center)
                Text("Your compass is calibrated. A quick tour starts when you close this.")
                    .font(.system(size: 15)).foregroundStyle(Clinical.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 40).padding(.top, 8)
                Spacer()
                primary("Start tracking") { finish() }
            }
        }
    }
}
