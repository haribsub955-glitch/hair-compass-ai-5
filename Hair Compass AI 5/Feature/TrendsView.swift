import SwiftData
import SwiftUI

struct TrendsView: View {
    var onLogToday: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil
    var onOpenPhotos: (() -> Void)? = nil

    @Query(sort: \DailyEntry.date) private var entries: [DailyEntry]
    @Query(sort: \Treatment.startDate) private var treatments: [Treatment]
    @Query private var doses: [TreatmentDose]
    @Query private var missedDoseRecords: [MissedDoseRecord]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]
    @Query(sort: \TriggerEvent.date, order: .reverse) private var triggers: [TriggerEvent]
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \PhotoRecord.createdAt) private var photos: [PhotoRecord]
    @Query(sort: \LabResult.collectedAt) private var labs: [LabResult]
    @Query(sort: \ProgressCheckIn.date) private var progressCheckIns: [ProgressCheckIn]
    @Query(sort: \ProcedureAppointment.date) private var procedureAppointments: [ProcedureAppointment]
    @Query(sort: \SideEffectLog.date) private var sideEffectLogs: [SideEffectLog]

    @State private var showCompare = false
    @State private var comparisonEventID: String?
    @State private var showExport = false
    @State private var showBadges = false
    @State private var showReport = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(StarterPlanDismissals.key) private var starterPlanDismissedJSON = "[]"
    @AppStorage(StarterPlanDismissals.discussedKey) private var starterPlanDiscussedJSON = "[]"
    @AppStorage("eveningCheckInEnabled") private var eveningCheckInEnabled = false

    // Round-5 addition: 1Y and All. The app's central teaching is "judge at 24 weeks" and
    // treatment journeys run multi-year — a 180-day cap meant the moment someone passed ~week
    // 26 they could never again see their pre-treatment baseline and treatment period on one
    // chart. "All" isn't literally unbounded (a fixed 10-year window is indistinguishable from
    // "everything logged" for any real account) — it just stops being the thing that quietly
    // truncates a loyal user's own history.
    enum Range: String, CaseIterable { case m1 = "1M", m3 = "3M", m6 = "6M", y1 = "1Y", all = "All"
        var days: Int {
            switch self {
            case .m1: return 30
            case .m3: return 90
            case .m6: return 180
            case .y1: return 365
            case .all: return 3650
            }
        }
    }
    @State private var range: Range = .m3
    /// 0…1 fraction driving the header's scroll-condense (see `ScreenHeader.condensed`) — set
    /// directly from the ScrollView's own content offset, so the title tracks the finger 1:1
    /// exactly like a native large-title collapse rather than a separate animated effect.
    @State private var headerCondense: CGFloat = 0
    /// Drives the range picker's sliding copper underline — see `InkTabs`.
    @Namespace private var rangeNamespace

    private var windowEntries: [DailyEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: .now) ?? .now
        return entries.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollContent(proxy: proxy)
        }
    }

    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Longitudinal",
                    title: "Trends",
                    trailing: AnyView(
                        HeaderActionButton(
                            systemName: "square.and.arrow.up",
                            accessibilityLabel: "Export trends"
                        ) {
                            showExport = true
                        }
                    ),
                    condensed: headerCondense
                )
                .padding(.top, 8)
                // Header wash: `art-trends` is itself a rising line over hills, so the plate
                // states the screen's subject before a single datum is drawn. Negative gutter
                // padding lets it bleed past the VStack's 20pt inset to the screen edges; as a
                // background it takes no layout space, so the scroll content can't widen.
                // It stays put while the serif title condenses over it — a free parallax.
                .background(alignment: .top) {
                    // Sized to finish dissolving above the range picker: at 172pt the foliage
                    // still had presence behind the 1M/3M/6M row, which is a control strip and
                    // needs to stay unambiguously readable.
                    BrandWash(art: BrandArt.trends, height: 148, opacity: 0.5, fade: 0.55)
                        .padding(.horizontal, -20)
                        .offset(y: -8)
                }

                if showsRangePicker {
                    rangePicker
                }

                relationshipCard

                currentReadCard

                if isBuildingPrimaryTrend {
                    sparseTrendExperience
                } else {
                    establishedTrendExperience
                }

                // Ends the scroll the way Today does, so the app's two longest reference pages
                // close in one voice. Inset rather than full-bleed on purpose — see `PageCloser`.
                PageCloser(opacity: 0.8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Condenses the header's serif title as the page scrolls — direct 1:1 offset tracking,
        // no `withAnimation`, so it's unaffected by the `.transaction` nil below.
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, newY in
            headerCondense = Clinical.headerCondenseFraction(newY)
        }
        // Trends is a reference surface, not a motion surface: the user reported chart elements
        // sliding "left and right" on interaction. The outer scroll is width-locked (content ==
        // viewport, verified), so that motion was never a horizontal pan — it was Swift Charts
        // animating mark/domain changes (e.g. tapping 1M/3M/6M) and entrance transitions sliding
        // the plotted line. Nil-ing the transaction animation for this subtree makes every data
        // or range change snap into place instead of interpolating, so nothing drifts on touch.
        .transaction { $0.animation = nil }
        .clinicalScreen()
        .sheet(isPresented: $showCompare) {
            NavigationStack {
                CompareView(initialEventID: comparisonEventID)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showCompare = false } } }
            }
        }
        .sheet(isPresented: $showExport) { ExportSheet() }
        .sheet(isPresented: $showReport) {
            if let report = progressReport { ProgressReportSheet(report: report, photos: photos) }
        }
        .sheet(isPresented: $showBadges) {
            AchievementsSheet(
                entries: entries, treatments: treatments, doses: doses,
                photos: photos, labs: labs
            )
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("HC_COMPARE") { showCompare = true }
            if args.contains("HC_EXPORT") { showExport = true }
            if args.contains("HC_BADGES") { showBadges = true }
            if args.contains("HC_BODY") {
                // Give the lazy scroll content one beat to lay out before jumping.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { proxy.scrollTo("body-signals", anchor: .top) }
                }
            }
            #endif
        }
    }

    // MARK: - Progressive trend experience

    private enum TrendFocus: Equatable {
        case shedding, scalpSymptoms, photos

        var title: String {
            switch self {
            case .shedding: return "shedding baseline"
            case .scalpSymptoms: return "scalp-symptom baseline"
            case .photos: return "visual baseline"
            }
        }

        var baselineTarget: Int { self == .photos ? 2 : 5 }
        var directionTarget: Int { self == .photos ? 2 : 10 }
        var journeyMetric: JourneyMetric? {
            switch self {
            case .shedding: return .shedding
            case .scalpSymptoms: return .scalpSymptoms
            case .photos: return nil
            }
        }
    }

    private var trendFocus: TrendFocus {
        switch profile?.condition ?? .unsure {
        case .seborrheicDermatitis: return .scalpSymptoms
        case .androgenetic, .alopeciaAreata, .traction: return .photos
        case .telogenEffluvium, .unsure: return .shedding
        }
    }

    private var primaryEvidenceCount: Int {
        switch trendFocus {
        case .shedding:
            return entries.filter { $0.hasRecorded(.shedding) }.count
        case .scalpSymptoms:
            return entries.filter { JourneyMetric.scalpSymptoms.value(for: $0) != nil }.count
        case .photos:
            let sameRegion = Dictionary(grouping: photos, by: \.regionRaw).values.map(\.count).max() ?? 0
            return max(sameRegion, progressCheckIns.count)
        }
    }

    private var isBuildingPrimaryTrend: Bool {
        primaryEvidenceCount < trendFocus.directionTarget
    }

    private var showsRangePicker: Bool {
        let dailyCount: Int
        if let metric = trendFocus.journeyMetric {
            dailyCount = entries.filter { metric.value(for: $0) != nil }.count
        } else {
            dailyCount = entries.filter { $0.hasRecorded(.shedding) }.count
        }
        // Keep the range reachable even when every saved highlight is outside the current window.
        let hasHighlights = !photos.isEmpty || !treatments.isEmpty || !progressCheckIns.isEmpty
            || !sideEffectLogs.isEmpty || !triggers.isEmpty || procedureAppointments.contains(where: \.isCompleted)
        if trendFocus == .photos && isBuildingPrimaryTrend { return hasHighlights }
        return dailyCount >= 5 || hasHighlights
    }

    private var rangePicker: some View {
        InkTabs(
            options: Range.allCases,
            selection: $range,
            namespace: rangeNamespace,
            spacing: 22,
            accessibilityLabel: { $0.rawValue }
        ) { option, isOn in
            Text(option.rawValue)
                .font(Clinical.body(13, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Clinical.ink : Clinical.secondary)
        }
    }

    /// A small, unboxed treatment-clock cue that remains useful while a photo-led baseline is
    /// still sparse. It separates "not enough comparison evidence" from "nothing is happening"
    /// without making an outcome claim or competing with the primary card below.
    @ViewBuilder
    private var trendsEvidenceHorizon: some View {
        if let phase = evidencePhase {
            let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: columns), spacing: 12) {
                JournalMetricTile(title: "Next review", value: phase.daysToReview == 0 ? "Ready" : "\(phase.daysToReview) days",
                                  caption: phase.nextReviewDate.formatted(.dateTime.day().month(.abbreviated)),
                                  symbol: "calendar", tint: Clinical.accent)
                JournalMetricTile(title: "Evidence horizon", value: "Week \(phase.week)",
                                  caption: phase.label, symbol: "safari", tint: Clinical.positive)
            }
            .accessibilityIdentifier("trendsEvidenceHorizon")
        }
    }

    @ViewBuilder
    private var sparseTrendExperience: some View {
        trendFoundationCard
        trendsEvidenceHorizon

        if let metric = trendFocus.journeyMetric {
            focusAnnotation
            journalChart(metric: metric)
        } else if entries.filter({ $0.hasRecorded(.shedding) }).count >= 5 {
            // The primary photo baseline remains unmet. Existing daily measurements can still
            // be inspected as supporting context, never substituted for visual evidence.
            journalChart(metric: .shedding, supporting: true)
        }

        highlightsCard
        sparsePlanCard
        whatWillTrendCard
    }

    @ViewBuilder
    private var establishedTrendExperience: some View {
        if let metric = trendFocus.journeyMetric {
            focusAnnotation
            journalChart(metric: metric)
        } else {
            conditionEvidenceCard
            if entries.contains(where: { $0.hasRecorded(.shedding) }) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Daily shedding context")
                    trajectoryAnnotation
                }
                journalChart(metric: .shedding, supporting: true)
            }
        }

        highlightsCard
        trendsEvidenceHorizon

        clinicianReviewCard
        progressCheckInsCard
        StrandDivider()

        ConsistencyCard(
            entries: entries,
            treatments: treatments,
            doses: doses,
            photos: photos,
            labs: labs,
            triggers: triggers,
            showAllBadges: $showBadges
        )

        BodySignalsDashboard(
            snapshots: snapshots,
            windowDays: range.days,
            hasTractionRisk: profile?.hasTractionRisk == true,
            recentTrigger: triggers.first
        )
        .id("body-signals")

        if windowEntries.filter({ $0.hasRecorded(.shedding) || $0.hasCompleteScalpRecording }).count < 2 {
            emptyState
        } else {
            scalpRow
            adherenceRows
        }

        excludedFootnote
    }

    private var trendFoundationCard: some View {
        let count = primaryEvidenceCount
        let target = trendFocus.directionTarget
        let progress = min(1, Double(count) / Double(max(1, target)))
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    CompanionView(moment: count == 0 ? .searching : .listening, size: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Building your trend")
                        Text("The long view").font(Clinical.headline(26)).foregroundStyle(Clinical.ink)
                    }
                    Spacer(minLength: 0)
                }
                Text(foundationHeadline(count: count))
                    .font(Clinical.headline(21))
                    .foregroundStyle(Clinical.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(foundationDetail(count: count))
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Clinical.hairline)
                        Capsule().fill(Clinical.accent)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 7)
                .accessibilityLabel("\(count) of \(target) observations toward a directional read")

                HStack {
                    Text("\(count) recorded")
                    Spacer()
                    Text(trendFocus == .photos ? "2 matching views" : "5 per week")
                }
                .font(Clinical.eyebrow(9))
                .foregroundStyle(Clinical.tertiary)

                Button(action: primaryAction) {
                    Label(primaryActionTitle, systemImage: trendFocus == .photos ? "camera" : "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ClinicalButtonStyle())
            }
        }
        .accessibilityIdentifier("trendsFoundation")
    }

    private func journalChart(metric: JourneyMetric, supporting: Bool = false) -> some View {
        ClinicalCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    BotanicalEmblem(symbol: "chart.xyaxis.line", tint: Clinical.accent, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.title).font(Clinical.headline(23)).foregroundStyle(Clinical.ink)
                        Text(supporting ? "Supporting context · not a density assessment" : "Your observations over time")
                            .font(Clinical.caption(11)).foregroundStyle(Clinical.secondary)
                    }
                }
                if supporting && !showsRangePicker { rangePicker }
                JourneyChart(entries: entries, treatments: treatments, doses: doses, triggers: triggers,
                             procedures: procedureAppointments, photos: photos, progressCheckIns: progressCheckIns,
                             sideEffects: sideEffectLogs, windowDays: range.days, metric: metric)
            }
        }
        .accessibilityIdentifier("trendsJournalChart")
    }

    private func foundationHeadline(count: Int) -> String {
        if count == 0 { return "Your \(trendFocus.title) starts here" }
        if count < trendFocus.baselineTarget { return "A useful baseline is taking shape" }
        return "Your baseline is ready — direction comes next"
    }

    private func foundationDetail(count: Int) -> String {
        switch trendFocus {
        case .photos:
            return count == 0
                ? "Take a standardized baseline photo. A second photo of the same region creates the first honest comparison."
                : "Keep the same region, angle, lighting, and wet-or-dry state for the comparison photo."
        case .shedding, .scalpSymptoms:
            if count == 0 { return "Log one honest observation today. Empty fields stay empty and will not be treated as normal values." }
            if count < 5 { return "These points preserve what happened. The app waits for five observations before drawing a baseline trace." }
            return "A week-to-week direction opens after at least five logged days in each adjacent week."
        }
    }

    private var primaryActionTitle: String {
        trendFocus == .photos ? "Open progress photos" : "Log today's observation"
    }

    private func primaryAction() {
        if trendFocus == .photos { onOpenPhotos?() } else { onLogToday?() }
    }

    private var focusAnnotation: some View {
        HStack(spacing: 7) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(Clinical.body(12, weight: .semibold))
                .foregroundStyle(Clinical.accent)
            Text(trendFocus == .shedding ? TrajectorySummary(entries: windowEntries).oneLiner : scalpFocusOneLiner)
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private var scalpFocusOneLiner: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? .now
        let currentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let points = entries.compactMap { entry in
            JourneyMetric.scalpSymptoms.value(for: entry).map { (date: entry.date, value: $0) }
        }
        let current = points.filter { $0.date >= currentStart && $0.date < tomorrow }
        let previous = points.filter { $0.date >= previousStart && $0.date < currentStart }
        guard current.count >= 5, previous.count >= 5 else {
            return "Scalp-symptom baseline forming · \(min(current.count, 7)) of 7 days logged."
        }
        let delta = ChartMath.mean(current.map(\.value)) - ChartMath.mean(previous.map(\.value))
        if abs(delta) < 0.3 { return "Scalp symptoms steady this week · \(current.count) of 7 days logged." }
        return "Scalp symptoms possibly \(delta < 0 ? "calmer" : "higher") this week · \(current.count) of 7 days logged."
    }

    private var conditionEvidenceCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 11) {
                Eyebrow(text: conditionEvidenceEyebrow)
                Text(conditionEvidenceTitle)
                    .font(Clinical.headline(20))
                    .foregroundStyle(Clinical.ink)
                Text(conditionEvidenceDetail)
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    evidenceStat(value: sameRegionPhotoCount, label: "SAME-REGION PHOTOS")
                    evidenceStat(value: progressCheckIns.count, label: "MONTHLY CHECK-INS")
                }
                Button("Open progress photos") { onOpenPhotos?() }
                    .font(Clinical.body(13, weight: .semibold))
                    .foregroundStyle(Clinical.accent)
                    .buttonStyle(.plain)
                    .minimumHitTarget()
            }
        }
    }

    private var sameRegionPhotoCount: Int {
        Dictionary(grouping: photos, by: \.regionRaw).values.map(\.count).max() ?? 0
    }

    private var conditionEvidenceEyebrow: String {
        switch profile?.condition ?? .unsure {
        case .alopeciaAreata: return "Patch and regrowth record"
        case .traction: return "Hairline and tension record"
        default: return "Monthly visual record"
        }
    }

    private var conditionEvidenceTitle: String {
        sameRegionPhotoCount >= 2 ? "Your visual comparison is ready" : "Match the same view over time"
    }

    private var conditionEvidenceDetail: String {
        switch profile?.condition ?? .unsure {
        case .alopeciaAreata:
            return "Same-region photos and monthly patch/regrowth answers are the primary progress record. Daily shedding stays secondary context."
        case .traction:
            return "Repeat the same hairline or affected-region view and record changes in tension exposure. Daily shedding stays secondary context."
        default:
            return "For gradual pattern thinning, standardized monthly photos and density or hairline check-ins carry more meaning than daily shedding alone."
        }
    }

    private func evidenceStat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(Clinical.number(21)).foregroundStyle(Clinical.ink)
            Text(label).font(Clinical.eyebrow(8)).foregroundStyle(Clinical.tertiary)
        }
    }

    private var starterPlanItems: [StarterPlanItem] {
        guard let profile else { return [] }
        return StarterPlan.items(for: .make(
            profile: profile,
            labs: labs,
            treatments: treatments,
            photos: photos,
            procedures: procedureAppointments,
            entries: entries,
            remindersEnabled: eveningCheckInEnabled,
            dismissed: StarterPlanDismissals.decode(starterPlanDismissedJSON),
            discussed: StarterPlanDismissals.decode(starterPlanDiscussedJSON)
        ))
    }

    @ViewBuilder
    private var sparsePlanCard: some View {
        let visible = Array(starterPlanItems.filter { !$0.isDone }.prefix(3))
        if !visible.isEmpty {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "From your plan")
                    Text("Small actions make the trend useful")
                        .font(Clinical.headline(19))
                        .foregroundStyle(Clinical.ink)
                    Text("Complete one today; the trend will keep the context beside your results.")
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.secondary)
                        .padding(.bottom, 4)
                    ForEach(visible) { item in
                        Divider().overlay(Clinical.hairline)
                        Button { openPlanItem(item) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: planIcon(item))
                                    .foregroundStyle(Clinical.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(Clinical.body(14, weight: .medium))
                                        .foregroundStyle(Clinical.ink)
                                    Text(item.why)
                                        .font(Clinical.caption(11))
                                        .foregroundStyle(Clinical.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(Clinical.caption(10))
                                    .foregroundStyle(Clinical.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.clinicalPressable)
                    }
                }
            }
        }
    }

    private func openPlanItem(_ item: StarterPlanItem) {
        switch item.kind {
        case .setup(.logToday): onLogToday?()
        case .setup(.baselinePhoto): onOpenPhotos?()
        default: onOpenPlan?()
        }
    }

    private func planIcon(_ item: StarterPlanItem) -> String {
        switch item.kind {
        case .setup(.logToday): return "checkmark.circle"
        case .setup(.baselinePhoto): return "camera"
        case .setup(.reminders): return "bell"
        case .setup(.enterLabs), .lab: return "testtube.2"
        case .setup(.addTreatments), .treatment: return "pills"
        case .procedure: return "cross.case"
        case .guidance(.labs): return "testtube.2"
        case .guidance(.care): return "person.crop.rectangle"
        }
    }

    private var whatWillTrendCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "What will appear here")
                futureTrendRow("Your primary outcome", detail: primaryOutcomeDescription)
                futureTrendRow("Plan consistency", detail: "Doses and scheduled care, shown as context rather than proof.")
                futureTrendRow("Events worth remembering", detail: "Photos, baby hairs you notice, plan changes, procedures, side effects, and life events.")
            }
        }
    }

    private var primaryOutcomeDescription: String {
        switch trendFocus {
        case .shedding: return "Wash-aware daily shedding and cautious week-to-week direction."
        case .scalpSymptoms: return "Flaking, redness, and itch from the symptoms you answer."
        case .photos: return "Same-region photos plus monthly density, hairline, patch, or regrowth answers."
        }
    }

    private func futureTrendRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(Clinical.accent).frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.ink)
                Text(detail).font(Clinical.caption(11)).foregroundStyle(Clinical.secondary)
            }
        }
    }

    private var highlightsCard: some View {
        TrendHighlightsCard(highlights: trendHighlights) { highlight in
            comparisonEventID = highlight.id
            showCompare = true
        }
    }

    private var trendHighlights: [TrendHighlight] {
        let start = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -range.days, to: .now) ?? .now)
        return TrendContext.highlights(treatments: treatments, procedures: procedureAppointments,
                                       photos: photos, progress: progressCheckIns, sideEffects: sideEffectLogs,
                                       triggers: triggers, entries: entries, start: start, end: .now)
    }

    private var relationshipCard: some View {
        Button {
            comparisonEventID = nil
            showCompare = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                BotanicalEmblem(symbol: "point.3.connected.trianglepath.dotted", tint: Clinical.accent, size: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Explore relationships").font(Clinical.body(15, weight: .semibold)).foregroundStyle(Clinical.ink)
                    Text("Compare shedding or side effects with your plan, new medications, and Apple Health. See what changed around a highlight.")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Clinical.caption(12)).foregroundStyle(Clinical.accent).padding(.top, 12)
            }
            .padding(16)
            .background(Clinical.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Clinical.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exploreRelationships")
    }

    // MARK: - Clinician-review flags (consolidated red-flag surface)

    /// Conservative, deterministic patterns worth a clinician's attention, computed from data
    /// already tracked elsewhere — see `ClinicianReviewFlags`. Previously scattered (scalp pain
    /// only in the monthly card, the 6-month shedding teaching buried in the recommender, the
    /// severity-3 side-effect banner only in Care) — this is the one quiet place they surface
    /// together.
    private var clinicianReviewFlags: [ClinicianReviewFlag] {
        ClinicianReviewFlags.evaluate(
            progressCheckIns: progressCheckIns,
            entries: entries,
            triggers: triggers,
            sideEffects: sideEffectLogs
        )
    }

    @ViewBuilder
    private var clinicianReviewCard: some View {
        let flags = clinicianReviewFlags
        if !flags.isEmpty {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Worth showing a clinician", color: Clinical.warning)
                    Text("Patterns your own tracking has surfaced — this is record-keeping, not a diagnosis.")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(flags) { flag in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(Clinical.body(12, weight: .semibold))
                                    .foregroundStyle(Clinical.warning)
                                Text(flag.detail)
                                    .font(Clinical.caption(13)).foregroundStyle(Clinical.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func emotionalHistory(checkIns: [ProgressCheckIn]) -> some View {
        let answered = checkIns.filter { $0.hairFeeling != .unspecified }
        if !answered.isEmpty {
            Divider().overlay(Clinical.hairline)
            VStack(alignment: .leading, spacing: 7) {
                Text("How this month felt")
                    .font(Clinical.body(12, weight: .medium)).foregroundStyle(Clinical.ink)
                ForEach(answered.suffix(3)) { checkIn in
                    HStack(alignment: .firstTextBaseline) {
                        Text(checkIn.date.formatted(.dateTime.month(.abbreviated).year()))
                        Spacer()
                        Text(checkIn.hairFeeling.title)
                    }
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                    if !checkIn.hairFeelingNote.isEmpty {
                        Text(checkIn.hairFeelingNote)
                            .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                    }
                }
                if answered.suffix(2).count == 2 && answered.suffix(2).allSatisfy({ $0.hairFeeling == .moreDifficult }) {
                    Text("You may want to mention how this is affecting you at your next appointment.")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Monthly check-ins (slow-moving, self-reported)

    /// The monthly `ProgressCheckIn` answers are collected but were never shown back — this
    /// renders the stored values as-is: a dot per month per question, colored by the trend the
    /// user already picked, plus the latest regrowth level and a prominent scalp-pain flag.
    /// Deterministic, no new math.
    @ViewBuilder
    private var progressCheckInsCard: some View {
        if !progressCheckIns.isEmpty {
            let sorted = progressCheckIns.sorted { $0.date < $1.date }
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Monthly check-ins")
                    Text("Your own answers to the questions a dermatologist asks between visits.")
                        .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)

                    if let latest = sorted.last {
                        HStack(spacing: 6) {
                            Text("Latest regrowth").font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                            Text(latest.regrowth.title).font(Clinical.body(13, weight: .semibold)).foregroundStyle(Clinical.ink)
                            Spacer()
                            Text(latest.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        checkInTrendRow(title: "Density", question: .density, checkIns: sorted)
                        checkInTrendRow(title: "Shedding", question: .shedding, checkIns: sorted)
                        checkInTrendRow(title: "Hairline", question: .hairline, checkIns: sorted)
                        checkInTrendRow(title: "Overall", question: .overall, checkIns: sorted)
                        // AA-only: the actual between-visit progress measure for patchy loss.
                        if profile?.condition == .alopeciaAreata {
                            checkInTrendRow(title: "Patches", question: .patches, checkIns: sorted)
                        }
                    }

                    // A genuine red flag — persistent scalp pain can mean scarring alopecia.
                    // Surfaced from the most recent check-in that reported it, however long ago.
                    if let pain = sorted.reversed().first(where: { $0.scalpPain }) {
                        Label(
                            "Scalp pain reported \(pain.date.formatted(.dateTime.month(.abbreviated).day())) — worth a prompt dermatology review.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(Clinical.body(12, weight: .medium))
                        .foregroundStyle(Clinical.warning)
                    }

                    emotionalHistory(checkIns: sorted)
                }
            }
        }
    }

    private func checkInTrendRow(title: String, question: ProgressTrend.Question, checkIns: [ProgressCheckIn]) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Clinical.body(12, weight: .medium)).foregroundStyle(Clinical.ink)
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(Array(checkIns.enumerated()), id: \.offset) { _, checkIn in
                    Circle()
                        .fill(trendDotColor(Self.trendValue(checkIn, question)))
                        .frame(width: 8, height: 8)
                }
            }
            Spacer(minLength: 8)
            if let last = checkIns.last {
                Text(Self.trendValue(last, question).label(for: question))
                    .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title): " + checkIns.map { Self.trendValue($0, question).label(for: question) }.joined(separator: ", then ")
        )
    }

    private static func trendValue(_ checkIn: ProgressCheckIn, _ question: ProgressTrend.Question) -> ProgressTrend {
        switch question {
        case .density: return checkIn.density
        case .shedding: return checkIn.shedding
        case .hairline: return checkIn.hairline
        case .overall: return checkIn.overall
        // Not-asked (non-AA, or recorded before this question existed) reads as neutral rather
        // than silently claiming "no change."
        case .patches: return checkIn.patchTrend ?? .same
        }
    }

    private func trendDotColor(_ trend: ProgressTrend) -> Color {
        switch trend {
        case .worse: return Clinical.warning
        case .same: return Clinical.tertiary
        case .better: return Clinical.sage
        }
    }

    /// The scalp and adherence ledger rows need two daily logs in the window. Until then the
    /// section is a chart that hasn't opened — the same shaded placeholder every Trends chart
    /// uses — with the rule and the progress toward it in one pill.
    private var emptyState: some View {
        let answeredCount = windowEntries.filter {
            $0.hasRecorded(.shedding) || $0.hasCompleteScalpRecording
        }.count
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Scalp and adherence")
                ChartPlaceholder(required: 2, have: answeredCount, unit: .dailyLogs)
            }
        }
    }

    // MARK: Baseline context

    private var profile: Profile? { profiles.first }

    private var progressReport: ProgressReport? {
        ProgressReport.build(entries: entries, treatments: treatments, doses: doses, labs: labs,
                             sideEffects: sideEffectLogs, triggers: triggers, missedDoses: missedDoseRecords)
    }

    /// The fixed treatment horizon is only shown for gradual pattern loss, matching the scope of
    /// `currentRead`; other concerns keep their own symptom/photo cadence.
    private var evidencePhase: EvidencePhase? {
        guard profile?.condition == .androgenetic else { return nil }
        return EvidencePhase.current(
            treatments: treatments,
            entries: entries,
            now: .now,
            calendar: .current
        )
    }

    private var currentRead: CurrentProgressRead? {
        // The existing 24-week assessment clock is specific to gradual pattern-loss treatment
        // outcomes; other concerns keep their own symptom/photo cadence.
        guard profile?.condition == .androgenetic else { return nil }
        guard let report = progressReport else { return nil }
        let elapsedDays = max(1, report.weekNumber * 7)
        let coverage = Double(report.entryCount) / Double(elapsedDays)
        let sameRegionCount = Dictionary(grouping: photos, by: \.regionRaw).values.map(\.count).max() ?? 0
        return .evaluate(
            week: report.weekNumber,
            treatmentPhase: report.treatment.map { TreatmentGuide.phase(for: $0.treatmentClass, weeksElapsed: report.weekNumber) } ?? nil,
            honestRead: report.honestRead,
            loggingCoverage: min(1, coverage),
            adherence: report.adherence?.overall,
            monthlyCheckInCount: progressCheckIns.count,
            sameRegionPhotoCount: sameRegionCount
        )
    }

    @ViewBuilder private var currentReadCard: some View {
        if let read = currentRead {
            Button {
                if read.opensPhotos { showCompare = true } else { showReport = true }
            } label: {
                ClinicalCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(BrandArt.medallion)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .blendMode(.multiply)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Eyebrow(text: "Your current read")
                                Text(read.title)
                                    .font(Clinical.headline(20)).foregroundStyle(Clinical.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.accent)
                        }

                    }
                }
            }
            .buttonStyle(.clinicalPressable)
            .accessibilityIdentifier("trendsCurrentRead")
        }
    }

    private func trendReviewLine(_ phase: EvidencePhase) -> String {
        if phase.daysToReview == 0 { return "Review window reached" }
        return "Next review · \(phase.nextReviewDate.formatted(.dateTime.day().month(.abbreviated)))"
    }

    // MARK: At-a-glance trajectory

    /// One quiet annotation line ahead of the chart — a direction glyph plus a single sentence
    /// (direction, delta, coverage) — replacing the old four-part card (icon tile, headline,
    /// body sentence, footer row) that used to say the same fact four ways before the actual
    /// star of the screen. The journey chart below remains the evidence surface.
    private var trajectoryAnnotation: some View {
        let summary = TrajectorySummary(entries: windowEntries)
        return HStack(spacing: 7) {
            Image(systemName: summary.symbol)
                .font(Clinical.body(12, weight: .semibold))
                .foregroundStyle(summary.tint)
            Text(summary.oneLiner)
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    // MARK: Explicitly-not-tracked (honesty made visible)

    /// The app's honesty made visible, demoted from its own card to a quiet small-caps footnote
    /// block that closes the page — every excluded myth's title and reason is unchanged, only the
    /// card edge is gone.
    private var excludedFootnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Clinical.hairline)
            Eyebrow(text: "Explicitly not tracked", color: Clinical.tertiary)
            Text("Left out on purpose — the evidence doesn't support them.")
                .font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ExcludedMyth.allCases) { myth in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·").font(Clinical.body(12, weight: .bold)).foregroundStyle(Clinical.tertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(myth.title).font(Clinical.body(12, weight: .medium)).foregroundStyle(Clinical.secondary)
                            Text(myth.reason).font(Clinical.caption(11)).foregroundStyle(Clinical.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: Scalp severity (unboxed ledger row — the shedding chart above no longer needs an echo)

    /// Round-6: the shedding trend used to get its own second `Chart` here, re-plotting the exact
    /// fact the hero `JourneyChart` already shows. That card is gone; scalp continues in the same
    /// margin-note ledger language as Today's signal ledger — one row, a current reading, a tiny
    /// inline trace, no card.
    private var scalpRow: some View {
        let recorded = windowEntries.filter(\.hasCompleteScalpRecording)
        let raw = recorded.map { Double($0.scalpTotal) }
        let dir = HairAnalytics.direction(raw)
        let (trend, tint) = trendWord(dir, invert: true)
        let latest = recorded.last
        let value = latest.map { "\($0.scalpTotal)/16 · \(trend)" } ?? "Not enough data"
        return VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Clinical.hairline)
            AnnotationRow(
                label: "Scalp",
                value: value,
                logged: latest != nil,
                valueColor: latest == nil ? Clinical.ink : tint,
                trace: latest.map { AnyView(MiniTrace(fraction: min(1, CGFloat($0.scalpTotal) / 16), color: Clinical.ink)) }
            )
        }
    }

    // MARK: Adherence (unboxed ledger rows)

    /// Round-6: dissolved out of its own `ClinicalCard` with a per-treatment progress bar into
    /// continuation rows of the same ledger — the 14-day percentage now lives in the row's own
    /// value slot instead of a separate bar widget.
    @ViewBuilder
    private var adherenceRows: some View {
        // "Daily" is schedule-driven (not class-driven), so `.other`-class items with slots count.
        let daily = treatments.filter { !$0.slots.isEmpty && $0.isActive }
        VStack(alignment: .leading, spacing: 0) {
            if daily.isEmpty {
                AnnotationRow(label: "Adherence", value: "Add a daily treatment in Care", logged: false)
            } else {
                ForEach(daily) { t in
                    // One adherence engine (Important 10 → G2-R16): the same PlanAdherence
                    // occurrence math Today and Care already read, not a second
                    // doseDates/expectedPerDay computation that can silently disagree with it.
                    let consistency = PlanAdherence.consistency(
                        treatment: t, doses: doses, missed: missedDoseRecords,
                        windowDays: 14, now: .now, calendar: .current
                    )
                    if let consistency, consistency.scored > 0 {
                        // A plain ink percentage everywhere the user can see it — never tinted
                        // by an ≥80%-is-good threshold, which reads as an unearned judgment.
                        AnnotationRow(
                            label: t.treatmentClass.title,
                            value: "\(consistency.percent)% · 14d",
                            logged: true,
                            valueColor: Clinical.ink,
                            trace: AnyView(MiniTrace(fraction: CGFloat(consistency.fraction), color: Clinical.ink))
                        )
                    } else {
                        AnnotationRow(
                            label: t.treatmentClass.title,
                            value: "Not enough due actions yet",
                            logged: false
                        )
                    }
                }
            }
            Divider().overlay(Clinical.hairline)
        }
    }

    /// Direction word + tint shared by every trend row — replaces the old chart-header
    /// `directionTag` Label now that scalp reads as ledger text instead of a chart title.
    private func trendWord(_ dir: Double, invert: Bool) -> (String, Color) {
        let improving = invert ? dir < -0.05 : dir > 0.05
        let worsening = invert ? dir > 0.05 : dir < -0.05
        if improving { return ("Improving", Clinical.positive) }
        if worsening { return ("Rising", Clinical.warning) }
        return ("Steady", Clinical.tertiary)
    }
}

