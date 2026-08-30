# App Review rejection log — Hair Compass AI

App Store record `6803796144` · version 1.0 · bundle `harib.Hair-Compass-AI-5`.
Companion docs: `APP_REVIEW_REPLY.md` (the reply kit for rejection 1),
`APP_STORE_SUBMISSION.md` (submission runbook).

---

## Rejection 1 — Guideline 2.1, Information Needed (2026-08-28)

- **Review submission**: `5ef4dbe3-c232-4f7f-8159-4c67180ac6f6`, submitted 2026-08-27 14:24 UTC
  (app version 1.0 only — no subscriptions were in this submission).
- **Thread**: `8c27cf22-ebaf-3d77-bd75-8ca024292f5d`, message received 2026-08-28 01:24 UTC.
- **Type**: information request, not a policy violation — Apple wanted review notes and a demo
  video before completing the review.

### Apple's message (verbatim)

> **Guideline 2.1 - Information Needed - New App Submission**
>
> We need additional information to continue the review of this new app. To help us fully
> understand the app and conduct a complete review, app submissions should include relevant
> details in the App Review Information section in App Store Connect.
>
> **Next Steps**
>
> Reply in App Store Connect with all of the following information:
>
> 1. A screen recording captured on a physical device, running the latest operating system,
> demonstrating the app's functionality. The recording must begin with launching the app and
> show the typical user flow through its core features. If the app has any of the following,
> include them in the recording:
>    - Account registration, login, and account deletion flows
>    - Accessing paid content or features within the app, including any purchase or
>      subscription flows
>    - User-generated content, including content reporting and blocking mechanisms
>    - Any prompts requesting access to sensitive data or device capabilities (for example,
>      location, contacts, camera, or App Tracking Transparency)
> 2. A list of the device models and operating systems the app was tested on before submitting
>    for review
> 3. A description of the app's functions and target audience, including the problem it solves
>    and the value it provides
> 4. Instructions for setting up and accessing the app's main features, including any required
>    login credentials or sample files
> 5. A list of the external services, tools, or platforms the app uses to deliver its core
>    functionality (for example, data providers, authentication services, payment processors,
>    or AI services)
> 6. Describe any regional differences in the app's features or content, or confirm that the
>    app functions consistently across all regions
> 7. If the app operates in a highly regulated industry or includes protected third-party
>    material, provide any relevant documentation or credentials to demonstrate you are
>    authorized to provide these services or protected material
>
> Include this information in the Notes field of the App Review Information section in App
> Store Connect for future submissions.

(The message also carried a generic "How to Prevent Common Issues" list: test on physical
devices, provide demo credentials, real screenshots, subscription pricing/Terms visibility
per 3.1.2, and complete purpose strings per 5.1.1.)

### Our response (sent 2026-08-28 12:53 UTC, message `ddc7fa06`)

- Replied in the thread answering all 7 items (text in `APP_REVIEW_REPLY.md`), with **two
  screen recordings attached**: a 4:00 feature walkthrough and a ~2:00 completed-purchase demo
  (StoreKit test environment, simulator capture).
- Items 2–7 were also written into **App Review Information → Notes** (3,795 chars) as
  requested.
- Underlying issues found and fixed along the way: the schemes' StoreKit configuration path
  was broken (`../../../` instead of `../../` — commit `0ea4803`), and the Paid Apps
  Agreement was inactive (missing W-8BEN), which had kept both subscriptions in
  Missing Metadata and the sandbox catalog empty.

### Outcome

Submission `5ef4dbe3` closed **COMPLETE** with no further questions. Version 1.0 was
resubmitted in a new package together with both subscriptions once the Paid Apps Agreement
activated.

---

## Rejection 2 — Guideline 2.1 + missing EULA link (2026-08-30)

- **Review submission**: `295b0440-9783-4a75-bb4b-fef9117a5c42` — the combined package:
  app version 1.0 + Pro Monthly (`…pro.monthly2`) + Pro Yearly (`…pro.yearly2`) + subscription
  group localization. First submission to include the subscriptions.
- **Thread**: `7c815b29-aba7-341b-bf65-c57dfed1e993`, message received 2026-08-30 01:54 UTC.
- **Two parts**: (a) the same boilerplate 2.1 "Information Needed" items 1–7 re-attached to the
  new submission (our answers already live in App Review Information → Notes), and (b) one new
  **automated, concrete blocker**:

### Apple's guideline issue (verbatim)

> **App Review Guideline Issue**
>
> *This is an automated message. The review of this submission cannot proceed. See below for
> more information.*
>
> The submission offers auto-renewable subscriptions but does not include a functional link to
> the Terms of Use (EULA) in the app metadata that appears on the app's App Store product page.
>
> If you are using the standard Apple Terms of Use (EULA), include a link to the Terms of Use
> in the App Description. If you are using a custom EULA, add it in App Store Connect.

(The message also repeated items 1–7 of the 2.1 information request verbatim from Rejection 1,
and the same "How to Prevent Common Issues" boilerplate.)

### Root cause

The in-app paywall links the standard Apple EULA (`AppInfo.termsOfUseURLString` →
apple.com/legal/…/stdeula), but the **App Store description** — the metadata on the product
page — carried no Terms of Use link. Apple requires it there for any app selling
auto-renewable subscriptions (Guideline 3.1.2). It surfaced only now because Rejection 1's
submission contained no subscriptions.

### Our response (2026-08-30 16:50 UTC, message `5b87e86c`)

1. **App Description updated** (en-US localization `178822d2`): appended
   `Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
   and `Privacy Policy: https://haircompass-ai.com/privacy-policy.html`.
2. **Replied in the thread** confirming the fix, pointing to the Notes field for items 2–7,
   and re-attaching both demo videos (attachments do not carry across threads).
3. **Resolved the rejected version item** (`resolved: true` on the review-submission item) and
   **resubmitted**: submission back to WAITING_FOR_REVIEW at 2026-08-30 16:51 UTC.

### Outcome

Pending — awaiting App Review.
