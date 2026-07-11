# Launch pricing + beautiful reminders — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the $5/mo + $39/yr-launch (struck from a real $79, Apple-honest) pricing, and make the reminder notifications few, beautiful, and low-text with a brand image.

**Architecture:** Two parallel Sonnet tracks, disjoint files. Spec: `docs/superpowers/specs/2026-07-11-pricing-notifications-design.md`. Same constraints (Clinical tokens, honesty rules, **agents do not run xcodebuild/git**, quote paths). No cross-track shared symbols.

---

### Task A: Launch pricing (honest, Apple-aligned)

**Files (owns exclusively):** `HairCompass.storekit`, `Hair Compass AI 5/Service/PurchaseService.swift`, `Hair Compass AI 5/Feature/Onboarding/OnboardingPlanStep.swift`, `Hair Compass AI 5/Feature/ProGate.swift`.

- [ ] **A1: StoreKit config.** In `HairCompass.storekit`:
  - Monthly (`com.harib.haircompass.pro.monthly`): `displayPrice` "4.99" → **"5.00"**. Keep its `introductoryOffer` (`paymentMode: "free"`, `P3D`).
  - Yearly (`com.harib.haircompass.pro.yearly`): `displayPrice` "29.99" → **"79.00"**; replace its `introductoryOffer` with a pay-up-front first-year discount:
    ```json
    "introductoryOffer" : {
      "displayPrice" : "39.00",
      "internalID" : "9C1A4E33",
      "numberOfPeriods" : 1,
      "paymentMode" : "payUpFront",
      "subscriptionPeriod" : "P1Y"
    }
    ```
    (Use a unique `internalID` not already in the file — grep the existing ones.)
  - Validate the file parses as JSON.

- [ ] **A2: PurchaseService.** Add (verify `Product.SubscriptionOffer.PaymentMode.payUpFront`/`.payAsYouGo`, `.price` (Decimal), `.displayPrice`, and `product.price`/`.displayPrice` against the iOS 26.2 StoreKit `.swiftinterface` first):
  ```swift
  /// For a product whose intro offer is a paid launch discount (pay-up-front / pay-as-you-go):
  /// the intro price, the base price, and the honest rounded percent off — all from real prices.
  func launchOffer(for product: Product) -> (intro: String, base: String, percentOff: Int)? {
      guard let offer = product.subscription?.introductoryOffer,
            offer.paymentMode == .payUpFront || offer.paymentMode == .payAsYouGo,
            product.price > 0 else { return nil }
      let base = product.price
      let intro = offer.price
      let pct = ((base - intro) / base * 100)
      let percentOff = Int((pct as NSDecimalNumber).doubleValue.rounded())
      return (intro: offer.displayPrice, base: product.displayPrice, percentOff: percentOff)
  }
  ```
  Keep `trialDescriptor(for:)` and `isEligibleForIntro(_:)` unchanged.

- [ ] **A3: OnboardingPlanStep yearly CTA.** Read the current `buy(yearly)` block + the `yearlyIntroEligible` `.task`. When `yearlyIntroEligible` AND `purchases.launchOffer(for: yearly) != nil`, render:
  - a price row: `Text(base).strikethrough().foregroundStyle(Clinical.tertiary)` then `Text(intro).font(...semibold).foregroundStyle(Clinical.ink)` + `Text("/year")`;
  - the CTA label "Start yearly — \(intro) first year";
  - a subtext line (11pt secondary): "First year — save \(percentOff)%, then \(base)/year · Limited-time".
  Else fall back to the existing "Start with yearly — \(yearly.displayPrice)/year". Monthly button stays "3-day free trial, then \(monthly.displayPrice)/month" via `trialDescriptor`. "Continue free" + restore unchanged; no countdown.

- [ ] **A4: ProGate yearly CTA.** Same `launchOffer` treatment on ProGate's yearly button (read it first); minimal, consistent with A3.

- [ ] **A5:** No unit test (StoreKit-bound); the percent-off math is pure — optionally add a tiny test if you can construct the inputs, else skip. Orchestrator build-verifies.

### Task B: Beautiful reminders

**Files (owns exclusively):** `Hair Compass AI 5/Service/NotificationService.swift`, new `Hair Compass AI 5/Service/NotificationArt.swift`.

- [ ] **B1: NotificationArt helper.** Create `NotificationArt.swift`:
  ```swift
  import UIKit
  import UserNotifications

  /// Builds a reusable image attachment so reminders render with a warm brand thumbnail
  /// instead of bare text. Writes a bundled gouache asset to a Caches JPEG once and reuses it.
  /// Fail-soft: returns nil if the asset/file can't be produced — the reminder still schedules.
  enum NotificationArt {
      static func attachment() -> UNNotificationAttachment? {
          let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
              .appendingPathComponent("reminder-art.jpg")
          if !FileManager.default.fileExists(atPath: url.path) {
              guard let image = UIImage(named: "brand-sprig"),
                    let data = image.jpegData(compressionQuality: 0.9) else { return nil }
              guard (try? data.write(to: url)) != nil else { return nil }
          }
          return try? UNNotificationAttachment(identifier: "reminderArt", url: url, options: nil)
      }
  }
  ```
  (Confirm `brand-sprig` exists in Assets; if a more centered motif reads better as a thumbnail — e.g. `brand-medallion` or `brand-dropper` — use that. Pick one recognizable gouache asset.)

- [ ] **B2: Short copy + attach the image.** In `NotificationService.performReschedule` and `planEveningCheckIn`, for every `UNMutableNotificationContent` built:
  - Set `content.attachments = [a]` when `NotificationArt.attachment()` returns one.
  - Replace the copy with short, evocative lines (drop the "Hair Compass" title prefix — the app name shows in the banner already):
    - Treatment: `title = t.name.isEmpty ? t.treatmentClass.title : t.name`; `body = "A tap when it's done."`
    - Refill: `title = "Running low"`; `body = "Time to reorder \(r.name)."`
    - Photo: `title = "Monthly photo"`; `body = "Same light, same spot."`
    - Evening check-in: `title = "Tonight's check-in"`; body = streak-aware but short — `streak >= 3 ? "Day \(streak + 1). Twenty seconds." : "Twenty seconds."`
  - Keep all identifiers, triggers, the ≤1/day evening cap, the skip-when-logged logic, and the coalescing guard exactly as-is — **content only**.

- [ ] **B3:** No unit test (side-effecting scheduling). Orchestrator build-verifies; note the image/copy are felt on a device.

### Task C (orchestrator): integrate, build, test, commit
- [ ] Validate `HairCompass.storekit` parses; build app + widget targets; run unit tests; commit per track + spec/plan. Note honestly that the paywall pricing needs the `.storekit` selected in the scheme to render live, and notifications are felt on-device — both are build + code verified here.
