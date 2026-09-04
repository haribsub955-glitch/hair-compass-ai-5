# Release readiness — 4 September 2026

## Decision: NO-GO for public release

The UI work is not a release certification. **Account-side payments are configured:** both live
subscriptions are approved and available, and the Paid Apps Agreement, bank account, and tax
forms are active. Purchase delivery on the final TestFlight build remains unverified.

This is a review, not authorization to submit. No submission, upload, App Store Connect edit,
pricing change, agreement acceptance, or real purchase was made. The user's subsequent
instruction explicitly limits further work to review; no further app-code changes were made.

## Release gates

| Gate | Evidence / current status | Required next action |
| --- | --- | --- |
| Provider credentials | **Blocked.** `HCDeepSeekAPIKey` is populated in the existing Debug and Release app bundles. Current Release build settings also resolve a provider credential. Values were not printed. `Config/AI.xcconfig` includes local secrets for both configurations; `CloudAIConfig` reads the expanded Info.plist value. Gitignore does not protect a distributed binary. | Keep provider credentials on an authenticated, metered production backend. Do not distribute this bundle. Rotate any credential included in builds already shared externally. |
| Production AI/backend | **Unverified/incomplete for the server-agent route.** `AgentBridge` is Debug-only. Its client construction does not connect StoreKit purchases to a subscription token. The handover assigns identity, ownership binding, metering, and server deployment to Mohammed's server. | Owner must confirm production backend and coordinate its readiness. An explicitly chosen on-device-only release is a different product scope and must update capability claims; it was not silently selected. |
| App Store payments | **Account configuration verified.** Monthly `com.harib.haircompass.pro.monthly2` and yearly `com.harib.haircompass.pro.yearly2` are **Approved**, with all countries/regions selected and current pricing for 175 storefronts. Paid Apps Agreement, bank account, and both displayed tax forms are **Active**. Prices are read from StoreKit in the app. | Complete sandbox/TestFlight purchase, cancellation, pending approval, restore, expiry, and refund validation on the final build. Local configuration is not proof of live checkout. |
| Stable candidate/build | **No stable candidate certified.** Other active tasks are editing this checkout. One fresh build encountered a temporary onboarding initializer mismatch; another could not resolve `StarterPlanAdviceSheet` while its file was being added. The final focused retry encountered a locked Xcode build database from concurrent builds. These are observations during active work, not proof the eventual finished revision still has those compilation errors. | Finish the onboarding/trends work, freeze a specific source revision, and build/test that exact revision without concurrent builds. Do not overwrite another task's in-progress files. |
| Tests | Initial audit: **675/677 unit tests passed**; two photo comparison tests had outdated expectations. **20/20 UI tests passed** in the run log. The xcresult could not finalize because storage ran out. New StoreKit tests independently type-check, but did not execute because fresh host builds were interrupted by concurrent changes/build contention. | The two assertions now require the existing incomplete-setup warning (production logic unchanged). Rerun the full suite and payment lifecycle tests on a stable candidate. No clean full-suite result is claimed. |
| Distribution signing/version | Development and distribution signing identities are present. The cached Release app passes local signature verification but has development-style provisioning. Project version is **1.1 (5)**, and version 1.1 already has **build 5** attached in ASC. Its status is **Developer Rejected**; version 1.0 is **Ready for Distribution**. | Use a new build number for the next upload. Create and validate a fresh App Store distribution archive/export from the final revision, including widget and entitlements. No archive/upload performed in this review. |
| Privacy/claims | Public privacy and support pages returned HTTPS **200**. ASC publishes Health, Fitness, and Other User Content for app functionality, not linked to identity. However, version 1.1 description/review notes and the U.S. subscription descriptions still claim **on-device AI**, while the local release configuration enables direct DeepSeek cloud processing and the public policy describes it. | Reconcile actual production architecture, consent, policy, marketing, subscription descriptions, and review notes. Do not submit inconsistent capability/privacy claims. |
| Regional compliance | Business shows Digital Services Act verification **In Review** for 27 countries/regions. | Confirm verification outcome and intended EU availability before a worldwide release; this observation is not a claim that all other storefronts are blocked. |
| Disk capacity | Initially about **0.5–0.6 GB free**; Xcode reported `No space left on device`. A later check showed about **10 GB available**. No files were deleted by this audit. | Recheck adequate storage before a full final test run and archive; previous incomplete results remain invalid even after space returns. |
| Physical-device acceptance | Not performed in this audit. Simulator checks do not certify real camera, HealthKit, Face ID, widget/Live Activity delivery, or hardware-dependent AI. | Test the final TestFlight build on supported physical iPhones, including denied permissions, offline state, data recovery, restore, and subscription expiry/refund. |

