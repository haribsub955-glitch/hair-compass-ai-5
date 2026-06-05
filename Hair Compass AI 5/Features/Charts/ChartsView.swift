import Charts
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct RoutineImpactChart: View {
    let points: [RoutineImpactPoint]
    let presentationStyle: ChartPresentationStyle
    @State private var selectedPrimaryMetric: ChartMetric = .shedding
    @State private var selectedSecondaryMetric: ChartMetric = .stress
    @State private var selectedRange: ChartRange = .threeMonths
    @State private var selectedLagWeeks = 0
    @State private var isPresentingExpanded = false
    @State private var selectedPointDate: Date?

    private struct ChartRenderPoint: Identifiable {
        let date: Date
        let chartValue: Double
        let rawValue: Double
        let hasRealData: Bool

        var id: Date { date }
    }

    init(
        points: [RoutineImpactPoint],
        initialPrimaryMetric: ChartMetric = .shedding,
        initialSecondaryMetric: ChartMetric = .stress,
        initialRange: ChartRange = .threeMonths,
        presentationStyle: ChartPresentationStyle = .embedded
    ) {
        self.points = points
        self.presentationStyle = presentationStyle
        _selectedPrimaryMetric = State(initialValue: initialPrimaryMetric)
        _selectedSecondaryMetric = State(initialValue: initialSecondaryMetric)
        _selectedRange = State(initialValue: initialRange)
    }

    private var presetComparisons: [ChartPreset] {
        [
            ChartPreset(title: "Shedding / Stress", primary: .shedding, secondary: .stress),
            ChartPreset(title: "Shedding / Sleep", primary: .shedding, secondary: .sleepHours),
            ChartPreset(title: "Shedding / Exercise", primary: .shedding, secondary: .exerciseMinutes),
            ChartPreset(title: "Shedding / Hydration", primary: .shedding, secondary: .hydration),
            ChartPreset(title: "Scalp / Water", primary: .scalp, secondary: .waterLiters),
            ChartPreset(title: "Shedding / Protein", primary: .shedding, secondary: .proteinGrams),
            ChartPreset(title: "Shedding / Smoking", primary: .shedding, secondary: .smokingCount),
            ChartPreset(title: "Shedding / Minoxidil", primary: .shedding, secondary: .minoxidilEntries),
            ChartPreset(title: "Shedding / Procedures", primary: .shedding, secondary: .procedureEvents),
            ChartPreset(title: "Shedding / Trigger Load", primary: .shedding, secondary: .recentTriggerLoad),
            ChartPreset(title: "Shedding / Traction", primary: .shedding, secondary: .tractionEvents),
            ChartPreset(title: "Scalp / Seb Derm", primary: .scalp, secondary: .sebDermEvents),
            ChartPreset(title: "Scalp / Routine", primary: .scalp, secondary: .routineActions),
            ChartPreset(title: "Shedding / Dutasteride Procedure", primary: .shedding, secondary: .dutasterideProcedureEvents)
        ]
    }

    private var filteredPoints: [RoutineImpactPoint] {
        let cutoff = selectedRange.cutoffDate(from: .now)
        return points
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    private var previewPoints: [RoutineImpactPoint] {
        let calendar = Calendar.current
        let count = selectedRange == .oneMonth ? 6 : 8
        // Deterministic noise based on index to avoid perfectly smooth curves
        let jitter: [Double] = [3, -2, 5, -1, 4, -3, 2, -4]
        return (0..<count).map { index in
            let date = calendar.date(byAdding: .day, value: -((count - index) * 6), to: .now) ?? .now
            let j = jitter[index % jitter.count]
            return RoutineImpactPoint(
                date: date,
                sheddingScore: max(10, min(80, Double(52 - (index * 3)) + j)),
                stressScore: max(15, min(75, Double(55 - (index * 2)) + j * 0.7)),
                scalpScore: max(30, min(85, Double(48 + (index * 4)) - j * 0.5)),
                hydrationScore: max(35, min(85, Double(50 + (index * 3)) + j * 0.3)),
                routineActions: min(index + (index.isMultiple(of: 2) ? 1 : 0), 5),
                medicationEntries: min(index, 3),
                minoxidilEntries: min(index, 2),
                expectedMedicationEntries: 3,
                expectedMinoxidilEntries: 2,
                procedureEvents: 0,
                dutasterideProcedureEvents: 0,
                sleepHours: max(5.0, min(9.0, Double(6) + Double(index) * 0.25 + j * 0.15)),
                exerciseMinutes: max(10, min(75, Double(20 + index * 6) + j)),
                proteinGrams: max(30, min(140, Double(55 + (index * 8)) + j * 2)),
                waterLiters: max(0.8, min(3.0, Double(12 + index) / 10 + j * 0.05)),
                smokingCount: Double(max(0, 3 - index / 2)),
                supplementEntries: min(index / 2, 2),
                triggerEvents: 0,
                tractionEvents: 0,
                sebDermEvents: 0,
                recentTriggerLoad: 0,
                recentProcedureLoad: index > 4 ? 0.8 : 0
            )
        }
    }

    private var visiblePoints: [RoutineImpactPoint] {
        filteredPoints.isEmpty ? previewPoints : filteredPoints
    }

    private var isPreviewMode: Bool {
        filteredPoints.isEmpty
    }

    private var analyticsPoints: [ChartAnalyticsPoint] {
        let sourcePoints = isPreviewMode ? previewPoints : points
        let cutoff = selectedRange.cutoffDate(from: .now)
        return ChartAnalyticsEngine
            .buildSeries(from: sourcePoints)
            .filter { $0.date >= cutoff }
    }

    private var needsNormalization: Bool {
        selectedPrimaryMetric.typicalRange != selectedSecondaryMetric.typicalRange
    }

    private var normalizedYDomain: ClosedRange<Double> {
        guard !needsNormalization else { return 0...100 }
        let allValues: [Double] = analyticsPoints.compactMap { selectedPrimaryMetric.availableValue(for: $0) }
            + analyticsPoints.compactMap { comparisonValue(for: $0) }
        let lo = allValues.min() ?? 0
        let hi = allValues.max() ?? 100
        let padding = max((hi - lo) * 0.08, 1)
        return max(0, lo - padding)...(hi + padding)
    }

    private var yAxisMarkValues: [Double] {
        let domain = normalizedYDomain
        if needsNormalization {
            return [0, 25, 50, 75, 100]
        }

        let lower = domain.lowerBound
        let upper = domain.upperBound
        guard upper > lower else { return [lower] }

        let step = (upper - lower) / 4
        return (0...4).map { lower + (Double($0) * step) }
    }

    private func axisLabel(for metric: ChartMetric, chartValue: Double) -> String {
        let rawValue = needsNormalization ? metric.denormalized(chartValue) : chartValue
        return metric.formattedAxisValue(rawValue)
    }

    private var xAxisDomain: ClosedRange<Date> {
        let dates = analyticsPoints.map(\.date).sorted()
        guard let first = dates.first, let last = dates.last else {
            let today = Calendar.current.startOfDay(for: .now)
            return today...today
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        return start...max(start, end)
    }

    private var xAxisMarkDates: [Date] {
        let calendar = Calendar.current
        let domain = xAxisDomain

        if selectedRange == .oneMonth {
            let stride = max(1, selectedRange.axisStrideCount)
            return strideDates(
                from: domain.lowerBound,
                to: domain.upperBound,
                component: .day,
                count: stride,
                calendar: calendar
            )
        }

        return strideDates(
            from: domain.lowerBound,
            to: domain.upperBound,
            component: .month,
            count: max(1, selectedRange.axisStrideCount),
            calendar: calendar
        )
    }

    private func strideDates(
        from start: Date,
        to end: Date,
        component: Calendar.Component,
        count: Int,
        calendar: Calendar
    ) -> [Date] {
        let alignedStart: Date
        switch component {
        case .month:
            let monthComponents = calendar.dateComponents([.year, .month], from: start)
            alignedStart = calendar.date(from: monthComponents) ?? calendar.startOfDay(for: start)
        default:
            alignedStart = calendar.startOfDay(for: start)
        }

        var dates: [Date] = []
        var current = alignedStart
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: component, value: count, to: current) else { break }
            current = next
        }

        if let last = dates.last, !calendar.isDate(last, inSameDayAs: end) {
            dates.append(end)
        } else if dates.isEmpty {
            dates = [start, end]
        }

        return dates
    }

    private var secondaryLegendRole: String {
        if selectedLagWeeks == 0 {
            return selectedSecondaryMetric.prefersBars ? "Compare Bar" : "Compare"
        }
        return selectedSecondaryMetric.prefersBars ? "\(selectedLagWeeks)W Lag Bar" : "\(selectedLagWeeks)W Lag Line"
    }

    private var shouldShowSecondaryArea: Bool {
        !selectedSecondaryMetric.prefersBars && analyticsPoints.count >= 5 && evidenceState != .tooThin
    }

    private var chartTitle: String {
        "\(selectedPrimaryMetric.title) vs \(selectedSecondaryMetric.title)"
    }

    private var pairedObservations: [ChartPairedObservation] {
        analyticsPoints.compactMap { point in
            guard
                let primaryValue = selectedPrimaryMetric.availableValue(for: point),
                let secondaryValue = comparisonValue(for: point)
            else {
                return nil
            }

            return ChartPairedObservation(
                date: point.date,
                primaryValue: primaryValue,
                secondaryValue: secondaryValue
            )
        }
    }

    private var relationshipSummary: ChartRelationshipSummary? {
        ChartRelationshipAnalyzer.summarize(
            observations: pairedObservations,
            lagWeeks: selectedLagWeeks
        )
    }

    private var primaryRenderPoints: [ChartRenderPoint] {
        analyticsPoints.compactMap { point in
            guard let rawValue = selectedPrimaryMetric.availableValue(for: point) else { return nil }
            let chartValue = needsNormalization ? selectedPrimaryMetric.normalized(rawValue) : rawValue
            return ChartRenderPoint(
                date: point.date,
                chartValue: chartValue,
                rawValue: rawValue,
                hasRealData: point.hasRealData
            )
        }
    }

    private var secondaryRenderPoints: [ChartRenderPoint] {
        analyticsPoints.compactMap { point in
            guard let rawValue = comparisonValue(for: point) else { return nil }
            let chartValue = needsNormalization ? selectedSecondaryMetric.normalized(rawValue) : rawValue
            return ChartRenderPoint(
                date: point.date,
                chartValue: chartValue,
                rawValue: rawValue,
                hasRealData: point.hasRealData
            )
        }
    }

    private var lagInsights: [LagInsight] {
        [0, 2, 4, 8, 12].compactMap { weeks in
            let observations = pairedObservations(for: weeks)
            guard let summary = ChartRelationshipAnalyzer.summarize(observations: observations, lagWeeks: weeks) else {
                return nil
            }
            return LagInsight(
                weeks: weeks,
                pairCount: summary.overlapCount,
                correlation: summary.correlation,
                effectSize: summary.effectSize
            )
        }
    }

    private var selectedPoint: ChartAnalyticsPoint? {
        guard let selectedPointDate else { return nil }

        return analyticsPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(selectedPointDate)) < abs(rhs.date.timeIntervalSince(selectedPointDate))
        }
    }

    private var nonZeroPrimaryPoints: Int {
        analyticsPoints.filter {
            guard let value = selectedPrimaryMetric.availableValue(for: $0) else { return false }
            return value > 0
        }.count
    }

    private var nonZeroSecondaryPoints: Int {
        analyticsPoints.filter {
            guard let value = comparisonValue(for: $0) else { return false }
            return value > 0
        }.count
    }

    private var evidenceState: ChartEvidenceState {
        if isPreviewMode {
            return .preview
        }
        if pairedObservations.count < 4 || nonZeroPrimaryPoints < 3 || nonZeroSecondaryPoints < 3 {
            return .tooThin
        }
        if pairedObservations.count < 8 {
            return .earlySignal
        }
        return .usable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pattern Studio")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.42, green: 0.49, blue: 0.45))
                            .textCase(.uppercase)

                        Text(chartTitle)
                            .font(.system(size: presentationStyle == .expanded ? 30 : 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.15, green: 0.21, blue: 0.18))

                    Text(isPreviewMode ? "Preview how your own pattern studio can look once you start logging." : "Track two signals in the same window and look for repeating patterns rather than one-off spikes.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.40, green: 0.46, blue: 0.43))
                    }

                    Spacer()

                    if presentationStyle == .embedded {
                        Button {
                            isPresentingExpanded = true
                        } label: {
                            Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.20, green: 0.34, blue: 0.33))
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(presetComparisons) { preset in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                selectedPrimaryMetric = preset.primary
                                selectedSecondaryMetric = preset.secondary
                            }
                        } label: {
                            Text(preset.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    selectedPrimaryMetric == preset.primary && selectedSecondaryMetric == preset.secondary
                                    ? LinearGradient(
                                        colors: [
                                            Color(red: 0.15, green: 0.24, blue: 0.23),
                                            Color(red: 0.26, green: 0.40, blue: 0.39)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.9),
                                            Color.white.opacity(0.88)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    selectedPrimaryMetric == preset.primary && selectedSecondaryMetric == preset.secondary
                                    ? Color.white
                                    : Color(red: 0.20, green: 0.24, blue: 0.22)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ChartMetricPicker(title: "Primary", selection: $selectedPrimaryMetric)
                    ChartMetricPicker(title: "Compare With", selection: $selectedSecondaryMetric)
                }

                VStack(spacing: 12) {
                    ChartMetricPicker(title: "Primary", selection: $selectedPrimaryMetric)
                    ChartMetricPicker(title: "Compare With", selection: $selectedSecondaryMetric)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectedPrimaryMetric)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectedSecondaryMetric)
            .onChange(of: selectedPrimaryMetric) { _, newValue in
                if newValue == selectedSecondaryMetric {
                    selectedSecondaryMetric = ChartMetric.defaultCompanion(for: newValue)
                }
            }
            .onChange(of: selectedSecondaryMetric) { _, newValue in
                if newValue == selectedPrimaryMetric {
                    selectedPrimaryMetric = ChartMetric.defaultCompanion(for: newValue)
                }
            }

            Picker("Range", selection: $selectedRange) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectedRange)

            HStack(spacing: 8) {
                ForEach([0, 2, 4, 8, 12], id: \.self) { weeks in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                            selectedLagWeeks = weeks
                        }
                    } label: {
                        Text(weeks == 0 ? "Same day" : "\(weeks)W lag")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedLagWeeks == weeks ? .white : Color(red: 0.27, green: 0.31, blue: 0.29))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedLagWeeks == weeks
                                ? selectedSecondaryMetric.color
                                : Color.white.opacity(0.88),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    LegendChip(metric: selectedPrimaryMetric, role: "Primary")
                    LegendChip(metric: selectedSecondaryMetric, role: secondaryLegendRole)
                    Spacer()
                    Text(isPreviewMode ? "Preview" : "\(pairedObservations.count) paired")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.50, blue: 0.47))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.88), in: Capsule())
                }

                ChartEvidenceCard(
                    state: evidenceState,
                    primaryMetric: selectedPrimaryMetric,
                    secondaryMetric: selectedSecondaryMetric,
                    pointCount: pairedObservations.count
                )

                Chart {
                    if selectedSecondaryMetric.prefersBars {
                        ForEach(secondaryRenderPoints) { point in
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(selectedSecondaryMetric.title, point.chartValue)
                            )
                            .foregroundStyle(selectedSecondaryMetric.color.opacity(isPreviewMode ? 0.22 : 0.48))
                            .cornerRadius(8)
                        }
                    } else {
                        if shouldShowSecondaryArea {
                            ForEach(secondaryRenderPoints) { point in
                                AreaMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value(selectedSecondaryMetric.title, point.chartValue)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            selectedSecondaryMetric.color.opacity(isPreviewMode ? 0.10 : 0.16),
                                            selectedSecondaryMetric.color.opacity(isPreviewMode ? 0.01 : 0.02)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        }

                        ForEach(secondaryRenderPoints) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(selectedSecondaryMetric.title, point.chartValue)
                            )
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(selectedSecondaryMetric.color.opacity(isPreviewMode ? 0.50 : 0.96))

                            if point.hasRealData {
                                PointMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value(selectedSecondaryMetric.title, point.chartValue)
                                )
                                .symbolSize(24)
                                .foregroundStyle(selectedSecondaryMetric.color.opacity(isPreviewMode ? 0.50 : 0.94))
                            }
                        }
                    }

                    if primaryRenderPoints.count >= 2 {
                        ForEach(primaryRenderPoints) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(selectedPrimaryMetric.title, point.chartValue)
                            )
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(selectedPrimaryMetric.color.opacity(isPreviewMode ? 0.55 : 1))
                        }
                    }

                    ForEach(primaryRenderPoints.filter(\.hasRealData)) { point in
                        PointMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value(selectedPrimaryMetric.title, point.chartValue)
                        )
                        .symbolSize(34)
                        .foregroundStyle(selectedPrimaryMetric.color.opacity(isPreviewMode ? 0.55 : 1))
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("Selected", selectedPoint.date, unit: .day))
                            .foregroundStyle(Color.black.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 270)
                .chartXScale(domain: xAxisDomain)
                .chartYScale(domain: normalizedYDomain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisMarkValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                            .foregroundStyle(Color.black.opacity(0.08))
                        AxisTick()
                            .foregroundStyle(Color.black.opacity(0.18))
                        AxisValueLabel {
                            if let numericValue = value.as(Double.self) {
                                Text(axisLabel(for: selectedPrimaryMetric, chartValue: numericValue))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(selectedPrimaryMetric.color)
                            }
                        }
                    }

                    AxisMarks(position: .trailing, values: yAxisMarkValues) { value in
                        AxisTick()
                            .foregroundStyle(Color.black.opacity(0.18))
                        AxisValueLabel {
                            if let numericValue = value.as(Double.self) {
                                Text(axisLabel(for: selectedSecondaryMetric, chartValue: numericValue))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(selectedSecondaryMetric.color)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisMarkDates) { value in
                        AxisTick()
                            .foregroundStyle(Color.black.opacity(0.14))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(selectedRange.xAxisFormat))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.41, green: 0.46, blue: 0.43))
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.94),
                                            Color(red: 0.95, green: 0.97, blue: 0.95).opacity(0.84)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if let plotFrame = proxy.plotFrame {
                                            let frame = geometry[plotFrame]
                                            let location = CGPoint(
                                                x: value.location.x - frame.origin.x,
                                                y: value.location.y - frame.origin.y
                                            )

                                            if let date: Date = proxy.value(atX: location.x) {
                                                selectedPointDate = date
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        if presentationStyle == .embedded {
                                            return
                                        }
                                    }
                            )
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isPreviewMode {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Preview")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .textCase(.uppercase)
                            Text("Start check-ins, routine logs, or meds to replace this sample with your own chart.")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Color(red: 0.26, green: 0.33, blue: 0.31))
                        .padding(12)
                        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(12)
                    }
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1)
            )
            .contentTransition(.interpolate)

            if let selectedPoint {
                SelectedPointCard(
                    date: selectedPoint.date,
                    primaryMetric: selectedPrimaryMetric,
                    secondaryMetric: selectedSecondaryMetric,
                    primaryValue: selectedPrimaryMetric.availableValue(for: selectedPoint),
                    secondaryValue: comparisonValue(for: selectedPoint)
                )
            }

            if let relationshipSummary, !isPreviewMode {
                RelationshipSummaryCard(
                    summary: relationshipSummary,
                    primaryMetric: selectedPrimaryMetric,
                    secondaryMetric: selectedSecondaryMetric
                )
            }

            if evidenceState != .tooThin && !lagInsights.isEmpty && !isPreviewMode {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lag Windows")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.42, green: 0.49, blue: 0.45))
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(lagInsights) { insight in
                                LagInsightCard(
                                    insight: insight,
                                    primaryMetric: selectedPrimaryMetric,
                                    secondaryMetric: selectedSecondaryMetric
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $isPresentingExpanded) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    RoutineImpactChart(
                        points: points,
                        initialPrimaryMetric: selectedPrimaryMetric,
                        initialSecondaryMetric: selectedSecondaryMetric,
                        initialRange: selectedRange,
                        presentationStyle: .expanded
                    )
                    .padding(20)
                }
                .background(appBackground.ignoresSafeArea())
                .navigationTitle("Trend Studio")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
    }

    private func pairedObservations(for lagWeeks: Int) -> [ChartPairedObservation] {
        analyticsPoints.compactMap { point in
            guard
                let primaryValue = selectedPrimaryMetric.availableValue(for: point),
                let secondaryValue = comparisonValue(for: point, lagWeeks: lagWeeks)
            else {
                return nil
            }

            return ChartPairedObservation(
                date: point.date,
                primaryValue: primaryValue,
                secondaryValue: secondaryValue
            )
        }
    }

    private func comparisonValue(for point: ChartAnalyticsPoint, lagWeeks: Int? = nil) -> Double? {
        let effectiveLagWeeks = lagWeeks ?? selectedLagWeeks

        guard effectiveLagWeeks > 0 else {
            return selectedSecondaryMetric.availableValue(for: point)
        }

        guard let lagDate = Calendar.current.date(byAdding: .day, value: -(effectiveLagWeeks * 7), to: point.date) else {
            return nil
        }

        let laggedPoint = analyticsPoints
            .sorted { $0.date < $1.date }
            .last { $0.date <= lagDate }

        return laggedPoint.flatMap { selectedSecondaryMetric.availableValue(for: $0) }
    }

    private func comparisonValue(for point: RoutineImpactPoint) -> Double? {
        guard let analyticsPoint = analyticsPoints.first(where: { Calendar.current.isDate($0.date, inSameDayAs: point.date) }) else {
            return nil
        }
        return comparisonValue(for: analyticsPoint)
    }
}

