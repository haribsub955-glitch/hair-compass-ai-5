import SwiftData
import SwiftUI

/// The storefront, deliberately outside the wall.
///
/// This is a revenue surface, not a feature: an affiliate link earns nothing from someone who
/// cannot reach it, so gating this would cost money rather than make it. It used to live inside
/// `CareView` — which this release puts behind Pro — so it moved here rather than being locked
/// away from exactly the free users it exists to serve.
///
/// `RecommenderView` is free to browse for the same reason, but the actions it hands back
/// (`RecommendedAction`) write into features that are not — add-to-plan, a patch photo series, a
/// lab result. `presentRecommendedAction` below is the same gating `CareView` used to run before
/// the Recommender moved here: it swaps in that feature's paywall instead of the real write
/// destination on a free tier, rather than silently granting it. `ScienceProductsSection`'s own
/// "Add to plan" tap gates itself the same way, independently — see `ScienceProductsView.swift`.
struct ShopView: View {
    @Environment(\.entitlements) private var entitlements
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    /// Shown above the product list, in body text rather than a footnote — 16 CFR Part 255
    /// wants it clear and conspicuous, and this codebase's honesty rules want it plain.
    static let affiliateDisclosure =
        "Some links here earn us a commission if you buy. It never changes the price you pay, "
        + "and it never affects which products appear or how they're ranked."

    @State private var showInClinicOptions = false
    /// A separate presentation point from `CareView`'s own `showProcedures` (the person's booked
    /// appointment ledger) — this one only ever opens `ProceduresView` for the Recommender's
    /// `.scheduleDoctorVisit` action, and that view carries its own `.proGated(.procedures)`, so
    /// no entitlement check is needed here either.
    @State private var showProcedures = false
    @State private var recommendedTreatmentClass: TreatmentClass?
    @State private var showRecommendedLab = false
    @State private var recommendedLabTest: LabTest = .ferritin
    @State private var showRecommendedTrigger = false
    @State private var showRecommendedPhoto = false
    /// Non-nil when a free-tier tap on a `RecommenderView` action targets a gated destination
    /// (add-to-plan, patch photo series, add lab result) — presents that feature's paywall
    /// instead of the write-destination itself. See `presentRecommendedAction`.
    @State private var recommendedGate: ProFeature?

    private var profile: Profile? { profiles.first }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Shop", title: "Products & options")
                    .padding(.top, 8)

                Text(Self.affiliateDisclosure)
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("affiliateDisclosure")

                RecommenderView(condition: profile?.condition ?? .unsure, sex: profile?.sex ?? .male) { action in
                    presentRecommendedAction(action)
                }

                ScienceProductsSection().id("science")

                Button("In-clinic options") { showInClinicOptions = true }
                    .buttonStyle(ClinicalButtonStyle(filled: false))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_INCLINIC") { showInClinicOptions = true }
            if ProcessInfo.processInfo.arguments.contains("HC_SCROLL_PRODUCTS") {
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { proxy.scrollTo("science", anchor: .top) }
            }
            #endif
        }
        }
        .clinicalScreen()
        .sheet(isPresented: $showInClinicOptions) { InClinicOptionsView() }
        .sheet(isPresented: $showProcedures) { ProceduresView() }
        .sheet(item: $recommendedTreatmentClass) { AddTreatmentSheet(initialClass: $0) }
        .sheet(isPresented: $showRecommendedLab) { AddLabSheet(initialTest: recommendedLabTest) }
        .sheet(isPresented: $showRecommendedTrigger) { AddTriggerSheet() }
        .sheet(isPresented: $showRecommendedPhoto) { GuidedCaptureView(defaultRegion: .frontal) }
        .sheet(item: $recommendedGate) { feature in
            NavigationStack {
                // Entitled users never linger here: once ProGate sees access, it renders this
                // clear placeholder, which immediately dismisses the sheet on appear — same
                // idiom as TodayView's history paywall.
                ProGate(feature: feature) {
                    Color.clear.onAppear { recommendedGate = nil }
                }
                .clinicalScreen()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { recommendedGate = nil } } }
            }
        }
    }

    /// `RecommenderView` itself is deliberately free on every tier, but the actions it hands
    /// back write into features that are not (treatments, photos, labs) — so each of those
    /// cases checks entitlement first and swaps in that feature's paywall (`recommendedGate`)
    /// rather than opening the real destination for a free user. `.scheduleDoctorVisit` needs no
    /// check here: it opens `ProceduresView`, which already carries its own `.proGated(.procedures)`.
    /// `.recordTrigger` needs none either: `TriggerEvent` logging has no `ProFeature` of its own.
    private func presentRecommendedAction(_ action: RecommendedAction) {
        switch action {
        case .addToPlan(let treatmentClass):
            guard entitlements.canAccess(.treatments) else { recommendedGate = .treatments; return }
            recommendedTreatmentClass = treatmentClass
        case .scheduleDoctorVisit: showProcedures = true
        case .startPatchPhotoSeries:
            guard entitlements.canAccess(.photos) else { recommendedGate = .photos; return }
            showRecommendedPhoto = true
        case .recordTrigger: showRecommendedTrigger = true
        case .addLabResult(let test):
            guard entitlements.canAccess(.labs) else { recommendedGate = .labs; return }
            recommendedLabTest = test; showRecommendedLab = true
        case .reviewPregnancyCaution:
            guard entitlements.canAccess(.treatments) else { recommendedGate = .treatments; return }
            recommendedTreatmentClass = .spironolactone
        }
    }
}
