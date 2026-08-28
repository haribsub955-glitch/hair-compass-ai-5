# Reply to Guideline 2.1 "Information Needed" (submission 1, 2026-08-28)

Actions: **reply in the App Review thread** with both videos attached and the text under
"Paste-ready reply". Apple also asked that the same information live in **App Review
Information → Notes** for future submissions — paste items 2–7 there too.

Before pasting, verify in App Store Connect that the *current* products
(`com.harib.haircompass.pro.monthly2` / `.yearly2` — the v1 IDs are burned, commit 68ea540)
still carry **$9.99/mo with the 3-day free trial** and **$39.99/yr with no intro offer**. The
prices/trial below assume the v2 products mirror the v1 configuration; fix the text if not.

---

## Recordings (done 2026-08-28)

Two files in `~/Desktop/HairCompass App Review/`, both simulator captures (iPhone 17 Pro,
iOS 26.3.1, fresh installs, `simctl recordVideo`):

- **HairCompass-demo-features.mp4** (4:00) — launch, full onboarding (HealthKit prompt, plan
  step with live prices), check-in, photos, Ask Wren consent + answer, Trends, Baseline
  cloud-AI toggle, Today.
- **HairCompass-demo-purchase.mp4** (~2:00) — launch, onboarding to the plan step, completed
  Pro Monthly purchase through the StoreKit purchase sheet, paid features active after.

Attach both in the App Review reply.

Simulator gotcha that cost a day, for next time: a scheme's StoreKit configuration reference
is resolved relative to `xcshareddata/`, so the correct identifier for a repo-root fixture is
`../../HairCompass.storekit`. The hand-written `../../../` pointed one level above the repo
and was silently ignored — every launch then queried the real sandbox catalog, which returns
empty for these product IDs on an account-less simulator, and the paywall showed "Can't reach
the App Store". Let Xcode's scheme editor write the reference (Run → Options → StoreKit
Configuration) rather than authoring it by hand. Fresh installs also start the 3-day
full-access period, so no paywall gates appear during a demo — the plan step in onboarding is
the only on-camera purchase moment.

There is intentionally nothing to record for account registration/login/deletion (no accounts)
or content reporting/blocking (no user-to-user content) — the reply text says so explicitly.

---

## Paste-ready reply

Hello, and thank you for the review. Answers to each requested item are below; the screen
recording for item 1 is attached.

1. Screen recordings: two files are attached, each beginning at app launch on a fresh
installation. The first ("features") is a full walkthrough: the onboarding flow including the
subscription plan screen, the HealthKit permission prompt, completing a daily check-in, adding
a standardized photo, the opt-in cloud-AI consent screen followed by an AI answer (Ask Wren)
and a Deep analysis, the Trends and Care screens, and enabling a reminder (notification
permission prompt). The second ("purchase") demonstrates the subscription flow end to end: the
plan screen with each subscription's title, length, price, free trial, and the Terms of Use
and Privacy Policy links, followed by a completed test purchase of Pro Monthly and the paid
features active afterwards. Note: every fresh install includes a 3-day full-access period, so
in the walkthrough all features are usable without a purchase — that is intended behavior, not
a missing paywall. The app has no account registration, login, or account-deletion flows — it
has no accounts and no server-side user database — and no user-generated content is visible to
any other user (all entries are private records on the device), so there are no content
reporting or blocking mechanisms to demonstrate. The app does not use App Tracking
Transparency because it does not track.

2. Devices and operating systems tested: iPhone 14 Pro (physical device, iOS 26.5.2) for
development and TestFlight builds, plus iPhone 17, iPhone 17 Pro, and iPhone 17 Pro Max
simulators (iOS 26.3) running the automated unit and UI test suites. The app is iPhone-only.

3. Functions and target audience: Hair Compass AI is a private record-keeping and education app
for adults (rated 16+) tracking changes in their hair or scalp — shedding, thinning, scalp
irritation, or the effects of treatments and procedures. The problem it solves: these changes
are slow and hard to judge from memory. The value it provides: structured daily check-ins, a
treatment and procedure log, lab-result tracking, standardized photo angles for honest
comparisons over time, optional lifestyle signals read from Apple Health, deterministic trend
charts, and an exportable PDF report the user can bring to their own clinician. An optional AI
assistant ("Wren") answers questions about the user's own logged record and writes plain-
language summaries. The app explicitly does not diagnose or treat any condition, and says so
in-app.

4. Setup and access: no login, no account, no credentials, and no sample files are required.
Install the app, complete a short onboarding, and every feature is immediately usable: each
fresh install includes a built-in 3-day full-access period, so the reviewer can reach all
features without purchasing. Daily check-ins and data export are free permanently; extended
history, trends, comparisons, photos, labs, treatments, procedures, reports, body signals, and
the two AI features are part of the Pro auto-renewable subscription (Pro Monthly USD 9.99 with
a 3-day free trial; Pro Yearly USD 39.99), purchased exclusively through Apple in-app purchase.
The two AI features (Ask Wren and Deep analysis) request explicit consent before anything is
sent to the cloud and need network access to api.deepseek.com; if that host is unreachable,
devices supporting Apple Intelligence fall back to on-device answers and other devices show a
"temporarily unavailable" message — this is intended behavior, not a bug.

5. External services, tools, and platforms:
- DeepSeek (api.deepseek.com): a cloud large-language-model API used only for the opt-in AI
features. After explicit in-app consent it receives a limited, identifier-free summary of the
user's logged values — no name, no contact details, no photos, no device identifiers. Nothing
is sent before consent, and consent can be withdrawn in-app at any time.
- Apple frameworks otherwise: StoreKit 2 (Apple in-app purchase is the only payment mechanism),
HealthKit (read-only, optional, user-approved categories), Apple Intelligence / Foundation
Models (on-device AI fallback; nothing leaves the device on that path), and WidgetKit (Home
Screen widget).
- No third-party analytics, advertising, tracking, authentication, or payment SDKs. The only
third-party library is Lottie, used for offline animation rendering; it makes no network
requests.

6. Regional differences: the app functions consistently across all regions and storefronts. The
only variation is inherited from the platform itself: the optional on-device Apple Intelligence
fallback exists only where Apple supports it (device and language); the primary cloud AI path
and every other feature are identical everywhere.

7. Regulated industry / protected material: the app is not a medical device and does not
operate in a regulated capacity. It is a personal record-keeping and education tool; it does
not diagnose, treat, or recommend medication, and displays that disclaimer in-app. It is
declared "Not a medical device" in App Information. All content — text, illustrations,
animations — is original or licensed to us; the app contains no protected third-party material.
