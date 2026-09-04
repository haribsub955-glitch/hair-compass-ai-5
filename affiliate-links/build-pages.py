#!/usr/bin/env python3
"""Generate the product landing pages from affiliate-links/mappings.json.

mappings.json is the single source of truth: the backup, the owner's edit surface, and the
input to these pages are one file, so they cannot drift apart. Run after any destination
change, then commit and push — GitHub Pages redeploys in about a minute and the app is
untouched.

    python3 affiliate-links/build-pages.py            # write docs/go/
    python3 affiliate-links/build-pages.py --check    # verify only, exit 1 on a problem
    python3 affiliate-links/build-pages.py --out DIR  # write somewhere else (dry runs)

Every route writes a page, so no path the app ships can 404. A route with a destination gets
the retailer button and the affiliate disclosure; a route without one gets the holding state,
which says plainly that there is no buying link yet and carries NO affiliate disclosure --
there is no affiliate link on it to disclose.
"""
from __future__ import annotations
import argparse, html, json, pathlib, sys
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAPPINGS = ROOT / "affiliate-links" / "mappings.json"
BUNDLED = ROOT / "Hair Compass AI 5" / "Resources" / "AffiliateLinks.json"
TEMPLATE = ROOT / "affiliate-links" / "product-page-template.html"


def destination_problem(url: str) -> str | None:
    """Reject anything that must never reach a published page."""
    parts = urlsplit(url)
    if parts.scheme != "https":
        return "not https"
    if not parts.hostname:
        return "no host"
    if parts.username or parts.password:
        return "embedded credentials"
    return None


def keep_block(template: str, keep: str) -> str:
    """The template carries both states between BLOCK markers; keep one, drop the other."""
    drop = "holding" if keep == "live" else "live"
    out, dropping = [], False
    for line in template.splitlines(keepends=True):
        marker = line.strip()
        if marker == f"<!-- BLOCK:{drop} -->":
            dropping = True
            continue
        if marker == f"<!-- /BLOCK:{drop} -->":
            dropping = False
            continue
        if marker in (f"<!-- BLOCK:{keep} -->", f"<!-- /BLOCK:{keep} -->"):
            continue
        if not dropping:
            out.append(line)
    return "".join(out)


def render(template: str, route: dict, live: bool) -> str:
    """Substitute the fields. Everything owner-supplied is HTML-escaped: a destination carries
    affiliate query parameters with & and = in them, and an unescaped & inside an href is how a
    tracking parameter silently goes missing."""
    page = keep_block(template, "live" if live else "holding")
    fields = [("PRODUCT_NAME", route["name"]), ("SUMMARY", route.get("summary") or "")]
    if live:
        fields += [("RETAILER_NAME", route.get("merchant") or "the retailer")]
    for token, value in fields:
        page = page.replace(token, html.escape(value))
    if live:
        # Last, and quote-escaped, so an escaped destination cannot be re-escaped by a later pass.
        page = page.replace("RETAILER_URL", html.escape(route["destination"], quote=True))
    return page


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate without writing")
    ap.add_argument("--mappings", default=str(MAPPINGS))
    ap.add_argument("--out", default=str(ROOT / "docs" / "go"))
    args = ap.parse_args()

    data = json.loads(pathlib.Path(args.mappings).read_text(encoding="utf-8"))
    template = TEMPLATE.read_text(encoding="utf-8")
    out = pathlib.Path(args.out)

    written, holding, problems, seen = [], [], [], set()
    for route in data["routes"]:
        slug = route["path"].lstrip("/")
        if slug in seen:
            problems.append(f"{slug}: duplicate path")
            continue
        seen.add(slug)

        destination = (route.get("destination") or "").strip()
        live = bool(destination)
        if live:
            if problem := destination_problem(destination):
                problems.append(f"{slug}: destination {problem}")
                continue
            if not route.get("merchant"):
                problems.append(f"{slug}: destination set but no merchant named")
                continue

        page = render(template, {**route, "destination": destination}, live=live)
        (written if live else holding).append(slug)
        if not args.check:
            # Directory form, so /go/<slug> resolves without depending on the host's
            # extension-stripping behaviour. GitHub Pages serves <slug>/index.html for both
            # /go/<slug> and /go/<slug>/.
            folder = out / slug
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "index.html").write_text(page, encoding="utf-8")

    # Drift guard. The app ships one URL per product and this script publishes the page behind
    # it; if the two files disagree, some button in a shipped build points at a path that was
    # never generated. Nothing else would catch that until a user tapped it.
    if BUNDLED.exists():
        shipped = json.loads(BUNDLED.read_text(encoding="utf-8")).get("links", {})
        expected = {r["productID"]: r["appURL"] for r in data["routes"]}
        for pid, url in sorted(shipped.items()):
            if pid not in expected:
                problems.append(f"{pid}: shipped in AffiliateLinks.json but not in mappings.json")
            elif url != expected[pid]:
                problems.append(f"{pid}: app ships {url}, mappings.json says {expected[pid]}")
        for pid in sorted(set(expected) - set(shipped)):
            print(f"  note     {pid} has a page but no link in AffiliateLinks.json (button hidden)")

    for slug in written:
        print(f"  live     {slug}")
    if holding:
        print(f"  holding  {len(holding)} route(s) with no destination yet: {', '.join(holding)}")
    for p in problems:
        print(f"  PROBLEM  {p}", file=sys.stderr)

    print(f"\n{len(written)} live, {len(holding)} holding, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
