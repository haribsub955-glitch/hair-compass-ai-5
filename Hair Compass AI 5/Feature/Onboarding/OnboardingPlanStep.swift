import StoreKit
import SwiftUI

/// Presentation only: StarterPlan, AccessWindow and PurchaseService remain the sources of truth.
struct OnboardingPlanStep: View {
    let profile: Profile
    var onBack: () -> Void
    var onContinue: () -> Void

    @Environment(PurchaseService.self) private var purchases
    @Environment(AccessWindow.self) private var accessWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = Self.initialPhase
    @State private var selectedID = PurchaseService.yearlyID
    @State private var purchasingProductID: String?
    @State private var introEligibility: [String: Bool] = [:]
    @State private var availabilityRefresh = 0
    @Namespace private var selection

    private var isBusy: Bool { purchasingProductID != nil || purchases.isRestoring }
    private var still: Bool { reduceMotion || MotionQA.isStatic }
    private var items: [StarterPlanItem] { StarterPlan.items(for: .fresh(profile: profile)) }
    private var products: [Product] { [purchases.yearly, purchases.monthly].compactMap { $0 } }
    private var selectedProduct: Product? { products.first { $0.id == selectedID } ?? products.first }
    private var eligibilityTaskID: String { "\(products.map(\.id).joined())-\(scenePhase == .active)" }

    private static var initialPhase: OnboardingOfferPhase {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("HC_PAYWALL_BOTTOM") { return .pricing }
        if let index = args.firstIndex(of: "HC_OFFER_PHASE"), index + 1 < args.count,
           let phase = OnboardingOfferPhase(rawValue: args[index + 1]) { return phase }
        #endif
        return .plan
    }

