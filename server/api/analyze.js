// Node serverless function (Vercel-style) — subscription-gated proxy for Hair Compass's cloud AI.
//
// The Anthropic API key lives ONLY here (env var), never in the app. Each request carries the
// StoreKit 2 entitlement JWS in `X-Subscription`. We verify it with Apple's OFFICIAL App Store
// Server Library — full signature + x5c certificate-chain validation against Apple's root CA, not
// just a claims check — then confirm it's a live Pro subscription and forward to Anthropic.
//
// Deploy: see ../README.md.

import { SignedDataVerifier, Environment } from "@apple/app-store-server-library";

const BUNDLE_ID = "harib.Hair-Compass-AI-5";
const PRO_PRODUCT_IDS = [
  "com.harib.haircompass.pro.monthly",
  "com.harib.haircompass.pro.yearly",
];
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";

// Apple's StoreKit transaction certs chain to "Apple Root CA - G3". Fetched once per cold start.
const APPLE_ROOT_URLS = ["https://www.apple.com/certificateauthority/AppleRootCA-G3.cer"];

let verifiersPromise;

async function loadAppleRoots() {
  return Promise.all(
    APPLE_ROOT_URLS.map(async (url) => Buffer.from(await (await fetch(url)).arrayBuffer()))
  );
}

// One verifier per environment. Production needs the numeric App Store app id (APP_APPLE_ID, set
// after you create the app record); sandbox (TestFlight / App Review) works without it. `true`
// enables online (OCSP) certificate-revocation checks for full verification.
async function buildVerifiers() {
  const roots = await loadAppleRoots();
  const appAppleId = Number(process.env.APP_APPLE_ID) || undefined;
  const list = [];
  if (appAppleId) {
    list.push(new SignedDataVerifier(roots, true, Environment.PRODUCTION, BUNDLE_ID, appAppleId));
  }
  list.push(new SignedDataVerifier(roots, true, Environment.SANDBOX, BUNDLE_ID, appAppleId));
  return list;
}

function getVerifiers() {
  if (!verifiersPromise) verifiersPromise = buildVerifiers();
  return verifiersPromise;
}

// Try production first, then sandbox — Apple's recommended order, so one deploy serves both.
async function verifyTransaction(jws) {
  const verifiers = await getVerifiers();
  let lastError;
  for (const verifier of verifiers) {
    try {
      return await verifier.verifyAndDecodeTransaction(jws);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? new Error("No verifier available.");
}

function fail(res, message) {
  return res.status(402).json({ error: { message } });
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: { message: "POST only." } });
  }

  const jws = req.headers["x-subscription"];
  if (!jws) return fail(res, "No subscription token.");

  // 1) Cryptographically verify the StoreKit transaction (signature + Apple cert chain).
  let transaction;
  try {
    transaction = await verifyTransaction(jws);
  } catch {
    return fail(res, "Subscription couldn't be verified.");
  }

  // 2) Confirm it's a live Pro subscription for THIS app.
  if (transaction.bundleId !== BUNDLE_ID) return fail(res, "Token is for a different app.");
  if (!PRO_PRODUCT_IDS.includes(transaction.productId)) return fail(res, "Not a Pro product.");
  if (transaction.revocationDate) return fail(res, "Subscription was revoked.");
  if (transaction.expiresDate && Number(transaction.expiresDate) < Date.now()) {
    return fail(res, "Subscription has expired.");
  }

  // 3) Forward the (unchanged) Claude Messages body upstream with the server-held key.
  const body = typeof req.body === "string" ? req.body : JSON.stringify(req.body);
  const upstream = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": process.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "anthropic-beta": "server-side-fallback-2026-06-01",
    },
    body,
  });

  res.status(upstream.status);
  res.setHeader("content-type", "application/json");
  return res.send(await upstream.text());
}
