#!/usr/bin/env python3
"""Generate the product landing pages from affiliate-links/mappings.json.

mappings.json is the single source of truth: the backup, the owner's edit surface, and the
input to these pages are one file, so they cannot drift apart. Run after any destination
change, then commit and push — GitHub Pages redeploys in about a minute and the app is
untouched.

    python3 affiliate-links/build-pages.py            # write docs/go/
    python3 affiliate-links/build-pages.py --check    # verify only, exit 1 on a problem
    python3 affiliate-links/build-pages.py --out DIR  # write somewhere else (dry runs)

A route with no destination yet writes NO page. That is deliberate: an unfinished page on a
live site is worse than a 404 nobody can reach, and the app hides the button for any product
missing from AffiliateLinks.json, so nothing links there in the first place.
"""
from __future__ import annotations
import argparse, html, json, pathlib, sys
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAPPINGS = ROOT / "affiliate-links" / "mappings.json"
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


def render(template: str, route: dict) -> str:
    """Substitute the four fields. Everything owner-supplied is HTML-escaped: the destination
    carries affiliate query parameters with & and = in them, and an unescaped & inside an
    href is how a tracking parameter silently goes missing."""
    page = template
    for token, value in (
        ("RETAILER_URL", html.escape(route["destination"], quote=True)),
        ("RETAILER_NAME", html.escape(route.get("merchant") or "the retailer")),
        ("PRODUCT_NAME", html.escape(route["name"])),
        ("SUMMARY", html.escape(route.get("summary") or "")),
    ):
        page = page.replace(token, value)
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

    written, pending, problems, seen = [], [], [], set()
    for route in data["routes"]:
        slug = route["path"].lstrip("/")
        if slug in seen:
            problems.append(f"{slug}: duplicate path")
            continue
        seen.add(slug)

        destination = (route.get("destination") or "").strip()
        if not destination:
            pending.append(slug)
            continue
        if problem := destination_problem(destination):
            problems.append(f"{slug}: destination {problem}")
            continue
        if not route.get("merchant"):
            problems.append(f"{slug}: destination set but no merchant named")
            continue

        page = render(template, {**route, "destination": destination})
        if not args.check:
            # Directory form, so /go/<slug> resolves without depending on the host's
            # extension-stripping behaviour. GitHub Pages serves <slug>/index.html for both
            # /go/<slug> and /go/<slug>/.
            folder = out / slug
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "index.html").write_text(page, encoding="utf-8")
        written.append(slug)

    for line in (f"  wrote    {s}" for s in written):
        print(line)
    if pending:
        print(f"  pending  {len(pending)} route(s) with no destination yet: {', '.join(pending)}")
    for p in problems:
        print(f"  PROBLEM  {p}", file=sys.stderr)

    print(f"\n{len(written)} page(s), {len(pending)} pending, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
