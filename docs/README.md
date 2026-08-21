# Hair Compass AI Public Pages

The three pages App Store Connect and the in-app paywall need to be able to reach. The
placeholders (`[DATE]`, `[SUPPORT EMAIL]`, `[SUPPORT URL]`) have already been filled in.

## Files

- `index.html` — the support/marketing landing page
- `privacy-policy.html` — describes cloud AI as opt-in: DeepSeek reads a limited tracking
  summary (no name, no photos) only after in-app consent, with everything else on-device
- `support.html`

## Hosting

These must be publicly reachable **before** submission. Two things depend on it:

- App Store Connect refuses a submission without a resolving privacy policy URL.
- `PaywallLegal` renders Privacy Policy and Terms links directly on the subscription paywall. A
  dead link there is a Guideline 3.1.2 rejection.

The repo is public, so GitHub Pages serves `/docs` directly: `docs/CNAME` points the custom
domain at `haircompass-ai.com`, and both legal pages are already live there over HTTPS. Pages
publishes from the **default branch** (`rebuild/clinical-minimal`) — edits to any file here take
effect only once merged, not on push to a feature branch.

## App Update

After publishing, set both constants in
[`Hair Compass AI 5/Model/AppInfo.swift`](../Hair%20Compass%20AI%205/Model/AppInfo.swift):

- `AppInfo.privacyPolicyURLString`
- `AppInfo.supportURLString`

`SubmissionReadinessTests` fails until these point somewhere real — that failure *is* the
pre-submission checklist. Don't satisfy it by emptying the strings: an empty URL hides the link
entirely, and App Review requires a reachable privacy policy link on an auto-renewable paywall.

Then confirm both actually resolve:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -L "<privacy URL>"
curl -s -o /dev/null -w "%{http_code}\n" -L "<support URL>"
```
