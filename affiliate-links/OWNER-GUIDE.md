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

A page with no destination yet renders a **holding state** instead: it says plainly that there is
no buying link for that product, and shows **no** affiliate disclosure, because there is no
affiliate link on it to disclose. That is what every page looks like today. Filling one in is the
"change a destination" job below — no app build, ever.

**No Cloudflare account and no DNS change is needed.** `haircompass-ai.com` already serves this
repository's `docs/` folder through GitHub Pages, and the pages live there. Nothing here touches
the AI/agent server: the buttons work with that server switched off, offline-cached links and
all. They do depend on **DNS for haircompass-ai.com** and on **GitHub Pages**, which is why
`affiliate-links/mappings.json` is provider-independent — it is the entire mapping, so the same
paths can be rebuilt on any host from that one file.

> **Status: the app ships all 16 links and all 16 pages exist, every one in its holding state —
> "no buying link yet" — because no destination exists yet. The pages go live on the website when
> this branch's `docs/` reaches `rebuild/clinical-minimal`, which is what GitHub Pages publishes.
> Until then the URLs 404.** See "What is still waiting on you".

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
2. Set `destination` to the affiliate URL — paste it **whole**, every tracking parameter intact —
   and set `merchant` to the retailer's name (it appears on the button). A page flips from the
   holding state to the live button-and-disclosure state the moment it has both.
3. Run `python3 affiliate-links/build-pages.py`.
4. Commit and push. Pages redeploys in about a minute; the app is untouched.

The script refuses anything that would publish a broken or unsafe page: a non-HTTPS destination,
a URL carrying embedded credentials, a destination with no merchant named, a duplicate path. It
also cross-checks `Resources/AffiliateLinks.json` against the routes and fails on any
disagreement — that is the guard against a shipped button pointing at a path nobody generated. It
exits non-zero so a mistake stops a release rather than reaching the site. `--check` validates
without writing.

## Disable a link gracefully

- **Best, and instant:** clear `destination` to `null` and re-run. The page reverts to the
  holding state — honest, no dead end, no build. This is why every route always has a page.
- **Point it elsewhere:** set `destination` to somewhere honest of yours and re-run.
- **Hide the button in the app:** remove that product from
  `Hair Compass AI 5/Resources/AffiliateLinks.json`. An unresolved link hides the button by
  design, with no empty space and no error — but it needs a build, and users on the old build
  keep the button until they update. Only do this alongside the holding state above.

Never delete a generated page while the app still ships its link: that is the one combination
that gives a user a browser error.

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

## What is done and verified

- **The app ships all 16 links** — `Resources/AffiliateLinks.json` names every catalog product at
  its permanent path. Neutral button wording, resolved from the bundle with no server dependency,
  stale-cache bypass closed, with tests.
- **All 16 pages exist** under `docs/go/<slug>/index.html`, in the holding state.
- **Verified by running the generator here:** a sample Amazon destination with
  `?tag=…&linkCode=…&ref_=…` renders to a page whose href, once a browser unescapes it, is
  byte-for-byte the URL that went in; the live and holding states never leak into each other; no
  holding page carries an affiliate disclosure; a non-HTTPS destination, a destination with no
  merchant, a wrong slug and an unknown product are each caught with a non-zero exit.

## What is NOT verified

- **No URL has been fetched.** GitHub Pages publishes `docs/` from `rebuild/clinical-minimal`, and
  these pages are on `claude/mosaowi-comments-review-5dmvsq`. **Every one of these links 404s
  until that `docs/` change reaches the Pages branch** — merge before shipping a build that
  carries them. This environment also cannot reach the domain, so nothing was fetched from here
  either way.
- **Nothing has been compiled** — no Mac in this environment, so the unit suite has not run on
  `HC-Automation`.

## What is still waiting on you

**The approved affiliate links** — one per product, with the programme each comes from. None
exist in this repository, so all 16 pages sit in the holding state and no commission is earned by
anything here. No affiliate id has been invented, and an ordinary product URL earns nothing.

Send them and it is a text edit: paste into `mappings.json`, run the script, push. The app never
changes again.
