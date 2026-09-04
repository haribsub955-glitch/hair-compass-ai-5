# Codex handover — trustworthy Trends and sparse-state guidance

**From:** Codex
**Date:** 2026-09-04

## What changed

- `DailyEntry` now records which daily signals the user actually answered. New logs no longer turn untouched default control values into observations. Legacy rows with no presence metadata remain readable as fully answered for migration compatibility.
- Trend calculations now aggregate duplicate entries by calendar day, use calendar-aware trailing means, avoid future-data leakage, use rank correlation, and require real lag-paired overlap.
- Trend, report, evidence, export, agent-context, and clinician-flag paths now ignore missing signals and use minimum-data thresholds before claiming direction or association.
- The Trends tab adapts its primary evidence to the selected hair-loss profile:
  - shedding for telogen effluvium or uncertain profiles;
  - scalp symptoms for seborrheic dermatitis;
  - standardized photos for androgenetic alopecia, alopecia areata, and traction alopecia.
- Sparse users see an honest progress state and up to three live unfinished items from their current starter plan. Empty charts, premature range controls, and confident trend language are withheld until there is enough evidence.
- The fixed 24-week interpretation is now limited to androgenetic alopecia profiles. Scalp scoring is described as an adapted self-report score, not a validated clinical scale.

## Compatibility notes

- `recordedSignalsRaw == nil` means a legacy entry and is interpreted as all signals answered.
- `recordedSignalsRaw == ""` means a new entry with no quantitative signals answered.
- Backup export/import preserves the new field; older backups decode with `nil` and retain legacy behavior.
- Generic repository inserts explicitly create entries with no recorded signals, while focused quick-log and onboarding paths set only the signals they collect.

## Verification

- Simulator build passed for iPhone 17 Pro / iOS 26.2.
- Focused model, Trends, body-signal, report, evidence, backup, AI-context, and research-payload tests passed.
- The sparse photo-led Trends state was visually checked in the simulator after the final layout changes.

## Existing repository state

`CLAUDE.md`, `Hair Compass AI 5.xcodeproj/project.pbxproj`, `.codex/`, and `AppStoreScreenshots/` were already modified or untracked before this work and were not intentionally changed as part of this implementation.

## Onboarding motion and artwork — 2026-09-04

- Replaced the long onboarding upsell with an internal plan → example record → pricing journey. Back and a free exit remain available; the final screen still calls the original completion path and opens Plan.
- Added two image-generator illustrations as sibling assets: `onboarding-plan-journal` and `onboarding-wren-support`. The original gouache assets are unchanged. Exact prompts, provenance and motion timings are in `docs/OnboardingMotionAssets.md`.
- Shared `OnboardingPlanCards` compact the same source items between moments. `OnboardingPlanDetails` preserves the full read-only plan. The parallel roadmap task integrated its clinician-first priorities and safety/source information; preserve those edits.
- `OnboardingRecordPreview` has a cancellable, one-shot entry-to-week transition and a clearly labeled Wren example. It never writes health data or calls AI. Reduce Motion and the existing static QA flag render its complete meaning immediately.
- Price selection only moves a background; buying is a separate action. `OnboardingPriceCopy` renders actual StoreKit currency, billing periods and eligible offer terms, including non-yearly introductory durations. Existing purchase/restore/availability/consent mechanisms remain in place. Active subscribers are not sold a second subscription.
- Added `OnboardingOfferTests` and `OnboardingOfferUITests`, including opt-in local StoreKit purchase/cancellation checks. The payment checks are not verified in this simulator environment; no account credentials were entered and no purchase was confirmed.
- The initial simulator app build passed. Verification uses a temporary project copy at `/tmp/HairCompass-OnboardingWorkspace.zQf0FU` with source directories symlinked to this workspace, because the original workspace hit an Xcode file-coordination lock. The failed first isolated build was caused by full disk; only this task's disposable build directory and new test simulator were removed. No user records were erased.
- Interruption fix: `LaunchPresentationState.keepsOnboardingMounted` separates keeping the flow alive from which surface is visible on top. Root's onboarding cover now uses that flag. Privacy still wins visually via the existing separate window, and lock/recovery still prevent onboarding presentation. This avoids tearing down a StoreKit/permission-sheet presenter merely because the scene becomes inactive.
- Final focused run: **25 passed, 0 failed, 2 skipped** on iPhone 17 Pro / iOS 26.3.1 (`/tmp/HairCompass-OnboardingWorkspace.zQf0FU/UXVerified.xcresult`). Covers 18 units and 7 UI checks: full free flow into Plan, selection without purchase, back/replay, static motion, background return, existing Pro, large text and availability disclosure. The two payment UI checks now require an explicitly confirmed local-store environment via `HC_UI_STOREKIT_TESTING=1`; earlier attempts and the separate app-hosted payment service suite reached Apple Account sign-in instead of local transactions. That service run was stopped, not counted as passing. Complete payment verification from Xcode with local StoreKit correctly attached before release. `git diff --check` passed; actual screenshots and exact image-generation prompts are in `docs/OnboardingMotionAssets.md`.
