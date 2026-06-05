import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct CheckInsTab: View {
    @Environment(\.modelContext) private var modelContext
    let entries: [CheckInEntry]
    let photoRecords: [PhotoRecord]
    let routineCompletions: [RoutineCompletionEntry]
    let medications: [MedicationLog]
    let medicationEntries: [MedicationDoseEntry]
    let procedureEvents: [ProcedureEvent]
    let lifestyleEntries: [LifestyleEntry]
    let healthMetricsByDay: [Date: HealthDailyMetric]
    let triggerEvents: [HairTriggerEvent]

    @State private var isPresentingAddCheckIn = false
    @State private var selectedDatasetRange: CheckInDatasetRange = .threeMonths
    @State private var historyDisplayLimit = 20

    private struct DatasetMetricCardData: Identifiable {
        let id = UUID()
        let title: String
        let currentAverage: Int
        let delta: Int
        let hasPreviousBaseline: Bool
        let tint: Color
        let improvesWhenLower: Bool

        private var adjustedDelta: Int {
            improvesWhenLower ? -delta : delta
        }

        var trendSymbol: String {
            if !hasPreviousBaseline || adjustedDelta == 0 { return "minus" }
            return adjustedDelta > 0 ? "arrow.up.right" : "arrow.down.right"
        }

        var trendTint: Color {
            if !hasPreviousBaseline || adjustedDelta == 0 {
                return Color(red: 0.53, green: 0.57, blue: 0.54)
            }
            return adjustedDelta > 0
            ? Color(red: 0.26, green: 0.54, blue: 0.42)
            : Color(red: 0.78, green: 0.42, blue: 0.35)
        }

        var deltaLabel: String {
            guard hasPreviousBaseline else { return "No baseline yet" }
            if delta == 0 { return "No change" }
            let sign = delta > 0 ? "+" : ""
            return "\(sign)\(delta) pts"
        }
    }

    private struct CheckInDatasetPoint: Identifiable {
        let id: UUID
        let date: Date
        let scalp: Double
        let hydration: Double
        let shedding: Double
        let stress: Double
    }

    private var impactPoints: [RoutineImpactPoint] {
        RoutineImpactCalculator.buildPoints(
            RoutineImpactInput(
                entries: entries,
                routineCompletions: routineCompletions,
                medications: medications,
                medicationEntries: medicationEntries,
                procedureEvents: procedureEvents,
                healthMetricsByDay: healthMetricsByDay,
                lifestyleEntries: lifestyleEntries,
                triggerEvents: triggerEvents
            )
        )
    }

    private var datasetEntries: [CheckInEntry] {
        let cutoff = selectedDatasetRange.cutoffDate
        return entries
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    private var previousDatasetEntries: [CheckInEntry] {
        let end = selectedDatasetRange.cutoffDate
        let start = Calendar.current.date(byAdding: .day, value: -selectedDatasetRange.daySpan, to: end) ?? end
        return entries.filter { $0.date >= start && $0.date < end }
    }

    private var datasetChartPoints: [CheckInDatasetPoint] {
        let raw = datasetEntries
        guard !raw.isEmpty else { return [] }

        // Raw daily self-reported scores are noisy; plotting four of them on top of
        // each other reads as spaghetti. Smooth each series with a trailing rolling
        // average so the chart shows clean, comparable trendlines instead.
        let window = max(2, min(9, raw.count / 8))
        let scalp = Self.rollingAverage(raw.map { Double($0.scalpScore) }, window: window)
        let hydration = Self.rollingAverage(raw.map { Double($0.hydrationScore) }, window: window)
        let shedding = Self.rollingAverage(raw.map { Double($0.sheddingLevel) }, window: window)
        let stress = Self.rollingAverage(raw.map { Double($0.stressLevel) }, window: window)

        return raw.indices.map { index in
            CheckInDatasetPoint(
                id: raw[index].id,
                date: raw[index].date,
                scalp: scalp[index],
                hydration: hydration[index],
                shedding: shedding[index],
                stress: stress[index]
            )
        }
    }

    private static func rollingAverage(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > 1 else { return values }
        return values.indices.map { index in
            let lowerBound = max(0, index - window + 1)
            let slice = values[lowerBound...index]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    private var datasetMetricCards: [DatasetMetricCardData] {
        [
            DatasetMetricCardData(
                title: "Scalp",
                currentAverage: average(\.scalpScore, in: datasetEntries),
                delta: average(\.scalpScore, in: datasetEntries) - average(\.scalpScore, in: previousDatasetEntries),
                hasPreviousBaseline: !previousDatasetEntries.isEmpty,
                tint: Color(red: 0.27, green: 0.54, blue: 0.42),
                improvesWhenLower: false
            ),
            DatasetMetricCardData(
                title: "Hydration",
                currentAverage: average(\.hydrationScore, in: datasetEntries),
                delta: average(\.hydrationScore, in: datasetEntries) - average(\.hydrationScore, in: previousDatasetEntries),
                hasPreviousBaseline: !previousDatasetEntries.isEmpty,
                tint: Color(red: 0.23, green: 0.49, blue: 0.72),
                improvesWhenLower: false
            ),
            DatasetMetricCardData(
                title: "Shedding",
                currentAverage: average(\.sheddingLevel, in: datasetEntries),
                delta: average(\.sheddingLevel, in: datasetEntries) - average(\.sheddingLevel, in: previousDatasetEntries),
                hasPreviousBaseline: !previousDatasetEntries.isEmpty,
                tint: Color(red: 0.80, green: 0.52, blue: 0.23),
                improvesWhenLower: true
            ),
            DatasetMetricCardData(
                title: "Stress",
                currentAverage: average(\.stressLevel, in: datasetEntries),
                delta: average(\.stressLevel, in: datasetEntries) - average(\.stressLevel, in: previousDatasetEntries),
                hasPreviousBaseline: !previousDatasetEntries.isEmpty,
                tint: Color(red: 0.76, green: 0.36, blue: 0.53),
                improvesWhenLower: true
            )
        ]
    }

    var body: some View {
        ZStack {
            appBackground
            // Chart screen atmosphere orbs
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [PremiumTheme.teal.opacity(0.12), .clear],
                            center: .center, startRadius: 10, endRadius: 180
                        )
                    )
                    .frame(width: 340, height: 340)
                    .blur(radius: 40)
                    .offset(x: 80, y: -220)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [PremiumTheme.gold.opacity(0.08), .clear],
                            center: .center, startRadius: 10, endRadius: 140
                        )
                    )
                    .frame(width: 260, height: 260)
                    .blur(radius: 30)
                    .offset(x: -90, y: 280)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SIGNALS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(PremiumTheme.mutedInk)

                        Text("Your signals")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(PremiumTheme.ink)

                        Text("Trendlines compared against the previous window.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PremiumTheme.mutedInk)
                    }
                    .cardStyle()

                    // Range picker pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CheckInDatasetRange.allCases) { range in
                                let isSelected = selectedDatasetRange == range
                                Button {
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                                        selectedDatasetRange = range
                                    }
                                    HapticHelper.selection()
                                } label: {
                                    Text(range.title)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .monospaced))
                                        .foregroundStyle(isSelected ? .white : PremiumTheme.forest)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected
                                                ? AnyShapeStyle(PremiumTheme.forestTealGradient)
                                                : AnyShapeStyle(PremiumTheme.forest.opacity(0.10)),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Metric summary cards
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(datasetMetricCards) { card in
                                datasetMetricCard(card)
                            }
                        }
                    }

                    // Chart card
                    if datasetChartPoints.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 36))
                                .foregroundStyle(PremiumTheme.teal.opacity(0.4))
                            Text("No Data In This Window")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(PremiumTheme.ink)
                            Text("Add check-ins to see charted trends for scalp, hydration, shedding, and stress.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PremiumTheme.mutedInk)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .cardStyle()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            // Legend row
                            HStack(spacing: 10) {
                                legendItem(title: "Scalp", tint: PremiumTheme.forest)
                                legendItem(title: "Hydration", tint: PremiumTheme.teal)
                                legendItem(title: "Shedding", tint: PremiumTheme.gold)
                                legendItem(title: "Stress", tint: Color(red: 0.76, green: 0.36, blue: 0.53))
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))

                            Chart {
                                ForEach(datasetChartPoints) { point in
                                    AreaMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("Scalp", point.scalp)
                                    )
                                    .interpolationMethod(.monotone)
                                    .foregroundStyle(Color(red: 0.27, green: 0.54, blue: 0.42).opacity(0.08))

                                    LineMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("Scalp", point.scalp)
                                    )
                                    .interpolationMethod(.monotone)
                                    .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(Color(red: 0.27, green: 0.54, blue: 0.42))
                                }

                                ForEach(datasetChartPoints) { point in
                                    LineMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("Hydration", point.hydration)
                                    )
                                    .interpolationMethod(.monotone)
                                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(Color(red: 0.23, green: 0.49, blue: 0.72))
                                }

                                ForEach(datasetChartPoints) { point in
                                    LineMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("Shedding", point.shedding)
                                    )
                                    .interpolationMethod(.monotone)
                                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(Color(red: 0.80, green: 0.52, blue: 0.23))
                                }

                                ForEach(datasetChartPoints) { point in
                                    LineMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("Stress", point.stress)
                                    )
                                    .interpolationMethod(.monotone)
                                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(Color(red: 0.76, green: 0.36, blue: 0.53))
                                }
                            }
                            .frame(height: 260)
                            .chartYScale(domain: 0...100)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: selectedDatasetRange.axisDayStride)) { value in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 5]))
                                        .foregroundStyle(PremiumTheme.forest.opacity(0.08))
                                    AxisTick()
                                        .foregroundStyle(PremiumTheme.forest.opacity(0.14))
                                    AxisValueLabel {
                                        if let date = value.as(Date.self) {
                                            Text(date.formatted(selectedDatasetRange.axisDateFormat))
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundStyle(PremiumTheme.mutedInk)
                                        }
                                    }
                                }
                            }
                            .chartYAxis {
                                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 6]))
                                        .foregroundStyle(PremiumTheme.forest.opacity(0.08))
                                    AxisTick()
                                        .foregroundStyle(PremiumTheme.forest.opacity(0.14))
                                    AxisValueLabel {
                                        if let score = value.as(Int.self) {
                                            Text("\(score)")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundStyle(PremiumTheme.mutedInk)
                                        }
                                    }
                                }
                            }
                            .chartPlotStyle { plotArea in
                                plotArea
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.50))
                                    )
                            }
                        }
                        .cardStyle()
                    }

                    // Impact patterns card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PATTERNS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(PremiumTheme.mutedInk)

                        Text("What seems to help")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(PremiumTheme.ink)

                        RoutineImpactChart(points: impactPoints)
                    }
                    .cardStyle()

                    // Recent entries
                    if entries.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 36))
                                .foregroundStyle(PremiumTheme.teal.opacity(0.4))
                            Text("No Check-Ins Yet")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(PremiumTheme.ink)
                            Text("Log scalp, hydration, shedding, and stress to start building your trendline.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PremiumTheme.mutedInk)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .cardStyle()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("HISTORY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.8)
                                .foregroundStyle(PremiumTheme.mutedInk)

                            ForEach(Array(entries.prefix(historyDisplayLimit))) { entry in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(entry.date, format: .dateTime.month().day().year())
                                            .font(.system(size: 16, weight: .bold, design: .serif))
                                            .foregroundStyle(PremiumTheme.ink)

                                        Spacer()

                                        Text(entry.date, format: .dateTime.hour().minute())
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(PremiumTheme.mutedInk)
                                    }

                                    if !entry.note.isEmpty {
                                        Text(entry.note)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(PremiumTheme.mutedInk)
                                    }

                                    if let linkedPhoto = linkedPhoto(for: entry) {
                                        PhotoThumbnailView(imagePath: linkedPhoto.imagePath)
                                    }

                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 8) {
                                            scoreTag(label: "Scalp", value: entry.scalpScore, tint: PremiumTheme.forest)
                                            scoreTag(label: "Hydration", value: entry.hydrationScore, tint: PremiumTheme.teal)
                                            scoreTag(label: "Shedding", value: entry.sheddingLevel, tint: PremiumTheme.gold)
                                            scoreTag(label: "Stress", value: entry.stressLevel, tint: Color(red: 0.76, green: 0.36, blue: 0.53))
                                        }

                                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                            scoreTag(label: "Scalp", value: entry.scalpScore, tint: PremiumTheme.forest)
                                            scoreTag(label: "Hydration", value: entry.hydrationScore, tint: PremiumTheme.teal)
                                            scoreTag(label: "Shedding", value: entry.sheddingLevel, tint: PremiumTheme.gold)
                                            scoreTag(label: "Stress", value: entry.stressLevel, tint: Color(red: 0.76, green: 0.36, blue: 0.53))
                                        }
                                    }

                                    let symptoms = symptomSummary(for: entry)
                                    if !symptoms.isEmpty {
                                        Text(symptoms.joined(separator: "  ·  "))
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(PremiumTheme.gold)
                                    }
                                }
                                .padding(14)
                                .background(
                                    Color.white.opacity(0.72),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(PremiumTheme.forest.opacity(0.06), lineWidth: 1)
                                )
                            }

                            if entries.count > historyDisplayLimit {
                                Button {
                                    historyDisplayLimit += 20
                                } label: {
                                    Text("Show more (\(entries.count - historyDisplayLimit) remaining)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(PremiumTheme.forest)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(PremiumTheme.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .cardStyle()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .safeAreaPadding(.top, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddCheckIn = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(PremiumTheme.forest)
                }
            }
        }
        .sheet(isPresented: $isPresentingAddCheckIn) {
            AddCheckInSheet()
        }
    }

    private func deleteEntries(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
    }

    private func average(_ keyPath: KeyPath<CheckInEntry, Int>, in source: [CheckInEntry]) -> Int {
        guard !source.isEmpty else { return 0 }
        let total = source.reduce(0) { partial, entry in
            partial + entry[keyPath: keyPath]
        }
        return Int((Double(total) / Double(source.count)).rounded())
    }

    private func datasetMetricCard(_ card: DatasetMetricCardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(PremiumTheme.mutedInk)

            Text("\(card.currentAverage)%")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(card.tint)

            HStack(spacing: 5) {
                Image(systemName: card.trendSymbol)
                    .font(.system(size: 10, weight: .bold))
                Text(card.deltaLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(card.trendTint)
        }
        .frame(width: 130, alignment: .leading)
        .padding(14)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PremiumTheme.forest.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: PremiumTheme.forest.opacity(0.04), radius: 8, y: 4)
    }

    private func legendItem(title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(PremiumTheme.mutedInk)
        }
    }

    private func scoreTag(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(PremiumTheme.mutedInk)
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: Capsule())
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

    private func linkedPhoto(for entry: CheckInEntry) -> PhotoRecord? {
        photoRecords.first { $0.checkIn?.id == entry.id }
    }
}

enum CheckInDatasetRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        }
    }

    var daySpan: Int {
        switch self {
        case .oneMonth: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        }
    }

    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -daySpan, to: .now) ?? .now
    }

    var axisDayStride: Int {
        switch self {
        case .oneMonth: return 7
        case .threeMonths: return 14
        case .sixMonths: return 30
        }
    }

    var axisDateFormat: Date.FormatStyle {
        switch self {
        case .oneMonth:
            return .dateTime.month(.abbreviated).day()
        case .threeMonths, .sixMonths:
            return .dateTime.month(.abbreviated)
        }
    }
}