/// A small, deterministic interpretation of recent self-reported shedding. It compares two
/// adjacent seven-day calendar windows and keeps thin-data language explicit.
/// Internal (not file-private) so its wash-day-hedge logic is unit-testable.
struct TrajectorySummary {
    let currentAverage: Double?
    let currentCount: Int
    let previousCount: Int
    let delta: Double?
    /// Wash days logged in each seven-day window — the confound behind a false "shedding rose"
    /// read (shed hair is far more visible on wash days than dry ones).
    let currentWashDays: Int
    let previousWashDays: Int

    init(entries: [DailyEntry], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let currentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today

        let answered = entries.filter { $0.hasRecorded(.shedding) }
        let current = answered.filter { $0.date >= currentStart && $0.date < tomorrow }
        let previous = answered.filter { $0.date >= previousStart && $0.date < currentStart }

        currentCount = current.count
        previousCount = previous.count
        currentWashDays = current.filter(\.washedHair).count
        previousWashDays = previous.filter(\.washedHair).count
        currentAverage = Self.average(current)
        if let currentAverage, let previousAverage = Self.average(previous) {
            delta = currentAverage - previousAverage
        } else {
            delta = nil
        }
    }

    /// Only surfaced once a delta is actually being reported, and only when the two windows'
    /// wash-day counts genuinely differ — never new data, just an honest caveat on the claim
    /// already being made.
    var washDayHedge: String? {
        guard let delta, hasComparableWindows, abs(delta) >= 0.25 else { return nil }
        guard currentWashDays != previousWashDays else { return nil }
        return " This week had \(currentWashDays) wash day\(currentWashDays == 1 ? "" : "s") vs \(previousWashDays) last week — wash days show more shed."
    }

