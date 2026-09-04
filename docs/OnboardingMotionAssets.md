# Onboarding motion and generated artwork

Implemented 2026-09-04. Native SwiftUI, using the existing Clinical palette and fonts.

## Flow

The final offer step now has three optional moments: a real starting plan, an explicitly fictional record preview, and Pro pricing. The same unfinished priority items keep their identity as they compact. The finale expands those same items before opening the existing Plan tab. Full clinical detail remains available in a disclosure. The parallel roadmap implementation supplies the current priorities; this presentation preserves its source items and clinical content.

- Card settle: 0.6 seconds, ease-in-out.
- Record preview: after 1.2 seconds, a check-in settles into a week; after another 1.5 seconds, a Wren example note fades in over 0.45 seconds.
- Pricing: only the selected card background moves, over 0.32 seconds. Prices do not count up or animate.
- No forced wait or automatic advance. Back and Continue free remain available.
- Reduce Motion / HC_MOTION_STATIC show the preview's complete meaning immediately. Playback cancels when the screen leaves or the app becomes inactive.
- No sample record is persisted or sent to AI. No purchase occurs on selection. StoreKit owns localized amounts, periods, offers and verified entitlements. AccessWindow owns the existing introductory-access state.

## Generated assets

Built with the **built-in image generator**, not the fallback CLI. New sibling assets; original art was not overwritten. Opaque warm-ivory plates (1536 × 1024), not transparent cutouts. All text, controls, prices and record marks are native UI.

1. `Hair Compass AI 5/Assets.xcassets/onboarding-plan-journal.imageset/onboarding-plan-journal.png`
2. `Hair Compass AI 5/Assets.xcassets/onboarding-wren-support.imageset/onboarding-wren-support.png`

Style references: intro-ritual-front, pro-analysis, wren-listening. The first generation used these as style/character references. Initial transparency attempts had visible background artifacts; the final image-generator edit replaced backgrounds with ivory. No procedural image editing was used.

## Exact prompt set

### Starting-plan journal

Use case: illustration-story. Asset type: transparent gouache illustration for the personalized starting-plan screen of Hair Compass, a native health-record app. Input image 1 is a STYLE reference, not a target to overwrite. Create a NEW companion illustration in exactly that quiet botanical-heritage design language: a small open cream-paper notebook with three unmarked copper page tabs and a single muted sage sprig resting beside its lower edge. Slight overhead three-quarter view, simple low horizontal arrangement, all objects entirely inside frame with generous transparent margins. Hand-painted opaque gouache, fine paper-grain texture inside the objects, softly imperfect hand-drawn outlines, restrained copper/terracotta #B1592E, antique gold #C9A15A, sage #8A9D7B, warm espresso accents. Notebook pages are blank with only a few faint ruled lines: NO text, numbers, checkmarks, charts, arrows or results. Warm, quiet, reassuring; the subject is organizing a record, never hair regrowth. Actual transparent RGBA background, not white and not checkerboard; no painted background, no vignette, no frame, no UI, no watermark. Landscape 3:2 composition suitable for a 140pt-high header.

### Wren support

Use case: illustration-story. Asset type: transparent gouache illustration for the support/pricing screen of Hair Compass. Input image 1 is the established Wren character reference: preserve this bird's species, proportions, feather colors and hand-painted personality. Input image 2 is a style/material reference for the notebooks and botanical accents. Create a NEW companion illustration: this same small friendly brown wren perched calmly on the upper edge of two slim closed cream-and-copper journals, with a single sage twig beside them. Quiet, grounded, attentive pose, no celebration, no waving, no speech bubble. Low horizontal composition, entire bird and notebooks visible, generous transparent margins. Painterly opaque gouache with paper-grain texture inside painted surfaces, warm brown/terracotta feathers, copper #B1592E, cream #FBF6EF, muted sage #8A9D7B, soft antique-gold touches. No magnifier, no charts, no money symbols, no text, no numbers, no medical claims. Actual transparent RGBA background, not white and not checkerboard; no backdrop, vignette, glow, frame, UI or watermark. Landscape 3:2 companion asset, readable at 120pt-high.

### Final background edit applied to each selected subject

Precise background replacement. Preserve the painted subject and its exact style, colors, proportions and details. Replace the ENTIRE background surrounding the subject with one perfectly flat opaque warm ivory color, hex #FBF6EF, RGB 251,246,239. No transparency is wanted. No checkerboard. No gradient, vignette, blur, glow, black, gray, color wash, extra shadow, or paper texture outside the painted subject. A clean plain light-ivory background all the way to all four image edges. Preserve the cream pages as painted. Subject fully within frame, no cropping. This is a production illustration to sit on an app screen with the same flat #FBF6EF background. No text or other elements.

## QA entry points

Simulator captures (iPhone 17 Pro, iOS 26.3.1): [starting plan](previews/onboarding/starting-plan.png), [example record](previews/onboarding/example-record.png), [Pro choice](previews/onboarding/pro-offer.png), [monthly billing](previews/onboarding/monthly-billing.png), [finale](previews/onboarding/ready-to-begin.png). Prices are StoreKit-supplied in the simulator, not a production billing certification. The command-line UI purchase path presented an Apple Account sign-in prompt instead of a local transaction; no credentials were entered and no purchase was confirmed.

The two end-to-end purchase UI tests require `HC_UI_STOREKIT_TESTING=1` in an environment where the local store is confirmed attached to the tested app. They are explicitly skipped otherwise; this is not a passing purchase-UI result. The separate app-hosted `StoreKitPurchaseIntegrationTests` also reached an Apple Account sign-in prompt in this environment and the run was stopped without authentication. Neither path establishes purchase verification. Apple describes local StoreKit testing as not requiring account authentication ([StoreKit testing introduction](https://developer.apple.com/videos/play/wwdc2020/10659/)); the observed sign-in prompt therefore cannot count as a local test result.

DEBUG launch arguments: `HC_ONBOARD HC_ONBOARD_STEP 13 HC_NORITUAL`; add `HC_OFFER_PHASE preview` or `HC_OFFER_PHASE pricing` to jump within the offer. Existing `HC_PAYWALL_BOTTOM` now opens pricing directly. `HC_ONBOARD_STEP 14` opens the finale. `HC_MOTION_STATIC` renders one-shots in their final state. `HC_PRO` checks existing subscribers.

Automated coverage: OnboardingOfferTests (phase progression, real-plan parity, StoreKit price/intro copy, bundled art, motion timings) and OnboardingOfferUITests (full free journey, selection without purchase, back/replay, static presentation, existing subscriber, accessibility text).

Final verification: simulator build succeeded. The final focused run passed **25 checks with 0 failures and 2 explicitly skipped payment UI tests**: 18 unit checks (OnboardingOfferTests and LaunchPresentationStateTests) and 7 UI checks (including the existing AI-availability disclosure check). Evidence: `/tmp/HairCompass-OnboardingWorkspace.zQf0FU/UXVerified.xcresult`. The earlier failed payment assertions and interrupted app-hosted payment run remain an environment limitation, not verified purchase behavior. `git diff --check` also passed. Temporary image exports and build index/module caches were removed to relieve disk pressure; source artwork, previews and test-result bundles were preserved.
