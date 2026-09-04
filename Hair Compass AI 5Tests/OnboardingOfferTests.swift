import StoreKit
import Testing
import UIKit
@testable import Hair_Compass_AI_5

@MainActor
struct OnboardingOfferTests {
    @Test func phasesHaveAnExitInBothDirections() {
        #expect(OnboardingOfferPhase.plan.previous == nil)
        #expect(OnboardingOfferPhase.plan.next == .preview)
        #expect(OnboardingOfferPhase.preview.previous == .plan)
        #expect(OnboardingOfferPhase.preview.next == .pricing)
        #expect(OnboardingOfferPhase.pricing.previous == .preview)
        #expect(OnboardingOfferPhase.pricing.next == nil)
    }

    @Test func summaryReusesRealUnfinishedPlanItems() {
        let profile = Profile()
        let all = StarterPlan.items(for: .fresh(profile: profile))
        let summary = OnboardingPlanSummary.items(from: all)
        #expect(summary.count == 3)
        #expect(summary.map(\.id) == ["setup.baselinePhoto", "procedure.consultation", "discussion.labs"])
        #expect(summary.allSatisfy { all.contains($0) })
        #expect(summary.allSatisfy { !$0.isDone })
        #expect(!summary.contains { $0.kind == .setup(.logToday) })
    }

    @Test func completedPlanNeverInventsNextSteps() {
        #expect(OnboardingPlanSummary.items(from: []).isEmpty)
        let item = StarterPlanItem(id: "setup.baselinePhoto", group: .setUp, kind: .setup(.baselinePhoto),
                                   title: "Done", why: "Done", caution: nil, isDone: true)
        #expect(OnboardingPlanSummary.items(from: [item]).isEmpty)
    }

    @Test func regularPriceKeepsStorefrontCurrencyAndPeriod() {
        let copy = OnboardingPriceCopy(price: "OMR 19.990", period: "1 year")
        #expect(copy.price == "OMR 19.990")
        #expect(copy.detail == "OMR 19.990 every 1 year. Auto-renews until cancelled.")
        #expect(copy.action == "Continue with Pro")
    }

    @Test func freeTrialStatesTheRenewal() {
        let copy = OnboardingPriceCopy(price: "€6,99", period: "1 month", introPrice: "€0,00",
                                       introPeriod: "7 days", mode: .freeTrial)
        #expect(copy.detail == "Free for 7 days, then €6,99 every 1 month. Auto-renews until cancelled.")
        #expect(copy.action == "Start free trial")
    }

    @Test func upfrontOfferDoesNotPretendToLastOneYear() {
        let copy = OnboardingPriceCopy(price: "$49.99", period: "1 year", introPrice: "$4.99",
                                       introPeriod: "3 months", mode: .payUpFront)
        #expect(copy.detail.contains("$4.99 for the first 3 months"))
        #expect(copy.detail.contains("then $49.99 every 1 year"))
        #expect(!copy.detail.contains("first year"))
    }

    @Test func repeatingOfferStatesPaymentCount() {
        let copy = OnboardingPriceCopy(price: "$9.99", period: "1 month", introPrice: "$2.99",
                                       introPeriod: "1 month", introCount: 3, mode: .payAsYouGo)
        #expect(copy.detail.contains("$2.99 every 1 month for 3 payments"))
        #expect(copy.detail.contains("then $9.99 every 1 month"))
    }

    @Test func incompleteOfferNeverAdvertisesATrial() {
        let copy = OnboardingPriceCopy(price: "$9.99", period: "1 month", mode: .freeTrial)
        #expect(!copy.detail.contains("Free"))
        #expect(copy.action == "Continue with Pro")
    }

    @Test func periodsUseStoreKitUnits() {
        #expect(OnboardingPriceCopy.period(1, unit: .year) == "1 year")
        #expect(OnboardingPriceCopy.period(3, unit: .month) == "3 months")
        #expect(OnboardingPriceCopy.period(2, unit: .week) == "2 weeks")
        #expect(OnboardingPriceCopy.period(7, unit: .day) == "7 days")
    }

    @Test func generatedArtShipsInTheAppBundle() {
        #expect(UIImage(named: OnboardingArt.journal) != nil)
        #expect(UIImage(named: OnboardingArt.support) != nil)
    }

    @Test func motionIsShortAndHasTimeToSettleBeforeTheNote() {
        #expect((0.4...0.7).contains(MotionSpec.onboarding.settle))
        #expect(MotionSpec.onboarding.selection < 0.4)
        #expect(MotionSpec.onboarding.noteDelay > MotionSpec.onboarding.settle)
        #expect(MotionSpec.onboarding.recordDelay + MotionSpec.onboarding.noteDelay < 3)
    }
}