enum ChartEvidenceState {
    case preview
    case tooThin
    case earlySignal
    case usable

    var title: String {
        switch self {
        case .preview:
            return "Preview mode"
        case .tooThin:
            return "Not enough signal yet"
        case .earlySignal:
            return "Early pattern"
        case .usable:
            return "More stable read"
        }
    }

    var message: String {
        switch self {
        case .preview:
            return "This is a sample pattern so new users can see how the chart experience will look after they begin logging real data."
        case .tooThin:
            return "This comparison is still sparse. Use it to collect directionally useful history, not to decide what is working."
        case .earlySignal:
            return "A pattern may be forming, but the window is still short enough that one or two logs can move the read materially."
        case .usable:
            return "This window has enough repeated points to be more informative, but it is still correlation rather than proof of cause."
        }
    }

    var tint: Color {
        switch self {
        case .preview:
            return Color(red: 0.30, green: 0.47, blue: 0.63)
        case .tooThin:
            return Color(red: 0.78, green: 0.49, blue: 0.24)
        case .earlySignal:
            return Color(red: 0.58, green: 0.44, blue: 0.70)
        case .usable:
            return Color(red: 0.28, green: 0.55, blue: 0.44)
        }
    }
}

struct ChartEvidenceCard: View {
    let state: ChartEvidenceState
    let primaryMetric: ChartMetric
    let secondaryMetric: ChartMetric
    let pointCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(state.tint)
                .frame(width: 34, height: 34)
                .background(state.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
                Text(state == .preview
                    ? "This is sample data to show what the chart looks like."
                    : "\(primaryMetric.title) against \(secondaryMetric.title.lowercased()) across \(pointCount) paired days."
                )
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(state.tint)
                Text(state.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.40, green: 0.45, blue: 0.42))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

enum ChartPresentationStyle {
    case embedded
    case expanded
}

struct LagInsight: Identifiable {
    let weeks: Int
    let pairCount: Int
    let correlation: Double
    let effectSize: Double

