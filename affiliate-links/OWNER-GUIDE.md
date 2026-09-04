# Product links — owner guide

The app's buy buttons point at **`https://haircompass-ai.com/go/<product>`**, one fixed path per
product. Those URLs are compiled into the app and never change. Where each one *sends people* is
a line in a file you edit, so changing a destination is a two-minute job — not a new build, not
an App Store review.

Each path is a real page on your existing website: the product name, the app's own honest
one-line summary, an affiliate disclosure, and one button to the retailer. That shape is
deliberate. Several affiliate programmes — Amazon's is the strict one — exclude commission on
referrals that arrive through a site which redirects automatically, so the visitor presses the
button themselves.

**No Cloudflare account and no DNS change is needed.** `haircompass-ai.com` already serves this
repository's `docs/` folder through GitHub Pages, and the pages live there. Nothing here touches
the AI/agent server: the buttons work with that server switched off, offline-cached links and
all. They do depend on **DNS for haircompass-ai.com** and on **GitHub Pages**, which is why
`affiliate-links/mappings.json` is provider-independent — it is the entire mapping, so the same
paths can be rebuilt on any host from that one file.

> **Status: not published.** No page exists yet, because no destination exists yet. See "What is
> still waiting on you".

---

## Where to log in

| What | Where |
| --- | --- |
| Destinations | this repository → `affiliate-links/mappings.json` |
| The published pages | this repository → `docs/go/<slug>/index.html` — **generated, never hand-edited** |
| Hosting | GitHub → repository **Settings → Pages** (source: `docs/` on `rebuild/clinical-minimal`) |
| The domain | wherever `haircompass-ai.com` DNS is managed — unchanged by any of this |

## Change a destination

1. Open `affiliate-links/mappings.json`, find the route by `productID` or `path`.
2. Set `destination` to the new affiliate URL — paste it **whole**, every tracking parameter
   intact — and set `merchant` to the retailer's name (it appears on the button).
3. Run `python3 affiliate-links/build-pages.py`.
4. Commit and push. Pages redeploys in about a minute; the app is untouched.

The script refuses anything that would publish a broken or unsafe page: a non-HTTPS destination,
a URL carrying embedded credentials, a destination with no merchant named, a duplicate path. It
exits non-zero so a mistake stops a release rather than reaching the site. `--check` validates
without writing.

## Disable a link gracefully

- **Best:** point `destination` at somewhere honest of yours — the support page, say — and
  re-run. The button still works and lands somewhere real.
- **Take the page down:** clear `destination` to `null`, re-run, and delete
  `docs/go/<slug>/index.html`. The path 404s, so also remove that product from
  `Hair Compass AI 5/Resources/AffiliateLinks.json` in the next build, which hides the button
  cleanly. Until that build ships, users on the old build get a browser error — prefer the first
  option.

Removing a product from `AffiliateLinks.json` is the only graceful way to hide a button, and it
needs a build. Redirecting the page needs no build. That asymmetry is why the page always exists.

## Restore a previous mapping

Every change is a line in one tracked file:

```
git log -p -- affiliate-links/mappings.json     # every destination this link has ever had
```

Copy the old `destination` back, re-run the script, push. `mappings.json` is the record of truth
and the backup at once, which is what keeps them from drifting apart.

---

## How it is built (for whoever rebuilds it)

- **`affiliate-links/mappings.json`** — the source of truth: 16 routes, one per catalog product,
  each with its stable path, the URL the app ships, the product name and summary, the merchant
  and the destination.
- **`affiliate-links/build-pages.py`** — renders `docs/go/<slug>/index.html` from
  `product-page-template.html`. Directory form, so `/go/<slug>` resolves without depending on the
  host stripping `.html`. Destinations are HTML-escaped: an unescaped `&` inside an `href` is how
  an affiliate parameter silently goes missing. A route with no destination writes **no** page —
  an unfinished page on a live site is worse than a path nobody can reach.
- **In the app** — `Service/AffiliateStore.swift` resolves each product's link from the bundled
  `Resources/AffiliateLinks.json`. No network call, no catalogue fetch, no AI session. The
  remote-catalogue path stays off (`RemoteConfig.catalogURLString` empty), and a payload cached by
  an earlier build is purged at launch instead of being allowed to outrank these links.
- **Optional later:** `routes.optional-cloudflare.csv` is the same 16 paths as a Cloudflare Bulk
  Redirects import (302, preserve-query-string off), if you ever want dashboard-speed edits for
  merchants whose rules permit automatic forwarding. It needs the domain on a Cloudflare zone, and
  an edge redirect would take precedence over the Pages page at that path. Amazon products must
  keep the page either way.

## Never put in the app or an outgoing URL

Cloudflare tokens, GitHub tokens, dashboard credentials, or anything about a person's health.
The app's outgoing URL carries the product path and nothing else — no user id, no record data.

---

## What is deployed and verified

- **The app side, in the repository:** neutral button wording, links resolved from the bundle with
  no server dependency, and the stale-cache bypass closed, with tests. Not compiled — see below.
- **The generator, verified end to end here:** a sample Amazon destination with
  `?tag=…&linkCode=…&ref_=…` renders to a page whose href, once a browser unescapes it, is
  byte-for-byte the URL that went in; a non-HTTPS destination and a destination with no merchant
  are both rejected with a non-zero exit; routes without a destination write nothing.
- **Not verified:** no page is published, so no HTTPS route has been fetched. Nothing has been
  compiled — this environment has no Mac, so the unit suite has not run on `HC-Automation`.

## What is still waiting on you

**The approved affiliate links.** One per product, each with the programme it comes from. None
exist anywhere in this repository — `AffiliateLinks.json` ships empty and the catalog carries only
search terms — so there is nothing to point a page at. No affiliate id has been invented, and an
ordinary product URL earns no commission.

Send them and the rest is mechanical: paste them into `mappings.json`, run the script, push,
check each route over HTTPS, copy `affiliate-links/AffiliateLinks.pending.json` into
`Hair Compass AI 5/Resources/AffiliateLinks.json`, and build.
