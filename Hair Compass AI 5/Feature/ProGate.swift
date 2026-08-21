import StoreKit
import SwiftData
import SwiftUI

/// Wraps premium content: shows it for Pro users, otherwise an inline, honest upsell
/// (feature name + a one-line description + the two Pro purchase buttons + restore). Used by
/// the AI sheets — gate at the caller's top level so the sheet's own chrome (title, Close
/// button) stays outside the gate and is always reachable. Purchase buttons never show a
/// placeholder price: while products haven't loaded they're replaced by `StoreUnavailableView`
/// (a loading spinner, or an honest "can't reach the store" message with Retry), matching
/// `OnboardingPlanStep`'s honesty rules. Does not apply its own background — callers already own
/// `.clinicalScreen()`.
struct ProGate<Content: View>: View {
    let feature: ProFeature
    @ViewBuilder var content: () -> Content

    @Environment(PurchaseService.self) private var purchases
    @Environment(\.entitlements) private var entitlements
    /// Only for picking the matching illustration pair — the gate itself stays profile-agnostic.
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    /// The product ID currently mid-purchase, or `nil`. A per-product id (not a plain `Bool`) so
    /// only the button the user actually tapped shows its spinner.
    @State private var purchasingProductID: String?
    @State private var yearlyIntroEligible = false
    @State private var monthlyIntroEligible = false

    private var isBusy: Bool { purchasingProductID != nil || purchases.isRestoring }

    /// Read fresh on every body evaluation rather than cached in `@State`: Apple Intelligence can
    /// be switched on, or finish downloading, while this gate is on screen.
    private var availability: OnDeviceAvailability { ProAvailability.current }

    var body: some View {
        if entitlements.canAccess(feature) {
            content()
        } else {
            locked
                .task(id: purchases.yearly?.id) {
                    guard let yearly = purchases.yearly else { return }
                    yearlyIntroEligible = await purchases.isEligibleForIntro(yearly)
                }
                .task(id: purchases.monthly?.id) {
                    guard let monthly = purchases.monthly else { return }
                    monthlyIntroEligible = await purchases.isEligibleForIntro(monthly)
                }
                // A failed/pending message from THIS gate shouldn't still be showing if the user
                // dismisses it and opens a different feature's gate later.
                .onDisappear { purchases.resetPurchaseState() }
        }
    }

    /// Tracks the gate ScrollView's own viewport height so `lockedBody` can centre in it. Inside
    /// a ScrollView the height proposal is nil, so the old `.frame(maxHeight: .infinity)` did
    /// nothing and the card hugged the top of the full-screen gates (Photos, Compare,
    /// Procedures) with all the leftover space piled below the legal links. Deliberately NOT a
    /// `GeometryReader` around the ScrollView: on the nested surfaces (CareView, TrendsView,
    /// LabsView put `.proGated(_:)` inside their own ScrollView) an unconstrained GeometryReader
    /// falls back to its 10pt ideal height and would collapse the gate outright. For a nested,
    /// unconstrained ScrollView `containerSize` is its own content-sized frame, so `minHeight`
    /// resolves to the height it already has — a no-op exactly where centring must not meddle.
    @State private var gateViewportHeight: CGFloat = 0

