import SwiftData
import SwiftUI

/// One-time baseline capture — the highest-value fields (family history, condition) up front.
/// Also reused as the editable profile from the Today header.
struct BaselineFlow: View {
    @Bindable var profile: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLockService.self) private var appLock
    @State private var replayOnboarding = false
    @State private var aiConsentGranted = AIConsent.isGranted()

    private let ageBands = ["Under 25", "26–35", "36–45", "46–55", "56+"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    intro

                    replayRow

                    field("Your name") {
                        TextField("Name", text: $profile.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(Clinical.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                            .accessibilityIdentifier("baselineName")
                    }

                    field("Biological sex") {
                        ClinicalSegmented(options: BiologicalSex.allCases, label: { $0.title }, selection: $profile.sex)
                        Text("Sets the staging scale: \(profile.sex.stagingScaleName).")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Age") {
                        chips(ageBands, selected: profile.ageBand) { profile.ageBand = $0 }
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
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Hair-care practices") {
                        VStack(spacing: 10) {
                            practiceToggle("Tight styles (braids, ponytails, extensions)", isOn: $profile.wearsTightStyles)
                            practiceToggle("Regular heat styling", isOn: $profile.usesHeat)
                            practiceToggle("Chemical treatments (relaxers, dyes, perms)", isOn: $profile.usesChemicalTreatments)
                        }
                        Text("Sustained tension, heat and chemicals cause traction alopecia — preventable and reversible early.")
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }

                    field("Baseline stage (optional)") {
                        TextField("e.g. \(profile.sex.stagingScaleName) III", text: $profile.baselineStage)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
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

                    aboutFooter
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .clinicalScreen()
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
                    .font(.system(size: 14))
                    .foregroundStyle(Clinical.secondary)
            }
        }
    }

    private var replayRow: some View {
        Button { replayOnboarding = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(Clinical.accent)
                    .frame(width: 40, height: 40)
                    .background(Clinical.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay the walkthrough").font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text("Revisit the animated intro anytime").font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Clinical.tertiary)
            }
            .padding(12)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Clinical.accent : Clinical.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                    Text(c.summary).font(.system(size: 12)).foregroundStyle(Clinical.secondary)
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

    /// Privacy controls: App Lock (Face ID / passcode) and the off-device AI-analysis consent.
    private var privacySection: some View {
        @Bindable var appLock = appLock
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Privacy")

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $appLock.isEnabled) {
                    Text("Require Face ID to open")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(appLock.canUseLock ? Clinical.ink : Clinical.tertiary)
                }
                .tint(Clinical.accent)
                .disabled(!appLock.canUseLock)
                .accessibilityIdentifier("appLockToggle")
                Text(appLock.canUseLock
                     ? "Locks Hair Compass when you leave it. Uses your device's Face ID or passcode."
                     : "Unavailable — this device has no Face ID, Touch ID or passcode set up.")
                    .font(.system(size: 12)).foregroundStyle(Clinical.secondary)

                Divider().overlay(Clinical.hairline)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud photo analysis")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(Clinical.ink)
                        Text(aiConsentStatusLine)
                            .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
                    }
                    Spacer()
                    if aiConsentGranted {
                        Button("Revoke") {
                            AIConsent.revoke()
                            aiConsentGranted = false
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Clinical.critical)
                        .accessibilityIdentifier("aiConsentRevoke")
                    }
                }
            }
            .padding(14)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
        }
        .onAppear { aiConsentGranted = AIConsent.isGranted() }
    }

    private var aiConsentStatusLine: String {
        guard aiConsentGranted else {
            return "Off — you'll be asked before any photo leaves this device."
        }
        if let date = AIConsent.grantedDate() {
            return "Allowed \(date.formatted(date: .abbreviated, time: .omitted)) — photos may be sent when you run a deep analysis."
        }
        return "Allowed — photos may be sent when you run a deep analysis."
    }

    private var aboutFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Clinical.hairline)
            Text(AppInfo.medicalDisclaimer)
                .font(.system(size: 11)).foregroundStyle(Clinical.tertiary)
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
    }

    private func practiceToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 14)).foregroundStyle(Clinical.ink)
        }
        .tint(Clinical.accent)
    }

    private func complete() {
        profile.hasOnboarded = true
        dismiss()
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
                            .font(.system(size: 14, weight: on ? .semibold : .regular))
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
