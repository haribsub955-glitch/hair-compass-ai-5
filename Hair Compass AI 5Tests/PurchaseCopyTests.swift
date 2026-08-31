//
//  PurchaseCopyTests.swift
//  Hair Compass AI 5Tests
//
//  Trial-period wording. Oracle source: English compound-modifier grammar — a hyphenated
//  period stays singular ("3-day free trial"). The pre-fix code pluralized the unit and
//  shipped "3-days free trial" on the paywall; `threeDayTrialReadsSingular` fails on it.
//

import Foundation
import StoreKit
import Testing
@testable import Hair_Compass_AI_5

struct PurchaseCopyTests {

    @Test func threeDayTrialReadsSingular() {
        #expect(PurchaseService.periodLabel(value: 3, unit: .day) == "3-day")
    }

    @Test func singleUnitsStaySingular() {
        #expect(PurchaseService.periodLabel(value: 1, unit: .day) == "1-day")
        #expect(PurchaseService.periodLabel(value: 1, unit: .month) == "1-month")
    }

    @Test func multiUnitsStaySingularInCompoundForm() {
        #expect(PurchaseService.periodLabel(value: 2, unit: .week) == "2-week")
        #expect(PurchaseService.periodLabel(value: 12, unit: .month) == "12-month")
    }
}
