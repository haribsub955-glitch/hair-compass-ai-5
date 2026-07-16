// Cloudflare Worker — subscription-gated proxy for Hair Compass's cloud AI (Anthropic Claude).
//
// WHY: the Anthropic API key must never ship inside the iOS app (it would be extracted and abused).
// It lives ONLY here as a Wrangler secret. Every request from the app carries the StoreKit 2
// entitlement JWS in the `X-Subscription` header; we verify the person has Pro before spending,
// then forward the request to Anthropic with the server-held key.
//
// Deploy: see README.md.

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const BUNDLE_ID = "harib.Hair-Compass-AI-5";
const PRO_PRODUCT_IDS = [
  "com.harib.haircompass.pro.monthly",
  "com.harib.haircompass.pro.yearly",
];

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: { message: "POST only." } }, 405);
    }

    // 1) Gate on the App Store subscription.
    const verdict = verifySubscription(request.headers.get("X-Subscription"));
    if (!verdict.ok) {
      return json({ error: { message: verdict.reason } }, 402);
    }

    // 2) Forward the (unchanged) Claude Messages body upstream with the server-held key.
    const upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "anthropic-beta": "server-side-fallback-2026-06-01",
      },
      body: await request.text(),
    });

    // 3) Pass Anthropic's response straight back to the app.
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  },
};

// Claims-level verification of the StoreKit 2 transaction JWS: right app, a Pro product, not
// revoked, not expired.
//
// NOTE: this decodes and checks the payload but does NOT cryptographically verify Apple's
// signature. For production, add x5c certificate-chain verification against Apple's root CA (or use
// Apple's App Store Server Library) so a forged token can't pass. This claims check stops casual
// abuse; harden it before you scale. See README.md → "Hardening".
function verifySubscription(jws) {
  if (!jws) return { ok: false, reason: "No subscription token." };
  const parts = jws.split(".");
  if (parts.length !== 3) return { ok: false, reason: "Malformed subscription token." };

  let payload;
  try {
    payload = JSON.parse(base64UrlDecode(parts[1]));
  } catch {
    return { ok: false, reason: "Unreadable subscription token." };
  }

  if (payload.bundleId && payload.bundleId !== BUNDLE_ID) {
    return { ok: false, reason: "Token is for a different app." };
  }
  if (!PRO_PRODUCT_IDS.includes(payload.productId)) {
    return { ok: false, reason: "Not a Pro product." };
  }
  if (payload.revocationDate) {
    return { ok: false, reason: "Subscription was revoked." };
  }
  // StoreKit dates are epoch milliseconds. A missing expiresDate (non-renewing) is allowed.
  if (payload.expiresDate && Number(payload.expiresDate) < Date.now()) {
    return { ok: false, reason: "Subscription has expired." };
  }
  return { ok: true };
}

function base64UrlDecode(segment) {
  const b64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  return decodeURIComponent(escape(atob(b64)));
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}