## Changes made in this audit

The following local changes preceded the user's review-only clarification; no production
purchase or AI logic was altered:

- Corrected two stale `PhotoCompareMismatchTests` expectations. Missing capture setup still
  produces a caution rather than falsely claiming comparability.
- Added `StoreKitPurchaseIntegrationTests`: local-engine coverage for both plans, restoration,
  expiration, cancelled/failed purchases, Ask to Buy approval, and refund. This is not evidence
  of production billing until it runs successfully, and even then proves only the local path.
- Added a read-only bundle preflight that withholds credential values:

```sh
bash scripts/release-preflight.sh "/absolute/path/Hair Compass AI 5.app"
```

The preflight rejected the existing Release bundle for its embedded credential and provisioning.
It does not change the bundle or automatically disable cloud features. It is a limited local
check, not a substitute for Xcode distribution validation or the external gates above.

## Live App Store Connect observations

- Correct app confirmed by bundle ID `harib.Hair-Compass-AI-5`, Apple ID `6803796144`.
  A second similarly named app record was not used.
- [Premium subscription group](https://appstoreconnect.apple.com/apps/6803796144/distribution/subscription-groups/22339186)
  is approved. Monthly is at level 1 and yearly at level 2. The app grants the same Pro
  entitlement for both; review whether those service levels are intentional before testing
  plan switching. The local StoreKit fixture puts both at level 1, so it does not model that
  live difference. No group configuration was changed.
- [Monthly](https://appstoreconnect.apple.com/apps/6803796144/distribution/subscriptions/6805916317):
  approved, all countries selected, current pricing present, 3-day introductory free trial
  displayed for all 175 storefronts.
- [Yearly](https://appstoreconnect.apple.com/apps/6803796144/distribution/subscriptions/6805915811):
  approved, annual upfront available in all countries, current pricing present, no introductory
  offer displayed. Do not promise a StoreKit free trial on this plan.
- Billing grace period is not configured. This is not, by itself, a release blocker.
- App Store server notification production/sandbox URLs are not configured. Their necessity
  depends on the finalized backend subscription architecture; do not treat them as mandatory
  for every device-only StoreKit implementation.
- Version 1.1 currently selects **automatic release after approval**. It was not changed.
  “Developer Rejected” indicates the version was withdrawn by the developer; it is not an
  Apple rejection finding.
- [Business](https://appstoreconnect.apple.com/business): Paid Apps Agreement, banking, and tax
  statuses active; DSA verification in review. Private financial details were not copied here.
- [App Privacy](https://appstoreconnect.apple.com/apps/6803796144/distribution/privacy): published
  Health, Fitness, and Other User Content, used for app functionality, not linked to identity.

## Audit artifacts

- Full pre-change run log: `/tmp/hc-release-audit-tests.log` (20 UI passes; 2 old unit failures).
- Incomplete result bundle: `/tmp/hc-release-audit-tests.xcresult` — do not treat as a clean run.
- Fresh-build failure log: `/tmp/hc-release-unit-payments.log`.
- Second build failure log: `/tmp/hc-release-unit-payments-recheck.log`.
- Focused retry log: `/tmp/hc-release-focused-storekit.log` (Xcode build database locked).
- New StoreKit test type-check log: `/tmp/hc-storekit-typecheck.log` (passed).
- Last successful Today-focused result from before concurrent edits:
  `/tmp/hc-today-checkin-final.xcresult` (32/32 focused tests).

## Apple references verified during the audit

- [In-App Purchase configuration prerequisites](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/): the Account Holder's Paid Apps Agreement, banking/tax, and product setup are separate from app code.
- [Submitting an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/): first submissions of an IAP/subscription type must accompany a new app version.
- [Testing at all stages](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox): Xcode local tests and App Store sandbox/TestFlight are distinct validation stages.

## Owner decisions needed

1. Confirm the production AI/backend path with Mohammed; do not ship provider credentials.
2. Reconcile store/review/subscription claims with that final architecture and review subscription
   service levels and EU verification status.
3. Finish concurrent edits, then validate a frozen candidate with a new build number, a clean
   full test result, distribution signing, and sandbox/TestFlight purchases on physical devices.
4. Keep submission and public release out of scope unless separately authorized.
