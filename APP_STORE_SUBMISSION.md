# App Store submission — working checklist

Everything in this file is **App Store Connect and Xcode work that must be done by a human signed
into the developer account**. Nothing in the repo can verify any of it.

Repo-side state as of 2026-08-21: privacy policy + support URLs are live and verified (see below),
the monetization hard-wall work is merged, and the test suite is green.

## Facts you will be asked for

| Field | Value |
|---|---|
| App name (store + Home Screen) | **Hair Compass AI** |
| Bundle ID (app) | `harib.Hair-Compass-AI-5` |
| Bundle ID (widget) | `harib.Hair-Compass-AI-5.HairCompassCheckInWidget` |
| Team ID | `2LZ89Q26N8` |
| Version / build | `1.0` / `1` |
| App Group | `group.harib.Hair-Compass-AI-5` |
| Subscription group | `21442176` |
| Product IDs | `com.harib.haircompass.pro.monthly`, `com.harib.haircompass.pro.yearly` |
| Privacy policy URL | https://haribsub955-glitch.github.io/hair-compass-ai-5/privacy-policy.html |
| Support URL | https://haribsub955-glitch.github.io/hair-compass-ai-5/ |
| Support email | harib.alazri@gmail.com |

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

- **App Privacy → Data Not Collected.** This matches both `PrivacyInfo.xcprivacy` files and the
  fact that the app makes no network requests at all. Do not casually tick anything else — it must
  stay consistent with the manifests.
- **Age rating.** Answer the medical/treatment questions honestly; the app is a documentation and
  education tool, not a medical device (`AppInfo.medicalDisclaimer` is the in-app wording).
- Description, keywords, support URL, screenshots **taken on a real device**.

## 4. Subscriptions — the description is the part that goes wrong

Create both products in group `21442176` and get each to *Ready to Submit*: localized display name
(≤30 chars), description (**≤45 chars**), price, and an IAP review screenshot.

`HairCompass.storekit` is a **local simulator fixture only** — it configures nothing on Apple's
side. Its description reads "On-device AI chat and record analysis."

**Do not reuse that string in App Store Connect.** It names only the two Apple Intelligence
features, but **twelve** features are gated (`ProFeature.allCases`):

> history · trends · compare · journey · photos · labs · procedures · treatments · reports ·
> body signals · Ask Wren · Deep analysis

Only the last two need Apple Intelligence; the other ten run on any supported iPhone, which is
exactly why the purchase buttons are unconditional. A description naming only the AI features
misrepresents what someone on an iPhone 14 is buying.

Trends is `.proGated(.trends)` — do **not** describe it as free.

Free tier keeps: unlimited daily check-ins, today's own values, the streak count, the Guide tab
(products + in-clinic options), Learn, and
export. Every fresh install is a **three-day taster** with everything unlocked.

## 5. App Review notes — write these, they prevent a rejection

Include all of:

- **No account is needed.** There is no sign-in, no backend, no network access.
- **Two of the twelve Pro features (Ask Wren, Deep analysis) require Apple Intelligence.** Name a
  device that has it (iPhone 15 Pro or later, Apple Intelligence switched on). A reviewer on
  ineligible hardware sees **live purchase buttons plus an honest notice** naming those two
  features — that is deliberate, not a bug, because the other ten features run everywhere.
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