    var body: some View {
        VStack(spacing: 0) {
            navigation
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header.id("offerTop")
                        OnboardingPlanCards(items: OnboardingPlanSummary.items(from: items), compact: phase != .plan)
                        phaseContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
                }
                .onChange(of: phase) { _, _ in
                    proxy.scrollTo("offerTop", anchor: .top)
                }
            }
            onward
        }
        .task(id: eligibilityTaskID) {
            guard scenePhase == .active else { return }
            introEligibility = [:]
            for product in products {
                let eligible = await purchases.isEligibleForIntro(product)
                guard !Task.isCancelled else { return }
                introEligibility[product.id] = eligible
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            availabilityRefresh += 1
            var last = ProAvailability.current
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    let now = ProAvailability.current
                    if now != last { last = now; availabilityRefresh += 1 }
                }
            } catch { /* No polling while backgrounded or after leaving. */ }
        }
        .onDisappear { purchases.resetPurchaseState() }
    }

    private var navigation: some View {
        HStack {
            Button {
                if let previous = phase.previous { move(to: previous) } else { onBack() }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(Clinical.body(13, weight: .medium))
                    .foregroundStyle(Clinical.secondary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("onboardOfferBack")
            Spacer()
            Text(phase == .plan ? "YOUR PLAN" : phase == .preview ? "A CLOSER LOOK" : "YOUR CHOICE")
                .font(Clinical.eyebrow(10))
                .foregroundStyle(Clinical.secondary)
                .accessibilityIdentifier("onboardOfferPhase")
        }
        .padding(.horizontal, 20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            if phase != .preview {
                OnboardingIllustration(name: phase == .plan ? OnboardingArt.journal : OnboardingArt.support,
                                       height: phase == .plan ? 134 : 106)
            }
            Text(phase == .plan ? "A small place to begin."
                 : phase == .preview ? "Small notes. A clearer record."
                 : purchases.hasPro ? "Your support is already here."
                 : "A little more support.")
                .font(Clinical.headline(28))
                .foregroundStyle(Clinical.ink)
                .accessibilityAddTraits(.isHeader)
            Text(phase == .plan
                 ? planIntroduction
                 : phase == .preview
                 ? "See how a check-in finds its place over time."
                 : "Your starting plan stays with you. Choose how you’d like to keep building your record.")
                .font(Clinical.caption(14))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planIntroduction: String {
        if profile.condition == .unsure {
            return "You don’t need to have it all figured out. Your answers give us a place to start."
        }
        return "Based on your answers about \(profile.condition.plainTitle.lowercased()). Take these at your own pace."
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .plan:
            Text("You don’t need to do everything today. These steps stay on your Plan tab, ready when you are.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
            OnboardingPlanDetails(items: items)
        case .preview:
            OnboardingRecordPreview()
            Text("Pro brings your check-ins, photos, labs and trends together. Ask \(Companion.name) for a plain-language reading, never a diagnosis.")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .pricing:
            pricing
        }
    }

    private var pricing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PRO INCLUDES")
                .font(Clinical.eyebrow(10)).foregroundStyle(Clinical.accent)
            Text("Daily check-ins · trends · photos · labs · clinician reports\n\(Companion.name) conversations & deep record analysis")
                .font(Clinical.caption(13))
                .foregroundStyle(Clinical.ink)
                .fixedSize(horizontal: false, vertical: true)
            let _ = availabilityRefresh
            ProAvailabilityNotice(status: ProAvailability.current)

            if purchases.hasPro {
                Label("Pro is already active", systemImage: "checkmark.circle")
                    .font(Clinical.body(15, weight: .medium))
                    .foregroundStyle(Clinical.positive)
                    .accessibilityIdentifier("onboardProActive")
            } else if products.isEmpty {
                StoreUnavailableView(isLoading: purchases.isLoading) {
                    Task { await purchases.load() }
                }
            } else {
                VStack(spacing: 9) {
                    ForEach(products) { product in productChoice(product) }
                }
                if let product = selectedProduct {
                    let copy = OnboardingPriceCopy(product: product, introEligible: introEligibility[product.id] == true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(copy.detail)
                            .font(Clinical.caption(12))
                            .foregroundStyle(Clinical.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboardBillingDisclosure")
                            .transaction { $0.animation = nil }
                        Button { buy(product) } label: {
                            PurchaseButtonLabel(isPurchasing: purchasingProductID == product.id, tint: Clinical.surface) {
                                Text(copy.action)
                            }
                        }
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(isBusy || introEligibility[product.id] == nil)
                        .opacity(isBusy || introEligibility[product.id] == nil ? 0.6 : 1)
                        .accessibilityIdentifier("onboardBuySelectedPlan")
                        if introEligibility[product.id] == nil {
                            Text("Checking available offers…")
                                .font(Clinical.caption(11)).foregroundStyle(Clinical.secondary)
                        }
                    }
                }
            }
            PurchaseStatusLine(purchaseState: purchases.purchaseState, restoreResult: purchases.restoreResult)
            Text(CloudAIConfig.current.isConfigured
                 ? "Cloud AI is optional and asks for your consent first. Entries are sent without your name or photos."
                 : "AI features use Apple Intelligence on supported devices. Your record stays on your phone.")
                .font(Clinical.caption(11))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(accessWindow.isActive
                 ? "Your current introductory access needs no purchase and won’t auto-renew. Medication logging stays free afterward."
                 : "Medication logging stays free. Pro is needed for check-ins, trends, photos, labs and AI features.")
                .font(Clinical.caption(12))
                .foregroundStyle(Clinical.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task {
                    await purchases.restore()
                    if purchases.hasPro { onContinue() }
                }
            } label: {
                HStack(spacing: 8) {
                    if purchases.isRestoring { ProgressView().tint(Clinical.secondary) }
                    Text("Restore purchases")
                        .font(Clinical.body(13, weight: .medium))
                        .foregroundStyle(Clinical.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("onboardRestorePurchases")
            PaywallLegal(showsRenewalDisclosure: !purchases.hasPro)
        }
    }

    private func productChoice(_ product: Product) -> some View {
        let selected = selectedProduct?.id == product.id
        let copy = OnboardingPriceCopy(product: product, introEligible: introEligibility[product.id] == true)
        return Button {
            withAnimation(still ? nil : .easeInOut(duration: MotionSpec.onboarding.selection)) {
                selectedID = product.id
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Clinical.accent : Clinical.secondary)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.id == PurchaseService.yearlyID ? "Yearly" : "Monthly")
                        .font(Clinical.body(15, weight: .medium))
                    Text(copy.price + " / " + (product.subscription.map {
                        OnboardingPriceCopy.period($0.subscriptionPeriod.value, unit: $0.subscriptionPeriod.unit)
                    } ?? "period"))
                        .font(Clinical.body(15, weight: .semibold))
                    if introEligibility[product.id] == true, product.subscription?.introductoryOffer != nil {
                        Text(copy.detail)
                            .font(Clinical.caption(11))
                            .foregroundStyle(Clinical.secondary)
                    }
                }
                .foregroundStyle(Clinical.ink)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(Clinical.surface)
                if selected {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Clinical.accentSoft)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Clinical.accent.opacity(0.55)))
                        .matchedGeometryEffect(id: "selected-plan", in: selection)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Clinical.hairline, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(product.id == PurchaseService.yearlyID ? "onboardPurchaseYearly" : "onboardPurchaseMonthly")
    }

    private var onward: some View {
        VStack(spacing: 2) {
            if let next = phase.next {
                Button(phase == .plan ? "See how it comes together" : "Explore Pro") { move(to: next) }
                    .buttonStyle(ClinicalButtonStyle())
                    .accessibilityIdentifier("onboardOfferNext")
            }
            Button(purchases.hasPro ? "Continue to my plan" : "Continue free", action: onContinue)
                .font(Clinical.body(15, weight: .medium))
                .foregroundStyle(Clinical.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("onboardContinueFree")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Clinical.canvas)
    }

    private func move(to destination: OnboardingOfferPhase) {
        guard !isBusy else { return }
        withAnimation(still ? nil : .easeInOut(duration: MotionSpec.onboarding.settle)) { phase = destination }
    }

    private func buy(_ product: Product) {
        guard !isBusy, introEligibility[product.id] != nil else { return }
        purchasingProductID = product.id
        Task {
            let bought = await purchases.purchase(product)
            purchasingProductID = nil
            if bought { onContinue() }
        }
    }
}