    var id: Int { weeks }
}

struct ChartRelationshipSummary {
    let overlapCount: Int
    let correlation: Double
    let effectSize: Double
    let lowExposurePrimaryAverage: Double
    let highExposurePrimaryAverage: Double
    let lagWeeks: Int
}

struct ChartPreset: Identifiable {
    let title: String
    let primary: ChartMetric
    let secondary: ChartMetric

    var id: String { "\(primary.rawValue)-\(secondary.rawValue)" }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .oneYear: return "1Y"
        }
    }

    var axisStrideComponent: Calendar.Component {
        switch self {
        case .oneMonth:
            return .day
        case .threeMonths, .sixMonths, .oneYear:
            return .month
        }
    }

    var axisStrideCount: Int {
        switch self {
        case .oneMonth:
            return 7
        case .threeMonths:
            return 1
        case .sixMonths:
            return 2
        case .oneYear:
            return 3
        }
    }

    var xAxisFormat: Date.FormatStyle {
        switch self {
        case .oneMonth:
            return .dateTime.month(.abbreviated).day()
        case .threeMonths, .sixMonths, .oneYear:
            return .dateTime.month(.abbreviated)
        }
    }

    func cutoffDate(from referenceDate: Date) -> Date {
        let monthsBack: Int
        switch self {
        case .oneMonth: monthsBack = 1
        case .threeMonths: monthsBack = 3
        case .sixMonths: monthsBack = 6
        case .oneYear: monthsBack = 12
        }
        return Calendar.current.date(byAdding: .month, value: -monthsBack, to: referenceDate) ?? referenceDate
    }
}

