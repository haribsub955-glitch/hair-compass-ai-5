# Hair Compass AI proxy

A small Node serverless function that lets the app use the cloud AI **without ever shipping the
Anthropic API key**. The key lives only here as an env var. Each request carries the user's
StoreKit 2 entitlement JWS, which this function verifies with **Apple's official App Store Server
Library** — full signature + certificate-chain validation against Apple's root, not just a claims
check — before forwarding to Anthropic.

This is the server side of the hybrid AI:
- **On-device (free, private):** the app uses Apple's FoundationModels for the *text* chat when the
  device supports Apple Intelligence — it never touches this proxy.
- **Cloud (this proxy):** photo/deep analysis, and chat on devices without on-device AI.

## Deploy (Vercel — easiest from your repo)

1. Install the CLI and log in:
   ```bash
   npm install -g vercel
   cd server && npm install
   vercel login
   ```
2. Set the two environment variables (in the Vercel dashboard → Project → Settings → Environment
   Variables, or via `vercel env add`):
   - `ANTHROPIC_API_KEY` — your Anthropic key (**required**).
   - `APP_APPLE_ID` — the numeric App Store app id (**for production**; get it from App Store
     Connect once the app record exists). You can deploy without it and test with **sandbox /
     TestFlight** first; add it before going live.
3. Deploy:
   ```bash
   vercel --prod
   ```
   Vercel prints a URL. Your endpoint is `https://<project>.vercel.app/api/analyze`.
4. Point the app at it — one line in `Hair Compass AI 5/Service/CloudAnalysisService.swift`:
   ```swift
   enum AIConfig {
       static let proxyURLString = "https://<project>.vercel.app/api/analyze"
       ...
   }
   ```
   When `proxyURLString` is non-empty the app carries **no key** and every cloud call goes through
   this function with the StoreKit entitlement attached. (Leave it empty for local dev, which uses a
   launch-provided `ANTHROPIC_API_KEY` env var and posts directly to Anthropic.)

> Any Node host works (Netlify Functions, AWS Lambda, a small Express server) — it's a standard
> handler; only the deploy command differs.

## How verification works

`api/analyze.js` uses `SignedDataVerifier.verifyAndDecodeTransaction(jws)` from
`@apple/app-store-server-library`, which:
- verifies the JWS **signature**,
- validates the **x5c certificate chain** up to Apple's root CA (fetched at cold start),
- runs online (OCSP) **revocation** checks.

It then confirms the decoded transaction is **this app's bundle id**, a **Pro product**, **not
revoked**, and **not expired**. It tries the production environment first, then sandbox, so one
deploy serves both TestFlight review and the live App Store. No subscription → `402`, and the app
shows "this is a Pro feature".

## Backstops worth adding
- A **monthly spend cap** on the Anthropic account (belt-and-braces against any abuse).
- A **per-subscription rate limit** (e.g. Vercel KV / Upstash) if usage grows.
