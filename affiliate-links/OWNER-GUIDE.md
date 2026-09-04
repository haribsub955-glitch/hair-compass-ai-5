# Product links — owner guide

The app's buy buttons point at **`https://go.haircompass-ai.com/<path>`**, one fixed path per
product. Those URLs are compiled into the app and never change. Where each one *sends people* is
a setting you edit in a dashboard, so changing a destination is a two-minute edit, not a new
build and not an App Store review.

Nothing here touches the AI/agent server. The buttons keep working with that server switched off.
They do depend on two things: **DNS for haircompass-ai.com** and **the redirect provider**
(Cloudflare below). If either is down or the domain lapses, the buttons stop working — which is
why `affiliate-links/mappings.json` exists: it is the whole mapping, provider-independent, so the
same hostname and paths can be rebuilt somewhere else without touching the app.

> **Status: not deployed.** No route below is live yet — see "What is still waiting on you" at
> the end. Everything in this guide is written for the moment the routes exist.

---

## Where to log in

| What | Where |
| --- | --- |
| Redirects (destinations) | Cloudflare dashboard → your account → **haircompass-ai.com** → **Bulk Redirects** |
| DNS for the `go` hostname | same zone → **DNS** → the `go` record |
| Interstitial pages (Amazon) | this repository → `docs/go/<slug>.html` → commit and push |

## Change a destination

**Redirect products** (merchants whose programme permits automatic forwarding):

1. Cloudflare → Bulk Redirects → open the `hair-compass-products` list.
2. Find the row whose **source** is the app path, e.g. `https://go.haircompass-ai.com/rosemary`.
3. Edit **target** to the new affiliate URL — paste it whole, tracking parameters and all.
4. Keep **status 302** and leave **Preserve query string OFF**. On 302 nothing caches the old
   destination for long, and preserve-query-string would append the incoming query to the
   destination, which can collide with the affiliate parameters already in it.
5. Save. Live within seconds. Then update `affiliate-links/mappings.json` and push, so the
   backup still matches reality.

**Interstitial products** (Amazon, and anything else whose rules forbid automatic forwarding):
edit `RETAILER_URL` in `docs/go/<slug>.html`, commit, push. GitHub Pages redeploys in about a
minute. The app URL does not change.

## Disable a link gracefully

Do **not** delete the route — a dead path gives the user a browser error inside your app.

- Point the target at the product's page on your own site (or the support page) until you have a
  new merchant. The button still works and lands somewhere honest.
- To remove the button from the app entirely, delete that product's entry from
  `Hair Compass AI 5/Resources/AffiliateLinks.json` — an unresolved link hides the button by
  design, with no empty space and no error. That one *does* need a build.

Prefer the first. It is instant and needs no release.

## Restore a previous mapping

Every destination change is a row edit, so the restore path is the backup file:

1. `git log -- affiliate-links/mappings.json` → find the revision you want.
2. `git show <sha>:affiliate-links/mappings.json` → read the old destination.
3. Paste it back into the Bulk Redirects row (or the interstitial page) and save.

Keeping `mappings.json` current is what makes this work — treat it as the record of truth and
push it whenever you change a destination.

---

## How it was set up (for whoever rebuilds it)

- **Hostname:** `go.haircompass-ai.com`, a separate hostname from the website so the marketing
  site and these redirects can never break each other. It needs a proxied (orange-cloud) DNS
  record on the Cloudflare zone — Bulk Redirects only run on proxied traffic.
- **Paths:** `affiliate-links/routes.template.csv` holds all 16, one per catalog product, in the
  Bulk Redirects CSV shape. Fill the empty `target` column and upload it. The importer is strict
  about its column set, so compare against the template the dashboard offers on the day and
  adjust the header if Cloudflare has changed it — the rows themselves are what matter.
- **Status code 302 (temporary), not 301.** A 301 is cached indefinitely by browsers and
  intermediaries; a destination you intend to change must never be announced as permanent.
- **Amazon:** their published commission rules exclude referrals that arrive through an
  automatically redirecting intermediate site. For any Amazon product the route targets
  `https://haircompass-ai.com/go/<slug>.html` — a real page with the affiliate disclosure and an
  explicit retailer button the visitor presses. Template:
  `affiliate-links/product-page-template.html`. Check the current programme terms before you
  configure any merchant this way; they change.
- **In the app:** `Service/AffiliateStore.swift` resolves a product's link from the bundled
  `Resources/AffiliateLinks.json`. No network call, no catalogue fetch, no AI session — the
  remote-catalogue path stays switched off (`RemoteConfig.catalogURLString` empty), and a payload
  cached by an earlier build is now purged at launch rather than being allowed to outrank the
  managed links.

## Never put in the app or an outgoing URL

Cloudflare tokens, dashboard credentials, or anything about a person's health. The outgoing URL
carries the product path and nothing else — no user id, no record data.

---

## What is deployed and verified

Nothing yet, on the link side. What is done and in the repository:

- The app-side model: neutral button wording, links resolved from the bundle with no server
  dependency, and the stale-cache bypass closed, with tests.
- The complete path scheme, the Cloudflare import template, the portable backup, and the
  interstitial page template.

## What is still waiting on you

1. **Cloudflare access, and confirmation that `haircompass-ai.com` is on a Cloudflare zone you
   own.** It could not be checked from here: this session has no Cloudflare credentials and its
   network cannot reach the domain, so the account, the zone and the nameservers are unverified.
2. **The approved affiliate links themselves**, one per product, plus which programme each comes
   from. None exist anywhere in this repository — `AffiliateLinks.json` ships empty and the
   catalogue carries only search terms. No affiliate id has been invented, and an ordinary
   product URL earns nothing, so the routes cannot be filled in until you supply real ones.

With those two, the remaining work is: create the `go` record, import the CSV, verify every
route over HTTPS, publish the interstitial pages for any Amazon products, paste
`affiliate-links/AffiliateLinks.pending.json` into `Hair Compass AI 5/Resources/AffiliateLinks.json`,
and build.
