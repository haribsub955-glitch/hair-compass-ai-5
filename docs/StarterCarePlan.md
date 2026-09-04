# Starting care plan and Plan navigation

Implemented 4 September 2026. This is educational navigation and record-keeping, not diagnosis or an automatically prescribed treatment plan. Clinical content should receive qualified clinical review before release.

## What changes

- Plan's pinned shortcuts highlight the current section, both after a tap and during manual scrolling. Equal-width buttons, selected accessibility state, and Reduced Motion support are retained. Products is no longer permanently selected.
- Normal launches and foreground returns no longer show random comb/knot/massage/serum games. Existing subtle in-context motion and Wren remain. Explicit DEBUG artwork previews still work.
- Onboarding hands off to the Plan destination with the roadmap first, including a replay with existing records. On ordinary later visits, existing users keep their routine first; people without a routine see the roadmap first.
- Essential next steps remain visible. Optional setup and already-recorded items are collapsed, keeping Plan shorter.

## Roadmap

1. A baseline photo and brief check-in establish a record without encouraging repeated checking.
2. An assessment step explains what to bring and what to ask. Its wording varies by the user's reported concern; the concern is not treated as a confirmed diagnosis.
3. A lab discussion is distinct from obtaining a result. For reported diffuse shedding, iron/thyroid tests are discussion examples, not an order. Other concerns do not generate an automatic vitamin, mineral or hormone panel. Sex or pregnancy alone does not populate a lab checklist.
4. Discuss care, side effects and a review date. Record the agreed schedule or appointment using existing app forms. The plan never requires buying a product, starting medication or undergoing a procedure.

Pregnancy-related answers add a clinician caution. Warning-sign guidance makes clear that users should not wait for enough tracking data to seek assessment.

## Completion and persistence

- Check-ins, photos, existing treatment and lab setup use actual local records.
- A consultation is complete only when explicitly marked completed and its date is not in the future. A saved appointment is not a clinic booking or an attended visit.
- Lab/care discussions require an explicit user confirmation; reading the screen or adding a result never checks them off. A conversation concluding that no tests or treatment are needed is valid.
- Discussion confirmations use `starterPlan.discussed` in local preferences, with Undo available by reopening a recorded item. They are convenience checklist state, not a clinical record and not included in medical exports. Like existing checklist dismissals, they are not part of the backup envelope; device restore may require confirming them again.
- “Not for me” only hides a checklist item; it does not delete underlying records. Erase-and-start-over clears preferences through the existing domain reset.

## Evidence and limits

- [American Academy of Dermatology: diagnosis and treatment](https://www.aad.org/public/diseases/hair-loss/treatment/diagnosis-treat): history and examination precede targeted investigations and treatment decisions; treatment is not always necessary.
- [British Association of Dermatologists: telogen effluvium](https://www.bad.org.uk/pils/telogen-effluvium): clinical assessment and possible investigation of iron deficiency or thyroid disease support the diffuse-shedding discussion.
- [American Academy of Dermatology: CCCA signs and symptoms](https://www.aad.org/public/diseases/hair-loss/types/ccca/symptoms): pain/burning and scar-like scalp changes support prompt assessment messaging, not an in-app diagnosis.

The monthly photo cadence is a product choice for consistent comparison and reduced checking, not a diagnostic threshold. The app does not order tests, book external appointments, change doses, or decide a clinician's follow-up interval. Sources are linked inside the roadmap.

## Verification

- Native simulator build passed (iPhone 17 Pro, iOS 26.3.1).
- 28 focused unit tests passed: roadmap rules, snapshot parity and completion, launch interruptions, section selection, and onboarding summary integration.
- Three UI tests passed: onboarding → roadmap, Products/Today navigation plus manual-scroll selection and centered tabs, and roadmap → clinician appointment form.
- Visually checked the post-onboarding roadmap in the simulator; optional/completed steps remain collapsed.
- Tests used an isolated source snapshot and a dedicated simulator to avoid another task's concurrent onboarding/IAP testing. Existing Swift 6 migration warnings remain outside this change's scope.
