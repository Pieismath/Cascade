# cascade-scan worker

The backend for Cascade's sheet-music scanning. Holds the provider API keys,
verifies Sign in with Apple, tracks per-account free-scan quota, caches
identical scans, and routes recognition to Anthropic (primary) with an
optional Gemini fallback.

## Deploy (one time, ~5 minutes)

```bash
cd server/cascade-scan-worker

# 1. Create the KV namespace and paste the printed id into wrangler.toml
npx wrangler kv namespace create SCAN_KV

# 2. Secrets — SESSION_SECRET plus at least one provider key
npx wrangler secret put SESSION_SECRET        # generate: openssl rand -hex 32
npx wrangler secret put GEMINI_API_KEY        # free tier at aistudio.google.com
npx wrangler secret put ANTHROPIC_API_KEY     # optional, best quality (paid)

# Gemini-only = $0 mode: the worker runs everything on Gemini's free tier.
# Add ANTHROPIC_API_KEY later and it automatically becomes primary, with
# Gemini demoted to outage fallback. No code changes either way.

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
| POST   | /v1/recognize   | session bearer | Pages (base64 JPEG) → MusicXML |

Error responses are `{error: {code, message}}`; the app maps `401` (re-sign-in),
`402 out_of_scans`, `413`, `422 unreadable/too_long`, and `502`.

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
