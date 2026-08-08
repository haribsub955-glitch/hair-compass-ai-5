# Device-tool dispatch — why it works this way

**Audience:** whoever picks this up next, human or agent. Read this before changing
`src/agent_core/dispatch.py`. The code is short; the reasoning behind it is not obvious, and every
rule in it was chosen against a specific failure.

---

## 1. The situation

The agent loop runs on a server. Some of its tools can only run on the phone:

| Why it can only run there | Tools |
|---|---|
| The data is the user's and stays on their device | `recall_memory`, `read_recent_entries`, `read_lab_results` |
| It needs an OS API that exists nowhere else | `read_health_signals` (HealthKit / Health Connect), `scan_label_text` (Vision / ML Kit), `add_calendar_event` (EventKit / CalendarContract) |
| It writes to the user's own store | `log_entry` |

So a turn is not one request. It is:

```
model thinks  →  server asks the phone  →  phone answers  →  model thinks again  →  …
```

Each of those arrows is a round trip over a mobile network. On a good LTE connection that is
roughly 150–400 ms; on a bad one, seconds. **How we schedule those trips is the difference between
a turn that feels instant and one the user abandons.**

## 2. Decision one — independent reads go together, mutations never do

### The rule

`plan()` splits the model's tool calls into waves:

- **All non-mutating calls become one parallel wave.** The client runs them concurrently and
  submits each result the instant it has it. A fast read never waits behind a slow one.
- **Each mutating call gets its own serial wave**, after the reads, in the order the model asked.

### Why reads can overlap

They have no side effects and no ordering. Asking for the user's recent entries does not change
what their lab results say. Running five reads concurrently produces exactly the same answers as
running them one after another — only sooner.

The arithmetic is the entire argument. Five sequential reads at ~400 ms each is about two seconds of
pure network transit, on top of the model calls. The same five in parallel is about 400 ms. Across a
multi-step turn that compounds into the difference between a product that feels responsive and one
that does not.

### Why mutations must not

Three separate reasons, any one of which would be sufficient:

1. **Concurrent writes interleave unpredictably.** Two writes racing on the same device store can
   land in either order, and the agent has no way to know which happened first.
2. **A partial failure leaves an unknowable state.** If three writes go out together and one fails,
   what happened? Did the other two land? Did they land before or after? There is no answer that
   can be recovered after the fact.
3. **The loop deserves a look between writes.** An agent that fires three writes at once and *then*
   discovers the first result should have stopped it has already done the damage. Serial dispatch
   means the loop sees each result before the next call goes out.

### Why reads go first

Not only speed. A mutation informed by fresh reads is better than one informed by stale ones — so
the ordering that is faster is also the ordering that is more correct. That is a happy alignment,
not a coincidence worth relying on; if it ever conflicts, correctness wins.

## 3. Decision two — a timed-out read may be retried, a timed-out write may not

This is the correctness heart of the module, and it is the rule most likely to be "simplified" by
someone who has not hit the bug.

### The failure it prevents

The server tells the phone: *add this procedure to the user's calendar.* The phone does it. The
acknowledgement is lost on the way back — the user walked into a lift, the app was backgrounded,
the socket died. The server sees a timeout.

If the server retries, the user now has **two identical calendar entries** and has to delete one by
hand. That is a real bug with a real support ticket attached, and it is the single most likely way
this architecture produces a visible defect.

### The asymmetry

| The call was a… | Silence means | Terminal status | Retry? |
|---|---|---|---|
| **Read** | It did not happen — a read cannot have changed anything | `EXPIRED` | Yes, free |
| **Mutation** | It may have happened and we cannot tell | `UNKNOWN` | **Never** |

`UNKNOWN` is a real, terminal, load-bearing state. It is not an error code — it is an honest
statement that the system does not know, and it stops the turn rather than guessing. Anything that
collapses `UNKNOWN` into `FAILED` has reintroduced the duplicate-calendar-entry bug.

An idempotent mutation is exempt, because repeating it is harmless by definition — that is what
`ToolSpec.idempotent` means and why it is allowed as an alternative to a key.

### Defence in depth

There are two independent barriers, deliberately:

1. **The server declines to retry** a non-idempotent mutation whose result never came back.
2. **The device declines to repeat** an effect for an `idempotency_key` it has already performed —
   so even if a retry arrives through some path nobody anticipated, nothing happens twice.

`ToolSpec` refuses at import time to declare a mutating tool that is neither idempotent nor keyed,
so this cannot be forgotten when a new tool is added.

## 4. Why submissions are idempotent

The client submits each result as its own request keyed by `call_id`. Those requests can themselves
be retried — same lost-connection problem, one layer up.

So `StepCollector.submit()` accepts the **first** result for a call and ignores later ones, returning
`False` rather than raising. Accepting a second would let a retry overwrite a real result: imagine a
successful read whose submission is resent after a timeout and arrives as a failure. The turn would
degrade because the network hiccuped *after* the work was already done correctly.

A result for a call the step never dispatched is rejected outright. That is either a bug or a client
trying to inject a result for something it was never asked to do.

## 5. What is deliberately NOT here

- **Speculative dispatch.** Guessing which tool the model will want next and pre-running it. Fine
  for reads in principle, wasteful in practice (it costs quota and battery on a guess), and
  catastrophic if the guess is ever wrong about mutability. Revisit only with measurements.
- **Batching across steps.** Reads from wave 1 and wave 3 are not merged, because wave 2 is a
  mutation and the reads after it must see its effect.
- **Retry of `DENIED`.** A user said no. Retrying an explicit denial is how an agent nags someone
  into approving something they already refused.
- **A durable orchestrator.** There is no persistent loop yet, so there is nothing to resume.
  Restate gets evaluated when the first real mutating device tool ships — see ARCHITECTURE.md §0
  finding 4.

## 6. Platform neutrality

Nothing in `dispatch.py` mentions iOS or Android. The client-side executor differs (Swift versus
Dart, HealthKit versus Health Connect) but the protocol does not: same call ids, same statuses, same
idempotency rules, same deadlines. A second platform is a second executor, not a second protocol.

## 7. Location neutrality

Nothing in `dispatch.py` knows whether the server is a laptop on the same wifi or a container in a
datacenter. That is intentional and it is how the migration stays cheap: today the phone points at
`http://<dev-box>:8000`, later at a hosted URL, and the only thing that changes is one config value.

Testing over LAN from day one is not a shortcut — it is the only way the round-trip behaviour this
document describes gets exercised before it matters. A simulator on localhost has no latency, never
drops a connection, and would let every bug above ship undetected.

## 8. If you change something here

Ask which of these you are breaking:

- Reads may overlap; mutations may not.
- A read that timed out may be retried; a non-idempotent mutation that timed out may not, ever.
- The first result for a call wins.
- A mutating tool without an idempotency key never gets dispatched.

If the change breaks none of them, it is probably fine. If it breaks one, the tests in
`tests/test_dispatch.py` will say so — they are written as "prove the unsafe thing is blocked", and
each one names the failure it prevents.
