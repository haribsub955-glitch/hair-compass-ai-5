# Daily Grounding + Plan Adherence — Product and UI Specification

**Date:** 2026-09-03  
**Status:** Product direction / implementation-ready design specification  
**Scope:** Today experience, AI-generated motivational cards, treatment-plan adherence, anxiety-aware interactions, reminders, widgets, and milestone handoff  
**Related documents:** [engagement science](../../research/2026-07-11-engagement-science.md), [adherence journey](2026-07-11-adherence-journey-design.md), [Wren companion](2026-07-22-wren-companion-mascot-design.md), [warm premium design system](../../DesignSystem.md)

This document consolidates the motivational and adherence ideas into one product system. Where it conflicts with older engagement or adherence proposals, this document governs the Today experience.

---

## 1. Product decision

Hair Compass should not behave primarily like a diary, a generic AI chatbot, or a game. It should behave like a calm companion that helps a worried person follow a plan long enough to collect trustworthy evidence.

The core promise is:

> **We will help you continue when progress is slow, calm you when one difficult day feels frightening, and tell you honestly when the evidence is ready.**

The primary loop is:

> **Ground the user → show one action → make completion effortless → close the day → wait for a meaningful milestone.**

The app succeeds when the user:

- understands what needs to be done today;
- completes a planned treatment with one tap;
- feels less compelled to inspect or photograph their hair unnecessarily;
- resumes calmly after missing a day;
- knows when the next meaningful review will occur;
- remains consistent long enough to produce an interpretable treatment record.

Daily active use is not the north-star metric. The app should often complete its job from a notification or widget without requiring a full app session. Remaining installed, being trusted, and reaching the next evidence milestone are more important than maximizing screen time.

---

## 2. The psychological job

A person experiencing hair loss is usually managing uncertainty as much as hair. The interface must respond to the underlying emotional state without diagnosing it or claiming that the app knows how the user feels.

| User experience | Product response | What to avoid |
|---|---|---|
| “Every shed hair feels like proof that I am getting worse.” | Distinguish one observation from a repeated trend. | Declaring improvement or decline from one day. |
| “I need to check the mirror again.” | State when the next comparable photo is due and give permission to stop checking. | Encouraging daily photographs or comparisons. |
| “I cannot see progress, so treatment must not be working.” | Show the treatment phase and the earliest meaningful review date. | Premature outcome scores. |
| “I missed yesterday; I have ruined the plan.” | Normalize resumption and show long-window consistency. | Broken-streak warnings, red failure screens, or shame. |
| “I do not know whether this needs a doctor.” | Screen for predefined warning signs and provide an appropriate next step. | AI reassurance when a safety rule is triggered. |
| “The app keeps making me think about my hair.” | Offer quiet days, minimal mode, and optional card frequency. | Engagement for engagement's sake. |

### Design principle: closure is a feature

Most health products tell the user what remains incomplete. Hair Compass must also explicitly say when nothing more is required:

> **You are done for today. Nothing else needs to be checked.**

This provides psychological closure and prevents the app from becoming another source of rumination.

---

## 3. Information architecture

The Today tab should answer four questions in this order:

1. **Where am I in the plan?**
2. **What should I remember today?**
3. **What is the one action due now?**
4. **When will the next meaningful review happen?**

Everything else is secondary.

### Recommended Today layout

```text
┌────────────────────────────────────────────┐
│ Good morning                         Wren  │
│ DAY 34 · EARLY ASSESSMENT                  │
├────────────────────────────────────────────┤
│ [small Wren avatar]                        │
│ ONE DIFFICULT DAY IS NOT A CONCLUSION      │
│                                            │
│ Yesterday's shedding was above your usual │
│ range. One observation is not a trend.     │
│                                            │
│ Your only task today is your evening dose. │
│                                            │
│ [ Mark treatment complete ]                │
│ [ I'm worried ]                 Helpful?   │
├────────────────────────────────────────────┤
│ TODAY'S PLAN                               │
│ ✓ Morning minoxidil              8:05 AM   │
│ ○ Evening minoxidil               Due 8 PM │
│ ○ Scalp care                    Due Friday │
├────────────────────────────────────────────┤
│ YOUR EVIDENCE                              │
│ This week       6 of 7 planned actions     │
│ Last 30 days    87% consistency            │
│ Next photo      In 8 days                  │
│ Next review     In 26 days                 │
├────────────────────────────────────────────┤
│ Add detail · View plan · Ask Wren          │
└────────────────────────────────────────────┘
```

