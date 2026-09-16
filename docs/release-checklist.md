# Cascade — App Store release checklist

Everything code-side for 1.0 is done in this repo. The items below need
your Apple / Cloudflare / GitHub accounts, so they are yours to click through.
Estimated time: about an hour, plus App Review.

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

## 3. Xcode signing (5 minutes)

1. Open `Cascade.xcodeproj`, select the **MyPianoInstructor** target →
   Signing & Capabilities. Team `6N239V8VV5` is already set with automatic
   signing.
2. Confirm **Sign in with Apple** shows as a capability (the entitlement file
   is wired; Xcode registers it on the App ID the first time you build with
   automatic signing while online). If it shows a red error, click "+
   Capability → Sign in with Apple" once.
3. Set **Version** (1.0) and **Build** (bump for every upload). Both live in
   the target's General tab.

## 4. Test on a real device (15 minutes)

The simulator can't do camera capture or Sign in with Apple properly.

- Scan flow: Sign in with Apple → camera scan of a simple piece → preview →
  **Save & Export Video** → share sheet → "Save Video" (this is the path that
  used to crash without the photo-library permission string; it's fixed).
- Player export of Für Elise: confirm the video plays back with audio in
  sync.
- Delete Account from scan settings, then sign in again.

## 5. App Store Connect (20 minutes)

- Create the app record with bundle id `jhfang.MyPianoInstructor2`.
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

## What is intentionally not in 1.0

- **Paid scan packs (IAP).** The worker meters free scans per account; selling
  more needs StoreKit 2 products plus server receipt verification and moving
  quota from KV to D1. Ship 1.0 free, add packs in 1.1 once you see demand.
- **App Attest.** Abuse hardening for the free tier; the session-token seam
  in the worker is where it goes.
