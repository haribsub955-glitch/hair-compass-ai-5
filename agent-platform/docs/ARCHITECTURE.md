# Agent Platform — architecture spec

**Version:** v1 (supersedes v0 after external adversarial review, 2026-07-29)
**Status:** approved direction, pre-implementation
**Target gate:** G1 now → G3 before it fronts a paid feature.

## 0. What changed from v0, and why

v0 was reviewed adversarially by two external models. Both returned *request changes before
implementation*. The findings that changed the design:

| # | Finding | Resolution in v1 |
|---|---|---|
| 1 | The Action Gate **cannot** govern effects performed by a patched device. The desktop guarantee depends on one in-process mandatory path (permit minted, passed down one call stack, consumed once); a remote phone is not that call stack. | §5 now publishes a **control matrix**: `server_authoritative` (enforced) vs `device_cooperative` (requested + audited, not enforced). Stated as a boundary, not a gap. |
| 2 | Taint-by-provenance is weaker than claimed — the server knows which tool it *requested*, not what produced the returned bytes. | §5: **every client-originated value is untrusted content**, regardless of tool. Decisions may depend only on server-derived facts. |
| 3 | The approval flow left "who mints the receipt" unspecified. (Note: the desktop implementation is *safer* than v0 described — it mints an opaque nonce in a `NonceStore` and consumes it atomically against the bound payload. v0 under-described it.) | Deferred out of G1 entirely — no mutating device tool in G1. When it lands: **server** persists an `Approval` row and sends an opaque ID; the client performs a compare-and-swap transition. |
| 4 | `LoopState` per-iteration checkpointing is not durable execution — it holds a frame and counters, not the transcript revision, pending tool call, or event sequence. And `PreparedAction.executable` is a **callable** while `ActionContext.cancellation` is an event object, so the core does **not** port "unchanged" into a resumable runtime. | Deferred out of G1 (no loop in G1). When it lands: pure serializable reducer `reduce(RunState, Event) -> (RunState, Commands[])`, with a tool lifecycle state machine, worker leases, idempotent inbox, transactional outbox. Evaluate Restate before hand-rolling. |
| 5 | Data residency contradicted the audit story — auditing raw prompts/results puts device-held data on the server anyway. | §9: **metadata-only audit** by default (IDs, hashes, policy versions, decisions, costs). Payload tracing behind short-lived explicit diagnostic consent. |
| 6 | Capability negotiation conflated availability with authorization. | §7: the client term is **subtractive only**. Entitlement comes from StoreKit/Play server records, never a client boolean. |
| 7 | `tenant + subject` is not an identity model. | §6: distinct immutable IDs, all derived from the authenticated server context, never from request JSON. |
| 8 | The "app pack" combined server IP, compiled client code, and deployment config — three different trust boundaries. | §4: split into `ServerPolicyPack` / `ClientIntegration` / `DeploymentManifest`. |
| 9 | Idempotency missing. Hair Compass books EventKit procedures — a retried "add to calendar" after a lost ACK duplicates the event. | Mutating device tools require idempotency keys; an effect that may have run but has no result becomes `UNKNOWN` and is never auto-retried. Out of G1. |
| 10 | Budget is raceable — the router takes one `budget_ok` boolean; two concurrent turns both see room. | §6: atomic ledger, reserve worst-case before each provider call, reconcile after. **In G1** — see §3. |
| 11 | The medical boundary is enforced by nothing. The gate controls effects, not the meaning of text, and there is no deterministic verifier for "diagnosed a condition". | §9: structured output with claim categories + deterministic deny rules + a versioned semantic verifier + a Hair-specific adversarial eval set tracking **false accepts**. In G1. |
| 12 | The Swift client is not thin — it owns reconnect, replay, Keychain, App Attest, backgrounding, approval UI. And Hair Compass forbids third-party/SPM deps, so a Swift package needs an explicit exception. | §11: wire contract defined independently; one cross-language conformance suite; Mac CI a release gate from the first Swift commit. |
| 13 | Offline was a fiction — server-held prompts mean an offline local model has no system prompt or tools. | Resolved by the owner's decision below. |
| 14 | "Model agnostic" needs a capability contract, not a shared session API. | §8: server-side `ModelAdapter` with an explicit capability matrix; packs declare required capabilities. |