### Completed-day state

After the final due action is completed:

- the Today plan collapses to one calm line;
- the primary button disappears rather than asking for more interaction;
- the card updates to a closure message;
- a subtle sage check and light success haptic confirm completion;
- there is no confetti, XP, countdown pressure, or prompt to add optional data.

Example:

> **Your plan is complete for today**  
> You showed up. Your next useful check is tomorrow evening. Nothing else needs to be checked today.

---

## 4. Daily Grounding cards

### 4.1 Purpose

Daily Grounding is an AI-assisted card generated from the user's treatment phase, record, due actions, and expressed concerns. It is not a generic quotation and not a daily medical conclusion.

Every card must do four jobs:

1. **Acknowledge** the situation without claiming to know an unreported emotion.
2. **Anchor** the user in one fact from the record or an approved educational fact.
3. **Direct** the user to no more than one primary action.
4. **Close** the interaction by explaining what does not need attention today.

### 4.2 Card anatomy

The visible card contains:

- small category eyebrow, such as `TODAY'S GROUNDING`;
- concise headline of no more than 10 words;
- two or three short sentences, ideally under 55 total words;
- optional factual anchor tied to the record;
- one primary action;
- one secondary action, normally **I'm worried** or **Why this?**;
- optional `Helpful / Not for me` feedback;
- small Wren avatar, never a large mascot covering the content.

The card is not a carousel. There is one primary card, stable for the day. It may refresh after a meaningful state change—such as completing the last treatment or reporting a new concern—but it must not change merely because the screen reopened. The user should not be trained to refresh for a different emotional reward.

### 4.3 Card categories

| Category | When to use it | Desired effect |
|---|---|---|
| Grounding | Increased shedding, repeated checking, or user-selected worry | Separate a moment from a trend. |
| Continuation | An action is due during a long treatment window | Make today's step feel manageable. |
| Recovery | A planned action was missed | Encourage resumption without shame. |
| Education | The user is too early to judge or misunderstands a milestone | Replace uncertainty with a time horizon. |
| Celebration | A real milestone was reached | Recognize stored evidence, not appearance. |
| Preparation | Photo, review, or appointment is approaching | Give one timely action. |
| Quiet day | Nothing needs action | Reduce unnecessary engagement. |
| Safety | A predefined warning sign is present | Replace motivation with care guidance. |

### 4.4 Inputs used for selection

The card-selection system may use:

- active plan and treatment names;
- treatment start dates and current phase;
- scheduled, completed, skipped, paused, and missed actions;
- rolling 7-day and 30-day consistency;
- whether a check-in or comparable photo is due;
- time remaining until the next evidence milestone;
- recent shedding observations, described conservatively;
- user-entered illness, procedure, stressor, or lifestyle event;
- an explicit concern submitted through **I'm worried**;
- preferred tone and notification frequency;
- previous cards, to prevent repetition;
- safety-screen results returned by the server.

The system must not infer an emotional diagnosis from passive data. It may say “You recorded higher shedding yesterday,” but not “You are anxious about shedding” unless the user explicitly reports worry.

### 4.5 Structured generation contract

The server owns card selection, medical scope, prompting, consent, and the output safety screen. The iOS app renders a structured response and provides a deterministic local fallback.

Recommended response shape:

```json
{
  "id": "grounding-2026-09-03-user-scope",
  "kind": "grounding",
  "eyebrow": "TODAY'S GROUNDING",
  "headline": "One difficult day is not a conclusion",
  "body": "Yesterday's shedding was above your usual range. One observation is not enough to establish a change.",
  "evidence_anchor": "Next trend review: 18 days",
  "primary_action": {
    "type": "complete_plan_item",
    "label": "Mark evening treatment complete",
    "target_id": "plan-item-id"
  },
  "secondary_action": {
    "type": "open_concern_flow",
    "label": "I'm worried"
  },
  "closure": "You have recorded what happened. Nothing else needs to be checked today.",
  "tone": "gentle",
  "valid_until": "2026-09-04T00:00:00+04:00",
  "served": true
}
```

