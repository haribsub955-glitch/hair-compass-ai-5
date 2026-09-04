# Hair Compass — Evidence-Based Tracking Spec

Every tracked field below traces to a verified finding from the 2020–2026 dermatology
literature (deep-research run, 106 agents, adversarial 3-vote verification). Fields that
failed verification are listed at the end so we never build them.

## Design intent
Clinical-minimal. The app is a **documentation instrument**, not a diagnosis engine.
Its job: capture signals a dermatologist would actually act on, time-lag them correctly,
and present them with honest uncertainty.

---

## 1. Baseline (captured once, editable)
One-time risk factors dominate AGA risk and must be captured up front, not tracked daily.

| Field | Why (evidence) |
|---|---|
| Family history of hair loss (none / one parent / both / extended) | **Strongest measured AGA risk factor** — presence OR 2.72 (1.85–3.99), progression OR 4.24 (2.77–6.49). |
| Primary condition focus (AGA / alopecia areata / telogen effluvium / traction / seborrheic dermatitis / unsure) | Determines which severity instrument and signals matter. |
| Biological sex, age band | Modifies staging scale (Norwood vs Ludwig) and baselines. |
| Baseline pattern stage (Norwood I–VII / Ludwig 1–3) | Anchor for longitudinal comparison. |

## 2. Daily / periodic signals (longitudinal)

### Seborrheic-dermatitis symptoms — self-reported score adapted from a 16-point scale
Zhang et al. 2023, *J Cosmet Dermatol* (verified 3-0). The source instrument was clinician-administered; the app's 0–3 flaking input and mapping are an unvalidated self-report adaptation. Three near-patient-observable items:
- **Flaking** 0–3 (scale item is 0–10, adherent flakes at the top; we band it 0–3 for self-report)
- **Erythema (max area)** 0–3
- **Itch / pruritus** 0–3
- **Severity band:** derived — 0–5 mild · 6–9 moderate · 10–16 severe (scaled from the 16-pt total)

### Shedding (self-report proxy)
No validated at-home count survived, but shedding is the core patient-tracked signal for
TE/AGA. Track as an ordinal daily estimate (minimal / normal / elevated / heavy) and trend it.

### Sleep quality (1–5)
Poor sleep quality is **significantly associated with AGA progression** (OR 1.36, 1.18–1.56),
though **not** with presence — so surface it against *progression*, timed, never as a cause.

### Smoking (cigarettes/day)
Genuine, quantified AGA risk factor (high confidence): ever-smoker pooled OR 1.82 (1.55–2.14);
2026 meta-analysis presence OR 1.46, progression OR 1.60. Weighted risk field, not a myth.

### Stress (1–5)
Retained as a common TE trigger context signal (lower evidence tier; framed as context only).

## 3. Treatments & adherence
Track adherence per treatment; **gate all outcome interpretation to ≥24 weeks (6 months)** —
the standard RCT endpoint for AGA hair-density change (verified 3-0). Never judge efficacy earlier.

- Classes: minoxidil, finasteride, dutasteride, microneedling, PRP, LLLT, other.
- Combination beats monotherapy in general; in men **finasteride + minoxidil is most efficacious**
  (SUCRA 80.21%, +29.68 hairs/cm² vs minoxidil alone at 24 weeks).
- UI shows weeks-elapsed vs the 24-week milestone as a progress gate.

## 4. Labs (individualized, with reference ranges + flags)
Testing should be **individualized, not blanket**. Order what derms actually order:
- Ferritin (keep — meta-analysis supports lower ferritin in TE, despite one outlier study)
- TSH, free T4
- Vitamin D (25-OH)
- Vitamin B12
- (Biotin is **not** routine — primary deficiency ~1/60,000; do not push blanket supplementation.)

## 5. Photos — standardized documentation protocol
Bare phone camera **cannot** count trichoscopic features (needs a clip-on dermatoscope), so we
document macro progress under controlled conditions instead:
- Fixed **regions**: frontal, vertex, temporal-L, temporal-R, global.
- Consistency metadata per shot: lighting, distance, hair parting, wet/dry — compare only
  same-region, same-condition pairs.
- Optional dermatoscope note field for users who own one (STRIAA / trichoscopy signs).

## 6. Severity instruments referenced (for staging, not phone-measured)
- **SALT** (alopecia areata scalp %), **STRIAA** trichoscopy index (5 signs × 4 areas, /60,
  correlates with SALT rho 0.664) — offered as guided self-assessment, clearly labeled as
  requiring magnification for the trichoscopy variant.

---

## Explicitly NOT built (failed adversarial verification)
- Hair-diameter-diversity / anisotrichosis >20% threshold (1-2 ✗)
- Serum zinc / Cu:Zn ratio tracking (0-3 and 1-2 ✗)
- 12-week treatment plateau timing (✗)
- LLLT "~80% effectiveness" claim (✗)
- Microneedling+minoxidil superiority in women (1-2 ✗)
- Blanket biotin / multivitamin efficacy tracking (individualize instead)