enum ChartMetric: String, CaseIterable, Identifiable {
    case shedding
    case stress
    case hydration
    case scalp
    case sleepHours
    case exerciseMinutes
    case proteinGrams
    case waterLiters
    case smokingCount
    case supplementEntries
    case routineActions
    case medicationEntries
    case minoxidilEntries
    case procedureEvents
    case dutasterideProcedureEvents
    case triggerEvents
    case tractionEvents
    case sebDermEvents
    case recentTriggerLoad
    case recentProcedureLoad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shedding: return "Shedding"
        case .stress: return "Stress"
        case .hydration: return "Hydration"
        case .scalp: return "Scalp"
        case .sleepHours: return "Sleep Hours"
        case .exerciseMinutes: return "Exercise Minutes"
        case .proteinGrams: return "Protein"
        case .waterLiters: return "Water"
        case .smokingCount: return "Smoking"
        case .supplementEntries: return "Supplement Entries"
        case .routineActions: return "Routine Burden"
        case .medicationEntries: return "Medication Adherence"
        case .minoxidilEntries: return "Minoxidil Adherence"
        case .procedureEvents: return "Procedure Burden"
        case .dutasterideProcedureEvents: return "Dutasteride Burden"
        case .triggerEvents: return "Trigger Burden"
        case .tractionEvents: return "Traction Burden"
        case .sebDermEvents: return "Seb Derm Burden"
        case .recentTriggerLoad: return "Trigger Load"
        case .recentProcedureLoad: return "Procedure Load"
        }
    }

    var systemImage: String {
        switch self {
        case .shedding: return "wind"
        case .stress: return "brain.head.profile"
        case .hydration: return "drop.fill"
        case .scalp: return "sparkles"
        case .sleepHours: return "bed.double.fill"
        case .exerciseMinutes: return "figure.run"
        case .proteinGrams: return "fork.knife"
        case .waterLiters: return "waterbottle.fill"
        case .smokingCount: return "smoke.fill"
        case .supplementEntries: return "capsule.portrait.fill"
        case .routineActions: return "checklist.checked"
        case .medicationEntries: return "pills.fill"
        case .minoxidilEntries: return "drop.circle.fill"
        case .procedureEvents: return "cross.case.fill"
        case .dutasterideProcedureEvents: return "syringe.fill"
        case .triggerEvents: return "timeline.selection"
        case .tractionEvents: return "link"
        case .sebDermEvents: return "aqi.low"
        case .recentTriggerLoad: return "calendar.badge.exclamationmark"
        case .recentProcedureLoad: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }

    var selectorSubtitle: String {
        switch self {
        case .shedding: return "Hair fall or loss intensity"
        case .stress: return "Stress pressure level"
        case .hydration: return "Moisture and softness trend"
        case .scalp: return "Overall scalp comfort score"
        case .sleepHours: return "Nightly sleep duration"
        case .exerciseMinutes: return "Daily exercise minutes"
        case .proteinGrams: return "Protein intake trend"
        case .waterLiters: return "Water intake level"
        case .smokingCount: return "Smoking event count"
        case .supplementEntries: return "Supplement or nutrition events"
        case .routineActions: return "14-day moving average of completed actions"
        case .medicationEntries: return "14-day consistency score capped at 14"
        case .minoxidilEntries: return "14-day minoxidil consistency capped at 14"
        case .procedureEvents: return "14-day moving average of procedure burden"
        case .dutasterideProcedureEvents: return "14-day moving average of dutasteride burden"
        case .triggerEvents: return "14-day moving average of trigger burden"
        case .tractionEvents: return "14-day moving average of traction burden"
        case .sebDermEvents: return "14-day moving average of seborrheic dermatitis burden"
        case .recentTriggerLoad: return "14-day moving average of lag-aware trigger pressure"
        case .recentProcedureLoad: return "14-day moving average of lag-aware procedure pressure"
        }
    }

    var color: Color {
        switch self {
        case .shedding: return Color(red: 0.83, green: 0.46, blue: 0.22)
        case .stress: return Color(red: 0.67, green: 0.39, blue: 0.73)
        case .hydration: return Color(red: 0.20, green: 0.47, blue: 0.79)
        case .scalp: return Color(red: 0.26, green: 0.56, blue: 0.42)
        case .sleepHours: return Color(red: 0.24, green: 0.49, blue: 0.78)
        case .exerciseMinutes: return Color(red: 0.29, green: 0.56, blue: 0.42)
        case .proteinGrams: return Color(red: 0.80, green: 0.56, blue: 0.34)
        case .waterLiters: return Color(red: 0.18, green: 0.63, blue: 0.82)
        case .smokingCount: return Color(red: 0.64, green: 0.36, blue: 0.28)
        case .supplementEntries: return Color(red: 0.57, green: 0.44, blue: 0.18)
        case .routineActions: return Color(red: 0.90, green: 0.78, blue: 0.56)
        case .medicationEntries: return Color(red: 0.29, green: 0.57, blue: 0.56)
        case .minoxidilEntries: return Color(red: 0.20, green: 0.63, blue: 0.50)
        case .procedureEvents: return Color(red: 0.64, green: 0.36, blue: 0.28)
        case .dutasterideProcedureEvents: return Color(red: 0.46, green: 0.29, blue: 0.69)
        case .triggerEvents: return Color(red: 0.71, green: 0.49, blue: 0.22)
        case .tractionEvents: return Color(red: 0.78, green: 0.35, blue: 0.26)
        case .sebDermEvents: return Color(red: 0.56, green: 0.47, blue: 0.18)
        case .recentTriggerLoad: return Color(red: 0.82, green: 0.48, blue: 0.20)
        case .recentProcedureLoad: return Color(red: 0.54, green: 0.34, blue: 0.66)
        }
    }

    var prefersBars: Bool {
        switch self {
        case .routineActions, .medicationEntries, .minoxidilEntries, .procedureEvents,
                .dutasterideProcedureEvents, .smokingCount, .supplementEntries,
                .triggerEvents, .tractionEvents, .sebDermEvents:
            return true
        default:
            return false
        }
    }

    var prefersHigherValues: Bool {
        switch self {
        case .shedding, .stress, .smokingCount, .triggerEvents, .tractionEvents, .sebDermEvents,
                .recentTriggerLoad, .procedureEvents, .dutasterideProcedureEvents, .recentProcedureLoad:
            return false
        case .hydration, .scalp, .sleepHours, .exerciseMinutes, .proteinGrams, .waterLiters,
                .supplementEntries, .routineActions, .medicationEntries, .minoxidilEntries:
            return true
        }
    }

    var unitSuffix: String {
        switch self {
        case .shedding, .stress, .hydration, .scalp:
            return "%"
        case .sleepHours:
            return "h"
        case .exerciseMinutes:
            return "min"
        case .proteinGrams:
            return "g"
        case .waterLiters:
            return "L"
        case .medicationEntries, .minoxidilEntries:
            return "/14"
        default:
            return ""
        }
    }

    /// The expected range for this metric, used to normalize values to 0–100 for visual comparison.
    var typicalRange: ClosedRange<Double> {
        switch self {
        case .shedding, .stress, .hydration, .scalp:
            return 0...100
        case .sleepHours:
            return 0...12
        case .exerciseMinutes:
            return 0...120
        case .proteinGrams:
            return 0...200
        case .waterLiters:
            return 0...4
        case .smokingCount:
            return 0...10
        case .supplementEntries:
            return 0...5
        case .routineActions:
            return 0...10
        case .medicationEntries, .minoxidilEntries:
            return 0...14
        case .procedureEvents, .dutasterideProcedureEvents:
            return 0...3
        case .triggerEvents, .tractionEvents, .sebDermEvents:
            return 0...5
        case .recentTriggerLoad, .recentProcedureLoad:
            return 0...3
        }
    }

    /// Normalize a raw value into the 0–100 visual range based on `typicalRange`.
    func normalized(_ value: Double) -> Double {
        let range = typicalRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return ((value - range.lowerBound) / span) * 100
    }

    func denormalized(_ value: Double) -> Double {
        let range = typicalRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return range.lowerBound }
        return range.lowerBound + ((value / 100) * span)
    }

    func formattedAxisValue(_ value: Double) -> String {
        let number: String
        switch self {
        case .sleepHours, .waterLiters:
            number = value.formatted(.number.precision(.fractionLength(1)))
        case .exerciseMinutes, .proteinGrams,
                .smokingCount, .supplementEntries, .routineActions, .medicationEntries, .minoxidilEntries,
                .procedureEvents, .dutasterideProcedureEvents, .triggerEvents, .tractionEvents, .sebDermEvents:
            number = value.formatted(.number.precision(.fractionLength(0)))
        case .shedding, .stress, .hydration, .scalp:
            number = value.formatted(.number.precision(.fractionLength(0)))
        case .recentTriggerLoad, .recentProcedureLoad:
            number = value.formatted(.number.precision(.fractionLength(1)))
        }

        return unitSuffix.isEmpty ? number : "\(number)\(unitSuffix)"
    }

    static func defaultCompanion(for metric: ChartMetric) -> ChartMetric {
        switch metric {
        case .shedding:
            return .stress
        case .stress:
            return .shedding
        case .hydration:
            return .waterLiters
        case .scalp:
            return .sebDermEvents
        case .sleepHours:
            return .shedding
        case .exerciseMinutes:
            return .stress
        case .proteinGrams:
            return .shedding
        case .waterLiters:
            return .hydration
        case .smokingCount:
            return .shedding
        case .supplementEntries:
            return .shedding
        case .routineActions:
            return .scalp
        case .medicationEntries:
            return .shedding
        case .minoxidilEntries:
            return .shedding
        case .procedureEvents:
            return .shedding
        case .dutasterideProcedureEvents:
            return .shedding
        case .triggerEvents:
            return .shedding
        case .tractionEvents:
            return .scalp
        case .sebDermEvents:
            return .scalp
        case .recentTriggerLoad:
            return .shedding
        case .recentProcedureLoad:
            return .shedding
        }
    }

    func formattedValue(_ value: Double) -> String {
        if self == .medicationEntries || self == .minoxidilEntries {
            if value >= 14 {
                return "14 max"
            }
            return "\(value.formatted(.number.precision(.fractionLength(0...1))))/14"
        }

        let number: String
        switch self {
        case .sleepHours, .waterLiters:
            number = value.formatted(.number.precision(.fractionLength(1)))
        case .proteinGrams, .exerciseMinutes:
            number = value.formatted(.number.precision(.fractionLength(0)))
        case .shedding, .stress, .hydration, .scalp:
            number = value.formatted(.number.precision(.fractionLength(0)))
        default:
            number = value.formatted(.number.precision(.fractionLength(1)))
        }
        return unitSuffix.isEmpty ? number : "\(number)\(unitSuffix)"
    }

    func value(for point: RoutineImpactPoint) -> Double {
        switch self {
        case .shedding: return point.sheddingScore
        case .stress: return point.stressScore
        case .hydration: return point.hydrationScore
        case .scalp: return point.scalpScore
        case .sleepHours: return point.sleepHours
        case .exerciseMinutes: return point.exerciseMinutes
        case .proteinGrams: return point.proteinGrams
        case .waterLiters: return point.waterLiters
        case .smokingCount: return point.smokingCount
        case .supplementEntries: return Double(point.supplementEntries)
        case .routineActions: return Double(point.routineActions)
        case .medicationEntries: return Double(point.medicationEntries)
        case .minoxidilEntries: return Double(point.minoxidilEntries)
        case .procedureEvents: return Double(point.procedureEvents)
        case .dutasterideProcedureEvents: return Double(point.dutasterideProcedureEvents)
        case .triggerEvents: return Double(point.triggerEvents)
        case .tractionEvents: return Double(point.tractionEvents)
        case .sebDermEvents: return Double(point.sebDermEvents)
        case .recentTriggerLoad: return point.recentTriggerLoad
        case .recentProcedureLoad: return point.recentProcedureLoad
        }
    }

    func availableValue(for point: RoutineImpactPoint) -> Double? {
        switch self {
        case .shedding, .stress, .hydration, .scalp:
            return point.hasCheckInData ? value(for: point) : nil
        case .sleepHours, .exerciseMinutes, .proteinGrams, .waterLiters:
            return point.hasHealthData ? value(for: point) : nil
        case .smokingCount, .supplementEntries, .routineActions, .medicationEntries, .minoxidilEntries,
                .procedureEvents, .dutasterideProcedureEvents, .triggerEvents, .tractionEvents, .sebDermEvents,
                .recentTriggerLoad, .recentProcedureLoad:
            return value(for: point)
        }
    }

    func availableValue(for point: ChartAnalyticsPoint) -> Double? {
        point.values[self]
    }
}

