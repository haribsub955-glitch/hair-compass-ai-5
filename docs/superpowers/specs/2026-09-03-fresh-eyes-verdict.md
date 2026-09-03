# Fresh-eyes verdict: is Hair Compass AI useful to a first-time user?

**Date:** 2026-09-03
**Build examined:** live line 42aff26 (sub-project A landed; B in progress), iPhone 17 Pro simulator, both a one-day record and the seeded 120-day record. Every surface reached by launch flag and screenshot: onboarding cover, concern picker, paywall, finale; Today; Trends; Plan; Labs; Photos; the daily log; Learn; Wren.
**Asked by the owner:** "consider yourself as a user and make a verdict: is this useful to you? If no, what would you add or modify — add it without consulting."

## Verdict

**Yes, useful — and unusually honest — with four gaps that decide whether I keep using it past week one.**

What earns the "yes":

- The loop is coherent: one log a day → a trend line that says when it is too early to judge → a ritual that tracks doses to the 24-week mark → labs with ranges and a plain-language flag → standardised photos. Nothing pretends to know more than the record does.
- Trends is the best screen in the app. "Too early to judge — week 20 of 24" and "Shedding lower this week · 5 of 7 days logged" are exactly what a worried person needs to hear, and the shaded "Opens after 2 daily logs" placeholder (sub-project A) tells a new user the chart is coming rather than showing a blank.
- Labs is clear and calm: value, range bar, "Vitamin D is below range" with a next step, and a footer that says context, not diagnosis.
- Onboarding's concern picker ("Pick the closest match — plain words, the clinical name is underneath") is the kindest version of a scary question I have seen in this category.
- Wren answers from the record, names its limits, and now works on every iPhone.

What would make me stop:

1. **The first week asks for a two-minute form every day, with reminders off.** Reminders default to Off and nothing offers to turn them on until you find the card on Plan. The daily log is rich (evidence badges, why-this-matters) but there is no one-tap way to log a quiet day from Today. A tracking app lives or dies in days two to seven; this one leaves that to willpower.
2. **The Compass Score is a number with no explanation.** "80 — Photo still open today" tells me what is missing but never what the number is made of or why it matters. It is the second thing on the screen.
3. **Nobody tells me what to do first.** After onboarding I land on Today with a giant word ("Normal") and no plan. Sub-project B fixes this (starting plan on the finale and the Plan tab), so it is not re-specified here.
4. **Small jargon leaks.** "Amber band — possible echo window" on Trends; "Ritual" as the Plan tab's eyebrow while the tab is called Plan. The first is opaque to a new user; the second is deliberate brand voice and stays.

Things I checked and would leave alone: the 15-step onboarding (long, but every step earns its place and the 3-day window makes the paywall honest); Learn's repeated illustration per category (by design: one piece per category); the gold "New badge" pill on Trends (loud, but earned); the Photos empty state (already the clearest in the app).

## Changes (sub-project E)

Small, high-value, all within the framing rule and the existing design language. Sequenced after B lands and before C and D, because the retention gap is the one that costs users now.

### E1. One-tap "Same as yesterday" on Today

When today has no log and yesterday has one, the Today hero shows a secondary outlined chip beside the log button: **"Same as yesterday"**. Tapping it creates today's entry as a copy of yesterday's values (shedding, scalp, oil, stress, sleep) through the existing repository upsert, gives the success haptic, and the hero flips to its logged state with the usual "Edit log" button so a wrong tap is a one-tap fix. The log sheet's existing "Start with yesterday's values" prefill stays for people who want to adjust first.

Rules: never shown when today is already logged; never shown on day one (no yesterday); a copy is a full entry, so streaks and the Compass Score treat it like any log.

### E2. A one-time reminder nudge after the first log

After the first saved log on a device where reminders are off and the nudge has never been shown (`@AppStorage("reminders.nudgeShown")`), Today shows one quiet card under the hero: **"Want a nudge tomorrow evening?"** with "Turn on" (enables the evening check-in reminder at its existing default time and requests notification permission through the existing service) and "Not now" (dismisses forever). One card, once, then never again — the Plan tab's reminders card remains the place to change it later.

### E3. The Compass Score explains itself

The score ring and its label become one tappable control. Tapping opens a small sheet, **"How your score works"**: what today's score counts (the three things the ledger already tracks — the check-in, the routine doses, and a photo when one is due), that it resets each day, and that it measures consistency, never hair health. Copy is derived from `CompassScore`'s real composition by the implementer, so the sheet cannot drift from the model. VoiceOver reads the ring as a button with the score as its value.

### E4. Copy: "echo window"

Trends' legend line becomes: **"Amber band — when a trigger's effect may show."** The word "echo" leaves the user-facing copy (it stays in code comments and in the Life Events sheet's developer-facing strings only if they are not shown to users; the implementer checks `LifeEventsSheet.swift:71,135` and rewrites any user-visible use the same way).

## Tests

- E1: unit test on the copy-from-yesterday function (values copied, date is today, no copy when today exists or yesterday is absent); UI test on Today: with a seeded record and today unlogged, the chip exists; after tapping, "Edit log" exists.
- E2: unit test on the nudge decision (shown once, only when reminders are off, never again after either button).
- E3: unit test that the explanation sheet's copy names every factor `CompassScore` scores.
- E4: existing suites.

## Not changed, and why

- Onboarding length and the paywall page: owner's monetization rulings; the 3-day window keeps the sale honest.
- Reminders during onboarding: the spec's non-goal ("no change to what onboarding asks") holds; E2 gets the same outcome at the moment it matters most, right after the first log.
- The Plan tab's "Ritual" eyebrow: brand voice.
