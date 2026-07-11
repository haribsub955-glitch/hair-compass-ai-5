# 3-Day Free Trial — Rollout Plan

How Hair Compass Pro gives new users a 3-day free trial, honestly and correctly. This is the
business/config playbook; the code hooks are implemented in the round-5 implementation plan.

## What a "free trial" is on the App Store

An Apple **introductory offer** of type *Free* attached to an auto-renewing subscription.
The user starts the subscription, is charged nothing for the intro period (3 days), and is
then auto-charged the standard price unless they cancel. Cancelling during the trial keeps
Pro until the trial ends and prevents the charge. This is Apple's only sanctioned "free
trial" mechanism — there is no separate trial SKU.

## Eligibility rules (Apple-enforced — design around these)

- **One introductory offer per subscription group, per Apple ID (and Family Sharing group).**
  Our group is `21442176` ("Pro"), containing monthly + yearly. A user who has ever used the
  intro on *either* product is ineligible on *both*. So we must check eligibility and not
  promise a trial to someone who can't get one.
- Eligibility is queried at runtime with `Product.SubscriptionInfo.isEligibleForIntroOffer`
  (per subscription group). The UI shows the trial CTA only when eligible; otherwise it shows
  the plain price CTA. Never show "Start free trial" to an ineligible user — that's the exact
  App-Store-rejection / trust-loss trap.

## Configuration

### App Store Connect (production — must be done by the account holder, not in code)
1. Subscriptions → Pro group → each subscription → **Introductory Offers** → Create.
2. Type: **Free**. Duration: **3 days**. Territories: all. Start/end: no end (ongoing intro).
3. Add localized display; submit with the next app version. Offers are reviewed with the app.
4. Paid Apps agreement + banking must be active or offers won't surface.

### Local (this repo — for development/simulator, already in the impl plan)
`HairCompass.storekit` → each subscription gets:
```json
"introductoryOffer" : {
  "displayPrice" : "0.00",
  "internalID" : "<unique>",
  "numberOfPeriods" : 1,
  "paymentMode" : "free",
  "subscriptionPeriod" : "P3D"
}
```
Run the app with this `.storekit` file selected in the scheme's StoreKit configuration to
exercise the trial in the simulator (Editor → StoreKit → "Manage Transactions" resets
eligibility for re-testing).

## UX (honest by construction)

- Primary CTA when eligible: **"Start 3-day free trial"**, with subtext
  **"then {price}/{period} · cancel anytime · no charge for 3 days."**
- The post-trial price is always visible next to the CTA. No countdown timer, no "limited
  time", no pre-checked upsell. "Continue free" remains equally prominent (the app is fully
  usable without Pro).
- Trial state: `hasPro` is true during the trial (entitlement is active), so Pro features
  unlock immediately and lock again if the user cancels and the trial lapses.
- A short line in Settings/Plan explains "Manage or cancel in the App Store" (StoreKit's
  `manageSubscriptionsSheet`), so cancelling is never hidden.

## Metrics to watch after launch (not built here)

Trial-start rate, trial→paid conversion, and — most important for this app's ethics — whether
trial users who *don't* convert still keep using the free tier (they should; the free tier is
the product, Pro is the AI layer). If trial pressure hurts free-tier retention, soften the
paywall, don't harden it.

## Out of scope

Offer codes / promo offers, win-back offers, and paywall A/B testing — all future work.