struct ChartAnalyticsPoint: Identifiable {
    let date: Date
    let values: [ChartMetric: Double]
    /// True when this day had at least one real data entry (check-in, health, routine, etc.)
    let hasRealData: Bool

    var id: Date { date }
}

struct ChartPairedObservation {
    let date: Date
    let primaryValue: Double
    let secondaryValue: Double
}

enum ChartAnalyticsEngine {
    static func buildSeries(
        from points: [RoutineImpactPoint],
        calendar: Calendar = .current
    ) -> [ChartAnalyticsPoint] {
        let sortedPoints = points.sorted { $0.date < $1.date }
        guard let firstDate = sortedPoints.first?.date, let lastDate = sortedPoints.last?.date else { return [] }

        let start = calendar.startOfDay(for: firstDate)
        let end = calendar.startOfDay(for: lastDate)
        let pointByDay = Dictionary(uniqueKeysWithValues: sortedPoints.map { (calendar.startOfDay(for: $0.date), $0) })

        let days = strideDays(from: start, through: end, calendar: calendar)

        return days.map { day in
            let trailing14 = trailingPoints(through: day, days: 14, in: pointByDay, calendar: calendar)
            let dayPoint = pointByDay[day]

            let medicationConsistency = rollingConsistencyScore(
                from: trailing14,
                takenKeyPath: \.medicationEntries,
                expectedKeyPath: \.expectedMedicationEntries
            )
            let minoxidilConsistency = rollingConsistencyScore(
                from: trailing14,
                takenKeyPath: \.minoxidilEntries,
                expectedKeyPath: \.expectedMinoxidilEntries
            )

            var values: [ChartMetric: Double] = [:]
            values[.shedding] = rollingAverage(from: trailing14, keyPath: \.sheddingScore, requireData: \.hasCheckInData)
            values[.stress] = rollingAverage(from: trailing14, keyPath: \.stressScore, requireData: \.hasCheckInData)
            values[.hydration] = rollingAverage(from: trailing14, keyPath: \.hydrationScore, requireData: \.hasCheckInData)
            values[.scalp] = rollingAverage(from: trailing14, keyPath: \.scalpScore, requireData: \.hasCheckInData)
            values[.sleepHours] = rollingAverage(from: trailing14, keyPath: \.sleepHours, requireData: \.hasHealthData)
            values[.exerciseMinutes] = rollingAverage(from: trailing14, keyPath: \.exerciseMinutes, requireData: \.hasHealthData)
            values[.proteinGrams] = rollingAverage(from: trailing14, keyPath: \.proteinGrams, requireData: \.hasHealthData)
            values[.waterLiters] = rollingAverage(from: trailing14, keyPath: \.waterLiters, requireData: \.hasHealthData)
            values[.smokingCount] = trailingAverage(from: trailing14, keyPath: \.smokingCount)
            values[.supplementEntries] = trailingAverage(from: trailing14, keyPath: { Double($0.supplementEntries) })
            values[.routineActions] = trailingAverage(from: trailing14, keyPath: { Double($0.routineActions) })
            values[.medicationEntries] = medicationConsistency
            values[.minoxidilEntries] = minoxidilConsistency
            values[.procedureEvents] = trailingAverage(from: trailing14, keyPath: { Double($0.procedureEvents) })
            values[.dutasterideProcedureEvents] = trailingAverage(from: trailing14, keyPath: { Double($0.dutasterideProcedureEvents) })
            values[.triggerEvents] = trailingAverage(from: trailing14, keyPath: { Double($0.triggerEvents) })
            values[.tractionEvents] = trailingAverage(from: trailing14, keyPath: { Double($0.tractionEvents) })
            values[.sebDermEvents] = trailingAverage(from: trailing14, keyPath: { Double($0.sebDermEvents) })
            values[.recentTriggerLoad] = trailingAverage(from: trailing14, keyPath: \.recentTriggerLoad)
            values[.recentProcedureLoad] = trailingAverage(from: trailing14, keyPath: \.recentProcedureLoad)

            let hasRealData = dayPoint != nil

            if !hasRealData {
                values = values.compactMapValues { $0 }
            }

            return ChartAnalyticsPoint(date: day, values: values, hasRealData: hasRealData)
        }
    }

