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
    let feature: String
    let symbol: String
    var description: String = "Included with Hair Compass Pro."
    @ViewBuilder var content: () -> Content

    @Environment(PurchaseService.self) private var purchases
    @Environment(\.scenePhase) private var scenePhase
    /// Only for picking the matching illustration pair — the gate itself stays profile-agnostic.
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    /// The product ID currently mid-purchase, or `nil`. A per-product id (not a plain `Bool`) so
    /// only the button the user actually tapped shows its spinner.
    @State private var purchasingProductID: String?
    @State private var yearlyIntroEligible = false
    @State private var monthlyIntroEligible = false
    /// Bumped on every return to the foreground. `ProAvailability.current` is a static system
    /// read SwiftUI does not track, so without this the gate would stay stale — a person who
    /// follows the notice, enables Apple Intelligence in Settings, and comes back would still
    /// see the purchase buttons withheld until an app restart.
    @State private var availabilityRefresh = 0

    private var isBusy: Bool { purchasingProductID != nil || purchases.isRestoring }

    /// Read fresh on every body evaluation, and invalidated by `availabilityRefresh` when the
    /// app foregrounds: Apple Intelligence can be switched on, or finish downloading, while
    /// this gate is on screen or while the person is away in Settings.
    private var availability: OnDeviceAvailability {
        _ = availabilityRefresh
        return ProAvailability.current
    }

    var body: some View {
        if purchases.hasPro {
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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { availabilityRefresh += 1 }
                }
                // While the model can't run, re-check every 2 s: the foreground bump alone
                // misses the person who stays on this screen while the model finishes
                // downloading — without this, the buttons would never appear for them.
                .task(id: availability.isAvailable) {
                    guard !availability.isAvailable else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        availabilityRefresh += 1
                    }
                }
        }
    }

    private var locked: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            Image(systemName: symbol)
                .font(Clinical.body(26, weight: .medium))
                .foregroundStyle(Clinical.accent)
                .frame(width: 60, height: 60)
                .background(Clinical.accentSoft, in: Circle())

            VStack(spacing: 6) {
                Text(feature)
                    .font(Clinical.headline(20))
                    .foregroundStyle(Clinical.ink)
                Text(description)
                    .font(Clinical.caption(13))
                    .foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Same component as the onboarding paywall, so both conversion surfaces make the
            // identical (and identically bounded) promise. `.compact` because this one lives
            // inside a sheet alongside the feature's own chrome.
            ClarityContrast(size: .compact, sex: profiles.first?.sex ?? .male)

            // Above the price, always: this gate's own feature is one of the two that need Apple
            // Intelligence, so an unavailable model is the single most important thing on screen.
            ProAvailabilityNotice(status: availability)

            if !ProAvailability.sellable(availability) {
                // No purchase while the model can't run right now (off, downloading, or
                // ineligible hardware) — the notice above says which and how to fix it. Restore
                // and the legal footer stay below, so an existing subscriber isn't stranded.
                EmptyView()
            } else if !purchases.products.isEmpty {
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

            PaywallLegal(showsRenewalDisclosure: ProAvailability.sellable(availability))

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