The action is represented by a closed enum and a validated target identifier. The model must never generate arbitrary deep links, medication instructions, or executable commands.

If `served` is false, generation fails, the device is offline, or the response violates the schema, the app uses a deterministic card assembled from local plan state. The user must always receive a useful Today state.

### 4.6 Generation hierarchy

The card is chosen in this order:

1. **Safety override:** warning signs or reported adverse effects.
2. **Explicit concern:** answer the reason the user selected **I'm worried**.
3. **Due action:** support completion of the next plan item.
4. **Missed-action recovery:** support a calm restart.
5. **Milestone preparation:** photo, review, or appointment approaching.
6. **Milestone recognition:** enough evidence has been collected.
7. **Treatment-phase education:** it is too early to judge.
8. **Quiet day:** no action is needed.

This prevents a cheerful motivational message from appearing when the user actually needs safety guidance or a concrete task.

### 4.7 Tone preferences

Ask during setup or the first card interaction:

> **How would you like Hair Compass to support you?**

- **Gentle:** warm and reassuring;
- **Direct:** brief and practical;
- **Scientific:** more explanation and uncertainty language;
- **Minimal:** only communicate when an action is due.

Tone changes presentation, not facts, safety thresholds, or medical scope. The choice remains editable in Settings.

### 4.8 Example cards

#### Early treatment

> **You are building the baseline**  
> You are on day 9. It is too early to judge visible change, but consistent records will make the first comparison more reliable.  
> **Today:** Complete your planned treatment.  
> No photo is needed today.

#### Increased shedding

> **One observation is not a trend**  
> You recorded more shedding yesterday. Hair shedding can vary between wash days, so Hair Compass will wait for a repeated pattern before interpreting it.  
> You logged it. That is enough for today.

#### Missed action

> **Restart with today's step**  
> You completed 12 of the last 14 planned actions. One missed action does not erase that consistency.  
> Resume your normal plan today unless your clinician told you otherwise.

#### Strong consistency

> **Consistency is becoming usable evidence**  
> You completed 91% of planned actions during the last 30 days. This will make your next review easier to interpret.  
> Your next comparable photo is due in eight days.

#### Photo-checking urge

> **The next useful photo is 11 days away**  
> Photos taken too frequently are easily distorted by lighting, styling, and angle. Waiting will produce a more trustworthy comparison.  
> Nothing needs to be photographed today.

#### Quiet day

> **You are allowed to have a normal day**  
> No unusual pattern or plan action needs your attention today. Hair Compass will remind you when something meaningful is due.  
> You can close the app.

#### Milestone preparation

> **Your first review is approaching**  
> You have collected four weeks of plan and shedding information. A guided photo this weekend will complete the checkpoint.  
> **Next step:** Schedule the photo for a time with consistent lighting.

#### Inconclusive outcome

> **Uncertainty is an honest result**  
> Your plan consistency was high, but the latest photos are not comparable enough to judge visible change.  
> Continue the plan and retake the photo using the baseline guide.

---

## 5. “I'm worried” flow

The card's secondary action opens a focused concern flow instead of dropping the user into an empty chat.

### Step 1: identify the concern

> **What is worrying you today?**

- More shedding
- My hair looks different
- A possible side effect
- A scalp symptom
- Doubt about treatment
- I keep checking
- Something else

### Step 2: collect only essential context

Ask at most two adaptive questions. Do not repeat information already in the record. A possible side effect or warning-sign category routes through approved safety logic before any generative response.

### Step 3: respond in four sections

1. **What the record shows**
2. **What cannot yet be concluded**
3. **What to do next**
4. **When to seek help**, if applicable

### Step 4: close or continue

The primary action should normally be a concrete task such as **Continue today's plan**, **Record this event**, **Prepare clinician questions**, or **Contact a clinician**. Freeform Ask Wren remains available after the structured response, not before it.

If a user repeatedly selects **I keep checking**, offer:

- fewer motivational notifications;
- a longer photo interval;
- hiding appearance charts until the next milestone;
- Minimal support mode;
- a neutral suggestion to seek additional support if worry is interfering with daily life.

The app must not label the user with an anxiety disorder or present itself as mental-health treatment.

