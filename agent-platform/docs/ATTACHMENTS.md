# Attachments — photos into the agent turn

**Status: specified. Contract and consent land first; transport and screening follow.**

The ask: a user attaches a photo of their hair or scalp to a question and the agent sees it. Today
`TurnRequest` carries text and nothing else, so a picker wired to the agent would silently drop the
file. `Capability.IMAGE_INPUT` is *declared* by the Anthropic adapter — declared is not wired, which
is the defect this project keeps paying for.

## Two-step, not inline

`POST /v1/attachments` returns an id; the turn references it.

Base64 in the turn body was the smaller change and it is the wrong one. A 5 MB photo becomes ~6.7 MB
of JSON in a single POST, on a phone, on cellular — and if the turn then fails on consent, on quota,
or on a dropped connection, the user uploads it all again. Splitting them means the photo goes up
while they are still typing, an oversized or wrong-typed file is refused **before any model spend**,
and a retried turn re-sends an id rather than the bytes.

```jsonc
POST /v1/attachments          // multipart/form-data
  X-Access-Key, session_token, file

{ "attachment_id": "att_…", "sha256": "…", "bytes": 812345, "media_type": "image/jpeg" }
```

```jsonc
POST /v1/turn
{ "session_token": "…", "user_text": "is this thinning at the crown?",
  "attachments": ["att_…"] }        // ids only, never bytes
```

## The bytes are transient, and that is the privacy position

A scalp photo is health data and biometric-adjacent. The strongest defensible stance is that the
server never becomes a photo library:

* **Deleted as soon as the turn that used them completes**, success or failure.
* **TTL sweep** for anything orphaned — uploaded and never used, or used by a turn that died.
  Same shape as `reclaim_orphans` in the ledger, and it must actually be *called*, which that one
  was not for a while.
* Never in a backup that outlives them, never in the audit log (metadata only: id, size, type).

The phone already keeps the photo permanently in `PhotoStore`. The server copy is an *input*, not a
record. Nothing accumulates, so nothing leaks later and erasure has almost nothing to reach.

## Consent is its own purpose

`agent-analysis` does not cover this. Sending a photograph of someone's scalp to a provider outside
Oman is a materially different act from sending derived numbers, and PDPL treats the transfer as
separately consentable in any case.

```python
Purpose(
    id="photo-analysis",
    description="Send a photo you choose to the analysis service so it can comment on it.",
    necessary=False,          # the product works fully without it
    crosses_border=True,
    min_plan="taster",
)
```

`/v1/attachments` refuses without a live grant, and refuses *again* at turn time — the upload and
the use are separate moments and consent can be withdrawn between them.

## Limits, and why each one

| Limit | Value | Reason |
|---|---|---|
| Max size | 8 MB | Above a phone photo, below a denial-of-wallet. Checked from `Content-Length` *and* while streaming — a lying header is the oldest trick. |
| Media types | `image/jpeg`, `image/png`, `image/heic`, `image/webp` | Allowlist, never a blocklist. |
| Sniffed, not trusted | magic bytes must match the declared type | A `.jpg` that is actually an HTML file is how a stored-XSS lands in whatever renders it later. |
| Per turn | 3 | A hair question needs one or two. More is someone using the turn as an upload channel. |
| Per plan | counted against the token budget | An image costs real tokens; a free-looking attachment is a hole in the budget the ledger otherwise closes. |

**No PDF.** Lab documents are already handled better: Vision OCR runs on-device and only the
extracted values travel, which is both cheaper and materially safer than shipping the document
across a border. Adding PDF here would duplicate that path worse. If a PDF genuinely needs a model,
OCR it on-device and send the text.

## Safety

The output screen already catches a diagnosis claim regardless of what prompted it, and that does
not change.

What is new is **injection through the image**: text inside a picture is text the model reads, and
"ignore your instructions" written on a card photographs perfectly well. The stance is the one
already taken for user text — an attachment is *data in a typed slot, never an instruction* — and
the system prompt says so explicitly. The existing output screen is the backstop, because it does
not care why the model said something.

Also worth stating: the agent must not be able to *fetch* an attachment by id it was not given.
Attachments resolve only through the turn that references them, scoped to the principal that
uploaded them.

## Client

`AgentClient.upload(_ data: Data, type: String) async throws -> String`, then pass ids to
`runTurn`. `PhotosPicker` for the picker; the photo is already on disk in `PhotoStore` for the
progress-photo case, so the common path is "attach an existing progress photo" rather than a fresh
capture.

Show the consent prompt **before** the picker, not after — asking for a photo and then asking
permission to send it is the wrong order and reads as a bait.

## Order of work

1. ~~Contract + consent purpose~~ **done**
2. `attachments` table, upload endpoint, sniffing and limits
3. ~~Adapter plumbing — image blocks on the wire~~ **done, and verified against a real model**
4. Reaper for orphans, and a test that it is actually called
5. Client: upload, picker, consent-first ordering

### On step 3, verified rather than assumed

`Message.images` carries `(media_type, base64)` and the OpenAI-compatible adapter renders a text
block followed by one `image_url` per image as a `data:` URI.

Driven against LM Studio with `gemma-4-e4b-it-qat` (type `vlm`): a synthetic image — red square
left, blue circle right — came back correctly described. **A synthetic image with a known answer,
deliberately, and not a hair photo:** a correct answer proves the model *saw* it, where plausible
hair prose can be produced from the text prompt alone. That distinction is the entire value of the
test.

One thing the run surfaced that is not a transport problem: the local model emitted its reasoning
scratchpad into the answer and ran to the token cap. Small local models do this; the pack's system
prompt needs a "do not think aloud" instruction on the local path, and the output safety screen sees
whatever it produces either way.
