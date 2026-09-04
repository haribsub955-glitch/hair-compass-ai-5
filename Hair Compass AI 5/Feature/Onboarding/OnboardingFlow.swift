import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    // Restore-from-backup, offered quietly on the welcome step for anyone migrating phones —
    // see `runRestore(from:)`. A migrating user shouldn't have to re-answer 14 questions just
    // to find the door back to their existing records.
    /// True only while the system Health permission sheet is up — drives the pairing animation's
    /// `.connecting` state.
    @State private var requestingHealth = false
    @State private var showRestoreImporter = false
    @State private var restoreSummary: BackupService.RestoreSummary?
    @State private var restoreErrorMessage: String?

    @FocusState private var nameFocused: Bool

    private let total = 15   // 0 welcome … 14 finale (step 3 = pregnancy, women only)

    /// The female-only pregnancy question. Non-female users hop over it, so it never appears for
    /// them and the progress bar simply skips a notch.
    private let pregnancyStepIndex = 3
    private var asksPregnancy: Bool { profile.sex == .female }

    private static var initialStep: Int {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "HC_ONBOARD_STEP"), i + 1 < a.count, let n = Int(a[i + 1]) { return max(0, min(14, n)) }
        #endif
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step 0 is the full-bleed illustrated cover, which carries its own page dots — the
            // progress bar would only compete with them. A *replayed* walkthrough still shows the
            // bar there, because that's where its close button lives.
            if step > 0 || onDismiss != nil { topBar }
            ZStack {
                content
                    .id(step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Clinical.canvas.ignoresSafeArea())
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                runRestore(from: url)
            case .failure(let error):
                restoreErrorMessage = error.localizedDescription
            }
        }
        .alert("Restore complete", isPresented: Binding(
            get: { restoreSummary != nil },
            set: { if !$0 { restoreSummary = nil } }
        )) {
            Button("OK") {
                let restoredOnboardedProfile = profile.hasOnboarded
                restoreSummary = nil
                // The envelope's profile only overwrites ours while ours is still untouched
                // (`BackupService.isDefaultProfile`) — true here on a fresh install's welcome
                // step. If the backup came from an already-onboarded phone, `hasOnboarded` just
                // flipped true, so finish the cover and land straight on a fully-populated
                // Today instead of marching the user through 14 questions they already answered.
                if restoredOnboardedProfile { onFinish() }
            }
        } message: {
            if let s = restoreSummary {
                Text("\(s.inserted) records added, \(s.photosRestored) photos restored.")
            }
        }
        .alert("Couldn't restore", isPresented: Binding(
            get: { restoreErrorMessage != nil },
            set: { if !$0 { restoreErrorMessage = nil } }
        )) {
            Button("OK") { restoreErrorMessage = nil }
        } message: {
            if let restoreErrorMessage { Text(restoreErrorMessage) }
        }
        // NOTE ON DARK MODE: the cover's step 0 (`OnboardingIntro`) is fully dark-aware via
        // `IntroPalette`, and its artwork is transparent so it reads on either ground. It renders
        // light today only because `HairCompassApp` pins the whole window with
        // `.preferredColorScheme(.light)`. A child cannot opt out of that — `.preferredColorScheme(nil)`
        // means "no preference", so the ancestor's `.light` still wins — and forcing `.dark` here
        // would flip the user into a dark cover and straight back to a light questionnaire one tap
        // later. Lifting the window-level lock is the correct fix, and is a deliberate migration of
        // the app's ~480 hardcoded `Clinical.*` call sites rather than a change to make here.
    }

    /// Reads and merges a backup picked from the welcome step's "Restoring from a backup?"
    /// link. Mirrors `BaselineFlow`'s `BackupRestoreSection.runRestore()` — same service call,
    /// same error surface — minus the mid-app "this merges, nothing is deleted" confirmation,
    /// which doesn't apply to a store that's still empty.
    private func runRestore(from url: URL) {
        do {
            restoreSummary = try BackupService.restore(from: url, into: context)
        } catch {
            restoreErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            // The paywall (13) is a forward-or-through screen — no back button, "Continue free"
            // is the honest exit.
            if step > 0 && step < total - 1 && step != 13 {
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(Clinical.body(16, weight: .semibold)).foregroundStyle(Clinical.ink)
                }
                .minimumHitTarget()
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
                    Image(systemName: "xmark").font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.tertiary)
                }
                .minimumHitTarget()
                .accessibilityLabel("Close walkthrough")
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: OnboardingIntro(
            onFinish: { next() },
            onRestore: { showRestoreImporter = true }
        )
        case 1: nameStep
        case 2: sexStep
        case 3: pregnancyStep
        case 4: ageStep
        case 5: concernStep
        case 6: sheddingStep
        case 7: scalpFeelStep
        case 8: stressSleepStep
        case 9: triggersStep
        case 10: familyStep
        case 11: habitsStep
        case 12: healthConnectStep
        case 13: OnboardingPlanStep(profile: profile, onBack: { back() }) { next() }
        default: finale
        }
    }

    // MARK: Navigation

    private func next() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        nameFocused = false
        withAnimation(reduceMotion || MotionQA.isStatic ? nil : .easeInOut(duration: 0.35)) { step = advanced(from: step, by: 1) }
    }
    private func back() {
        nameFocused = false
        withAnimation(reduceMotion || MotionQA.isStatic ? nil : .easeInOut(duration: 0.3)) { step = advanced(from: step, by: -1) }
    }

    /// One screen forward or backward, hopping over the female-only pregnancy step for anyone who
    /// isn't female — in both directions, so it's never reachable for them.
    private func advanced(from s: Int, by delta: Int) -> Int {
        var n = max(0, min(total - 1, s + delta))
        if n == pregnancyStepIndex && !asksPregnancy {
            n = max(0, min(total - 1, n + delta))
        }
        return n
    }

    private func finish() {
        // Seed today's full status (shedding + scalp + stress/sleep) so day one has data, plus
        // one TriggerEvent per recent trigger the user flagged.
        let seed = OnboardingSeed.dayOneEntry(
                shedIntensity: shedIntensity,
                oiliness: GaugeBand.index(oilI, count: 4),
                flaking: GaugeBand.index(flakeI, count: 4),
                itch: GaugeBand.index(itchI, count: 4),
                stress: GaugeBand.index(stressI, count: 5) + 1,
                sleepQuality: GaugeBand.index(sleepI, count: 5) + 1
            )
        _ = try? DailyEntryRepository(context: context).upsert(
            day: .now, updateExisting: false
        ) { entry in
            // Onboarding has always seeded only an empty day. A resumed flow must not replace
            // any existing entry, including one whose values happen to equal model defaults.
            entry.shed = seed.shed
            entry.oiliness = seed.oiliness
            entry.flaking = seed.flaking
            entry.itch = seed.itch
            entry.stress = seed.stress
            entry.sleepQuality = seed.sleepQuality
            entry.recordedSignals = seed.recordedSignals
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
            if let sub { Text(sub).font(Clinical.caption(15)).foregroundStyle(Clinical.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 12)
    }

    // MARK: Steps

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
                            Text(s.title).font(Clinical.body(17, weight: .medium)).foregroundStyle(on ? Clinical.surface : Clinical.ink)
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

    /// Women only (non-female users skip it via `advanced(from:by:)`). Self-reported context so
    /// the plan can flag medications usually avoided in or around pregnancy — never a diagnosis.
    private var pregnancyStep: some View {
        // Friendlier order than raw `allCases`: the plain answers first, "Prefer not to say" last.
        let options: [PregnancyStatus] = [.no, .pregnant, .tryingToConceive, .breastfeeding, .unspecified]
        return VStack(spacing: 0) {
            head("About you", "Are you pregnant or\nplanning a pregnancy?",
                 "A few hair-loss medications aren't recommended in or around pregnancy. This just lets us flag them — you always decide with your clinician, and it stays private on your device.")
            // Question, options anchor together at the top with a fixed gap; any leftover
            // vertical space accumulates below the options (the trailing Spacer), never as a
            // dead zone between the question and its answers.
            VStack(spacing: 10) {
                ForEach(options) { s in
                    let on = profile.pregnancyStatus == s
                    Button {
                        profile.pregnancyStatus = s
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack {
                            Text(s.title)
                                .font(Clinical.body(16, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            Spacer()
                            if on {
                                Image(systemName: "checkmark").font(Clinical.body(13, weight: .bold)).foregroundStyle(Clinical.surface)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 15)
                        .background(on ? Clinical.accent : Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }.padding(.horizontal, 20).padding(.top, 28)
            Spacer()
            primary("Continue") { next() }
        }
    }

    private var ageStep: some View {
        let bands = ["Under 25", "26–35", "36–45", "46–55", "56+"]
        return VStack(spacing: 0) {
            head("About you", "How old are you?")
            // Question and options anchor together at the top with a fixed gap; leftover
            // vertical space accumulates below the options, never between question and answers.
            VStack(spacing: 10) {
                ForEach(bands, id: \.self) { b in
                    let on = profile.ageBand == b
                    Button { profile.ageBand = b; UISelectionFeedbackGenerator().selectionChanged() } label: {
                        // Copper selected state — matches sexStep/pregnancyStep/familyStep so the
                        // whole linear flow speaks one "selected" language instead of switching to
                        // a near-black ink pill just for this step.
                        Text(b).font(Clinical.body(16, weight: on ? .semibold : .regular)).foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(on ? Clinical.accent : Clinical.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20).padding(.top, 28)
            Spacer()
            primary("Continue", enabled: !profile.ageBand.isEmpty) { next() }
        }
    }

    private var concernStep: some View {
        VStack(spacing: 0) {
            head("What are you noticing?", "Pick the closest match", "Plain words — the clinical name is underneath. You can change this anytime.")
            // The animated `ConditionDemo` box used to sit here, previewing the selected pattern.
            // Now that every card carries its own vignette, it was showing the same idea twice and
            // costing ~250pt of the screen the grid needs — so the grid absorbed its job.
            // `ConditionDemo` itself is unchanged and still used elsewhere.
            ScrollView(showsIndicators: false) {
                ConditionPicker(selection: $profile.condition)
                    .padding(.horizontal, 20).padding(.top, 12)
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
                    Text(cap.1).font(Clinical.caption(14)).foregroundStyle(Clinical.secondary)
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
                                Image(systemName: t.symbol).font(Clinical.caption(16)).foregroundStyle(on ? Clinical.accent : Clinical.secondary).frame(width: 22)
                                Text(t.title).font(Clinical.body(15, weight: .medium)).foregroundStyle(Clinical.ink)
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
                            Text("None of these").font(Clinical.body(15, weight: .medium)).foregroundStyle(Clinical.ink)
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
                .font(Clinical.caption(12))
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
                        Text(f.title).font(Clinical.body(15, weight: on ? .semibold : .regular)).foregroundStyle(on ? Clinical.surface : Clinical.ink)
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
        Toggle(isOn: b) { Text(title).font(Clinical.caption(14)).foregroundStyle(Clinical.ink) }
            .tint(Clinical.accent)
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    private var healthConnectStep: some View {
        VStack(spacing: 0) {
            head("Automatic signals", "Connect Apple Health?", "Sleep, body weight, and recovery fill in automatically — no typing. You control exactly what's shared, and you can change it anytime in Settings.")

            HealthPairingView(state: healthPairingState)
                .padding(.top, 26)

            // Question and benefit list anchor together at the top with a fixed gap; leftover
            // vertical space accumulates below the list, never between question and content.
            VStack(spacing: 10) {
                healthBenefitRow(symbol: "bed.double.fill", text: "Sleep hours, every night")
                healthBenefitRow(symbol: "figure", text: "Body weight and BMI")
                healthBenefitRow(symbol: "heart.fill", text: "Recovery (HRV) as a stress signal")
            }.padding(.horizontal, 20).padding(.top, 28)
            Spacer()
            healthConnectCTA
        }
    }

    /// Maps the real HealthKit state onto the pairing animation, so the picture is a status
    /// readout rather than decoration. `requestingAuthorization` covers the window while the
    /// system permission sheet is up.
    private var healthPairingState: HealthPairingView.State {
        if healthKit.authorization.isQueryable { return .joined }
        return requestingHealth ? .connecting : .idle
    }

    @ViewBuilder private var healthConnectCTA: some View {
        switch healthKit.authorization {
        case .requestedQueryable:
            Text("Health request completed — available samples can now be queried")
                .font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.sage)
                .padding(.bottom, 8)
            primary("Continue") { next() }
                .accessibilityIdentifier("onboardHealthConnect")
        case .unavailable:
            Text("Health isn't available on this device")
                .font(Clinical.caption(13)).foregroundStyle(Clinical.tertiary)
                .padding(.bottom, 8)
            primary("Continue") { next() }
                .accessibilityIdentifier("onboardHealthConnect")
        default:
            primary("Connect Apple Health") {
                Task {
                    requestingHealth = true
                    await healthKit.requestAuthorization()
                    if healthKit.authorization.isQueryable { await healthKit.refreshSnapshot(context: context) }
                    requestingHealth = false
                    // Let the connector settle into its joined state before the step advances,
                    // so the animation resolves rather than being cut off mid-transition.
                    try? await Task.sleep(for: .milliseconds(650))
                    next()
                }
            }
            .accessibilityIdentifier("onboardHealthConnect")
            Button("Not now") { next() }
                .font(Clinical.caption(13)).foregroundStyle(Clinical.tertiary)
                .padding(.bottom, 24)
        }
    }

    private func healthBenefitRow(symbol: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(Clinical.caption(16)).foregroundStyle(Clinical.accent).frame(width: 28)
            Text(text).font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
            Spacer()
        }
        .padding(14)
        .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    /// Step 14: the starting plan, previewed. `finish()` seeds day one and hands over; the
    /// Plan tab then shows the same items as a checklist.
    private var finale: some View {
        StarterPlanFinale(profile: profile) { finish() }
    }
}