---

## 6. Plan adherence tracker

### 6.1 What is being measured

Adherence measures completed planned actions, never hair outcomes.

Every plan item has:

- name and category;
- start date and optional end date;
- schedule and acceptable completion window;
- prescribed or user-defined frequency;
- current state: active, paused, or ended;
- completion events;
- optional notes about clinician instructions;
- milestone schedule appropriate to the plan.

Every occurrence has one of these states:

- **Upcoming**
- **Due**
- **Completed**
- **Skipped intentionally**
- **Missed**
- **Paused / not expected**

Future, paused, and not-expected occurrences are excluded from the adherence denominator. As-needed treatments are recorded as usage events and must not receive an adherence percentage unless a real schedule exists.

The app must never recommend doubling a missed medication dose. It should say to resume according to clinician or medication instructions.

### 6.2 Primary adherence views

#### Today: action list

Use compact rows with one obvious tap target:

```text
TODAY'S PLAN
✓ Morning minoxidil                         8:05 AM
○ Evening minoxidil                         Due 8 PM
○ Scalp treatment                         Due Friday
```

Tapping the circle completes the item with a soft haptic. Tapping the row opens details. A long press or overflow menu provides **Skip**, **Pause**, **Edit time**, and **Undo**; these should not compete with the primary completion action.

#### Seven-day continuity strip

Use seven small day capsules rather than a large calendar heatmap:

```text
M   T   W   T   F   S   S
✓   ✓   ·   ✓   ✓   ✓   ○
```

- sage check: all expected actions completed;
- copper dot: partially completed;
- warm neutral dash: no action expected;
- outline circle: today/upcoming;
- muted taupe dot: missed, without red alarm styling.

This gives context without turning an imperfect month into a wall of failure.

#### Thirty-day consistency

Show a horizontal bar and plain-language count:

> **87% consistency**  
> 26 of 30 planned actions completed

Avoid grades such as A/B/C and avoid judging words such as poor, failed, or non-compliant. When appropriate, explain whether adherence is sufficient to interpret the next milestone; do not equate high adherence with treatment effectiveness.

#### Multi-treatment detail

The Plan tab shows each treatment separately because a blended number can hide an important problem:

```text
Minoxidil             91% · 30 days
Finasteride           97% · 30 days
Scalp treatment       64% · 30 days
```

The Today hero may summarize the overall plan, but clinical export and treatment review must retain per-treatment adherence.

### 6.3 Milestone timeline

Every active plan receives a visible timeline. Dates are driven by the treatment plan and approved guidance, not invented by the generative model.

```text
Baseline ── 4-week review ── 12-week review ── 24-week review
   ✓             ✓                 ●                  ○
                              You are here
```

Each milestone states:

- why it exists;
- what evidence will be reviewed;
- whether a comparable photo is needed;
- whether the result can be interpreted yet;
- the next action after the review.

The model may explain the milestone in the user's preferred tone. It may not change the milestone schedule unless the server returns an approved plan update.

### 6.4 Recovery after missed actions

Missing an action should create a recovery path, not a penalty state.

Required behavior:

- no broken-streak modal;
- no red full-screen warning unless there is a true safety concern;
- do not reset long-term progress to zero;
- show rolling consistency so one miss remains proportional;
- provide an easy **Resume today** action;
- permit correction when the user completed an action but forgot to log it;
- allow pause reasons such as clinician instruction, side effect discussion, travel, or treatment unavailable;
- never suggest unsafe catch-up dosing.

Recommended recovery copy:

> **Today is a clean place to restart**  
> One missed action does not erase the record you have built. Resume your normal plan today unless your clinician instructed otherwise.

### 6.5 Notification and widget completion

Plan actions must be completable from:

- the Today row;
- a scheduled notification action;
- the Home Screen widget;
- the Lock Screen widget, where supported.

Opening the app should not be required for a routine completion.

Treatment reminders and motivational messages are distinct:

- treatment reminders follow the user's actual schedule and explicit permission;
- motivational-card notifications are separately opt-in;
- no more than one motivational notification is sent per day;
- a motivational notification is cancelled when its action is already completed;
- the notification preview must be neutral enough to protect health privacy on a locked screen;
- notification wording is invitation-based, never guilt-based.

