# Hair Compass AI proxy

A tiny Cloudflare Worker that lets the app use the cloud AI **without ever shipping the Anthropic
API key**. The key lives only here as a secret; the app calls this Worker, which verifies the user's
App Store subscription and forwards the request to Anthropic.

This is the server side of the hybrid AI:
- **On-device (free, private):** the app uses Apple's FoundationModels for the *text* chat when the
  device supports Apple Intelligence — it never touches this proxy.
- **Cloud (this proxy):** photo/deep analysis, and chat on devices without on-device AI.

## Deploy (≈5 minutes, free tier)

1. Install Wrangler and log in:
   ```bash
   npm install -g wrangler
   wrangler login
   ```
2. From this `server/` folder, set the Anthropic key as a secret (never committed):
   ```bash
   wrangler secret put ANTHROPIC_API_KEY
   # paste your Anthropic key when prompted
   ```
3. Deploy:
   ```bash
   wrangler deploy
   ```
   Wrangler prints a URL like `https://hair-compass-ai-proxy.<your-subdomain>.workers.dev`.
4. Point the app at it — set this in `Hair Compass AI 5/Service/CloudAnalysisService.swift`:
   ```swift
   enum AIConfig {
       static let proxyURLString = "https://hair-compass-ai-proxy.<your-subdomain>.workers.dev"
       ...
   }
   ```
   When `proxyURLString` is non-empty the app carries **no key** and every cloud call goes through
   the Worker with the StoreKit entitlement attached. (Leave it empty for local dev, which uses a
   launch-provided `ANTHROPIC_API_KEY` env var.)

## How the gate works

Each request from the app sends the StoreKit 2 entitlement JWS in `X-Subscription`. The Worker
checks it's this app's bundle id, a Pro product, not revoked, and not expired — then forwards to
Anthropic. No subscription → `402`, and the app shows "this is a Pro feature".

## Hardening (do before scaling)

`verifySubscription` currently checks the JWS **claims** but does not cryptographically verify
Apple's signature, so a determined attacker could forge a token. Before you have real volume, add
**x5c certificate-chain verification** against Apple's root CA (`AppleRootCA-G3`), or use Apple's
[App Store Server Library](https://github.com/apple/app-store-server-library-node). Also consider:
- a **rate limit** per subscription (Workers KV or Durable Objects),
- a **monthly spend cap** on the Anthropic account as a backstop,
- logging/analytics on usage.

Cloudflare is one option; the same ~40 lines port directly to a Vercel/Netlify function if you prefer.
