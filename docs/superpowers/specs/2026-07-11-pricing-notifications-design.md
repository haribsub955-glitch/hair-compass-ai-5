# Launch pricing + beautiful reminders — Design (2026-07-11)

Two changes: the yearly launch discount (user-chosen "$79 struck to $39, limited 50% off")
implemented Apple-honestly, and a beautification pass on the reminder notifications.

## 1. Pricing — $5/mo, $39/yr launch (struck from $79)

**User decision:** show the yearly as `~~$79~~ $39/year · limited-time 50% off`, 3-day trial
then subscribe, Apple-aligned.

**Honest, Apple-compliant realization** (so both numbers are real, not a display anchor):
- **Yearly base price = $79/year** (the genuine renewal price). Introductory offer =
  **pay-up-front $39 for the first year** (`payUpFront`, `P1Y`, 1 period). StoreKit then
  supplies the paywall with `product.displayPrice` = "$79" (struck) and the intro offer's
  `displayPrice` = "$39" (charged). It renews at $79, so "$39, then $79" is truthful and
  "50% off the first year" is a real discount. Neither number is hardcoded.
- **Monthly base price = $5.00/month**, keep the **3-day free-trial** intro offer.
- Apple allows one introductory offer per subscription group per Apple ID, so a user gets the
  monthly 3-day trial **or** the yearly $39-first-year — whichever they pick at the paywall.
  The paywall shows both; eligibility already gates the CTAs.
- **"Limited-time"** is honest only if the offer has an end date in App Store Connect — the
  in-app label says "Limited-time" but there is **no fake countdown timer**.

**PurchaseService additions:**
- `launchOffer(for:) -> (intro: String, base: String, percentOff: Int)?` — for a product whose
  intro offer is `.payUpFront`/`.payAsYouGo`: returns the intro `displayPrice`, the base
  `displayPrice`, and `percentOff = Int(((base − intro) / base × 100).rounded())` computed from
  the real `Decimal` prices (never a literal). nil when no such offer.
- Keep `trialDescriptor(for:)` (monthly free trial) and `isEligibleForIntro(_:)`.

**Paywall (`OnboardingPlanStep`) + `ProGate` yearly CTA** — when the yearly has a launch offer
and the user is eligible:
- Price line: `Text("$79").strikethrough()` (base) next to `Text("$39")` (intro, bold), then
  `"/year"`; a small line "First year — save {percentOff}%, then $79/year · Limited-time".
- CTA label: "Start yearly — $39 first year".
- When not eligible / no offer: fall back to the plain base price ("Yearly — $79/year").
- Monthly stays "3-day free trial, then $5/month".
- "Continue free" stays equally prominent; no timers/scarcity beyond the honest "Limited-time"
  label; restore present.

## 2. Beautiful reminders — balanced, minimal text, an image

**Principle:** fewer, prettier, quieter. Keep the existing balanced cadence (opt-in evening
check-in ≤1/day skipped when logged; the user's own treatment-time reminders; refill; monthly
photo) — do **not** add more. Make each one:
- **Short + evocative copy** (few words, no paragraphs). Examples:
  - Evening check-in → title "Tonight's check-in", body "Twenty seconds."
  - Treatment → title "{treatment}", body "A tap when it's done."
  - Refill → title "Running low", body "Time to reorder {name}."
  - Photo → title "Monthly photo", body "Same light, same spot."
  (Keep the streak-aware evening variant, shortened.)
- **A brand image attachment** so the notification renders with a warm thumbnail, not just
  text. A `NotificationArt` helper loads a bundled gouache asset (`brand-sprig` or
  `brand-medallion`) via `UIImage(named:)`, writes it once to a Caches JPEG, and returns a
  `UNNotificationAttachment`; attach it to every reminder's `UNMutableNotificationContent`.
  Fail-soft: if the attachment can't be built, schedule without it (never drop the reminder).
- Titles drop the redundant "Hair Compass" prefix (the app name already shows in the banner).

No cadence/scheduling logic changes — only content (copy + attachment). The ≤1/day evening
cap, coalescing guard, and identifiers stay as-is.

## Verification honesty
The paywall can't be screenshotted without the `.storekit` config selected in the run scheme
(products don't load in a plain sim launch) — verified by build + code review, and the numbers
are pulled from StoreKit, not literals. Notifications can't be triggered/inspected headlessly —
verified by build + code review; the image + copy are felt on a device.

## Execution
Two Sonnet tracks (disjoint files): A commerce (storekit + PurchaseService + OnboardingPlanStep
+ ProGate), B notifications (NotificationService + a NotificationArt helper). Fable integrates,
builds both targets, runs tests, commits.