Examples:

- “Your evening plan is ready when you are.”
- “One step today keeps your next review interpretable.”
- “Nothing is due today. Your next check is Friday.”

Do not send lock-screen text such as “Your hair loss is getting worse” or expose medication names unless the user explicitly enables detailed previews.

---

## 7. Best UI treatment

### 7.1 Visual hierarchy

Use the existing warm premium design system:

- `Clinical.canvas` warm ivory as the page background;
- `Clinical.surface` for the grounding card;
- `Clinical.ink` for primary text;
- `Clinical.secondary` for explanation;
- `Clinical.accent` copper for the one primary action;
- `Clinical.sage` for quiet completion;
- gold only for earned milestones;
- critical red only for genuine safety states.

The largest type on Today should be the grounding headline or current plan phase—not a numerical score. Numbers are supporting evidence, not the emotional center of the screen.

### 7.2 Card appearance

The Daily Grounding card should feel like a reassuring note, not a dashboard tile:

- 22-point corner radius;
- warm surface with the existing diffuse espresso shadow;
- generous 20–24 point interior padding;
- serif headline and plain sans-serif body;
- maximum comfortable text width;
- a small static Wren avatar aligned with the eyebrow;
- no background chart, gradient animation, carousel dots, or competing badges;
- one filled copper button and at most one quiet text action.

### 7.3 Motion and feedback

- Card entrance: subtle opacity and 4–6 point vertical settle, once per new card.
- Completion: soft haptic, check morph, and a short sage wash contained inside the completed row.
- Milestone: restrained Wren celebration, shown once and Reduce Motion-safe.
- No pulsing incomplete rings, shaking reminders, urgency countdowns, or infinite mascot animation.
- Do not animate shedding or density data merely to increase salience.

### 7.4 Progressive disclosure

The default Today screen shows only what is needed today. Place these behind secondary navigation:

- detailed shedding entry;
- stress, sleep, alcohol, smoking, oiliness, and long notes;
- historical charts;
- treatment education;
- complete milestone history;
- raw AI explanation;
- advanced adherence comparison.

This preserves the rich record without making every day feel like a clinical questionnaire.

### 7.5 Wren's role

Wren is the source of the supportive voice, but the data remains the authority.

- use a small avatar on Today and in structured concern responses;
- use a full Wren illustration only during onboarding, empty states, and real milestones;
- do not place a large mascot on charts, lab tables, photo comparisons, or safety guidance;
- never make Wren look sad because the user missed a task;
- never make Wren's health, happiness, or survival depend on adherence.

The user should feel accompanied, not emotionally manipulated.

### 7.6 Accessibility

- Support Dynamic Type without truncating card meaning.
- Treat the grounding card as a heading followed by body, evidence, and actions in VoiceOver order.
- Do not rely on color alone for plan states; use symbols and labels.
- Maintain 44-point minimum action targets.
- Respect Reduce Motion and Reduce Transparency.
- Use tabular digits for adherence and dates.
- Make **Mark complete**, **Undo**, **Skip**, and **Pause** distinct to assistive technology.
- Decorative Wren art is hidden from VoiceOver; interactive Wren controls receive descriptive labels.

---

## 8. What this replaces or removes

| Current or proposed element | Decision | Replacement |
|---|---|---|
| Compass Score as the Today hero | Remove from the hero; consider retiring entirely | Treatment phase, today's action, and next review |
| XP and levels | Remove | Meaningful evidence milestones |
| Perfect-streak pressure | Remove | Rolling 7-day/30-day consistency and calm recovery |
| Weekly photo as a daily-score requirement | Remove | Treatment-appropriate monthly or milestone photo schedule |
| Full two-minute form as the default daily action | Demote | Four-input quick check or one-tap same-as-yesterday; details optional |
| Generic motivational quotations | Do not build | Record-grounded Daily Grounding cards |
| New AI card on every app open | Do not build | One stable card per day/state change |
| Floating full Wren presence on every screen | Reduce | Contextual Wren avatar and structured entry points |
| Early trigger conclusions | Hide until evidence threshold | “Still collecting evidence” state |
| Red failure styling for missed actions | Remove | Neutral missed state and **Resume today** |
| Long post-onboarding feature tour | Remove | Contextual teaching at first use |