    /// Scrollable: `CompareView`/`ProceduresView` apply `.proGated(_:)` in place of their own
    /// `ScrollView`, so at large accessibility text sizes this card was tall enough to push its
    /// own purchase buttons off-screen — a paywall that hides the thing it exists to offer.
    private var locked: some View {
        ScrollView {
            lockedBody
                .frame(minHeight: gateViewportHeight > 0 ? gateViewportHeight : nil)
        }
        // Several surfaces (CareView, TrendsView, LabsView…) apply `.proGated(_:)` INSIDE their
        // own ScrollView, so this one is nested. `.basedOnSize` keeps it inert whenever the card
        // already fits — no bounce, no captured pan — and it only becomes a real scroll view at
        // the accessibility sizes this exists for.
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.height }) { _, new in
            gateViewportHeight = new
        }
    }

    private var lockedBody: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            Image(systemName: feature.gateSymbol)
                .font(Clinical.body(26, weight: .medium))
                .foregroundStyle(Clinical.accent)
                .frame(width: 60, height: 60)
                .background(Clinical.accentSoft, in: Circle())

            VStack(spacing: 6) {
                Text(feature.gateTitle)
                    .font(Clinical.headline(20))
                    .foregroundStyle(Clinical.ink)
                Text(feature.gateDescription)
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Same component as the onboarding paywall, so both conversion surfaces make the
            // identical (and identically bounded) promise. `.compact` because this one lives
            // inside a sheet alongside the feature's own chrome.
            ClarityContrast(size: .compact, sex: profiles.first?.sex ?? .male)

            // The notice only speaks for features that actually need the on-device model, so
            // gating Trends never tells someone their iPhone is the problem — and with the
            // cloud model configured `canRun` is true for everything, so no gate warns at all.
            // Asked through `canRun` rather than `usesAI` directly so the tested policy
            // function is the shipping one, not a parallel copy. `.deviceNotEligible` here is
            // deliberately hardcoded, not the live `availability` — this is a worst-case probe
            // ("could this feature ever be device-limited at all?"), independent of whatever
            // this particular iPhone's status actually is; the live status still drives what
            // `ProAvailabilityNotice` renders when this check passes.
            if !ProAvailability.canRun(feature, status: .deviceNotEligible) {
                ProAvailabilityNotice(status: availability)
            }

            // The purchase buttons are UNCONDITIONAL on Apple Intelligence — see
            // `ProAvailability.showsPurchaseButtons`, which is where that rule is asserted. Even
            // where this particular feature can never run, the subscription still unlocks the
            // other ten, so withdrawing the sale would be wrong — it is what left ineligible
            // iPhones with nothing to buy.
            if ProAvailability.showsPurchaseButtons(status: availability, hasLoadedProducts: !purchases.products.isEmpty) {
                purchaseButtons
            } else {
                StoreUnavailableView(isLoading: purchases.isLoading) {
                    Task { await purchases.load() }
                }
            }

            PurchaseStatusLine(purchaseState: purchases.purchaseState, restoreResult: purchases.restoreResult)

            Button {
                Task { await purchases.restore() }
            } label: {
                HStack(spacing: 6) {
                    if purchases.isRestoring {
                        ProgressView().tint(Clinical.tertiary)
                    }
                    Text("Restore purchases")
                        .font(Clinical.caption(12))
                        .foregroundStyle(Clinical.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            PaywallLegal(showsRenewalDisclosure: true)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        // Width only. `maxHeight: .infinity` was dead code inside the ScrollView (nil height
        // proposal); vertical filling is the `minHeight:` in `locked`, where the viewport is known.
        .frame(maxWidth: .infinity)
    }

    private var purchaseButtons: some View {
        VStack(spacing: 10) {
            if let yearly = purchases.yearly {
                // Eligibility-gated: the launch offer only renders for Apple IDs that
                // haven't already used the group's introductory offer.
                let offer = yearlyIntroEligible ? purchases.launchOffer(for: yearly) : nil
                VStack(spacing: 8) {
                    if let offer {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(offer.base)
                                .font(Clinical.caption(14))
                                .strikethrough()
                                .foregroundStyle(Clinical.tertiary)
                            Text(offer.intro)
                                .font(Clinical.body(18, weight: .semibold))
                                .foregroundStyle(Clinical.ink)
                            Text("/year")
                                .font(Clinical.caption(13))
                                .foregroundStyle(Clinical.secondary)
                        }
                    }
                    Button {
                        buy(yearly)
                    } label: {
                        PurchaseButtonLabel(isPurchasing: purchasingProductID == yearly.id, tint: Clinical.surface) {
                            VStack(spacing: 2) {
                                if let offer {
                                    Text("Start yearly — \(offer.intro) first year")
                                    Text("First year — save \(offer.percentOff)%, then \(offer.base)/year · Limited-time")
                                        .font(Clinical.body(11, weight: .regular))
                                } else {
                                    Text("Yearly — \(yearly.displayPrice)/year")
                                    if let perMonth = yearly.monthlyEquivalentDisplay {
                                        Text(perMonth).font(Clinical.body(11, weight: .regular))
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(ClinicalButtonStyle())
                    .disabled(isBusy)
                    .accessibilityIdentifier("proGatePurchaseYearly")
                }
            }
            if let monthly = purchases.monthly {
                let trialText = monthlyIntroEligible ? purchases.trialDescriptor(for: monthly) : nil
                Button {
                    buy(monthly)
                } label: {
                    PurchaseButtonLabel(isPurchasing: purchasingProductID == monthly.id, tint: Clinical.ink) {
                        if let trialText {
                            Text("\(trialText)/month")
                        } else {
                            Text("Monthly — \(monthly.displayPrice)/month")
                        }
                    }
                }
                .buttonStyle(ClinicalButtonStyle(filled: false))
                .disabled(isBusy)
                .accessibilityIdentifier("proGatePurchaseMonthly")
            }
        }
    }

    private func buy(_ product: Product) {
        guard !isBusy else { return }
        purchasingProductID = product.id
        Task {
            await purchases.purchase(product)
            purchasingProductID = nil
        }
    }
}
