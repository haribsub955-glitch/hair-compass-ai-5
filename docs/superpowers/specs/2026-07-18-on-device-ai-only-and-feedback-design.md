# On-device-only AI + Feedback + App Store readiness

**Date:** 2026-07-18
**Branch:** `feature/on-device-ai-only`
**Status:** approved (user authorized autonomous implementation)

## Goal

Make **all** AI run on Apple Foundation Models on-device. Remove every cloud/proxy path,
the API key plumbing, and the off-device consent flow. Keep Pro as a **local** entitlement
gate. Add a user feedback button. Get the build App-Store-submittable.

## Decisions (confirmed by the user)

1. **Photo AI → dropped.** Foundation Models is text-only (no image input). Scalp-photo
   *interpretation* has no on-device path, so it goes away. Photos + on-device Vision OCR stay.
2. **Pro subscription → kept, gated locally.** AI (chat, insights, written analysis) stays
   Pro-only but runs on-device at $0 API cost. `PurchaseService.hasPro` is the only gate;
   no server verification (there's no server).
3. **Unsupported devices → clear "needs iPhone 15 Pro or newer" state.** No cloud fallback.
   Insights degrade to the existing rule-based paragraph; chat/analysis show an unavailable card.

## What the AI surfaces become

| Feature | Before | After |
|---|---|---|
| Daily insight | on-device + rule fallback | **unchanged** (already had no cloud) |
| Hair chat | on-device → cloud fallback (consent) | **on-device only**; unavailable card otherwise |
| Deep analysis | cloud, sends scalp photos to Anthropic | **on-device written analysis of the tracking record** (text only, no photos sent) |
| Ingredient ID | on-device OCR → cloud photo call (consent) | **on-device OCR → on-device text summary** |

## Changes

**Delete**
- `Service/AIGateway.swift` (the only cloud egress).
- `server/` (proxy — no longer used).
- `AIConsent` and `AIConfig` (consent + key/proxy) from `CloudAnalysisService.swift`.
- `AIConsentSheet` (in `DeepAnalysisSheet.swift`) and every consent sheet/gate call site.

**Rewrite / rename**
- `Service/CloudAnalysisService.swift` → `Service/OnDeviceAnalysisService.swift`
  (`OnDeviceAnalysisService` + an `OnDeviceAnalysis` FoundationModels wrapper mirroring
  `OnDeviceChat`/`OnDeviceInsight`). `isAvailable` replaces `hasKey`; `analyze(context:)`
  drops the `images` param; `analyzeIngredients(labelText:)` takes OCR text, not an image.
- `Service/HairChatService.swift` — on-device only; `isAvailable` replaces `hasKey`;
  remove cloud body + consent gate.

**Reshape UI**
- `HairChatSheet.swift` — drop consent card/state; on-device availability gating; unavailable card.
- `DeepAnalysisSheet.swift` — drop consent toggle + "sends to Anthropic" copy + `images`;
  on-device availability gating; copy = private on-device record analysis.
- `TodayView.swift` / `AddTreatmentSheet.swift` — remove consent sheets/state; open features directly.
- `BaselineFlow.swift` — remove the "Cloud photo analysis" consent row from Privacy; **add the
  Feedback button** here (the profile/settings hub).
- `App/HairCompassApp.swift` — remove `AIConfig.seedKeyIfProvided()`.

**Feedback (new, no backend)**
- `Feature/FeedbackButton.swift` — a reusable button + `MFMailComposeViewController`
  representable. Opens a mail composer prefilled to `AppInfo.feedbackEmail` with app version +
  device/iOS diagnostics. Falls back to a `mailto:` link, then an alert with the address, when
  no mail account is configured. Collecting feedback via email keeps the app fully on-device /
  backend-free (consistent with decision 1–2).
- `AppInfo.feedbackEmail` — the destination (defaults to the owner's email; editable).

**App Store readiness**
- `PrivacyInfo.xcprivacy` — nothing leaves the device now, so `NSPrivacyCollectedDataTypes`
  becomes empty (was Health + Photos). Required-reason API declarations stay.
- Legal URLs already set (`AppInfo`). Encryption flag already `false`. Paywall legal intact.

**Tests**
- `PrivacyTests.swift` — remove the two `AIConsent` / `CloudAnalysisService` tests; keep App Lock.

## Out of scope
- CloudKit sync, accounts, Supabase — explicitly not part of this change.

## Release deliverable
- Implement + build clean on this branch; then a Claude-data-free copy of the project folder
  for release (per the user's request), reminding once that a git branch already versions this.
