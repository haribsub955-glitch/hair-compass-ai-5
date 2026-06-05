import Combine
import StoreKit
import SwiftUI

@MainActor
final class PurchaseManager: ObservableObject {
    static let premiumMonthlyProductID = "com.harib.haircompass.pro.monthly"
    static let premiumYearlyProductID = "com.harib.haircompass.pro.yearly"
    static let subscriptionGroupID = "21442176"
    static let productIDs = [premiumMonthlyProductID, premiumYearlyProductID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var isLoadingProducts = false
    @Published var purchaseErrorMessage = ""

    private var hasStarted = false
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    var sortedSubscriptionProducts: [Product] {
        products.sorted(by: subscriptionSort)
    }

    func start() async {
        guard !hasStarted else {
            await refreshEntitlements()
            return
        }

        hasStarted = true
        isLoadingProducts = true
        purchaseErrorMessage = ""

        defer {
            isLoadingProducts = false
        }

        do {
            products = try await Product.products(for: Self.productIDs)
            await refreshEntitlements()
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        purchaseErrorMessage = ""

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified(_, let error):
                    purchaseErrorMessage = error.localizedDescription
                }
            case .userCancelled:
                break
            case .pending:
                purchaseErrorMessage = "Purchase is pending approval."
            @unknown default:
                purchaseErrorMessage = "Purchase failed with an unknown result."
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        purchaseErrorMessage = ""

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var premiumAccess = false
        var currentProductID: String?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.productIDs.contains(transaction.productID) {
                premiumAccess = true
                currentProductID = transaction.productID
            }
        }

        hasPremiumAccess = premiumAccess
        activeProductID = currentProductID
    }

    func isMonthly(_ product: Product) -> Bool {
        subscriptionPeriodLabel(for: product) == "month"
    }

    func badgeText(for product: Product) -> String? {
        if product.id == activeProductID {
            return "Current"
        }
        if isMonthly(product) {
            return "Flexible"
        }
        if introOfferLabel(for: product) != nil {
            return "Best value"
        }
        return "Yearly"
    }

    func trialHeadline(for product: Product) -> String? {
        guard let introOffer = product.subscription?.introductoryOffer else { return nil }
        let periodText = periodDescription(
            unit: introOffer.period.unit,
            value: introOffer.period.value,
            count: introOffer.periodCount
        )

        switch introOffer.paymentMode {
        case .freeTrial:
            return "\(periodText) free trial"
        case .payAsYouGo:
            return "\(product.displayPrice) for \(periodText)"
        case .payUpFront:
            return "Intro offer for \(periodText)"
        default:
            return nil
        }
    }

    func renewalDescription(for product: Product) -> String {
        let periodLabel = subscriptionPeriodLabel(for: product)
        if let trialHeadline = trialHeadline(for: product) {
            return "\(trialHeadline), then \(product.displayPrice)/\(periodLabel)"
        }
        return "\(product.displayPrice)/\(periodLabel)"
    }

    func planDescription(for product: Product) -> String {
        if let trialHeadline = trialHeadline(for: product) {
            return "Includes \(trialHeadline). Renews at \(product.displayPrice)/\(subscriptionPeriodLabel(for: product))."
        }
        return "Full premium access billed \(product.displayPrice) per \(subscriptionPeriodLabel(for: product))."
    }

    func savingsMessage(comparedTo monthlyProduct: Product?, yearlyProduct: Product) -> String? {
        guard
            let monthlyProduct,
            let monthlyPrice = Decimal(string: monthlyProduct.displayPrice.filter("0123456789.,".contains).replacingOccurrences(of: ",", with: ".")),
            let yearlyPrice = Decimal(string: yearlyProduct.displayPrice.filter("0123456789.,".contains).replacingOccurrences(of: ",", with: "."))
        else {
            return nil
        }

        let monthlyYearCost = monthlyPrice * 12
        guard monthlyYearCost > yearlyPrice else { return nil }

        let savings = monthlyYearCost - yearlyPrice
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current

        guard let savingsText = formatter.string(from: savings as NSDecimalNumber) else { return nil }
        return "Save about \(savingsText) vs paying monthly for a year."
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private func subscriptionSort(_ lhs: Product, _ rhs: Product) -> Bool {
        let lhsRank = periodSortRank(for: lhs)
        let rhsRank = periodSortRank(for: rhs)
        if lhsRank == rhsRank {
            return lhs.displayPrice < rhs.displayPrice
        }
        return lhsRank < rhsRank
    }

    private func periodSortRank(for product: Product) -> Int {
        switch product.subscription?.subscriptionPeriod.unit {
        case .month:
            return 0
        case .year:
            return 1
        case .week:
            return 2
        case .day:
            return 3
        default:
            return 4
        }
    }

    private func subscriptionPeriodLabel(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "period" }

        switch period.unit {
        case .day:
            return period.value == 1 ? "day" : "\(period.value) days"
        case .week:
            return period.value == 1 ? "week" : "\(period.value) weeks"
        case .month:
            return period.value == 1 ? "month" : "\(period.value) months"
        case .year:
            return period.value == 1 ? "year" : "\(period.value) years"
        @unknown default:
            return "period"
        }
    }

