# Shipment readiness — the server server, one remote tester, before Supabase

**Verdict as of 2026-07-31: NOT READY — one blocker left, and it is the account takeover.** Two external adversarial reviews (two external reviewers) both
returned FAIL, independently, on the same root cause.

The bar being measured against is deliberately narrower than production: the server runs on the
the server, one trusted external tester drives the phone remotely, no Supabase, no real revenue.
Roughly G2 InternalPilot. It is still not met.

---

## Blocking

### 1. `/v1/session` authenticates nothing
`src/agent_server/api.py` → `src/agent_server/auth.py`. `principal_id` is a pure function of the
client-supplied `installation_id`. Post a victim's id, receive a signed token naming **their**
principal, then read their consent record and audit trail or erase their account.

Session tokens were introduced believing they closed this. They did not — they moved the
credential from every endpoint to one endpoint. `sessions.py` asserted otherwise in a docstring;
that claim was false and has been corrected in place.

Second consequence, and the one that costs money: a never-seen installation id is **by
construction** granted the 3-day taster. Any random string is a new principal with a fresh grant on
the provider key. The cost of farming it was estimated at "a reinstall cycle"; it is **one POST**.
That estimate was wrong by orders of magnitude and it was the basis of the taster's whole design.

*Partially built:* `src/agent_server/devicebind.py`, the `device_keys` table and the proof check on
`/v1/session` exist. `REQUIRE_DEVICE_BINDING` is off by default and the Swift client does not yet
generate or register a key, so the hole is open until both change.

### ~~2. `/v1/turn` has no consent gate and no entitlement check~~ — FIXED
Both gates now run in `TurnService.authorize()`, called from the route **before** the
`StreamingResponse` is constructed. The first attempt put them inside the generator and a test
caught it: the status line is already sent by then, so raising produced "response already started"
and the client got a broken stream instead of a clean 403.

Verified live: a turn with no consent record returns `403 consent_required`; after granting, the
same token streams.

### ~~3. Per-plan limits resolve to the free plan for everyone~~ — FIXED
`Principal` carries `plan_id` alongside the coarse enum, and it travels inside the signed session
token so every endpoint measures against the same value. `Agent.run` takes the output and iteration
caps per CALL, because one Agent serves every concurrent turn and the limits cannot live on the
instance.

Measured before and after: `"pro"` resolved to 512 `max_output_tokens`, `pro_monthly` to 2048.

`Entitlement` survives for the tool registry's coarse gate. Deleting it is the right end state and
a wider refactor than that fix wanted to be.

---

## The recurring defect

Five instances of one pattern: **written, unit-tested, and not on the path that executes.**

| Control | State |
|---|---|
| App Attest | imported by tests only |
| `/v1/turn` consent gate | absent |
| Arabic safety rules | 233 lines of guards, no caller — Arabic answers screened by English regex, audited `ALLOW` |
| `policy_version` in the consent check | never passed; bumping it changes nothing |
| Per-plan output/iteration caps | reach the wrong function |

`tests/test_request_path.py` is the right idea and needs extending: for each control, assert the
**HTTP** path enforces it. Correctness and reachability are separate claims and a unit test only
makes the first.

---

## Fixed this round

* **App Attest chain validation was fully bypassable** — proven by an executed PoC. The check
  returned success when *any* certificate in the client's list reached an Apple root rather than
  when the leaf did, so a forged leaf plus a self-signed CA plus the genuine (public) Apple
  intermediate passed. Now an ordered path with CA and length checks; both attack variants are
  regression tests. The test fixture was complicit — it built a "root" with no `BasicConstraints`.
* **Backups had never run.** Scheduled, executable, mounted — and CRLF line endings meant the
  kernel looked for an interpreter named `bash\r`. `.gitattributes` now pins LF. Restore verified:
  10 tables, 135 principals, constraints intact.
* **`TRUST_CLIENT_WITHOUT_RECEIPT`** — which grants pro to every caller — removed from the server
  and replaced by named, expiring, audited tester grants.
* A non-ASCII session token was an unhandled 500 (`hmac.compare_digest` on `str`); now a clean 401.

---

## What held under adversarial review

Worth recording, because it is what does not need re-examining: token forgery and
token→principal confusion; StoreKit receipt replay across principals; the ledger's `FOR UPDATE`
row lock and its fail-closed behaviour on unknown plans and unregistered principals; the audit
metadata screen, including the `device_id` column; the taster's per-principal re-take guard; and
`claim_database` preventing a staging process from writing to a production database.

---

## Queued behind the above

* **Affiliate catalogue** — specified in `docs/CATALOG.md`. Server-owned, device-cached, images
  served by us, aggregate tap counts, tier hidden behind a reversible flag.
* Alembic. `create_all` cannot ALTER; the receipt-uniqueness constraint was applied by hand and the
  drift guard only warns.
* `token_version`, so erasure and the build kill-switch do not lag a 24-hour token TTL.
* `appAccountToken` — receipt ownership is first-presenter-wins. Must land **before the first paid
  release** or existing subscribers never have one.
* App Store Server Notifications; refunds surface only when the client next presents a receipt.
* `CLIENT_IP_HEADER` under the tunnel — the default walks into the trap its own comment documents.
* Offsite backup destination; `sync_records` has a schema and no transport.
* Device Swift: BGTaskScheduler, NWPathMonitor, RTL layout. **No Swift has ever been compiled.**
