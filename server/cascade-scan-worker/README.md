# cascade-scan worker

The backend for Cascade's sheet-music scanning. Holds the provider API keys,
verifies Sign in with Apple, tracks per-account free-scan quota, caches
identical scans, and routes recognition to Anthropic or Gemini
(`PRIMARY_PROVIDER` picks; the other covers retryable failures).

## Current deployment

Deployed as `cascade-scan` at `https://cascade-scan.jaydfds.workers.dev` with
`SESSION_SECRET` set and KV namespace `35ee0915…` bound. It still needs a
provider key (`GEMINI_API_KEY` and/or `ANTHROPIC_API_KEY`) before `/v1/recognize`
does anything but return 503.

## Deploy from scratch (one time, ~5 minutes)

```bash
cd server/cascade-scan-worker

# 1. Create the KV namespace and paste the printed id into wrangler.toml
npx wrangler kv namespace create SCAN_KV

# 2. Secrets — SESSION_SECRET plus at least one provider key
npx wrangler secret put SESSION_SECRET        # generate: openssl rand -hex 32
npx wrangler secret put GEMINI_API_KEY        # aistudio.google.com — cheapest
npx wrangler secret put ANTHROPIC_API_KEY     # best accuracy

# Either key alone is enough. With both, PRIMARY_PROVIDER in wrangler.toml
# ("anthropic" or "gemini") picks who answers first and the other covers rate
# limits and outages. No code changes either way.
#
# Gemini's free tier is for development only: Google trains on what you send,
# human reviewers may read it, and its terms allow unpaid use only outside the
# EEA / Switzerland / UK. Enable billing before shipping to users.

# 3. Ship it
npx wrangler deploy
```

`wrangler deploy` prints the worker URL (e.g. `https://cascade-scan.<you>.workers.dev`).
Paste it into `ScanCloudConfig.baseURL` in `Models/ScanCloud.swift` and rebuild the app.

Tuning knobs live in `wrangler.toml` (`FREE_SCANS`, model ids, session length) —
edit and redeploy.

## Endpoints

| Method | Path            | Auth           | Purpose |
|--------|-----------------|----------------|---------|
| POST   | /v1/auth/apple  | Apple id token | Verify Apple sign-in, mint session token |
| GET    | /v1/me          | session bearer | Remaining scans |
| DELETE | /v1/account     | session bearer | Delete the usage record (App Store 5.1.1 account deletion) |
| POST   | /v1/purchases/redeem | session bearer | `{signedTransaction}` (StoreKit 2 JWS) → verify with Apple's chain, grant credits once |
| POST   | /v1/recognize   | session bearer | Images (base64 JPEG) → MusicXML |

`/v1/recognize` body: `{pages: [b64...], pageCount?: n, quality?: "standard"|"high", context?: string, jobId?: string}`.
Cost is `ceil(pageCount / PAGES_PER_CREDIT)` credits per job; free credits (`FREE_SCANS`) are
spent before purchased ones. Every balance response carries `remainingScans`, `freeRemaining`,
`credits`, `pagesPerCredit`.
The app splits long scores into several requests (system crops in batches) that share a
`jobId`; only the first request of a job consumes a free scan. `context` is appended to the
prompt so continuation batches know the divisions/key/time/tempo and measure number to
continue from.

Error responses are `{error: {code, message}}`; the app maps `401` (re-sign-in),
`402 insufficient_credits` (+`needed`/`remaining`), `413 job_too_large/too_many_pages`,
`422 unreadable/too_long`, `429 rate_limited`, `400 invalid_purchase/unknown_product`,
`502`, and `503 scan_unavailable` (deployed without any provider key).

## Notes & hardening roadmap

- Quota uses KV (eventually consistent) — fine for free-scan stakes; move to D1
  before selling scan packs via IAP.
- App Attest and a sign-in nonce are the next abuse-hardening steps once the
  app ships with a paid tier; the session-token seam is where the assertion
  check belongs.
- Long pieces stream from Anthropic (SSE) so idle timeouts don't kill big
  transcriptions. If you see terminated requests on very long scores, Workers
  paid plan removes the tighter free-plan limits.

## Tests

`node test/run.js` exercises token verification (signature/audience/expiry),
session round-trips, MusicXML extraction, SSE parsing, and provider fallback
with mocked fetch. No network access required.
