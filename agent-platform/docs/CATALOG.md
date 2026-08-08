# Affiliate catalogue — server-controlled, device-cached

**Status: specified, not built.** Queued behind the security work in `docs/READINESS.md`.

The commercial surface: brand partnerships shown in-app as a picture and a tap that opens an
affiliate link. The server owns the list; devices cache it and keep working offline until the next
refresh. Adding a brand must be a data change — no code, no App Store release.

## Why this is not Firebase Remote Config

The obvious off-the-shelf answer, rejected on three grounds and worth recording so it is not
revisited by accident:

* It is a **third-party SDK**, which the app's own rule forbids — Hair Compass is Apple frameworks
  only, no SPM, no CocoaPods.
* It **sends user data to Google**, which reopens App Privacy labels and the PDPL cross-border
  consent question that the current architecture has already answered.
* It solves a problem we already own the solution to. There is a server here with authentication,
  an audit log, a versioned protocol and a plan catalogue. This is one endpoint and a cached JSON
  file.

CloudKit's public database is the credible Apple-native alternative — no SDK, free, caches for
you. It earns its place only if editing the catalogue from a Mac app beats editing a config file.
Given the server exists, it is a second system for no gain.

**Where a kit does belong: the affiliate network.** Amazon Associates, Impact, ShareASale, Rakuten
generate tracked links and handle commission attribution. We never integrate their SDK — we paste
the URL they issue into the catalogue. That is the part not to build.

## Decisions taken

| Decision | Choice | Consequence |
|---|---|---|
| Image hosting | **Our server** | Brands never see a user's IP; a brand CDN outage cannot blank the screen. We resize on upload and serve bytes. |
| Click data | **Aggregate counts only** | Per-product totals, never per-person. No new consent purpose, nothing added to App Privacy, no deletion obligation. |
| Evidence tier | **Not shown** | See the objection below. Implemented as a flag so it is reversible without a release. |

### The evidence-tier objection, recorded

`CLAUDE.md` states the product's stance: *"where money is involved (affiliate products) the
evidence rating is shown and never bent. Preserve this framing in every prompt, label, and copy
string."* Hiding the tier contradicts that invariant directly.

The concrete risk is not abstract disapproval. Unlabelled products rendered next to tier-badged
Learn and Science content read as endorsed by the same evidence system — which is the
"myth asserted as fact" failure the safety layer exists to prevent, occurring on the one surface
the safety layer does not screen. It is also a plausible App Review question for a health app
carrying commerce.

The decision is the product owner's and is implemented as asked. It is a **catalogue-level flag**
(`show_evidence_tier`), not a hardcoded omission, so reversing it is one config change. A middle
position exists if wanted: show the tier when it is decent, show "not rated" otherwise — honest
without a scarlet letter.

## Shape

### Server

A product is DATA, in a pack, exactly like plans and locales:

```python
class AffiliateProduct(BaseModel):
    id: str
    brand: str
    title: str
    #: Path served by us, not a brand URL — see the image decision above.
    image: str
    #: The affiliate network's tracked link, pasted verbatim.
    link: str
    #: Recorded even when not displayed. The decision to hide it must not also destroy it.
    evidence_tier: str = ""
    active: bool = True
    #: Optional. Lets a product be shown only to certain locales/markets.
    locales: frozenset[str] = frozenset()
```

`GET /v1/catalog` returns `{version, show_evidence_tier, products: [...]}`.

**Versioned, not timestamped.** The client sends the version it holds; an unchanged catalogue
returns `304` and costs one round trip with no body. A timestamp invites clock-skew bugs for no
benefit.

**Not gated by plan.** Affiliate revenue does not work behind a paywall, and a lapsed user is
still someone who buys shampoo.

`POST /v1/catalog/{id}/tap` increments an aggregate counter. **No principal id is recorded** — that
is what makes it a count rather than behavioural data, and it is the whole reason no consent
purpose is needed. Rate-limited like everything else.

### Device

Reuses what already exists rather than inventing a surface: `ScienceProduct`, `TierBadge` and
`ProductBadge` are already in `Design/Clinical.swift` and `Model/ScienceProduct.swift`, and
`AffiliateStore` already keeps per-product links in `UserDefaults`.

* `CatalogStore` — fetches on launch and on foreground, writes JSON plus images to `Documents/`,
  and **always renders from the cache**. The network is a refresh, never a dependency.
* A tap calls `openURL` and posts the aggregate tap. A failed post is dropped, not retried — a
  commission is attributed by the affiliate network's own link, so our counter is analytics, and
  analytics must never delay a user's tap.
* Ships with a bundled seed catalogue so the very first launch, offline, is not an empty screen.

### Disclosure — not optional

The surface must state that these are affiliate links and that we may earn a commission. Required
by the FTC and the ASA among others, independent of the tier decision above. One persistent line
on the surface, not buried in Settings.

## Open

* Image pipeline: upload, resize, serve, cache headers. Smallest thing that works is a directory
  and `StaticFiles`.
* Whether a brand can target a locale/market — the field is specified, the UI is not.