    private func introOfferLabel(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer else { return nil }
        return periodDescription(unit: offer.period.unit, value: offer.period.value, count: offer.periodCount)
    }

    private func periodDescription(unit: Product.SubscriptionPeriod.Unit, value: Int, count: Int) -> String {
        let total = max(1, value * count)

        switch unit {
        case .day:
            return total == 1 ? "1 day" : "\(total) days"
        case .week:
            return total == 1 ? "1 week" : "\(total) weeks"
        case .month:
            return total == 1 ? "1 month" : "\(total) months"
        case .year:
            return total == 1 ? "1 year" : "\(total) years"
        @unknown default:
            return "limited time"
        }
    }
}

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @State private var purchasingProductID: String?
    @State private var isRestoringPurchases = false
    @State private var headerVisible = false
    @State private var cardsVisible = false

    private var monthlyProduct: Product? {
        purchaseManager.sortedSubscriptionProducts.first(where: purchaseManager.isMonthly)
    }

    private var yearlyProduct: Product? {
        purchaseManager.sortedSubscriptionProducts.first(where: { !$0.id.isEmpty && !$0.id.elementsEqual(PurchaseManager.premiumMonthlyProductID) && !purchaseManager.isMonthly($0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                paywallBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                            .opacity(headerVisible ? 1 : 0)
                            .offset(y: headerVisible ? 0 : 20)

                        premiumFeatureCard
                            .opacity(cardsVisible ? 1 : 0)
                            .offset(y: cardsVisible ? 0 : 18)

                        if purchaseManager.hasPremiumAccess {
                            premiumActiveCard
                                .opacity(cardsVisible ? 1 : 0)
                                .offset(y: cardsVisible ? 0 : 18)
                        } else if purchaseManager.isLoadingProducts && purchaseManager.products.isEmpty {
                            loadingCard
                        } else if purchaseManager.products.isEmpty {
                            premiumStatusCard(
                                title: "Subscription unavailable",
                                detail: "No products were returned. Update the product IDs in PurchaseManager and finish App Store Connect or StoreKit config setup."
                            )
                        } else {
                            productSection
                                .opacity(cardsVisible ? 1 : 0)
                                .offset(y: cardsVisible ? 0 : 18)
                        }

                        if !purchaseManager.purchaseErrorMessage.isEmpty {
                            Text(purchaseManager.purchaseErrorMessage)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.69, green: 0.20, blue: 0.16))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 0.99, green: 0.93, blue: 0.90), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        restoreButton

                        legalFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.40, green: 0.46, blue: 0.43))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.7), in: Circle())
                    }
                }
            }
            .task {
                await purchaseManager.start()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    headerVisible = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.12)) {
                    cardsVisible = true
                }
            }
            .onChange(of: purchaseManager.hasPremiumAccess) { _, hasPremiumAccess in
                if hasPremiumAccess {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Background

    private var paywallBackground: some View {
        PremiumBackdrop()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [PremiumTheme.gold, Color(red: 0.92, green: 0.78, blue: 0.44)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("PRO")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(PremiumTheme.gold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(PremiumTheme.goldSoft, in: Capsule())
                    }

                    Text("Hair Compass Pro")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(PremiumTheme.ink)

                    Text("Unlock AI intelligence, clinician export, and advanced photo analysis.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PremiumTheme.mutedInk)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                premiumMetricPill(title: "Clinical", subtitle: "exports")
                premiumMetricPill(title: "AI", subtitle: "insights")
                premiumMetricPill(title: "Photo", subtitle: "analysis")
            }

            if let yearlyProduct, let savings = purchaseManager.savingsMessage(comparedTo: monthlyProduct, yearlyProduct: yearlyProduct) {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PremiumTheme.teal)
                    Text(savings)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumTheme.teal)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.78), in: Capsule())
            }
        }
        .padding(22)
        .premiumGlassCard(fillOpacity: 0.36, shadowOpacity: 0.16)
    }

    // MARK: - Features

    private var premiumFeatureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What you get")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(PremiumTheme.ink)

            paywallFeatureRow(icon: "sparkles", iconColor: Color(red: 0.72, green: 0.55, blue: 0.22), title: "AI Dashboard Intelligence", detail: "AI-generated pattern readings from your logs, labs, and medications")
            paywallFeatureRow(icon: "doc.text.fill", iconColor: Color(red: 0.24, green: 0.49, blue: 0.78), title: "Clinician Export", detail: "Share a professional summary with your dermatologist")
            paywallFeatureRow(icon: "camera.viewfinder", iconColor: Color(red: 0.46, green: 0.62, blue: 0.52), title: "Photo Analysis", detail: "AI-powered session analysis for scalp and hair photos")
            paywallFeatureRow(icon: "flask.fill", iconColor: Color(red: 0.63, green: 0.39, blue: 0.73), title: "Product AI Reads", detail: "Check if a hair product is useful for your specific profile")
        }
        .padding(22)
        .premiumGlassCard(fillOpacity: 0.56)
    }

    private func paywallFeatureRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PremiumTheme.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PremiumTheme.mutedInk)
            }
        }
    }

    // MARK: - Products

    private var loadingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
            Text("Loading subscription options...")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.44, blue: 0.41))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumGlassCard(cornerRadius: 24, fillOpacity: 0.34, shadowOpacity: 0.08)
    }

    private var productSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(purchaseManager.sortedSubscriptionProducts, id: \.id) { product in
                productCard(product)
            }

            Text("Free trials and introductory pricing are determined by StoreKit eligibility.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.48, green: 0.54, blue: 0.50))
                .padding(.top, 4)
        }
    }

    private var premiumActiveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.27, green: 0.56, blue: 0.42))
                Text("Pro is active")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.18, blue: 0.16))
            }
            Text("This Apple ID already has premium access. All Pro features are unlocked.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.44, blue: 0.41))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.90, green: 0.96, blue: 0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.72, green: 0.86, blue: 0.76), lineWidth: 1)
        )
    }

    private var restoreButton: some View {
        Button {
            isRestoringPurchases = true
            Task {
                await purchaseManager.restorePurchases()
                isRestoringPurchases = false
                if purchaseManager.hasPremiumAccess {
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 10) {
                if isRestoringPurchases {
                    ProgressView()
                        .tint(Color(red: 0.38, green: 0.44, blue: 0.41))
                }
                Text("Restore Purchases")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.38, green: 0.44, blue: 0.41))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .premiumGlassCard(cornerRadius: 20, fillOpacity: 0.28, shadowOpacity: 0.08)
        }
        .buttonStyle(.plain)
        .disabled(purchasingProductID != nil || isRestoringPurchases)
    }

    private var legalFooter: some View {
        Text("Payment is charged to your Apple ID. Subscriptions auto-renew unless cancelled at least 24 hours before the current period ends. Manage subscriptions in Settings.")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color(red: 0.52, green: 0.57, blue: 0.54))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func productCard(_ product: Product) -> some View {
        let isYearly = product.id == PurchaseManager.premiumYearlyProductID
        let isActive = product.id == purchaseManager.activeProductID

        return Button {
            purchasingProductID = product.id
            Task {
                await purchaseManager.purchase(product)
                purchasingProductID = nil
                if purchaseManager.hasPremiumAccess {
                    dismiss()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(product.displayName)
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .foregroundStyle(PremiumTheme.ink)

                            if let badge = purchaseManager.badgeText(for: product) {
                                Text(badge)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isYearly ? PremiumTheme.gold : PremiumTheme.forest)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        isYearly ? PremiumTheme.goldSoft : Color(red: 0.87, green: 0.94, blue: 0.89),
                                        in: Capsule()
                                    )
                            }
                        }

                        Text(purchaseManager.planDescription(for: product))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PremiumTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    if purchasingProductID == product.id {
                        ProgressView()
                            .tint(Color(red: 0.15, green: 0.38, blue: 0.56))
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(product.displayPrice)
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(PremiumTheme.teal)
                            Text("per \(purchaseManager.isMonthly(product) ? "month" : "year")")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(PremiumTheme.mutedInk)
                        }
                    }
                }

                if let trial = purchaseManager.trialHeadline(for: product) {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.72, green: 0.48, blue: 0.22))
                        Text(trial.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.72, green: 0.48, blue: 0.22))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.98, green: 0.94, blue: 0.86), in: Capsule())
                }

                HStack(spacing: 10) {
                    Text(purchaseManager.renewalDescription(for: product))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumTheme.secondaryInk)

                    Spacer()

                    if !isActive {
                        Text("Subscribe")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(PremiumTheme.accentGradient, in: Capsule())
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .premiumGlassCard(cornerRadius: 26, fillOpacity: 0.60, shadowOpacity: isYearly ? 0.16 : 0.10)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        isYearly
                        ? LinearGradient(
                            colors: [PremiumTheme.gold.opacity(0.66), PremiumTheme.goldSoft.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color.white.opacity(0.66), Color.white.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isYearly ? 1.5 : 1
                    )
            )
            .shadow(color: isYearly ? Color(red: 0.82, green: 0.65, blue: 0.30).opacity(0.12) : Color(red: 0.30, green: 0.42, blue: 0.56).opacity(0.10), radius: 20, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(purchasingProductID != nil || isRestoringPurchases || isActive)
    }

    private func premiumStatusCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.13, green: 0.18, blue: 0.16))
            Text(detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.44, blue: 0.41))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumGlassCard(cornerRadius: 24, fillOpacity: 0.36, shadowOpacity: 0.08)
    }
}

struct PremiumLockedCallout: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color(red: 0.80, green: 0.55, blue: 0.28))
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.18))
            }

            Text(detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.39, green: 0.45, blue: 0.42))

            Button(actionTitle, action: action)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.17, green: 0.34, blue: 0.30))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
private extension PremiumPaywallView {
    func premiumMetricPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PremiumTheme.secondaryInk)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(PremiumTheme.mutedInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