Rich charts, labs, photo history, clinician export, and detailed lifestyle context remain valuable. They are not primary daily elements and should appear only when relevant.

---

## 9. Safety and trust rules

These rules are non-negotiable for generated cards and adherence messages:

- never diagnose a hair-loss condition;
- never claim causation from a correlation;
- never invent a number, event, treatment, symptom, or milestone;
- never promise regrowth or treatment success;
- never use one shedding entry or one photograph to declare deterioration;
- never provide catch-up dosing instructions;
- never override clinician instructions;
- never provide reassurance when a deterministic safety rule requires escalation;
- clearly state when evidence is insufficient or photo quality is not comparable;
- do not use fear, shame, appearance insecurity, or Wren's emotions to drive adherence or conversion;
- do not place affiliate products inside grounding, safety, or milestone cards;
- display the reason a card appeared when the user taps **Why this?**;
- provide card frequency, tone, and notification controls;
- allow the user to turn Daily Grounding off while retaining plan tracking.

When the server returns a successful off-topic response with no model work, render the scope guidance as a normal Wren message. When the output safety screen returns `served: false`, show the app's deterministic safe summary rather than an error or empty card.

---

## 10. Loading, offline, and failure states

Today must never depend on live AI to render.

1. Render the locally cached card immediately if it is still valid.
2. Render the local plan and due actions from SwiftData.
3. Request a refreshed card in the background when allowed.
4. Replace the cached card only when the new response is valid and materially relevant.
5. If generation fails, use a deterministic local card based on plan state.

Fallback examples:

- action due: “Your next planned action is ready.”
- all complete: “Your plan is complete for today.”
- missed action: “Resume with today's scheduled action.”
- photo due: “Your next guided photo is due today.”
- no action: “Nothing needs your attention today.”

Do not show “AI unavailable” as the main Today message. A small non-blocking retry indicator may appear inside **Why this?** or Wren chat.

---

## 11. Access and monetization recommendation

Daily Grounding, basic plan completion, reminders, and a basic consistency view should remain part of the durable free core. They establish trust and create the record that later makes paid analysis valuable.

Appropriate paid capabilities include:

- advanced multi-treatment comparisons;
- AI-generated milestone interpretation;
- multi-angle photo comparison and long-term journey;
- detailed correlations;
- labs intelligence;
- complete clinician report;
- deeper Wren conversations grounded in the full record.

Do not lock the user's ability to see or export their own basic adherence history after a short trial. Do not use an anxious Daily Grounding card as a disguised paywall entry.

---

## 12. Measurement

Measure whether the feature helps the user's plan rather than merely increasing attention.

### Primary outcomes

- percentage of users who create an active plan;
- first planned action completed;
- median seconds required to complete a routine action;
- plan continuity at days 7, 30, 90, and 180;
- percentage reaching the first meaningful milestone;
- percentage completing a comparable milestone photo;
- missed-action recovery within the next scheduled window;
- clinician report created or shared at a milestone.

### Card quality outcomes

- `Helpful / Not for me` response by card category;
- **I'm worried** reason distribution;
- concern resolved without repeated opening in the same day;
- cards hidden, frequency reduced, or feature disabled;
- AI generation and schema-validation success;
- deterministic fallback frequency;
- repetition rate over 30 days;
- safety overrides and escalation completion.

### Guardrail metrics

- notification opt-out and app uninstall following notifications;
- repeated same-day photo capture;
- repeated same-day comparison opening;
- increased opening without plan completion;
- self-reported card-induced worry;
- paywall impressions originating from vulnerable/safety states—target zero.

Do not optimize the system for card opens, chat length, or daily screen time in isolation.

---

## 13. Delivery sequence

### Phase 1 — Calm adherence foundation

- replace the Today score hero with treatment phase and today's plan;
- implement one-tap plan completion and undo;
- add seven-day continuity and 30-day per-treatment consistency;
- add notification/widget completion;
- implement deterministic local grounding cards;
- implement completed-day closure;
- remove shame states and weekly-photo scoring.

### Phase 2 — Server-generated Daily Grounding

- add the structured card response to the session/turn contract;
- implement category selection, preferred tone, caching, and validation;
- add **Why this?** and card feedback;
- add safety-screen and local-fallback behavior;
- add repetition controls and stable-per-day behavior.

