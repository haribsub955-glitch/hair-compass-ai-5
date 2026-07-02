# Hair Compass — Warm & Premium Design System

Source of truth for tokens is `Hair Compass AI 5/Design/Clinical.swift` (type name kept
for low-risk continuity; the content is warm & premium, not clinical-minimal — see history
below). This document is the written spec — update both together.

## History
1. **Pearl/forest/serif** — the original app design.
2. **Clinical-minimal** — a full from-scratch rebuild (white/gray/blue, hairline structure,
   no imagery). Rejected by the user (2026-07-02): "too plain, doesn't feel like a hair
   app, wrong colors, no pictures."
3. **Warm & premium** (current) — ivory/cream surfaces, a signature copper accent, real
   generated illustrated artwork. Chosen explicitly by the user over bold/vibrant and
   dark/luxe alternatives.

## Principles
A premium wellness/skincare brand feel — warm, tactile, a little indulgent, unmistakably
about hair. Real illustrated imagery carries emotional weight; flat tokens alone don't.

## Color
| Token | Hex | Use |
|---|---|---|
| Canvas | `#FBF6EF` | Screen background — warm ivory |
| Surface | `#FEFCF9` | Cards — warm card white |
| Ink | `#2B211A` | Primary text — espresso, not black |
| Secondary | `#7A6B5D` | Supporting text — warm taupe |
| Tertiary | `#A69687` | Captions, chart ticks — muted warm gray |
| Hairline | `#EDE1D3` | Borders — soft warm tan |
| Accent | `#B1592E` | Signature copper/terracotta — CTAs, active states, selected segments |
| Gold | `#C9A15A` | Antique gold — secondary highlight, not yet load-bearing in UI |
| Sage | `#8A9D7B` | Botanical green — matches the artwork palette |
| Positive / Warning / Critical | `#5C7A52` / `#B98B2E` / `#A6432E` | Flags only |

## Typography
- **Headlines:** `.serif` design (renders as New York) — warm, editorial. `Clinical.headline(_:)`.
- **Eyebrows:** SF monospaced, uppercase, tracked.
- **Body/data:** SF, tabular digits for numbers.

## Shape & elevation
Soft tactile depth, not hairline-only: cards are 22pt-radius warm white with a diffuse
warm-espresso shadow (`Clinical.cardShadow`, not a cold gray shadow). Primary buttons are
solid copper with a soft copper glow shadow.

## Imagery — `BrandArt`
All artwork is one consistent painterly gouache style: warm terracotta/cream/sage/gold,
botanical sprigs (rosemary, eucalyptus) woven with hair-strand and compass-rose motifs, no
text baked into any asset. Generated via Nano Banana Pro (Higgsfield MCP,
`nano_banana_pro`), 2k resolution.

| Asset | Imageset | Used in |
|---|---|---|
| Today hero banner | `hero-today` | `TodayView` — 16:9 banner under the greeting |
| Baseline welcome art | `hero-baseline` | `BaselineFlow` — portrait hero above the intro copy |
| Photos empty state | `hero-photos-empty` | `PhotosView` — shown when a region has no captures |
| App icon (light/dark/tinted) | `AppIcon.appiconset` | Home screen |

**App icon gotcha:** the first dark-icon generation baked in its own rounded corners with
a white background showing through the gaps — iOS applies its own corner mask on top of a
full-bleed square asset, so any pre-baked rounding shows as a corner artifact. Verified by
sampling corner pixels with a small CoreGraphics script; fixed by explicitly prompting for
"full-bleed square, sharp 90° corners, background extends to all four corners."

## What changed from clinical-minimal
- No more hairline-only depth — soft shadows are back, deliberately.
- No more flat blue accent — copper/terracotta carries the same job.
- Segmented control and buttons use the accent color, not ink, for selected/filled states.
- Real illustrated imagery on Today, Baseline, and Photos-empty — the single biggest lever
  for "feels like a hair app."
