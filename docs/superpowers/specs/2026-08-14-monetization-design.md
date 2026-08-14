# Monetization — hard wall, compounding lock, open storefront

**Date:** 2026-08-14
**Status:** Design approved in conversation; spec under review
**Author:** brainstormed with Claude Code

---

## 1. Summary

Hair Compass earns nothing today from most of its installed base and nothing at all from its
storefront. This spec closes both gaps.

Three changes, in order of revenue impact:

1. **A hard freemium wall.** Free users may check in daily, forever, but see only *today*.
   Every past entry, every trend, every photo, every lab is Pro. The lock is expressed as a
   counter that grows each day they stay free — loss aversion on their own data rather than a
   button that refuses to work.
2. **Pro decoupled from Apple Intelligence.** Today a subscription is unsellable on ineligible
   hardware, because the only two things it gates need on-device models. After this change Pro
   sells on every iPhone; only two of its features carry a hardware notice.
3. **The affiliate storefront switched on and moved to the free side of the wall.** It is fully
   built and currently ships zero links.

Funnel: **3-day local taster (no payment method) → 14-day App Store trial → $6.99/month.**

## 2. Current state

### 2.1 What exists and works

`Service/PurchaseService.swift` is a complete StoreKit 2 implementation — entitlement refresh
from `Transaction.currentEntitlements`, purchase state machine, restore, plain-language error
mapping, introductory-offer eligibility, and an honest yearly-vs-monthly comparison
(`yearlyVersusMonthly()`) whose doc comment correctly distinguishes a legitimate 12×-monthly
comparison from an illegal fictitious reference price. **No changes needed to the purchase
layer itself.**

Two purchase surfaces exist: `Feature/Onboarding/OnboardingPlanStep.swift` (onboarding step 12)
and `Feature/ProGate.swift` (inline, inside feature sheets).

`Service/AffiliateStore.swift` is likewise complete — bundled JSON, remote refresh, UserDefaults
caching, a four-step resolution order, and 64 KB / 32-link payload caps.

### 2.2 What is broken or unused

- **Pro gates exactly two features.** `ProGate` is applied at `Feature/HairChatSheet.swift:34`
  and `Feature/DeepAnalysisSheet.swift:33`. Nothing else. `OnboardingPlanStep.swift:290`
  enforces this deliberately: "If a benefit isn't behind `hasPro`, it does not appear."
- **Both need Apple Intelligence, so Pro is unsellable without it.**
  `ProAvailability.sellable()` (`Feature/ProAvailability.swift:50`) returns `false` for
  `.deviceNotEligible`, and both paywalls withdraw their purchase buttons. On an iPhone 14, or
  a non-Pro 15, the app cannot sell anything at all.
- **The storefront earns nothing.** `Resources/AffiliateLinks.json` contains `"links": {}` and
  `AffiliateStore.RemoteConfig.catalogURLString` is `""`. Every buy button is hidden.
- **The storefront is on the wrong side of the wall.** `RecommenderView`,
  `InClinicOptionsView` and the science-backed product rows are presented from inside
  `Feature/CareView.swift:207,220` — the Plan tab, which this spec makes Pro.

### 2.3 Navigation as it stands

`App/RootView.swift:37` — `enum AppTab { today, trends, care, labs, photos }`. Under the wall,
four of those five become Pro. `LearnView` hangs off `Feature/TodayView.swift:242` and stays free.

## 3. The reframe — why the server's plan model does not transfer

