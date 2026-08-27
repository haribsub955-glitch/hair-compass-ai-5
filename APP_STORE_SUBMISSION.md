# App Store submission — working checklist

Everything in this file is **App Store Connect and Xcode work that must be done by a human signed
into the developer account**. Nothing in the repo can verify any of it.

Repo-side state as of 2026-08-22: the privacy policy + support URLs resolve (see below), but the
**live content at those URLs still predates the cloud-AI change** — it will not match the shipping
binary until this branch merges to `rebuild/clinical-minimal` (§0b covers the merge and the
re-verify step). The monetization hard-wall work is merged, the AI runs through DeepSeek's cloud
API (opt-in consent, on-device fallback), and the test suite is green.

## 0. DeepSeek account — do this before the first archive

The DeepSeek API key is compiled into the app (`Config/Secrets.local.xcconfig` on this Mac —
never in the repo). A shipped binary's Info.plist is readable by anyone, so treat the key as
extractable and manage it at the account, not the client:

- **Set a spend cap / usage alert** on the DeepSeek platform dashboard (platform.deepseek.com)
  and keep only a bounded balance on the account. The app has a client-side budget of 100 cloud
  requests per device per day, but that bounds accidents, not adversaries.
- **Rotate the key on a schedule** (each app update is a natural moment): issue a new key, put
  it in `Config/Secrets.local.xcconfig`, archive, and revoke the old one once the previous build
  is no longer the live version. Rotating instantly kills every extracted copy.
- **Watch the balance**: DeepSeek answers HTTP 402 when credit runs out, which the app shows as
  "temporarily unavailable" and quietly falls back to on-device — users on non-Apple-Intelligence
  iPhones lose AI entirely with no alarm on your side. A weekly balance check is the alarm.
- Longer term, the honest fix is a tiny proxy that holds the key server-side
  (`CloudAIConfig.defaultBaseURLString` is the one line that changes); the client already
  enforces HTTPS and treats the endpoint as configuration.

## Facts you will be asked for

| Field | Value |
|---|---|
| App name (store + Home Screen) | **Hair Compass AI** |
| Bundle ID (app) | `harib.Hair-Compass-AI-5` |
| Bundle ID (widget) | `harib.Hair-Compass-AI-5.CheckInWidget` |
| Team ID | `2LZ89Q26N8` |
| Version / build | `1.0` / `1` |
| App Group | `group.harib.Hair-Compass-AI-5` |
| Subscription group | `21442176` |
| Product IDs | `com.harib.haircompass.pro.monthly2`, `com.harib.haircompass.pro.yearly2` (v1 IDs are burned — subscription product IDs can never be reused once created, even after deletion) |
| Privacy policy URL | https://haircompass-ai.com/privacy-policy.html |
| Support URL | https://haircompass-ai.com/support.html |
| Support email | harib.alazri@gmail.com |

## 0b. Merge the docs to `rebuild/clinical-minimal` BEFORE anything in App Store Connect

GitHub Pages serves `docs/` from the **default branch**. Until this branch merges, the live
privacy policy and support page still claim all AI runs on-device and nothing is ever sent to a
third party — which directly contradicts the shipping binary and is a Guideline 5.1.1/5.1.2
rejection waiting to happen (the in-app consent card links a reviewer straight to that page).

The merge will CONFLICT in `docs/index.html`, `docs/privacy-policy.html`, `docs/support.html`
(both branches rebuilt the site independently). Resolve by keeping THIS branch's versions (they
carry the cloud-AI truth in the same visual shell), and verify `docs/CNAME` — which exists only
on `rebuild/clinical-minimal` — survives the merge, or the custom domain and both legal URLs go
dark. After merging: re-fetch https://haircompass-ai.com/privacy-policy.html and confirm the
DeepSeek paragraph is live before entering the URL anywhere in App Store Connect.

## 1. Paid Apps agreement + banking and tax — do this first

Business → Agreements. Sign the **Paid Applications** agreement and complete banking + tax.

This is first because it silently breaks everything else: until it is active, StoreKit returns no
products, so `hasLoadedProducts` is false, purchase buttons never appear, and a reviewer sees
`StoreUnavailableView`. That reads as a broken app and gets rejected. It can take days to clear.

## 2. Certificates and the App ID

- Create an **Apple Distribution** certificate. The keychain on this Mac currently has only
  `Apple Development: harib9557@icloud.com` — an App Store archive cannot be signed with it.
  Easiest path: Xcode → Settings → Accounts → Manage Certificates → **+** → Apple Distribution.
- On the App ID `harib.Hair-Compass-AI-5`, enable **HealthKit** and **App Groups**
  (`group.harib.Hair-Compass-AI-5`), and add the same App Group to the widget's App ID. If these
  are missing the entitlements will not sign.

