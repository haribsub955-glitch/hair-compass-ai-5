import Foundation
import Testing
@testable import Hair_Compass_AI_5

/// The 3-day full-access window every fresh install gets before the paywall appears.
/// Anchored on first launch via an injected store (Keychain in production, so deleting and
/// reinstalling the app does not restart the clock) and measured against an injected `now`
/// so every boundary is testable.
@MainActor
struct AccessWindowTests {

    private final class MemoryAnchorStore: AccessAnchorStoring {
        var stored: Date?
        func loadAnchor() -> Date? { stored }
        func saveAnchor(_ date: Date) { stored = date }
    }

    @Test func firstLaunchAnchorsTheWindowAndIsActive() {
        let store = MemoryAnchorStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let window = AccessWindow(store: store, now: { t0 })

        #expect(window.isActive)
        #expect(store.stored == t0)
    }

    @Test func remainsActiveJustBeforeSeventyTwoHours() {
        let store = MemoryAnchorStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.stored = t0
        let almostThreeDays = t0.addingTimeInterval(72 * 3600 - 1)
        let window = AccessWindow(store: store, now: { almostThreeDays })

        #expect(window.isActive)
    }

    @Test func lapsesExactlyAtSeventyTwoHours() {
        let store = MemoryAnchorStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.stored = t0
        let threeDays = t0.addingTimeInterval(72 * 3600)
        let window = AccessWindow(store: store, now: { threeDays })

        #expect(!window.isActive)
    }

    @Test func existingAnchorIsNeverOverwritten() {
        let store = MemoryAnchorStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.stored = t0
        let later = t0.addingTimeInterval(10 * 3600)
        let window = AccessWindow(store: store, now: { later })

        _ = window.isActive
        #expect(store.stored == t0)
    }

    @Test func clockSetBackwardsDoesNotRestartTheWindow() {
        // A device clock moved behind the anchor must not mint a fresh anchor or crash;
        // the window simply reads as active until the real 72h boundary passes.
        let store = MemoryAnchorStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.stored = t0
        let beforeAnchor = t0.addingTimeInterval(-3600)
        let window = AccessWindow(store: store, now: { beforeAnchor })

        #expect(window.isActive)
        #expect(store.stored == t0)
    }

    @Test func remainingDaysRoundsUpForPaywallCopy() {
        let store = MemoryAnchorStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.stored = t0
        // 2 days + 1 hour left → "3 days" would overstate; the copy wants ceil in days of the
        // remaining interval: 49h → 3 is wrong, 49/24 = 2.04 → ceil = 3? No: 49h remaining
        // means the third day is already partly consumed — the honest ceil is 3 only when a
        // full 2 days are still ahead. ceil(49/24) = 3 overstates by nothing the user can
        // exploit, but the paywall promises "N days left", so ceil is the kindest true value.
        let now = t0.addingTimeInterval(23 * 3600)   // 49h remaining
        let window = AccessWindow(store: store, now: { now })
        #expect(window.remainingDays == 3)

        let lastHours = t0.addingTimeInterval(71 * 3600)  // 1h remaining
        let endWindow = AccessWindow(store: store, now: { lastHours })
        #expect(endWindow.remainingDays == 1)

        let lapsed = t0.addingTimeInterval(80 * 3600)
        let lapsedWindow = AccessWindow(store: store, now: { lapsed })
        #expect(lapsedWindow.remainingDays == 0)
    }
}
