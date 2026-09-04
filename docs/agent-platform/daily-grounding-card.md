# Daily Grounding Card: server contract

Status: the iOS decoder, validator, same-day cache, feature gate, and deterministic fallback are
implemented. The server endpoint described here still needs to be added to `agent-platform`.

The card is one calm, record-grounded message on Today. It is not a diagnosis, chat reply, generic
affirmation, engagement notification, or treatment recommendation. The server chooses the useful
message; the app verifies that the response is safe to render. Any failure is silent and leaves the
local deterministic card visible.

## Availability and request

Advertise `daily_grounding` in the `/v1/session` `features` array only for sessions allowed to use
the endpoint. The app does not infer access from `plan_id` or `entitlement`.

`POST /v1/grounding` requires the normal `X-Access-Key` header and this JSON body:

```json
{
  "session_token": "signed session token",
  "state": {
    "flags": ["stable identifiers owned by the app"],
    "plan_items": [
      {
        "id": "exact occurrence id",
        "state": "open|completed|missed|paused",
        "slot": "Evening",
        "treatment": "recorded display name"
      }
    ],
    "plan_complete": false,
    "plan_counts": { "total": 2, "completed": 1, "open": 1 },
    "missed_yesterday": 0,
    "shedding_above_usual": false,
    "logged_today": true,
    "photo_within_two_weeks": false,
    "policy": {
      "review_weeks": [4, 12, 24],
      "photo_interval_days": 28,
      "consistency_window_days": 30
    },
    "phase": {
      "day": 18,
      "week": 3,
      "label": "Building a baseline",
      "next_review_week": 4,
      "days_to_review": 10
    },
    "consistency_30d": {
      "completed": 8,
      "planned": 11,
      "scored": 10,
      "percent": 80
    },
    "photo": { "status": "upcoming", "days_until": 8 },
    "concern": "optional concern kind"
  }
}
```

Optional objects are omitted when unavailable. `planned` is every scheduled occurrence in the
window; `scored` is only settled occurrences that can honestly be graded. Include `percent` only
when `scored > 0`, calculated as `completed / scored`. Never emit or accept the old `expected`
field, and never describe an open-only window as `0%`.

## Successful response

Return one complete object with an ISO-8601 expiry:

```json
{
  "id": "opaque stable response id",
  "kind": "grounding",
  "eyebrow": "TODAY'S GROUNDING",
  "headline": "One difficult day is not a conclusion",
  "body": "Yesterday's shedding was above your usual range. One observation is not enough to establish a change.",
  "evidence_anchor": "Next trend review: 10 days",
  "primary_action": {
    "type": "complete_plan_item",
    "label": "Mark evening treatment complete",
    "target_id": "exact occurrence id"
  },
  "secondary_action": {
    "type": "open_concern_flow",
    "label": "I'm worried"
  },
  "closure": "You have recorded what happened. Nothing else needs to be checked today.",
  "tone": "gentle",
  "valid_until": "2026-09-05T00:00:00+04:00",
  "served": true
}
```

Closed values:

- `kind`: `safety`, `concern`, `grounding`, `continuation`, `preparation`, `closure`, `settled`,
  `recovery`, `celebration`, `education`, or `quiet`.
- `tone`: `gentle`, `direct`, `scientific`, or `minimal`.
- primary `type`: `complete_plan_item`, `log_checkin`, `open_photos`, `open_plan`,
  `prepare_visit`, or `none`.
- secondary `type`: only `open_concern_flow`; otherwise omit it.

For `complete_plan_item`, `target_id` must be an id in the request. Other primary actions must not
depend on an arbitrary URL or server-defined destination.

## Rendering gate in iOS

The app rejects the response when any of these is true:

- `served` is false, a required string is empty, or an enum/action is unknown;
- the headline exceeds 10 words or the body exceeds 55 words;
- the expiry is not in the future;
- a completion target is not in the current local plan;
- any visible number is absent from the request's allowed facts and policy constants;
- an unscored consistency window is framed as `0%`;
- wording diagnoses, promises a cure, prescribes, commands treatment changes, labels anxiety, says
  the condition is getting worse, or uses an exclamation mark;
- the server tries to provide a safety card. Local deterministic safety always wins.

A passing response is cached for the same calendar day and exact state fingerprint. Today shows a
server card only when it is materially different from the local one and the record has not changed
while the request was in flight. The network is attempted at most once for that day/state identity.

## Server implementation checklist

1. Add the authenticated route and reuse the existing session, consent, budget, scope, and output
   safety middleware. An off-topic/no-spend result may still be HTTP 200 with `served: false`.
2. Build the prompt solely from the submitted state. Do not infer medical facts, attach external
   clinical claims, or manufacture dates and percentages.
3. Return structured JSON only. Enforce the same enums, word limits, number provenance, and action
   target validation server-side before marking `served: true`.
4. Make the hierarchy prefer urgent deterministic guidance, then the person's current concern,
   then one actionable plan step, then evidence-timing reassurance. Do not optimize for streaks or
   repeated checking.
5. Add contract tests for absent fields, invalid targets, invented numbers, `scored == 0`, safety
   stripping, expiry, and feature denial. Log rejection categories without storing card text or
   health details.

## Release boundary

The iOS call is intentionally `DEBUG`-only and additionally requires `HC_AGENT`. Before enabling it
in production, update the privacy policy, privacy manifest and App Store disclosure; provide clear
consent for sending the summarized state; verify deletion/retention behavior; and complete the
session-device binding work called out in `MOOSAWI_HANDOVER.md`. Until all of that is complete, the
deterministic on-device card remains the production behavior.