## 3. App record

New app → iOS → name, primary language, bundle ID, SKU. Then:

- **App Privacy → declare Health & Fitness data.** The opt-in cloud AI (DeepSeek) sends a limited
  tracking summary — check-in values, dates, treatment names, lab values, logged notes,
  health-derived values — to generate answers, so "Data Not Collected" is no longer true. Declare:
  **Health & Fitness → Health** and **User Content → Other User Content** (the free-text
  check-in notes), each: App Functionality → Not linked to the user's identity → No tracking.
  This matches the app target's `PrivacyInfo.xcprivacy` (the widget's manifest declares no
  collected data — correct, it makes no network requests). Nothing else is collected: no
  analytics, no identifiers, no accounts.
- **Guideline 5.1.3 (HealthKit), write this into the review notes:** health-derived values the
  user chose to track (sleep, HRV, weight trend) are part of the tracking summary sent to the AI
  provider **only** to write the user's own record summary/answers — a health-management purpose —
  only after explicit in-app consent, never for ads, marketing, or any other use, and never
  linked to an identity (the app has no accounts).
- **Age rating.** Answer the medical/treatment questions honestly; the app is a documentation and
  education tool, not a medical device (`AppInfo.medicalDisclaimer` is the in-app wording).
- Description, keywords, support URL, screenshots **taken on a real device**.

## 4. Subscriptions — the description is the part that goes wrong

Create both products in group `21442176` and get each to *Ready to Submit*: localized display name
(≤30 chars), description (**≤45 chars**), price, and an IAP review screenshot.

`HairCompass.storekit` is a **local simulator fixture only** — it configures nothing on Apple's
side. Its description reads "AI chat, deep analysis and your full record."

**Do not reuse that string in App Store Connect.** It names only the two AI
features, but **twelve** features are gated (`ProFeature.allCases`):

> history · trends · compare · journey · photos · labs · procedures · treatments · reports ·
> body signals · Ask Wren · Deep analysis

All twelve now run on any supported iPhone — the two AI features are answered by the cloud model
(DeepSeek) once the person consents, with Apple Intelligence as the on-device fallback. A
description naming only the AI features still misrepresents what someone is buying.

Trends is `.proGated(.trends)` — do **not** describe it as free.

Free tier keeps: unlimited daily check-ins, today's own values, the streak count, the Guide tab
(products + in-clinic options), Learn, and
export. Every fresh install is a **three-day taster** with everything unlocked.

## 5. App Review notes — write these, they prevent a rejection

Include all of:

- **No account is needed.** There is no sign-in and no backend of ours. The app's only network
  use is the opt-in cloud AI: Ask Wren, Deep analysis and ingredient summaries call DeepSeek's
  API with a limited tracking summary (no name, no photos) after in-app consent.
- **The review device needs network access to `api.deepseek.com`** for the AI features. If that
  host is unreachable, devices with Apple Intelligence quietly fall back to on-device answers;
  devices without it show an honest "temporarily unavailable" message — not a bug.
- **Subscription setup must mirror the intent of `HairCompass.storekit`:** the fixture gives the
  monthly product a 3-day free trial and gives the yearly product **no** introductory offer
  (`introductoryOffer: null`). Configure the same in App Store Connect — monthly with a 3-day free
  trial, yearly with nothing — or update the fixture first if the team decides yearly should carry
  an intro offer too; the paywall reads real eligibility and will advertise whatever offer actually
  exists, so the two must stay in sync.
- **The two AI features (Ask Wren, Deep analysis) ask for cloud-AI consent on first use.** A
  reviewer will see the consent card; accepting routes answers through the cloud model on any
  iPhone. Declining falls back to Apple Intelligence where the device supports it, and the other
  ten Pro features run everywhere regardless.
- Do **not** mention `HC_TIER free` — the flag is `#if DEBUG` and compiled out of the build App
  Review runs. A reviewer sees the fresh install's three-day taster with everything unlocked; if
  the free-tier wall matters to the review, describe it in words or attach a screenshot.

## 6. Before the archive

**TestFlight on a physical device.** HealthKit, Face ID, the widget, Live Activities and
Foundation Models are all things the Simulator cannot prove. Note that an iOS 26 Simulator on an
Apple Intelligence Mac *does* report `.available` and really runs the model — so the Simulator
does not exercise the unavailable branches. Use `HC_AI_STATUS` to force them.

## 7. Archive and upload

In Xcode: destination **Any iOS Device (arm64)** → Product → Archive → Distribute App → App Store
Connect. The widget extension is embedded and ships with the app; it needs no separate upload.
