# Temporary iHerb navigation test — 10 September 2026

At Harib's request, `/go/rosemary` automatically opens `https://www.iherb.com/`.
This tests remote control of an existing app URL. It is an ordinary homepage link,
not an affiliate link or a recommendation of a particular rosemary product.

The route's `testIHerbRedirect: true` flag is the canonical switch. The generator
only redirects to the fixed iHerb homepage in this mode, and rejects combining it
with a retailer destination. All other routes retain their existing behavior.

To stop the test, remove the flag or set it to false, run
`python3 affiliate-links/build-pages.py --check` and then
`python3 affiliate-links/build-pages.py`, and publish the mapping plus generated
pages to `rebuild/clinical-minimal`. With a null destination, Rosemary returns to
its holding page. Remove this test mode before activating an approved affiliate
destination; the normal retailer-button/disclosure page remains the production
affiliate flow.
