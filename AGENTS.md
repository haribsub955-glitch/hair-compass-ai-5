# AGENTS.md

Read **CLAUDE.md** in this directory — it is the single, current source of guidance for AI
agents working in this repository (architecture, build/test commands, AI engine order, consent
rules, monetization rulings, gotchas). This file exists only so Codex-style tooling finds it.

Two rules worth repeating even here:

- **This repository is PUBLIC.** Never commit a key, token, or secret. The DeepSeek key lives
  only in `Config/Secrets.local.xcconfig` (gitignored).
- The app is record-keeping and education, **never diagnosis** — preserve that framing in every
  prompt, string, and doc you touch.