    var headline: String {
        guard currentAverage != nil else { return "No recent check-ins yet" }
        guard let delta, hasComparableWindows else {
            return "Your recent baseline is forming"
        }
        if delta <= -0.25 { return "Shedding may be lower this week" }
        if delta >= 0.25 { return "Shedding may be higher this week" }
        return "Shedding has been steady this week"
    }

    var detail: String {
        guard currentAverage != nil else {
            return "Log today to start a seven-day view of your pattern."
        }
        guard let delta, hasComparableWindows else {
            return "A week-to-week read opens after five logged days in each adjacent week."
        }
        let magnitude = abs(delta).formatted(.number.precision(.fractionLength(1)))
        if abs(delta) < 0.25 {
            return "The seven-day average is very close to the prior week."
        }
        return "A \(magnitude)-band change versus the previous seven-day average." + (washDayHedge ?? "")
    }

    var symbol: String {
        guard let delta, hasComparableWindows else {
            return "chart.line.uptrend.xyaxis"
        }
        if delta <= -0.25 { return "arrow.down.right" }
        if delta >= 0.25 { return "arrow.up.right" }
        return "arrow.right"
    }

    var tint: Color {
        guard let delta, hasComparableWindows else { return Clinical.accent }
        if delta <= -0.25 { return Clinical.positive }
        if delta >= 0.25 { return Clinical.warning }
        return Clinical.sage
    }

