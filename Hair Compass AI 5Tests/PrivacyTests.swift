//
//  PrivacyTests.swift
//  Hair Compass AI 5Tests
//
//  App Lock (Face ID / passcode) and the off-device AI-analysis consent gate.
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct PrivacyTests {

    /// Throwaway defaults so tests never touch the app's real preferences.
    private func makeDefaults() -> (UserDefaults, cleanup: () -> Void) {
        let suite = "privacy-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    // MARK: - App Lock

    @Test func appLockTogglePersistsAndAFreshLaunchStartsLocked() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }

        let lock = AppLockService(defaults: defaults, canEvaluate: { true }, authenticate: { _ in true })
        #expect(lock.isEnabled == false)
        #expect(lock.isLocked == false)

        // Enabling persists but does not lock mid-session.
        lock.isEnabled = true
        #expect(defaults.bool(forKey: AppLockService.enabledKey) == true)
        #expect(lock.isLocked == false)

        // A fresh instance over the same defaults (= next launch) starts enabled AND locked.
        let relaunch = AppLockService(defaults: defaults, canEvaluate: { true }, authenticate: { _ in true })
        #expect(relaunch.isEnabled == true)
        #expect(relaunch.isLocked == true)

        // Turning it off unlocks immediately and persists.
        relaunch.isEnabled = false
        #expect(relaunch.isLocked == false)
        #expect(defaults.bool(forKey: AppLockService.enabledKey) == false)
    }

    @Test func appLockAutoUnlocksWhenDeviceCannotAuthenticate() async {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        defaults.set(true, forKey: AppLockService.enabledKey)

        final class Flag { var attempted = false }
        let flag = Flag()
        let lock = AppLockService(
            defaults: defaults,
            canEvaluate: { false },                                  // no Face ID / Touch ID / passcode
            authenticate: { _ in flag.attempted = true; return false }
        )
        #expect(lock.canUseLock == false)
        #expect(lock.isLocked == true)

        // No way to authenticate → unlock() must never trap the user: auto-unlock,
        // without ever invoking the authenticator.
        await lock.unlock()
        #expect(lock.isLocked == false)
        #expect(flag.attempted == false)
    }

    @Test func appLockRelocksOnBackgroundAndUnlocksOnSuccess() async {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }

        let lock = AppLockService(defaults: defaults, canEvaluate: { true }, authenticate: { _ in true })
        lock.isEnabled = true
        #expect(lock.isLocked == false)

        // Relock policy: backgrounding relocks whenever the lock is enabled.
        lock.markBackgrounded()
        #expect(lock.isLocked == true)

        await lock.unlock()   // authenticator succeeds
        #expect(lock.isLocked == false)

        // Disabled → backgrounding never locks.
        lock.isEnabled = false
        lock.markBackgrounded()
        #expect(lock.isLocked == false)
    }

    @Test func appLockFailedAuthenticationStaysLocked() async {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        defaults.set(true, forKey: AppLockService.enabledKey)

        let lock = AppLockService(defaults: defaults, canEvaluate: { true }, authenticate: { _ in false })
        #expect(lock.isLocked == true)
        await lock.unlock()
        #expect(lock.isLocked == true)
    }

    // MARK: - AI consent

    @Test func aiConsentRoundTripsGrantAndRevoke() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }

        #expect(AIConsent.isGranted(defaults) == false)
        #expect(AIConsent.grantedDate(defaults) == nil)

        let stamp = Date(timeIntervalSince1970: 1_750_000_000)
        AIConsent.grant(defaults, now: stamp)
        #expect(AIConsent.isGranted(defaults) == true)
        #expect(AIConsent.grantedDate(defaults) == stamp)

        // Revoking flips the flag and clears the date — the next deep-analysis tap re-asks.
        AIConsent.revoke(defaults)
        #expect(AIConsent.isGranted(defaults) == false)
        #expect(AIConsent.grantedDate(defaults) == nil)
    }

    @Test func cloudAnalysisRefusesWithoutConsent() async {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }

        // Consent never granted in this defaults suite → the service must refuse before any
        // network work (belt and braces under the UI gate).
        let service = CloudAnalysisService(defaults: defaults)
        let context = InsightContext.build(
            entries: [], treatments: [], doses: [], snapshots: [], triggers: [], profile: nil)
        await service.analyze(context: context, images: [])

        #expect(service.result == nil)
        #expect(service.errorMessage?.contains("consent") == true)
    }
}