### Phase 3 — Concern and milestone intelligence

- implement the structured **I'm worried** flow;
- add treatment-specific milestone timelines;
- add guided photo preparation and comparable-photo checks;
- generate milestone reviews with uncertainty and next actions;
- integrate appointment preparation and clinician export.

### Phase 4 — Personal control and refinement

- add Gentle, Direct, Scientific, and Minimal support modes;
- add optional appearance-checking protections;
- tune messages using helpfulness and opt-out signals;
- validate tone, safety, and emotional effects with real users experiencing hair loss.

---

## 14. Acceptance criteria

The feature is ready only when all of the following are true:

- Today communicates the next action without scrolling.
- A routine action can be completed in one tap and undone safely.
- A quiet day explicitly tells the user that nothing is required.
- Missing one action never resets progress or triggers shame copy.
- The visible adherence percentage can be reconstructed from scheduled and completed events.
- Each treatment has its own adherence value.
- As-needed actions are not assigned misleading adherence percentages.
- Motivational cards remain stable during repeated opens and change only after meaningful state changes.
- Every card contains an anchor, no more than one primary action, and a closure statement.
- Every generated fact is traceable to approved guidance or the user's record.
- A generated-card failure still leaves a useful deterministic card.
- Safety conditions override motivational content.
- Red is reserved for true safety concerns.
- Daily Grounding can be muted or disabled without disabling the treatment plan.
- VoiceOver, Dynamic Type, Reduce Motion, and lock-screen privacy are verified.
- No grounding or safety state routes directly to an affiliate offer or fear-based paywall.

---

## Final experience statement

The best Hair Compass Today experience is not “Here is everything we know about your hair.” It is:

> **Here is where you are. Here is the one thing that matters today. Here is why you do not need to panic. We will tell you when the evidence is ready.**

That combination—human reassurance, honest uncertainty, effortless adherence, and meaningful milestones—is the durable reason to keep Hair Compass installed.

---

## Appendix A — Creative screen concept set

The demonstration set intentionally moves beyond a conventional stack of dashboard cards. Each screen uses a distinct Hair Compass metaphor while preserving the same information hierarchy and safety rules.

### A1. Calm Horizon — Today

The user's treatment is drawn as a quiet path across a sunrise horizon: Baseline → You are here → Review. Wren sits on the current position rather than floating as an unrelated chat button. The horizon communicates that the answer is ahead in time, which is more emotionally meaningful than a generic progress percentage.

The supportive note overlaps the horizon like a personal letter. It contains one observation, one treatment action, and one reason not to check again. A compact evidence ribbon at the bottom shows plan rhythm and the next photo date without becoming another dashboard.

### A2. Close the Day — Completion

Completing the last planned action opens a quiet closure state. Wren appears inside a restrained botanical halo; the visual reads as rest rather than celebration pressure. The primary message is “Nothing else needs checking today.” A seven-day constellation acknowledges continuity while rendering a missed day as a muted pause—not a broken chain.

### A3. Evidence Lens — “I'm worried”

The first state asks what pulled the user's attention using six soft, irregular thought tiles. Selecting a concern transforms the screen from emotion to evidence. For shedding, seven observations appear as six steady points and one highlighted day, making “one moment versus a pattern” immediately understandable before the explanatory text is read.

The response is always organized as:

1. What this says
2. What it cannot say
3. One next step
4. Closure

### A4. Living Evidence Path — Plan

Milestones follow a gently winding path rather than a clinical horizontal progress bar. Completed checkpoints use sage, the current position uses copper, and the future remains softly outlined. The path makes slow progress visible without implying that the user should be further ahead.

Per-treatment consistency appears underneath as thin “strand” lines. Percentages remain available for accuracy, but the treatment journey—not a score—is the screen's emotional focus.

### Creative constraints

- Metaphors must clarify time, uncertainty, or action; decoration alone is insufficient.
- The current position is emphasized more than the destination.
- Wren guides the user but never reacts sadly to missed adherence.
- Completion should feel like release, not a request for another interaction.
- No screen should contain more than one visually dominant idea.
- Charts and percentages remain subordinate to the decision they support.
