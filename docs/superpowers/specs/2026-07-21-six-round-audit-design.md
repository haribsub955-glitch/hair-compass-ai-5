# Six-round audit & improvement cycle — design

Date: 2026-07-21 · Branch: `feature/on-device-ai-only` · Requested by user (autonomous run)

## Goal (user request, verbatim intent)
1. Audit whether the app is the **one-stop shop for hair loss**; find and implement improvements.
2. Make the app have the **best UI/UX experience in the world**.
3. Ensure the **user experience, demands, and journey are covered A–Z**.
4. Repeat the find-improvements cycle **6 times**, with **Sonnet agents implementing** the findings.

## Approach
A single Workflow orchestration with 6 rounds. Each round:
- **Audit** — 3 parallel auditors, one per dimension: feature completeness (one-stop-shop for hair loss), world-class UI/UX, and A–Z user journey. Auditors read the actual source and verify every claim; they receive the list of already-implemented and rejected items to avoid repeats.
- **Prioritize** — dedupe by title, rank by impact (high→low) then effort (small→large), cap per round: 6/5/4/4/3/3 (≈25 improvements max).
- **Implement** — Sonnet agents, one finding at a time, **serially** (shared files like RootView/TodayView would conflict under parallel edits).
- **Verify** — a Sonnet agent runs `xcodebuild build` and fixes forward up to 3 attempts.

After round 6: a final build + unit-test pass.

## Constraints (hold for every change)
- Apple frameworks only; no new dependencies; no backend.
- AI stays fully on-device (FoundationModels); never reintroduce cloud AI/keys.
- Health framing: record-keeping and pattern-spotting, explicitly **not** diagnosis.
- Design tokens from `Hair Compass AI 5/Design/Clinical.swift`; file organization follows Feature/Model/Service split; new files auto-register (synchronized Xcode groups).
- Widget snapshot struct is duplicated app-side and widget-side — keep in sync; App Group `group.harib.Hair-Compass-AI-5`.
- SwiftData schema changes additive with defaults.
- No git commits during the run; all changes stay in the working tree for user review.

## Alternatives considered
- **One mega-audit instead of 6 rounds** — rejected: the user explicitly asked for 6 iterations, and iterative rounds let later audits see and build on earlier fixes.
- **Parallel implementers per round** — rejected: most findings touch the same handful of screens; serial implementation avoids edit conflicts without worktree overhead.
