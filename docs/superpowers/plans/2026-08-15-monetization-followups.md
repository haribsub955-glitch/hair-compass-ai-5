# Monetization — follow-ups after the hard-wall branch

**Date:** 2026-08-15
**Branch it came from:** `design/monetization-hard-wall` (21 commits, `5f2cba1..829d7e1`)
**Status:** the branch shipped clean — final whole-branch review verdict was **ship**. Everything
below was deliberately deferred, triaged, and is recorded here so it survives the scratch
workspace being deleted.

Nothing in this file blocks merge. It is ordered by what actually costs money or trust.

---

## 1. Blocked on you, not on code

| Item | Why it's blocked |
|---|---|
| **Privacy + support URLs** | `privacyAndSupportURLsAreRealBeforeSubmission` is the suite's only failing test, and it is a genuine App Store blocker. `AppInfo.privacyPolicyURLString` / `.supportURLString` still point at a GitHub Pages site that does not resolve. Pre-existing; this branch never touched it. |
| **App Store Connect** | Create the 14-day introductory offer on both products, set $6.99/month and $39.99/year. `PurchaseService.trialDescriptor(for:)` renders whatever is configured — no Swift change needed. |
| **Amazon Associates tag** | `Resources/AffiliateLinks.json` is `{}` and `RemoteConfig.catalogURLString` is `""`, so the Shop tab is reachable and ungated but has **no outbound links on any product**. `resolvedLinkCount` exists so a test can prove the buy buttons appear the moment a catalogue lands. |
| **Product-ID mismatch with Mohammed** | The app sells `com.harib.haircompass.pro.monthly`; `agent_platform/src/agent_core/plans.py` joins on `harib.haircompass.pro.monthly`. His `PlanResolver` would drop a genuine subscriber to `FREE_PLAN_ID`. Raised on PR #1. |

## 2. Worth fixing before the storefront goes live

- **Buy buttons hardcode "View on iHerb"** — `ScienceProductsView.swift:189`, `LabProposalCard.swift:72`. The disclosure sits directly above these rows and the deferred catalogue work targets Amazon. The moment those links land, every button names the wrong merchant under a disclosure promising honesty. Make the label follow the resolved link's host, or stop naming a merchant.
- **Two different affiliate disclosures on one screen** — `ShopView.swift:22-24` ("never affects which products appear or how they're ranked") and `ScienceProductsView.swift:77-79` ("never changes a product's evidence rating"). Both render on Shop, about a screen apart, making different promises. Retire one.
- **"In your plan" badge discloses `.treatments` state on the free Shop tab** — `ScienceProductsView.swift:67`. A lapsed subscriber whose stored treatment matches a catalogue product sees that fact, and gets no paywall tap-through because the badge replaces the "Add to plan" button.

## 3. Correctness follow-ups from the final re-review

- **Entitlement resolution sits behind a network fetch.** `PurchaseService.load()` calls `refreshEntitlement()` *after* `await Product.products(...)`, so `isEntitlementResolved` waits on an App Store round-trip rather than the local `Transaction.currentEntitlements` walk. Only ever over-permissive and self-correcting, but the one-line fix is to call `refreshEntitlement()` before the product fetch.
- **`now` is not threaded into the streak.** `TodayGating.swift:134` calls `HairAnalytics.loggingStreak(entryDates:)` on the real clock while `now` is threaded into `HistoryAccess.visible` at `:119`. The covering test only passes because its fixture's `now` is `Date.now`.
- **Lock card is no longer vertically centred.** `ProGate.lockedBody` keeps `.frame(maxHeight: .infinity)` (`ProGate.swift:136`); under the new `ScrollView`'s nil height proposal it hugs the top on the full-screen gates. Cosmetic; `GeometryReader` + `minHeight:` fixes it.
- **Two `HANDOVER.md` inaccuracies of exactly the class that document exists to prevent.** The `HC_TIER` row says "the four gated tabs" — there are three. And it tells the submitter to mention `HC_TIER free` in App Review notes, but the flag is compiled out of release, so a reviewer on the shipped build cannot use it.

## 4. Structural, worth doing eventually

- **`Entitlements.canAccess(_:)` ignores its argument.** `Entitlements.swift:57-62` switches only on tier, so all twelve `ProFeature` mappings collapse to one boolean at runtime. The per-feature mapping is documentary and future-proofing today — real the moment a middle tier exists.
- **Nothing asserts that `TodayView` *calls* `insightContext`.** The gap is now one obviously-named call rather than four silent arguments, but a reverted call site is still invisible to the suite because `buildContext()` is `private`.
- **Three near-identical self-dismissing-paywall state vars** — `recommendedGate`, `showTreatmentsGate`, `showHistoryPaywall`. The "extract when a third appears" trigger has fired.
- **`FlowLayout` ships untested** — ~35 lines of custom `Layout` on the onboarding paywall, no coverage of its wrap arithmetic.
- **Free users can write `TriggerEvent`s they can never read back.** `ShopView.swift:139` leaves `.recordTrigger` ungated by decision, but `LifeEventsSheet` is inside `.proGated(.treatments)`. Same shape as the write-path leaks Task 7 closed for the other three actions.
- **Safety and honesty copy moved behind the wall** — `severeSideEffectBanner` ("You logged a severe side effect — worth discussing with your prescriber") and `gateExplainer` (the central "density change is judged at 24 weeks" colophon) are both inside `CareView`'s gate. A lapsed subscriber who logged a severity-3 side effect never sees the nudge again.
- **Gate-boundary conventions differ across five screens** — header outside on Trends (deliberate, Export) and Plan, inside on Labs and Photos, whole-`ScrollView` on Compare and Procedures.
- **`.journey` and `.bodySignals` gate cards are unreachable** — both components only render inside `TrendsView`'s `.trends` gate, so 2 of 12 gate cards are dead copy. Keep them; they're one refactor from being reachable.
- **`\.entitlements` is not re-injected on `RootView`'s covers** (`:380-386`, `:406-409`) the way `healthKit` and `purchases` are. Latent — the first `.proGated(…)` added to onboarding would hard-lock a Pro subscriber via the `.free` default.

## 5. Rulings made during the run — recorded so they aren't "fixed" later

- **`BaselineFlow.swift:131` reading `purchases.hasPro` directly is CORRECT.** It gates the Manage-Subscription section, which drives Apple's `manageSubscriptionsSheet` — meaningless without a real StoreKit subscription. A `.taster` has none, so `canAccess` would be the wrong question. Re-examined at final review and upheld.
- **The widget's streak is computed from UNFILTERED entries, deliberately.** Filtering would make the number *wrong*, not private — it would collapse toward zero and disagree with what `TodayView` and the evening reminder already show. A streak reveals "logged N consecutive days", strictly less than the locked-day count the free tier is already shown. Re-examined at final review and upheld. The comment at `WidgetBridge.swift:153-158` is the reason nobody will "fix" it later — leave it there.
- **Today's SLEEP row showing today's HealthKit hours is fine.** Today's own values are on the free side of the spec's packaging table, and the row falls back to free self-reported sleep.
- **`requiresAppleIntelligence` using `default: false` is fine.** `onlyTheTwoAIFeaturesNeedAppleIntelligence` asserts the exact set, so a thirteenth AI case fails the build.