    private static func strideDays(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private static func trailingPoints(
        through day: Date,
        days: Int,
        in pointByDay: [Date: RoutineImpactPoint],
        calendar: Calendar
    ) -> [RoutineImpactPoint] {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: day) ?? day
        return pointByDay
            .filter { $0.key >= start && $0.key <= day }
            .map(\.value)
            .sorted { $0.date < $1.date }
    }

    private static func rollingAverage(
        from points: [RoutineImpactPoint],
        keyPath: KeyPath<RoutineImpactPoint, Double>,
        requireData: KeyPath<RoutineImpactPoint, Bool>
    ) -> Double? {
        let usable = points.filter { $0[keyPath: requireData] }.map { $0[keyPath: keyPath] }
        guard !usable.isEmpty else { return nil }
        return usable.reduce(0, +) / Double(usable.count)
    }

    private static func trailingAverage(
        from points: [RoutineImpactPoint],
        keyPath: (RoutineImpactPoint) -> Double
    ) -> Double {
        guard !points.isEmpty else { return 0 }
        return points.map(keyPath).reduce(0, +) / Double(points.count)
    }

    private static func rollingConsistencyScore(
        from points: [RoutineImpactPoint],
        takenKeyPath: KeyPath<RoutineImpactPoint, Int>,
        expectedKeyPath: KeyPath<RoutineImpactPoint, Int>
    ) -> Double {
        guard !points.isEmpty else { return 0 }

        let score = points.reduce(0.0) { partial, point in
            let expected = point[keyPath: expectedKeyPath]
            guard expected > 0 else { return partial }

            let taken = point[keyPath: takenKeyPath]
            let dailyConsistency = min(1.0, Double(taken) / Double(expected))
            return partial + dailyConsistency
        }

        return min(14, score)
    }
}

