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

    // MARK: - Cloud AI consent

    /// The consent gate returned with the cloud engine (DeepSeek). The rules a UI cannot be
    /// trusted to keep on its own: undecided is a real third state (never silently granted),
    /// both answers persist, and the choice is reversible.
    @Test func cloudAIConsentDefaultsToUndecidedAndPersistsEitherAnswer() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }

        // Undecided until someone actually answers — and undecided is not "granted".
        #expect(CloudAIConsent.isDecided(defaults) == false)
        #expect(CloudAIConsent.isGranted(defaults) == false)

        CloudAIConsent.record(true, in: defaults)
        #expect(CloudAIConsent.isDecided(defaults))
        #expect(CloudAIConsent.isGranted(defaults))

        // Reversible — declining later wins over the earlier grant.
        CloudAIConsent.record(false, in: defaults)
        #expect(CloudAIConsent.isDecided(defaults))
        #expect(CloudAIConsent.isGranted(defaults) == false)

        CloudAIConsent.reset(in: defaults)
        #expect(CloudAIConsent.isDecided(defaults) == false)
    }

    /// The engine decision honours consent: no cloud before a grant, ever — undecided asks, and
    /// a decline routes on-device or to a clear unavailable message, never silently to the cloud.
    @Test func engineNeverPicksCloudWithoutAGrant() {
        // Undecided → ask (regardless of on-device state).
        #expect(AIEngine.resolve(cloudConfigured: true, consentDecided: false, consentGranted: false,
                                 onDevice: .available) == .needsCloudConsent)
        #expect(AIEngine.resolve(cloudConfigured: true, consentDecided: false, consentGranted: false,
                                 onDevice: .deviceNotEligible) == .needsCloudConsent)

        // Granted → cloud.
        #expect(AIEngine.resolve(cloudConfigured: true, consentDecided: true, consentGranted: true,
                                 onDevice: .deviceNotEligible) == .cloud)

        // Declined → on-device where it exists, an honest dead end where it doesn't.
        #expect(AIEngine.resolve(cloudConfigured: true, consentDecided: true, consentGranted: false,
                                 onDevice: .available) == .onDevice)
        #expect(AIEngine.resolve(cloudConfigured: true, consentDecided: true, consentGranted: false,
                                 onDevice: .deviceNotEligible)
                == .unavailable(message: AIEngine.cloudDeclinedMessage))

        // No cloud key at all → the pre-cloud behaviour, message included.
        #expect(AIEngine.resolve(cloudConfigured: false, consentDecided: false, consentGranted: false,
                                 onDevice: .available) == .onDevice)
        #expect(AIEngine.resolve(cloudConfigured: false, consentDecided: true, consentGranted: true,
                                 onDevice: .deviceNotEligible)
                == .unavailable(message: OnDeviceAvailability.deviceNotEligible.message))
    }
}
