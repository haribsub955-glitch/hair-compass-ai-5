import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct ProfileTab: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    let profile: HairProfile?
    let entries: [CheckInEntry]
    let tasks: [RoutineTask]
    let triggerEvents: [HairTriggerEvent]
    let medications: [MedicationLog]
    let procedureEvents: [ProcedureEvent]
    let labResults: [LabResultEntry]
    let photoRecords: [PhotoRecord]

    @State private var isPresentingPremiumPaywall = false

    private var streak: Int {
        HairInsightCalculator.currentStreak(for: entries)
    }

    private var completionRate: Int {
        let scheduled = tasks.count
        guard scheduled > 0 else { return 0 }
        let completed = tasks.filter(\.isCompleted).count
        return Int((Double(completed) / Double(scheduled) * 100).rounded())
    }

    private var trackingDays: Int {
        guard let first = profile?.createdAt else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0)
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Avatar and name header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [PremiumTheme.sand, PremiumTheme.gold, PremiumTheme.mist],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text(String((profile?.name ?? "A").prefix(1)).uppercased())
                                .font(.system(size: 34, weight: .bold, design: .serif))
                                .foregroundStyle(PremiumTheme.ink)
                        }
                        .frame(width: 82, height: 82)
                        .shadow(color: PremiumTheme.gold.opacity(0.3), radius: 12, y: 4)

                        Text(profile?.name ?? "User")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(PremiumTheme.ink)

                        HStack(spacing: 6) {
                            Text("TRACKING")
                            Text("·")
                            Text("\(trackingDays) DAYS")
                            Text("·")
                            Text(profile?.texture.uppercased() ?? "")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(PremiumTheme.mutedInk)
                    }
                    .padding(.top, 16)

                    // Streak grid 3x1
                    HStack(spacing: 12) {
                        profileStreakTile(value: "\(streak)d", label: "Ritual streak", tint: PremiumTheme.forest)
                        profileStreakTile(value: "\(completionRate)%", label: "This month", tint: PremiumTheme.teal)
                        profileStreakTile(value: "\(photoRecords.count)", label: "Photos", tint: PremiumTheme.gold)
                    }
                    .padding(.horizontal, 20)

                    // Profile list glass card
                    VStack(alignment: .leading, spacing: 0) {
                        profileInfoRow(label: "Hair type", value: profile?.texture ?? "Not set")
                        Divider().padding(.leading, 16)
                        profileInfoRow(label: "Tracking focus", value: profile?.hairLossFocus ?? "Not set")
                        Divider().padding(.leading, 16)
                        profileInfoRow(label: "North Star", value: profile?.primaryGoal ?? "Not set")
                        Divider().padding(.leading, 16)
                        profileInfoRow(label: "Treatment", value: medications.first(where: \.isActive)?.name ?? "None")
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.82))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(PremiumTheme.forest.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    // Premium card
                    if !purchaseManager.hasPremiumAccess {
                        Button {
                            isPresentingPremiumPaywall = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(PremiumTheme.gold)
                                    Text("Hair Compass Pro")
                                        .font(.system(size: 17, weight: .bold, design: .serif))
                                        .foregroundStyle(PremiumTheme.ink)
                                    Spacer()
                                }
                                Text("Unlock clinician exports and AI pattern reads")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(PremiumTheme.secondaryInk)
                                Text("7-day trial · $3.99/mo")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundStyle(PremiumTheme.gold)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [PremiumTheme.goldSoft.opacity(0.5), PremiumTheme.gold.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(PremiumTheme.gold.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

                    // Full profile editor below
                    if let profile {
                        ProfileEditor(
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
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isPresentingPremiumPaywall) {
            PremiumPaywallView()
        }
    }

    private func profileStreakTile(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(PremiumTheme.mutedInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PremiumTheme.forest.opacity(0.08), lineWidth: 1)
        )
    }

    private func profileInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PremiumTheme.mutedInk)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PremiumTheme.ink)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PremiumTheme.mutedInk.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

enum RoutineAgendaBucket: CaseIterable, Hashable {
    case morning
    case midday
    case evening
    case anytime

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .midday: return "Midday"
        case .evening: return "Evening"
        case .anytime: return "Anytime"
        }
    }

    var sortOrder: Int {
        switch self {
        case .morning: return 0
        case .midday: return 1
        case .evening: return 2
        case .anytime: return 3
        }
    }
}

enum RoutineAgendaSource {
    case task(RoutineTask)
    case medication(MedicationLog)
}