Branch `feat/agent-platform-server` (Mohammed Al Moosawi, 2026-08-08) vendored a complete,
costed monetization model into `agent-platform/`. `src/agent_core/plans.py` defines four plan
rows — `free` (rank 0, the *lapsed* state, not a tier), `taster` (3 days, no payment method,
5 turns), `trial` (14 days, Apple's introductory offer, ~19 turns), and `pro_monthly` /
`pro_yearly` (ranks 100/110, identical limits by design).

**Its economics are built to ration cloud inference.** `TOKENS_PER_TURN = 18_000`, weekly budget
windows, lifetime ceilings, and comments sizing exposure at "~$1.70 per trial user, so a thousand
trials is $1,700 before revenue."

**The shipping app has no such cost.** `feature/on-device-ai-only` runs Foundation Models
on-device. Marginal cost per turn is zero. Two consequences, both favourable, and both are
design decisions in this spec:

- **Gate on features, never on usage.** Any turn cap would be artificial scarcity that costs
  nothing to lift. "Unlimited AI, on your device, private" is a selling point instead of a cost
  centre.
- **The taster needs no abuse defence.** Mohammed capped his at 5 turns because it is farmable
  by reinstall and each turn is real money. On-device, a farmed taster costs $0, so the local
  version can be generous and needs no server, no receipt, and no device binding.

What *does* transfer: the **$6.99/month price anchor** (his budget comment sizes against
"~$5.94 net after Apple's 15% Small Business rate on a $6.99 subscription") and the **14-day
trial length**, which he costed and justified — the app's own efficacy gate is 24 weeks, so no
trial of any length shows an outcome; what it can show is the tracking loop.

## 4. Packaging

| Capability | Free | Pro |
|---|---|---|
| Daily check-in — unlimited, forever | ✅ | ✅ |
| Today's own values, as entered | ✅ | ✅ |
| Streak count (the number only) | ✅ | ✅ |
| Shop / product browsing | ✅ | ✅ |
| Learn library | ✅ | ✅ |
| Export own data | ✅ | ✅ |
| Any past check-in | ❌ | ✅ |
| Consistency chart, averages | ❌ | ✅ |
| Trends, Compare, Journey | ❌ | ✅ |
| Photos — capture, history, angles | ❌ | ✅ |
| Labs, Procedures, Treatments | ❌ | ✅ |
| Progress reports, Body signals | ❌ | ✅ |
| Ask Wren | ❌ | ✅ *needs Apple Intelligence* |
| Deep Analysis | ❌ | ✅ *needs Apple Intelligence* |

Two entries are deliberate and load-bearing:

- **Export stays free.** A lapsed subscriber must be able to retrieve data they created while
  paying. This is what keeps the design clear of App Store Guideline 3.1.2(a).
- **The streak count stays free** while the consistency *chart* locks. One number motivates the
  habit that fills the data pile; the chart is analysis and belongs to Pro.

### 4.1 The compounding lock

The free Today screen carries a locked-history card:

```
🔒  23 days recorded
    You haven't seen any of it
    [ Unlock my history ]
```

The count is `CheckInEntry` records excluding today. It grows every day the user stays free,
so conversion pressure increases with tenure instead of hitting a wall on day one. This is the
core commercial mechanic of the spec.

Rejected alternatives, recorded so they are not revisited: a weekly check-in cap (~29% of the
data, breaks the daily habit), and a 7-check-in lifetime cap (Guideline 4.2 risk, and uninstall
is the likelier response than subscription). Both restrict the action that *generates the value
being sold*.

## 5. The funnel

| Stage | Length | Payment method | Mechanism |
|---|---|---|---|
| Taster | 3 days | None | Local first-launch date |
| Trial | 14 days | Required | App Store Connect introductory offer |
| Pro | Recurring | — | `com.harib.haircompass.pro.monthly` / `.yearly` |

**Taster.** Full app, no restrictions, no card. Backed by a first-launch timestamp persisted
locally. Farming by reinstall is possible and explicitly accepted: on-device inference makes
the cost of a farmed taster zero, so defending it would spend engineering effort to protect
nothing.

The two free periods are **additive, not exclusive**: taking the taster does not consume the
Apple introductory offer, because the taster is local and Apple tracks eligibility separately.
A user may therefore have 3 free days, hit the wall, and later start a 14-day trial. When the
taster expires the app drops to the free tier of §4 — it does not auto-start the trial, which
would require a payment method the taster deliberately never asked for.

**Trial.** StoreKit permits exactly one introductory offer per subscription group per Apple ID,
so this is the single Apple-tracked free period and it is reinstall-proof.
`PurchaseService.trialDescriptor(for:)` already renders the copy; this is an App Store Connect
configuration change plus display wiring, not new purchase logic. `hasPro` already reflects
trial entitlements through `Transaction.currentEntitlements`, so no entitlement work is needed.

**Price.** $6.99/month. Yearly proposed at $39.99 (≈52% off, which `yearlyVersusMonthly()` will
render honestly from real prices). Both prices are authoritative in App Store Connect — this
spec does not duplicate them in code.

## 6. Architecture

### 6.1 `Entitlements.swift` (new)

Policy lives in exactly one file, as a readable table:

```swift
enum ProFeature {
    case history, trends, compare, journey, photos, labs,
         procedures, treatments, reports, bodySignals
    case askWren, deepAnalysis          // the only two needing Apple Intelligence

    var requiresAppleIntelligence: Bool {
        switch self {
        case .askWren, .deepAnalysis: true
        default: false
        }
    }
}
```

`history` covers every read of a past `CheckInEntry` — which includes the consistency chart and
any average in `ConsistencyCard`. The streak *count* is not a `ProFeature` at all; it stays free
per §4 and is computed without exposing the underlying entries.

`Entitlements` answers `canAccess(_ feature: ProFeature) -> Bool` from `hasPro || tasterActive`.
A `.proGated(_:)` view modifier applies it at each surface, so call sites carry one line each.

Chosen over two alternatives. Gating in `RootView`'s tab switch is four lines but is
all-or-nothing per tab, cannot express the per-feature Apple Intelligence distinction, and still
requires the shop extraction. Wrapping ~20 sheets in the existing `ProGate` duplicates the same
policy decision across 20 files.

### 6.2 Inverting the scope of `sellable`

`ProAvailability.sellable()` currently decides **whether the paywall sells at all**. It must
instead decide **whether the two AI rows appear in the feature list**.

After the change, an Apple-Intelligence-ineligible iPhone is offered a genuine, working
subscription and told plainly that two of its features need hardware it does not have. Before
the change, that iPhone would face a mostly-locked app with no button to unlock it — a Guideline
3.1.2 rejection risk and a dead end for the user.

`Feature/ProGate.swift:81-86` hard-codes the availability notice and the `sellable` check into
its body. That is correct for its two current AI callers and wrong for the other eighteen
surfaces, so the notice moves behind `ProFeature.requiresAppleIntelligence`.

**This changes assertions that already exist.** `SubmissionReadinessTests` asserts
`ProAvailability.sellable(.deviceNotEligible) == false` and that the `.deviceNotEligible`
message mentions Apple Intelligence and the word "free". Those assertions encode the *old*
contract and must be rewritten to the new one, not deleted.

### 6.3 The history wall

Free users must not read past entries. Enforcing this only in the view layer would leave the
data reachable through any future surface, so the gate belongs at the query boundary: the
free path fetches today's `CheckInEntry` only, and the locked-history card renders a `count`
rather than any record content.

**The widget is a second read path and must respect the same rule.** The app writes a
`HairCompassWidgetSnapshot` into App Group `group.harib.Hair-Compass-AI-5`, and the struct is
duplicated on both sides. Whatever the free tier may not see in-app, the snapshot must not
carry — otherwise the wall leaks onto the Home Screen. Today's values and the streak count are
allowed; averages and history are not.

### 6.4 Navigation

Merge **Labs into the Plan tab** and promote **Shop** into the freed slot:

```
before:  today · trends · care · labs · photos
after:   today · shop · trends · care · photos
          free    free    pro    pro    pro
```

The `care` case keeps its identifier and its "Plan" display title; `labs` is removed from
`AppTab` and its content absorbed into `CareView`, and a new `shop` case takes the free slot.

Labs and Procedures are both clinical records and belong together; both are Pro regardless, so
merging costs no capability. This gives a free user two working tabs — one of which is the
storefront — and keeps `FloatingTabBar` at five items.

## 7. Affiliate storefront

Ship Amazon-tagged links in `Resources/AffiliateLinks.json` so the shop is never empty, then
host the same JSON shape at `AffiliateStore.RemoteConfig.catalogURLString` and swap in
direct-brand links per product as programs approve. `AffiliateStore`'s existing resolution order
(debug override → cached remote → bundled → nil) already supports exactly this, so no link
change ever needs an app update.

Two items that are not optional:

- **FTC disclosure.** 16 CFR Part 255 requires a clear, conspicuous affiliate disclosure on the
  shop surface. Given how strictly this codebase polices its own honesty elsewhere, it should be
  a visible line near the products, not a footer.
- **Region routing.** Amazon Associates links are storefront-locked; a UK tap on a US link earns
  nothing. Either route by `Locale.current.region` or accept the loss knowingly.

## 8. Testing

Swift Testing (`@Test` / `#expect`), matching the existing suite.

| Area | Assertion |
|---|---|
| Policy table | Every `ProFeature` resolves as specified in §4 for free, taster, and Pro |
| AI split | Exactly `askWren` and `deepAnalysis` return `requiresAppleIntelligence == true` |
| Sellability | Pro is offered on `.deviceNotEligible`; the two AI rows are not |
| History wall | A free entitlement fetches today only, regardless of stored entry count |
| Locked counter | Count excludes today and matches stored entries |
| Taster | Active within 3 days of first launch, inactive after; expiry drops to free, not trial |
| Widget | A free-tier snapshot carries no average and no past entry |
| Export | Reachable on a free entitlement (3.1.2(a) guard) |
| Submission | Existing `sellable` assertions rewritten to the new contract |

## 9. Open items — need Mohammed, not us

1. **Product-ID prefix mismatch.** The app sells `com.harib.haircompass.pro.monthly`
   (`PurchaseService.swift:22`); `agent_core/plans.py` joins on
   `harib.haircompass.pro.monthly`. App Store Connect is the authority, so his catalogue would
   fail to match a genuine receipt. One of the two is wrong and it is cheaper to find out now.
2. **Yearly price confirmation** — $39.99 assumed against his costed $6.99 monthly.

## 10. Out of scope

- Server-side plans, metering, and token budgets. They govern the agent platform, which does
  not ship in `feature/on-device-ai-only` (that branch contains no agent client).
- The `/v1/session` account-takeover recorded in `agent-platform/docs/READINESS.md`. It is a
  real go-live gate for the agent platform and unrelated to monetization.
- Notifications, win-back offers, and promotional offers. Worth doing; separate spec.