enum ChartRelationshipAnalyzer {
    static func summarize(
        observations: [ChartPairedObservation],
        lagWeeks: Int
    ) -> ChartRelationshipSummary? {
        guard observations.count >= 4 else { return nil }

        let sortedByExposure = observations.sorted { $0.secondaryValue < $1.secondaryValue }
        let splitIndex = max(1, sortedByExposure.count / 2)
        let lowExposure = Array(sortedByExposure.prefix(splitIndex))
        let highExposure = Array(sortedByExposure.suffix(sortedByExposure.count - splitIndex))

        guard !lowExposure.isEmpty, !highExposure.isEmpty else { return nil }

        let lowAverage = mean(lowExposure.map(\.primaryValue))
        let highAverage = mean(highExposure.map(\.primaryValue))

        return ChartRelationshipSummary(
            overlapCount: observations.count,
            correlation: pearsonCorrelation(
                x: observations.map(\.secondaryValue),
                y: observations.map(\.primaryValue)
            ),
            effectSize: highAverage - lowAverage,
            lowExposurePrimaryAverage: lowAverage,
            highExposurePrimaryAverage: highAverage,
            lagWeeks: lagWeeks
        )
    }

    private static func pearsonCorrelation(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 2 else { return 0 }
        let xMean = mean(x)
        let yMean = mean(y)

        let numerator = zip(x, y).reduce(0.0) { partial, pair in
            partial + ((pair.0 - xMean) * (pair.1 - yMean))
        }
        let xVariance = x.reduce(0.0) { $0 + pow($1 - xMean, 2) }
        let yVariance = y.reduce(0.0) { $0 + pow($1 - yMean, 2) }
        let denominator = sqrt(xVariance * yVariance)
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct ChartMetricPicker: View {
    let title: String
    @Binding var selection: ChartMetric
    @State private var isPresentingMetricSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.41, green: 0.46, blue: 0.43))

