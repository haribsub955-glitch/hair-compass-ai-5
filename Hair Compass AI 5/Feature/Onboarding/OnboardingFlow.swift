import SwiftData
import SwiftUI

/// The cinematic first-run. Nine screens that demonstrate rather than ask; each writes the same
/// `Profile` fields as the plain BaselineFlow (which stays as the editable profile). The answer
/// drives the physics — the shedding dial *is* the falling-hair simulation.
struct OnboardingFlow: View {
    @Bindable var profile: Profile
    var onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @State private var step = OnboardingFlow.initialStep
    @State private var shedIntensity: CGFloat = 0.34

    private let total = 9   // 0 welcome … 8 finale

    private static var initialStep: Int {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "HC_ONBOARD_STEP"), i + 1 < a.count, let n = Int(a[i + 1]) { return max(0, min(8, n)) }
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
            if step > 0 && step < total - 1 {
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
        case 6: familyStep
        case 7: habitsStep
        default: finale
        }
    }

    // MARK: Navigation

    private func next() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeInOut(duration: 0.35)) { step = min(total - 1, step + 1) }
    }
    private func back() { withAnimation(.easeInOut(duration: 0.3)) { step = max(0, step - 1) } }

    private func finish() {
        // Seed today's shedding from the dial so day one has data.
        let today = Calendar.current.startOfDay(for: .now)
        let hasToday = (try? context.fetch(FetchDescriptor<DailyEntry>(predicate: #Predicate { $0.date >= today })))?.isEmpty == false
        if !hasToday {
            context.insert(DailyEntry(date: .now, shed: SheddingDial.shedLevel(shedIntensity)))
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

    private var nameStep: some View {
        VStack(spacing: 0) {
            head("About you", "What should we call you?")
            Spacer()
            TextField("Your name", text: $profile.name)
                .textFieldStyle(.plain).font(Clinical.headline(26)).foregroundStyle(Clinical.ink)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
                .accessibilityIdentifier("onboardName")
            Spacer(); Spacer()
            primary("Continue", enabled: profile.name.trimmingCharacters(in: .whitespaces).count >= 2) { next() }
        }
    }

    private var sexStep: some View {
        VStack(spacing: 0) {
            head("About you", "Your biological sex", "It sets the staging scale we compare against.")
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
            head("What are you noticing?", "Tell us what you see")
            ConditionDemo(condition: profile.condition)
                .frame(height: 190).frame(maxWidth: .infinity)
                .background(Clinical.surface).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                .padding(.horizontal, 20).padding(.top, 12)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(HairCondition.allCases) { c in
                        let on = profile.condition == c
                        Button { withAnimation(.easeInOut(duration: 0.3)) { profile.condition = c }; UISelectionFeedbackGenerator().selectionChanged() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                                    Text(c.summary).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
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

    private var familyStep: some View {
        VStack(spacing: 0) {
            head("Risk", "Does hair loss run\nin your family?", "The single strongest measured factor — context, not a prediction.")
            Spacer()
            RiskArc(value: riskValue).padding(.bottom, 8)
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

    private var habitsStep: some View {
        VStack(spacing: 0) {
            head("Habits", "How do you treat\nyour hair?", "Watch what each does to a single strand.")
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

    private var finale: some View {
        ZStack {
            FallingHairView(intensity: 0.25)
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Clinical.accent)
                    .padding(.bottom, 16)
                Text(profile.name.isEmpty ? "You're all set" : "You're all set, \(profile.name)")
                    .font(Clinical.headline(30)).foregroundStyle(Clinical.ink).multilineTextAlignment(.center)
                Text("Your compass is calibrated. Log your first day and the trends begin.")
                    .font(.system(size: 15)).foregroundStyle(Clinical.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 40).padding(.top, 8)
                Spacer()
                primary("Start tracking") { finish() }
            }
        }
    }
}