**Owner decision (2026-07-29), which resolves #13 and simplifies #6, #7, #14:**

> **No local-LLM option. All AI is server-side, subscription-gated.** The API key requires internet
> regardless; a local rung would add iOS-version, OS-version and hardware constraints for a feature
> that is paid anyway. Data is stored on-device and syncs when connectivity returns.

Consequences, accepted deliberately:
- Wider device support, not narrower — no Apple Intelligence hardware floor, no iOS 27, no PCC
  entitlement, no Apple-controlled per-user quota.
- Platform symmetry — a Flutter/Android client gets the identical AI experience.
- The cost ledger is on the **critical path**, because no free rung absorbs cheap work.
- Every AI surface has a round trip, so **no screen may block on the server**: render the
  deterministic result instantly, let AI refine asynchronously.
- Reversible: because the server holds policy, adding a local model later for a cheap step is a
  policy change plus one device tool, not an architecture change.
- **This reverses part of the `feature/on-device-ai-only` branch** (its decision #2: "Pro gated
  locally, no server verification"). Server-side AI must verify entitlement before spending the key.
  That branch's non-AI work all stands; its on-device chat and on-device deep analysis do not.

## 1. Goal

One reusable agent platform behind many mobile apps. First consumer: **Hair Compass AI 5** (iOS,
SwiftUI, shipping). Later: additional consumer apps, some Flutter/Android.

1. **Plug and play across apps** — a new app is declarative config plus a compiled client
   integration, never a fork of the core.
2. **Agent logic must not ship in the binary** — an attacker decompiling the IPA/APK must not
   recover the loop, the policy, the prompts, or the playbook rules. (See §5 for what this does and
   does **not** buy.)
3. **User data may stay on the device** — memories, playbook values and user records are not IP;
   keeping them local is a privacy and PDPL asset.
4. **Model-agnostic** behind a server-side adapter with an explicit capability contract.
5. **Windows-developable** — the owner has no usable Mac (theirs is a 2016 Intel MacBook Pro on
   macOS 12.7.6, no Xcode: cannot run Xcode 26, cannot run Apple Intelligence).

## 2. Non-goals

Not in v1 at all: rewriting Hair Compass in Flutter · multi-agent teams · accounts/SSO ·
CloudKit sync · local/on-device LLM rungs · device MCP.

Deferred until a real user story demands it: the multi-turn agent loop · mutating device tools ·
approval-over-wire · durable orchestration · memory RPC · deferred tool loading/LRU · the Dart SDK.

## 3. G1 — the first deliverable (one server-authoritative path, no agent loop)

Both reviewers judged v0's "one turn, one device tool, one approval round-trip" to be a
workflow-engine demonstration rather than a product slice. Hair Compass's actual cloud feature today
is **bounded analysis over one context snapshot**, and no current user story needs a multi-turn loop
or a mutating device tool. So G1 is:

1. Anonymous installation auth → a **server-derived principal** (no account, schema account-ready).
2. Entitlement verification by exchanging the StoreKit JWS for a short-lived server session bound to
   that principal.
3. A **versioned context envelope** (the app's own `AIContext`) with explicit consent and size limits.
4. One **server-held prompt pack**, one model call through the `ModelAdapter`.
5. **Structured output** + the safety evaluator (§9).
6. **Atomic cost reservation** and a usage record.
7. Streamed response with a polling fallback.

Needs none of: memory RPC, approval receipts, device MCP, persistent loop, tool LRU, Dart SDK,
model ladder. Fully testable on Windows against a fake client.

## 4. Layers

```
agent-core       Python, pure, serializable values only     ← policy: classification, completion, routing
      ↑
agent-server     FastAPI + Postgres                         ← identity, entitlement, cost ledger, adapters, transport
      ↑ versioned wire contract (HTTP + SSE + polling)
client SDK       Swift now; Dart later                      ← session, event cursor, idempotent submission, local journal
      ↑
per app:  ServerPolicyPack  +  ClientIntegration  +  DeploymentManifest
```

- **`ServerPolicyPack`** (server IP): prompts, allowed tool schemas, effect policy, completion
  policy, budgets, safety rules, eval corpus.
- **`ClientIntegration`** (compiled client code): native handlers, permission/consent UX, local
  storage adapters, app-specific context builders. Hair Compass's `AIContextBuilder` lives here and
  is **not** promoted to a universal subject API.
- **`DeploymentManifest`**: compatible server pack, client build range, flags, rollout, rollback.

Protocol, schema and pack versions are pinned on every run; incompatible combinations are rejected
before a turn starts.

## 5. Trust boundary — the control matrix

Anti-decompilation protects **IP** and **server-side authority**. It does **not** make device-local
effects enforceable, because code already running on a patched device can bypass the server for
anything the OS lets it do. State the boundary rather than pretend otherwise.

| Domain | Contents | Enforcement |
|---|---|---|
| `server_authoritative` | billing, entitlement, model spend, server data, server tools, provider calls, server-mediated remote MCP | **Mandatory.** Server gate is the only path. |
| `device_cooperative` | local reads/writes, local exports, local notifications, device-originated calls | Server may **request and audit**; a compromised device is outside the enforcement boundary. |

Rules that follow:

- **Every client-originated value is untrusted content**, regardless of which tool was requested.
  Server-owned labels (`origin`, `integrity`, `instruction_trust`) replace a single `taints` boolean.
- Safety, entitlement, completion and budget decisions may depend **only** on server-derived facts,
  or on client values explicitly marked advisory.
- Untrusted text travels in a typed data channel with size limits and structured parsing. "Data, not
  instruction" is a framing, never a control.
- Any effect that must remain enforceable against a patched client moves behind a server-controlled
  credential.
- **Threat model:** a rooted / OS-modified device is out of scope for enforcement. App Attest raises
  confidence that a request came from a genuine app instance and is defence in depth — Apple states
  it can be bypassed by OS modification, and it never proves returned content is honest.

**Server holds what *decides*; the device holds what gets *operated on*.** Policy, entitlements,
budgets, prompts and the tool manifest are config, not corpus — keeping them server-side does not
compromise the data-on-device goal.

## 6. Identity, tenancy, cost

Distinct immutable IDs, every one derived from the authenticated server context and **never**
accepted from request JSON: `app_id`, optional `tenant_id`, `principal_id`, `installation_id`,
`data_subject_id`, `session_id`, `turn_id`.

- Composite tenant keys and foreign keys on every table: runs, events, approvals, tool calls, audit,
  quotas, caches, memory.
- RLS executed under an application role that **cannot bypass RLS**, plus DB constraints so an
  application bug cannot join across partitions.
- Installation key rotation, reinstall recovery, account linking/unlinking, subscription restoration
  and deletion are defined **before** data exists.
- `memstore/scopes.py` keeps its grammar unchanged, but its storage API requires an authority object
  so a query cannot exist without a partition. Otherwise one forgotten predicate turns `global` into
  cross-app data.

**Cost ledger (G1, critical path):** reserve a worst-case amount before each provider call, recording
provider, model and price version; reconcile actual usage after. Hard per-turn ceilings in the
provider adapter. Define behaviour when actual exceeds reservation. No cache may ever cross a subject
or tenant boundary.

## 7. Capability negotiation — subtractive only

```
server app-policy allowlist
  ∩ authenticated product entitlements       (StoreKit / Play server records — never a client boolean)
  ∩ server-known protocol/build compatibility
  ∩ server-side tool/provider availability
  ∩ client-advertised current availability    ← may only REMOVE
```

Every invocation still passes per-call server authorization. Tool identity binds to a schema hash,
effects version, pack version and minimum client protocol. Any client-side classification is an
advisory routing hint: it can never lower a safety tier, unlock a paid strategy, or raise a quota.

## 8. Models

One rung: **server-side provider via `ModelAdapter`**, with an explicit capability matrix (tool-call
semantics, structured output, streaming, context limits, token accounting, refusals, image support,
cancellation, retries, data handling). Packs declare required capabilities; a provider missing a
required safety feature is rejected, never silently downgraded. Conformance tests cover malformed
tool arguments, parallel calls, truncation, refusals, cancellation, usage accounting and retries.

**Offline is a separate product mode, not a degraded agent tier.** Offline, the app runs its existing
deterministic paths (`HairAnalytics`, `RuleBasedInsight`) — which already work fully offline. A user
request made offline is queued as *intent*; on reconnect a **fresh** turn starts with a **fresh**
context snapshot. Local state is never merged into a suspended server run.

## 9. Security & safety floor (day 1)

- Deny-by-default authorization on every endpoint, including reads, lists and exports.
- Object-level authz: permission + resource scope, resources referenced by validated ID.
- **Metadata-only audit by default** — IDs, hashes, policy/pack versions, effect descriptors,
  decisions, costs. No raw prompts, tool results or model outputs. Payload tracing sits behind
  explicit short-lived diagnostic consent.
- No provider key in any client binary, ever.
- **Medical-claims boundary is code, not copy.** Structured response carrying claim categories,
  evidence references, uncertainty and escalation flags; deterministic allow/deny rules first; then a
  separately versioned verifier for semantic claims; fail to the app's deterministic fallback when
  the safety result is uncertain.
- **Hair-specific adversarial eval set before any prompt iteration** — adversarial user text, OCR
  injection, unsupported diagnoses, sub-24-week treatment windows, emergency symptoms. Track **false
  accepts**, not overall pass rate.
- Negative-authz tests are a **merge gate**: cross-tenant read denied, cross-user memory read denied,
  quota exhaustion enforced, client-claimed entitlement ignored, client-claimed capability cannot add.
- Abuse controls: oversized tool results, repeated disconnects, model-spend races, client-created work.

## 10. Data residency

Owner operates from Oman. Oman PDPL (Royal Decree 6/2022 + Executive Regulations, Ministerial
Decision 34/2024) requires **explicit consent before transferring personal data outside Oman**.
Device-resident data is a compliance asset: what never leaves is not transferred.

A field-level data-flow matrix is required **before** choosing infrastructure — for each field:
origin, transit, server persistence, provider processing, region, encryption, log policy, retention,
deletion, export, consent purpose and version. The processor chain includes the inference provider,
observability vendor, backups and support exports, not just the database region.

**Decision for v1:** local-only memory with ephemeral, consented per-turn projections. Metadata-only
audit. Revisit only with a complete residency + deletion + account-migration design.

## 11. Clients

- **Hair Compass stays Swift.** ~139 Swift files plus a live branch 13.5k insertions ahead of main.
  Value concentrated in Apple-only frameworks (WidgetKit, App Intents, Live Activities, SwiftData,
  StoreKit 2), each of which would need a hand-written plugin under Flutter.
- **Future apps default to Flutter** where Android matters on day one.
- **Mixing:** Flutter Add-to-App, or Flutter-first with Swift plugins. Both valid. Splitting ordinary
  screens across both runtimes is rejected — two UI systems, two navigation systems, two state
  systems, larger binary.
- The SDK is **not** thin: reconnect, event replay, durable local IDs, background transitions,
  Keychain identity, App Attest, approval presentation, schema compatibility, error recovery.
  Define the wire contract independently, generate or mechanically validate DTOs, run one
  cross-language conformance suite against Python and Swift, and make Mac CI (hosted or the
  partner's) a release gate from the first Swift commit.
- Hair Compass currently permits **Apple frameworks only, no SPM** — a Swift package needs an
  explicit exception or a vendored in-repo target.

## 12. Development strategy (Windows-first)

`agent-core` and `agent-server` are Python and test end-to-end on Windows against a **fake client**.
No macOS in the critical path. Windows cannot validate FoundationModels, Keychain, App Attest,
StoreKit, backgrounding, entitlements or approval UI — those need the Mac CI gate above.

## 13. Open questions

1. Which device effects, if any, must be enforceable against a patched app? If any, why are they not
   server-mediated?
2. What is the stable anonymous principal across reinstall, device transfer and subscription restore?
3. Which first Hair Compass user story genuinely needs a multi-turn loop or a mutating device tool?
   (G1 assumes: none yet.)
4. Who owns the Mac CI runner and the physical-device release check?
5. Hosting region and provider, given §10.