            Button {
                isPresentingMetricSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selection.color)
                        .frame(width: 34, height: 34)
                        .background(selection.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selection.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.20))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(selection.selectorSubtitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.45, green: 0.50, blue: 0.47))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.45, green: 0.50, blue: 0.47))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selection.color.opacity(0.18), lineWidth: 1)
            )
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isPresentingMetricSheet) {
            ChartMetricSelectionSheet(title: title, selection: $selection)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct ChartMetricSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selection: ChartMetric

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ChartMetric.allCases) { metric in
                        Button {
                            selection = metric
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: metric.systemImage)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(metric.color)
                                        .frame(width: 38, height: 38)
                                        .background(metric.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                                    Spacer()

                                    if selection == metric {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(metric.color)
                                    }
                                }

                                Text(metric.title)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))

                                Text(metric.selectorSubtitle)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(red: 0.44, green: 0.49, blue: 0.46))
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
                            .padding(16)
                            .background(
                                LinearGradient(
                                    colors: selection == metric
                                    ? [metric.color.opacity(0.18), Color.white.opacity(0.95)]
                                    : [Color.white.opacity(0.95), Color.white.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(selection == metric ? metric.color.opacity(0.30) : Color.white.opacity(0.65), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LegendChip: View {
    let metric: ChartMetric
    let role: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(metric.color)
                .frame(width: 18, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(role)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.47, green: 0.51, blue: 0.49))
                    .textCase(.uppercase)
                Text(metric.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.20))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.76), in: Capsule())
    }
}

struct LagInsightCard: View {
    let insight: LagInsight
    let primaryMetric: ChartMetric
    let secondaryMetric: ChartMetric

    private var isTooFewPairs: Bool {
        insight.pairCount < 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(insight.weeks == 0 ? "Same day" : "\(insight.weeks) weeks before")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .textCase(.uppercase)

            if isTooFewPairs {
                Text("--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.60, green: 0.64, blue: 0.62))
            } else {
                Text(correlationText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(secondaryMetric.color)
            }

            Text(isTooFewPairs ? "Too few points" : "Correlation")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))

            if !isTooFewPairs {
                Text(effectText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.37, green: 0.43, blue: 0.40))
            }

            Text("n=\(insight.pairCount) paired days")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
        }
        .frame(width: 170, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.82),
                    secondaryMetric.color.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(secondaryMetric.color.opacity(0.12), lineWidth: 1)
        )
    }

    private var correlationText: String {
        let sign = insight.correlation >= 0 ? "+" : ""
        return "\(sign)\(insight.correlation.formatted(.number.precision(.fractionLength(2))))"
    }

    private var effectText: String {
        let sign = insight.effectSize >= 0 ? "+" : ""
        return "\(sign)\(primaryMetric.formattedValue(insight.effectSize)) in \(primaryMetric.title.lowercased())"
    }
}

struct SelectedPointCard: View {
    let date: Date
    let primaryMetric: ChartMetric
    let secondaryMetric: ChartMetric
    let primaryValue: Double?
    let secondaryValue: Double?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected Point")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                    .textCase(.uppercase)

                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))
            }

            Spacer()

            if let primaryValue {
                metricValueChip(metric: primaryMetric, value: primaryValue)
            }
            if let secondaryValue {
                metricValueChip(metric: secondaryMetric, value: secondaryValue)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.82),
                    Color(red: 0.94, green: 0.97, blue: 0.94).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1)
        )
    }

    private func metricValueChip(metric: ChartMetric, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .textCase(.uppercase)
            Text(metric.formattedValue(value))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(metric.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct RelationshipSummaryCard: View {
    let summary: ChartRelationshipSummary
    let primaryMetric: ChartMetric
    let secondaryMetric: ChartMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Effect Summary")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .textCase(.uppercase)

            Text(headlineText)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.17, green: 0.22, blue: 0.19))

            Text("Across \(summary.overlapCount) paired days, this compares high \(secondaryMetric.title.lowercased()) exposure windows against low exposure windows using a \(summary.lagWeeks)-week lag.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.43, blue: 0.40))

            HStack(spacing: 12) {
                valueTile(title: "High Exposure", value: summary.highExposurePrimaryAverage)
                valueTile(title: "Low Exposure", value: summary.lowExposurePrimaryAverage)
                valueTile(
                    title: "Correlation (n=\(summary.overlapCount))",
                    customValue: summary.overlapCount < 8 ? "--" : correlationText,
                    tint: summary.overlapCount < 8 ? Color(red: 0.60, green: 0.64, blue: 0.62) : secondaryMetric.color
                )
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.84),
                    primaryMetric.color.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(primaryMetric.color.opacity(0.12), lineWidth: 1)
        )
    }

    private var headlineText: String {
        let sign = summary.effectSize >= 0 ? "+" : ""
        return "\(sign)\(primaryMetric.formattedValue(summary.effectSize)) when \(secondaryMetric.title.lowercased()) is higher"
    }

    private var correlationText: String {
        let sign = summary.correlation >= 0 ? "+" : ""
        return "\(sign)\(summary.correlation.formatted(.number.precision(.fractionLength(2))))"
    }

    private func valueTile(title: String, value: Double? = nil, customValue: String? = nil, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.43, green: 0.50, blue: 0.46))
                .textCase(.uppercase)
            Text(customValue ?? primaryMetric.formattedValue(value ?? 0))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint ?? primaryMetric.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

