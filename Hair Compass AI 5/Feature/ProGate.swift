import StoreKit
import SwiftUI

/// Wraps premium content: shows it for Pro users, otherwise an inline, honest upsell
/// (feature name + a one-line description + the two Pro purchase buttons + restore). Used by
/// the AI sheets — gate at the caller's top level so the sheet's own chrome (title, Close
/// button) stays outside the gate and is always reachable. Purchase buttons hide entirely
/// (never a placeholder price) when products haven't loaded, matching `OnboardingPlanStep`'s
/// honesty rules. Does not apply its own background — callers already own `.clinicalScreen()`.
struct ProGate<Content: View>: View {
    let feature: String
    let symbol: String
    var description: String = "Included with Hair Compass Pro."
    @ViewBuilder var content: () -> Content

    @Environment(PurchaseService.self) private var purchases
    @State private var isPurchasing = false
    @State private var yearlyIntroEligible = false

    var body: some View {
        if purchases.hasPro {
            content()
        } else {
            locked
                .task(id: purchases.yearly?.id) {
                    guard let yearly = purchases.yearly else { return }
                    yearlyIntroEligible = await purchases.isEligibleForIntro(yearly)
                }
        }
    }

    private var locked: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)

            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Clinical.accent)
                .frame(width: 60, height: 60)
                .background(Clinical.accentSoft, in: Circle())

            VStack(spacing: 6) {
                Text(feature)
                    .font(Clinical.headline(20))
                    .foregroundStyle(Clinical.ink)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Clinical.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !purchases.products.isEmpty {
                VStack(spacing: 10) {
                    if let yearly = purchases.yearly {
                        let trialText = yearlyIntroEligible ? purchases.trialDescriptor(for: yearly) : nil
                        Button {
                            buy(yearly)
                        } label: {
                            VStack(spacing: 2) {
                                if let trialText {
                                    Text("Start 3-day free trial")
                                    Text("\(trialText) · cancel anytime")
                                        .font(.system(size: 11, weight: .regular))
                                } else {
                                    Text("Yearly — \(yearly.displayPrice)/year")
                                    if let perMonth = yearly.monthlyEquivalentDisplay {
                                        Text(perMonth).font(.system(size: 11, weight: .regular))
                                    }
                                }
                            }
                        }
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(isPurchasing)
                        .accessibilityIdentifier("proGatePurchaseYearly")
                    }
                    if let monthly = purchases.monthly {
                        Button {
                            buy(monthly)
                        } label: {
                            Text("Monthly — \(monthly.displayPrice)/month")
                        }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                        .disabled(isPurchasing)
                        .accessibilityIdentifier("proGatePurchaseMonthly")
                    }
                }
            }

            Button {
                Task { await purchases.restore() }
            } label: {
                Text("Restore purchases")
                    .font(.system(size: 12))
                    .foregroundStyle(Clinical.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buy(_ product: Product) {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            await purchases.purchase(product)
            isPurchasing = false
        }
    }
}