enum RoutineWorkspace: String, CaseIterable, Identifiable {
    case plan
    case tracking
    case reference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan:
            return "Plan"
        case .tracking:
            return "Tracking"
        case .reference:
            return "Reference"
        }
    }
}

struct RoutineAgendaEntry: Identifiable {
    let id: String
    let title: String
    let detail: String
    let category: String
    let timeLabel: String
    let bucket: RoutineAgendaBucket
    let source: RoutineAgendaSource
    let isCompleted: Bool
}

struct RoutineAgendaRow: View {
    let item: RoutineAgendaEntry
    let canMarkComplete: Bool
    let onToggleTask: (RoutineTask) -> Void
    let onLogMedication: (MedicationLog, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            switch item.source {
            case .task(let task):
                Button {
                    guard canMarkComplete else { return }
                    onToggleTask(task)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(canMarkComplete ? (item.isCompleted ? Color.green : Color.gray.opacity(0.8)) : Color.gray.opacity(0.45))
                }
                .buttonStyle(.plain)
            case .medication(let medication):
                Button {
                    guard canMarkComplete else { return }
                    onLogMedication(medication, item.timeLabel)
                } label: {
                    Image(systemName: "pills.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canMarkComplete ? Color(red: 0.20, green: 0.47, blue: 0.79) : Color.gray.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Text(item.timeLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.47, blue: 0.79))
                }

                Text(item.category)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.49, blue: 0.45))

                Text(item.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if !canMarkComplete {
                    Text("Marking is available when this day becomes today.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.62, green: 0.41, blue: 0.15))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct GuidanceTab: View {
    let entries: [CheckInEntry]

    private var alerts: [GuidanceAlert] {
        HairClinicalGuidance.alerts(for: entries)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                guidanceHero
                scopeCard
                if !alerts.isEmpty {
                    flagsCard
                }
                evidenceCard
                measurementCard
            }
            .padding(20)
        }
        .background(
            ZStack {
                appBackground
                Circle()
                    .fill(Color(red: 0.27, green: 0.48, blue: 0.42).opacity(0.14))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: -80, y: -200)
                Circle()
                    .fill(PremiumTheme.gold.opacity(0.10))
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(x: 100, y: 250)
            }
            .ignoresSafeArea()
        )
        .navigationTitle("Guidance")
    }

    private var guidanceHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(red: 0.27, green: 0.48, blue: 0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color(red: 0.27, green: 0.48, blue: 0.42).opacity(0.35), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Evidence-Based Use")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.14))
                    Text("Clinical guidance & documentation")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.42, green: 0.49, blue: 0.46))
                }
            }

            Text("Hair Compass should help you document patterns, not diagnose disease. Use it to support better conversations with a clinician.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.41, blue: 0.37))
        }
        .cardStyle()
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What This App Can Honestly Do")
                .font(.system(size: 22, weight: .heavy, design: .rounded))

            guidanceLine("Track symptoms like itch, flaking, tenderness, and patchy loss over time.")
            guidanceLine("Keep routine consistency data for wash cadence, protective styling, and scalp care.")
            guidanceLine("Highlight patterns worth discussing with a dermatologist.")
            guidanceLine("Avoid claiming growth predictions or diagnoses that the app cannot validate.")
        }
        .cardStyle()
    }

    private var flagsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current Flags")
                .font(.system(size: 22, weight: .heavy, design: .rounded))

            ForEach(alerts) { alert in
                VStack(alignment: .leading, spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(alert.message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .cardStyle()
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Evidence Priorities")
                .font(.system(size: 22, weight: .heavy, design: .rounded))

            guidanceLine("Patchy hair loss, scalp pain, or burning need medical evaluation rather than cosmetic experimentation.")
            guidanceLine("Persistent dandruff-like symptoms may reflect seborrheic dermatitis, psoriasis, or another scalp disorder.")
            guidanceLine("Painful tight hairstyles can contribute to traction alopecia and should be reduced early.")
            guidanceLine("Hair apps should frame advice as supportive self-care, not treatment claims.")
        }
        .cardStyle()
    }

    private var measurementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Better Scientific Tracking")
                .font(.system(size: 22, weight: .heavy, design: .rounded))

            guidanceLine("Take photos at the same angle, distance, lighting, and hairstyle.")
            guidanceLine("Log major changes like illness, stress, tight styles, and new products.")
            guidanceLine("Track symptoms consistently before judging whether a routine helped.")
            guidanceLine("Bring repeated red flags and your timeline to a clinician.")
        }
        .cardStyle()
    }

    private func guidanceLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.27, green: 0.48, blue: 0.42))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.41, blue: 0.37))
        }
    }
}

