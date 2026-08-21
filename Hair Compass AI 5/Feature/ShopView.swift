import SwiftData
import SwiftUI

/// The Guide tab: what's worth buying, and which procedures are worth considering —
/// deliberately outside the wall.
///
/// Reframed from a storefront by owner ruling (2026-08-21): this surface exists to help someone
/// DECIDE — the personalized recommender first, the in-clinic catalogue beside it, the
/// evidence-graded product list under both. It is still the app's revenue surface (the product
/// links are affiliate-ready, which is why it stays free on every tier — a link earns nothing
/// from someone who cannot reach it), but the framing is advice with a disclosure, never a
/// checkout. It used to live inside `CareView` — which this release puts behind Pro — so it
/// moved here rather than being locked away from exactly the free users it exists to serve.
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
    /// "May earn": the shipped catalogue links carry no affiliate tag yet, so a flat "earn"
    /// would claim a commission that doesn't exist — and "may" stays true after a tag lands.
    static let affiliateDisclosure =
        "Some links here may earn us a commission if you buy. It never changes the price you pay, "
        + "and it never affects which products appear or how they're ranked."

    /// The one-line variant for screens that show a single outbound product link outside this
    /// tab (e.g. `LabProposalCard` on Labs), where the full body-text paragraph would outweigh
    /// the card it sits in.
    static let linkDisclosureShort = "Link may earn us a commission. It never changes the price you pay."

    @State private var showInClinicOptions = false
    /// A separate presentation point from `CareView`'s own `showProcedures` (the person's booked
    /// appointment ledger) — this one only ever opens `ProceduresView` for the Recommender's
    /// `.scheduleDoctorVisit` action, and that view carries its own `.proGated(.procedures)`, so
    /// no entitlement check is needed here either.
    @State private var showProcedures = false
    /// 0…1 fraction driving the header's scroll-condense (see `ScreenHeader.condensed`) — same
    /// idiom as `TrendsView`/`CareView`. Task 9 fix-round: Shop is a primary tab now, so it should
    /// carry the same header behavior every other tab does, not a plain static title.
    @State private var headerCondense: CGFloat = 0
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
                ScreenHeader(eyebrow: "Evidence", title: "Guide", condensed: headerCondense)
                    .padding(.top, 8)
                    // Same header-wash idiom as Trends/Plan: `art-guidance` (a stethoscope/plant
                    // still life) states the screen's subject before a single card renders.
                    // Previously lived on `RecommenderView`'s own now-retired header — the section
                    // moved inline, the wash moved up to the page header it used to duplicate.
                    .background(alignment: .top) {
                        BrandWash(art: BrandArt.guidance, height: 150, opacity: 0.5, fade: 0.55)
                            .padding(.horizontal, -20)
                            .offset(y: -8)
                    }

                Text(Self.affiliateDisclosure)
                    .font(Clinical.caption(12))
                    .foregroundStyle(Clinical.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("affiliateDisclosure")

                // The procedures half of this page's job, in the FIRST screenful. It used to be
                // one bordered button below the entire 16-product catalogue — roughly ten screens
                // of scrolling down — which meant, in practice, that nobody ever saw it. "Which
                // procedure should I go with" is half of what this tab exists to answer, so it
                // leads the page: one compact banner card, then the personalized recommendations
                // own everything below. (InClinicOptionsView itself is education-only and carries
                // no links, so leading with it under the disclosure sells nothing.)
                inClinicCard

                // Section-shaped, not screen-shaped (Task 9 fix-round) — `RecommenderView` used to
                // be a full sheet destination with its own `ScrollView`/`ScreenHeader`/
                // `.clinicalScreen()`. Embedding that as-is nested a vertical scroll inside this
                // one and could capture the pan before it ever reached the product rows below, on
                // top of a doubled header/canvas/bleed. It now renders only its option cards, at
                // the same 20pt inset as everything else on this page.
                RecommenderView(condition: profile?.condition ?? .unsure, sex: profile?.sex ?? .male) { action in
                    presentRecommendedAction(action)
                }

                ScienceProductsSection().id("science")

                // Closes the tab like every other primary screen (Today, Trends, Plan) — this was
                // the one `ScreenHeader` tab missing this ending.
                PageCloser(opacity: 0.8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Condenses the header's serif title as the page scrolls — same 1:1 offset tracking as
        // every other primary tab (`CareView`, `TrendsView`, `LabsView`, `PhotosView`).
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, newY in
            headerCondense = Clinical.headerCondenseFraction(newY)
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

    /// The entry into `InClinicOptionsView` — the read-before-you-book procedures catalogue
    /// (PRP, transplant, microneedling…), each graded on the app's shared evidence scale. Same
    /// banner-image card family as `ScienceProductsSection` so the page's two halves — products
    /// below, procedures here — read as siblings. The whole card is one button.
    private var inClinicCard: some View {
        Button { showInClinicOptions = true } label: {
            ClinicalCard {
                VStack(alignment: .leading, spacing: 12) {
                    Image("procedure-consultation")
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity).frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    HStack(spacing: 8) {
                        Eyebrow(text: "In-clinic options")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Clinical.caption(12))
                            .foregroundStyle(Clinical.accent)
                    }
                    Text("What clinics offer for hair loss — PRP, transplants, microneedling and more — each graded by how strong the evidence actually is, with the caution worth raising first.")
                        .font(Clinical.caption(13)).foregroundStyle(Clinical.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("In-clinic options")
        .accessibilityHint("Opens the procedures catalogue")
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
