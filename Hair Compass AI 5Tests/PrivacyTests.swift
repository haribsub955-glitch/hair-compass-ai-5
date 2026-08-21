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

    // MARK: - Cloud AI daily budget

    /// A fixed UTC calendar so day-boundary tests never depend on the test host's own time
    /// zone or on when in the real day the suite happens to run.
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// `CloudAIBudget` is a client-side abuse guard on the key embedded in the binary, not
    /// billing enforcement — see its doc comment in CloudAI.swift. It reuses this file's
    /// throwaway-`UserDefaults` pattern rather than CloudAITests.swift because the behaviour
    /// under test (a day-keyed counter, persisted) is the same shape as the App Lock and
    /// consent state above, not the network wire format CloudAITests.swift covers.
    @Test func cloudAIBudgetIncrementsWithinTheSameDay() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let now = utcCalendar().date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 9))!

        #expect(CloudAIBudget.consume(now: now, defaults: defaults, calendar: utcCalendar()))
        #expect(defaults.integer(forKey: CloudAIBudget.countDefaultsKey) == 1)
        #expect(CloudAIBudget.consume(now: now, defaults: defaults, calendar: utcCalendar()))
        #expect(defaults.integer(forKey: CloudAIBudget.countDefaultsKey) == 2)
    }

    /// The limit exists to stop a runaway/abusive client, not to ration normal use — but it
    /// must actually bite once `dailyLimit` requests have gone out today.
    @Test func cloudAIBudgetRefusesOnceTheDailyLimitIsReached() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let now = utcCalendar().date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 9))!
        let calendar = utcCalendar()

        for _ in 0..<CloudAIBudget.dailyLimit {
            #expect(CloudAIBudget.consume(now: now, defaults: defaults, calendar: calendar))
        }
        // The (dailyLimit + 1)th request today is refused by this client-side guard — DeepSeek
        // never even sees it, and the caller's on-device fallback is what makes that harmless.
        #expect(CloudAIBudget.consume(now: now, defaults: defaults, calendar: calendar) == false)
        #expect(defaults.integer(forKey: CloudAIBudget.countDefaultsKey) == CloudAIBudget.dailyLimit)
    }

    /// The day key's *production default* is pinned to UTC, not `.current` — a timezone
    /// change (travel, or someone manually changing it) must never shift the day boundary and
    /// mint a fresh 100 out of thin air. This is the same UTC calendar `utcCalendar()` above
    /// builds by hand for the rest of this section's tests; asserting it here pins that the
    /// production default is that exact choice, not a coincidentally-matching one.
    /// Not just that `CloudAIBudget.utcCalendar` itself reads as UTC — every earlier test in
    /// this section passes `calendar: utcCalendar()` explicitly to `consume`, so they'd all stay
    /// green even if the production *default* silently reverted to `.current`; the explicit
    /// argument would paper right over that regression. This test omits the `calendar:` argument
    /// entirely, exercising the actual default, and checks the stored day string against what
    /// UTC says `now` was — not against a UTC/non-UTC day-boundary trick, which isn't reliably
    /// controllable across whatever timezone the host running this suite happens to be in.
    @Test func cloudAIBudgetDayKeyCalendarIsPinnedToUTC() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        // Zero offset, not string identity: Foundation reports `TimeZone(identifier: "UTC")`'s
        // own `.identifier` back as the "GMT" alias on this platform, so the offset is the
        // stable thing to assert — it's the offset, not the label, that fixes the day boundary.
        #expect(CloudAIBudget.utcCalendar.timeZone.secondsFromGMT() == 0)

        let now = Date()
        #expect(CloudAIBudget.consume(now: now, defaults: defaults))
        // This pins the production default, not this file's own `utcCalendar()` helper: if
        // `consume`'s default calendar ever reverted to `.current`, this would fail on any host
        // whose local timezone reads `now` as a different calendar day than UTC does.
        #expect(defaults.string(forKey: CloudAIBudget.dayDefaultsKey)
                == CloudAIBudget.dayString(now, calendar: CloudAIBudget.utcCalendar))
    }

    /// No midnight timer drives the reset — the rollover to zero happens lazily, the first
    /// time `consume` sees a day string that no longer matches what's stored.
    @Test func cloudAIBudgetResetsOnANewLocalDay() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        let calendar = utcCalendar()
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 23, minute: 59))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 0, minute: 1))!

        for _ in 0..<CloudAIBudget.dailyLimit {
            #expect(CloudAIBudget.consume(now: day1, defaults: defaults, calendar: calendar))
        }
        #expect(CloudAIBudget.consume(now: day1, defaults: defaults, calendar: calendar) == false)

        // Crossing local midnight resets the count to zero with no explicit reset call.
        #expect(CloudAIBudget.consume(now: day2, defaults: defaults, calendar: calendar))
        #expect(defaults.integer(forKey: CloudAIBudget.countDefaultsKey) == 1)
    }
}
