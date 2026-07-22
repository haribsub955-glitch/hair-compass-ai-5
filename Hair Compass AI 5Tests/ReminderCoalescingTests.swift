//
//  ReminderCoalescingTests.swift
//  Hair Compass AI 5Tests
//
//  The routine-reminder coalescing (Service/NotificationService.swift): treatments that share a
//  time slot collapse into one banner instead of a separate ping each — the fatigue fix.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct ReminderCoalescingTests {

    @Test func routineTitleKeepsOneNameButBlocksSeveral() {
        // A single step keeps its own name — the reminder still feels personal.
        #expect(NotificationService.routineTitle(slot: "08:00", stepCount: 1, firstName: "Minoxidil") == "Minoxidil")
        // Two or more collapse to the time-of-day block.
        #expect(NotificationService.routineTitle(slot: "08:00", stepCount: 2, firstName: "Minoxidil") == "Morning routine")
        #expect(NotificationService.routineTitle(slot: "13:30", stepCount: 3, firstName: "X") == "Afternoon routine")
        #expect(NotificationService.routineTitle(slot: "21:00", stepCount: 2, firstName: "X") == "Evening routine")
    }

    @Test func routineBodyListsEveryStepWhenCoalesced() {
        #expect(NotificationService.routineBody(names: ["Minoxidil"]) == "A tap when it's done.")
        let body = NotificationService.routineBody(names: ["Minoxidil", "Finasteride", "Biotin"])
        #expect(body.contains("3 steps"))
        #expect(body.contains("Minoxidil"))
        #expect(body.contains("Finasteride"))
        #expect(body.contains("Biotin"))
    }

    @Test func ownedRequestsRespectSystemLimitWithoutTouchingForeignCapacity() {
        #expect(NotificationService.acceptedOwnedCount(desired: 20, foreignPending: 50) == 14)
        #expect(NotificationService.acceptedOwnedCount(desired: 3, foreignPending: 10) == 3)
        #expect(NotificationService.acceptedOwnedCount(desired: 3, foreignPending: 64) == 0)
    }
}
