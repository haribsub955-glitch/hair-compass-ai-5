# Hair Compass — Clinical Minimal Design System

Source of truth for tokens is `Hair Compass AI 5/Design/Clinical.swift`. This document
is the written spec (refined via a Google Stitch concept pass, 2026-07-02) — update both
together.

## Principles
Clinical minimalism: clarity, data integrity, professional trust. Objective, meticulous,
calm — built for a high-stakes documentation context, not a lifestyle app.

- **No decorative effects.** No shadows, gradients, blurs, or glassmorphism.
- **Structural depth, not elevation.** Hairline borders and tonal shifts, never drop shadows.
- **High information density, low visual noise.** A rigorous grid over decoration.

## Color
| Token | Hex | Use |
|---|---|---|
| Canvas | `#F7F7F9` | Screen background |
| Surface | `#FFFFFF` | Cards, inputs — anything interactive |
| Ink | `#0B0B0C` | Primary text |
| Secondary | `#6B7078` | Supporting text |
| Tertiary | `#9FA3A8` | Captions, disabled, chart ticks |
| Hairline | `#E6E7EA` | The only border color |
| Accent | `#1666D6` | The one functional color — actions, active states, links |
| Positive / Warning / Critical | `#1C7C54` / `#B4690E` / `#C73636` | Flags only, never decorative |

## Typography
Native SF (San Francisco) — not Inter/Space Mono as in the Stitch concept, since a bundled
web font breaks the "this is a native iOS instrument" read. SF's tabular-digit feature
serves the same role as a monospaced data face.

- **Eyebrow:** SF monospaced, 10–11pt, semibold, uppercase, tracked +1.2–1.8pt.
- **Headline:** SF, 24–30pt, bold.
- **Body:** SF, 13–16pt, regular/medium.
- **Data:** SF monospaced-digit, sized to context — always tabular so values don't jitter.

## Shape & elevation
- Card radius: 16pt. Small controls: 9–13pt. Capsule for chips/segmented backgrounds only.
- Depth = a 1px hairline border, never a shadow. Pressed/active state = fill or border-color
  change, not a lift.

## Components
- **Card** (`ClinicalCard`): white fill, 16pt radius, 1px hairline border, no shadow.
- **Primary button** (`ClinicalButtonStyle(filled: true)`): solid ink fill, white text.
- **Secondary button** (`filled: false`): white fill, hairline border, ink text.
- **Segmented control** (`ClinicalSegmented`): canvas track, ink pill for the active option.
- **Checklist row:** outlined 22pt ring, fills with an accent check only when done — never a
  solid pre-filled circle. (Adopted from the Stitch concept pass; more restrained than a
  filled/unfilled system icon toggle.)
- **Status footer:** a quiet, centered card reporting real last-activity time — confirms the
  app is current instead of leaving a silent screen to read as stale.

## What we deliberately did not adopt from the Stitch concept
- Inter / Space Mono fonts — SF is the correct native choice.
- Fully custom Material-style token names (`surface-container-highest`, etc.) — our SwiftUI
  token set in `Clinical.swift` covers the same ground with fewer names.
