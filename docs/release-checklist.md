# Cascade — App Store release checklist

Everything code-side for 1.0 is done in this repo. The items below need
your Apple / Cloudflare / GitHub accounts, so they are yours to click through.
Estimated time: about an hour of clicking, plus Apple Developer Program
enrollment (step 3, one to two days) and App Review.

Do these in order: 1 → 2 → 3 → 4 → 5 → 6.

## 1. Backend (5 minutes)

The scan worker is deployed at `https://cascade-scan.jaydfds.workers.dev`
with its session secret set and the app already points at it. It still needs
**one provider key** before scans work (right now it answers "temporarily
unavailable"):

```bash
cd server/cascade-scan-worker
npx wrangler secret put GEMINI_API_KEY        # free tier: aistudio.google.com  ($0 mode)
npx wrangler secret put ANTHROPIC_API_KEY     # optional, best quality (paid); becomes primary automatically
```

Sanity check afterwards: `curl https://cascade-scan.jaydfds.workers.dev/` should return `{"service":"cascade-scan","ok":true}`.

Optional knobs in `wrangler.toml`: `FREE_SCANS` (default 5), model ids. Redeploy with `npx wrangler deploy`.

## 2. Privacy policy URL (10 minutes)

App Store Connect requires a public privacy-policy URL, and the app links to it.

1. Host `docs/privacy-policy.md` somewhere public. Easiest: push this repo to
   GitHub, enable Pages on the `docs/` folder, and the policy appears at
   `https://<you>.github.io/<repo>/privacy-policy`.
2. Paste that URL into `ScanCloudConfig.privacyPolicyURL` in
   `Models/ScanCloud.swift` (currently `nil`, which hides the in-app link).
3. Paste the same URL into App Store Connect → App Privacy.

## 3. Apple Developer Program + signing (enrollment: 1–2 days, then 5 minutes)

**Blocker found while archiving:** the team currently in the project
(`6N239V8VV5`, "Jason Fang") is a *personal* team, i.e. a free Apple ID. Personal
teams cannot publish to the App Store and cannot use Sign in with Apple, so the
archive fails with:

> Personal development teams, including "Jason Fang", do not support the Sign In with Apple capability.

1. Enroll in the Apple Developer Program (developer.apple.com/programs, US$99/year).
   Approval usually takes a day or two.
2. Open `Cascade.xcodeproj` → **MyPianoInstructor** target → Signing &
   Capabilities → switch **Team** to the new paid team (keep automatic signing).
   Xcode will register the App ID `jhfang.MyPianoInstructor2` with the Sign in
   with Apple capability on first build while online. If it shows a red error,
   click "+ Capability → Sign in with Apple" once.
3. Set **Version** (1.0) and **Build** (bump for every upload) in the General tab.

Until enrollment completes you can still run Debug builds on your own device
with the personal team **if** you temporarily remove the Sign in with Apple
entitlement (Signing & Capabilities → delete the capability, don't commit that
change). The scan flow then only works in the debug bring-your-own-key mode.

## 4. Test on a real device (15 minutes)

The simulator can't do camera capture or Sign in with Apple properly.

- Scan flow: Sign in with Apple → camera scan of a simple piece → preview →
  **Save & Export Video** → share sheet → "Save Video" (this is the path that
  used to crash without the photo-library permission string; it's fixed).
- Player export of Für Elise: confirm the video plays back with audio in
  sync.
- Delete Account from scan settings, then sign in again.

## 5. App Store Connect (30 minutes)

- Create the app record with bundle id `jhfang.MyPianoInstructor2`.
- **Sign the Paid Apps agreement** (Agreements, Tax, and Banking) — required before
  in-app purchases can be tested or sold. Add banking and tax info.
- **Create the two consumable in-app purchases** (App → Monetization → In-App
  Purchases → + → Consumable). The product ids must match exactly:

  | Reference name | Product ID | Price tier | Display name |
  |---|---|---|---|
  | 10 Scans | `jhfang.MyPianoInstructor2.scans10` | $4.99 | 10 Scans |
  | 25 Scans | `jhfang.MyPianoInstructor2.scans25` | $9.99 | 25 Scans |

  Description for both: "Scan credits for turning sheet music into falling-note
  lessons. One credit covers a scan of up to 4 pages. Credits never expire."
  Add a 1024×1024 review screenshot of the scan screen for each. Submit the
  products **with** the first app version (select them on the version page under
  In-App Purchases), otherwise the packs show "not available" in review.
- Optional: enroll in the App Store Small Business Program (15% commission
  instead of 30%) at developer.apple.com — the margin numbers below assume it.
- Copy in `docs/app-store-listing.md` (name, subtitle, description,
  keywords, review notes).
- Screenshots: 6.9" iPhone and 13" iPad are required. Use the simulator
  (`iPhone 17 Pro Max`, `iPad Pro 13-inch`) → Home tab, Play tab in
  landscape, Scan screen, Progress tab, an export share sheet.
- App Privacy questionnaire (matches `PrivacyInfo.xcprivacy`):
  - **Photos or Videos** — used for App Functionality, not linked to identity, not used for tracking.
  - **User ID** — App Functionality, linked to identity, not used for tracking.
  - No tracking.
- Age rating: 4+. Category: Music (secondary: Education).
- Export compliance: already answered in `Info.plist` (`ITSAppUsesNonExemptEncryption = NO`), so no prompt per build.

## 6. Archive and upload

Product → Archive in Xcode, then Distribute → App Store Connect. Or from the terminal:

```bash
xcodebuild -project Cascade.xcodeproj -scheme MyPianoInstructor -configuration Release -destination 'generic/platform=iOS' -archivePath build/Cascade.xcarchive archive
```

TestFlight it to yourself first; the scan flow deserves one real-world run on
a phone camera before review.

## 7. Review notes to include

Already drafted in `docs/app-store-listing.md`. The key points: scanning
needs network; Sign in with Apple grants 5 free scans; provide the reviewer
with a sample PDF (the bundled starter songs are also available offline so
the app is fully testable without scanning).

## Money model (how you break even)

- Every Apple ID gets **1 free scan credit** (`FREE_SCANS` in `wrangler.toml`).
- A scan costs **1 credit per 4 pages** (`PAGES_PER_CREDIT`). A 5-page piece is 2 credits.
- Per credit the worker allows at most 24 images / 6 model requests
  (`MAX_IMAGES_PER_CREDIT`, `MAX_REQUESTS_PER_CREDIT`), which bounds worst-case
  provider spend per credit to roughly $0.40 on Sonnet 5 with the Opus retry,
  and typically $0.15–0.25.
- Packs: 10 for $4.99 (≈ $0.42 net per credit after Apple's 15%), 25 for $9.99
  (≈ $0.34 net). Both clear typical cost; the 10-pack clears worst case.
- Credits are granted **only** after the worker verifies Apple's signature on the
  transaction (`src/appstore.js`), once per transaction id. A modified app cannot
  mint credits; a hacked session can only spend what that account has.
- 20 requests per minute per account, 12 pages per scan, identical scans cached.
- Backstop: set a monthly spend limit in the Anthropic console.

Testing purchases before enrollment: the scheme points at `Cascade.storekit`, so
running from Xcode shows the packs and completes local purchases. Those local
transactions are signed by Xcode, not Apple, so the worker (correctly) rejects
them — expect "This purchase could not be verified" in that mode. Real
verification works in TestFlight / sandbox once the products exist in App Store
Connect.

## What is intentionally not in 1.0

- **App Attest.** Extra abuse hardening for the free tier; the session-token seam
  in the worker is where it goes.
- **D1 instead of KV.** KV is eventually consistent; two devices racing could get
  one extra free request. Bounded by the per-job caps, so acceptable at launch.