    var coverageLabel: String { "\(min(currentCount, 7)) of 7 days logged" }

    var confidenceLabel: String {
        switch currentCount {
        case 5...: return "Good coverage"
        case 3...4:
            let remaining = 5 - currentCount
            return "Log \(remaining) more day\(remaining == 1 ? "" : "s") to firm this up"
        default: return "Limited coverage"
        }
    }

    /// The card's headline stat: once two comparable seven-day windows exist, the number IS the
    /// delta the body copy describes ("A 0.5-band change…") — captioned and colored to match, so
    /// the big number and the sentence underneath it can never contradict each other. Before that
    /// (baseline still forming), there's no delta to show, so it falls back to the plain current
    /// average captioned for exactly what it is.
    var heroStat: (value: String, caption: String, isDelta: Bool)? {
        if let delta, hasComparableWindows {
            let text = delta.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))
            return (text, "BANDS VS LAST WK", true)
        }
        if let currentAverage {
            return (currentAverage.formatted(.number.precision(.fractionLength(1))), "7D AVG", false)
        }
        return nil
    }

    var accessibilityLabel: String {
        "At a glance. \(headline). \(detail) \(coverageLabel). \(confidenceLabel)."
    }

    /// The decongested Trends header: direction, delta and coverage in one breath, replacing
    /// the old four-part card (icon tile, headline, detail sentence, footer row). Never
    /// contradicts `headline`/`heroStat` — same underlying numbers, just one sentence.
    var oneLiner: String {
        guard currentAverage != nil else {
            return "Log today to start your seven-day view."
        }
        guard let delta, hasComparableWindows else {
            return "Your baseline is forming · \(coverageLabel)."
        }
        if abs(delta) < 0.25 {
            return "Shedding steady this week · \(coverageLabel)."
        }
        let direction = delta <= -0.25 ? "possibly lower" : "possibly higher"
        let magnitude = delta.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))
        return "Shedding \(direction) this week · \(magnitude) vs last wk · \(coverageLabel)."
    }

    private static func average(_ entries: [DailyEntry]) -> Double? {
        guard !entries.isEmpty else { return nil }
        return entries.reduce(0) { $0 + Double($1.shed.rawValue) } / Double(entries.count)
    }

    private var hasComparableWindows: Bool { currentCount >= 5 && previousCount >= 5 }
}
