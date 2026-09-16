# Cascade

Cascade is an iOS app that turns piano sheet music into interactive falling-note
lessons and shareable videos. Photograph a printed score or import a PDF, and a
minute later you can slow it down, loop it, play along with accuracy feedback,
or export a 1080p60 video with piano audio.

- **Scan** — VisionKit document camera or PDF/image import → cloud recognition → MusicXML → falling notes
- **Import** — `.musicxml`, `.xml`, `.mxl` from MuseScore, Finale, Sibelius, …
- **Learn** — 25–200% speed, hand isolation, looping, Listen Mode, on-screen or MIDI keyboard with note-by-note grading
- **Export** — 1080p 60fps video with offline-rendered piano audio, from the player or straight from a scan
- **Progress** — practice calendar, streaks, achievements, reminders

Everything except scanning works offline.

## Repository layout

```
App/            entry point, orientation handling
Models/         MusicXML parser, playback model, scan pipeline, video/audio export
Views/          SwiftUI screens (library, scan, player, stats, onboarding)
ViewModels/     song library persistence
Audio/          AVAudioEngine sampler, note scheduler, MIDI input
Resources/      starter library (.musicxml), sample scan pages (Sample-*.png), PrivacyInfo.xcprivacy
Piano.sf2       Fluid R3 GM piano soundfont (MIT), bundled
MyPianoInstructorTests/    Swift Testing: parser goldens, scan pipeline units
server/cascade-scan-worker/ Cloudflare Worker backend for scanning
docs/           privacy policy, App Store listing copy, release checklist
```

Xcode project: `Cascade.xcodeproj` (file-system-synchronized groups — drop a
file into a folder and it joins the target). Deployment target iOS 26.1.

## How scanning works

```
pages ─▶ SheetSystemSplitter ─▶ system crops, batched ─▶ cascade-scan worker ─▶ vision model
      ◀─ MeasureChecker ◀─ MusicXMLStitcher ◀───────────── MusicXML per batch ◀─┘
```

1. **Capture.** The document camera auto-crops and deskews; PDFs are rasterised at ~3000 px.
2. **Split.** `SheetSystemSplitter` (`Models/ScoreTranscription.swift`) finds staff lines with a
   row-darkness profile and crops each grand-staff system. Sending systems instead of whole
   pages gives the model several times more pixels per staff line and keeps every reply short.
   If detection is unsure the page goes whole.
3. **Recognise.** Batches of ~4 systems go to the worker with a shared job id (one request per
   batch, one free scan per job). The prompt pins the model to the MusicXML subset our parser
   reads; continuation batches receive the divisions/key/time/tempo established so far.
4. **Stitch + check.** `MusicXMLStitcher` concatenates and renumbers measures; `MeasureChecker`
   flags measures whose durations don't add up to the time signature. A bad report triggers one
   whole-page retry on the stronger model.
   Bundled samples (`Models/SampleScans.swift`, pages rendered by `docs/tools-engrave.swift`)
   skip steps 2–4 and use the starter-library MusicXML, so the flow can be tried free and offline.
5. **Validate + preview.** The app's own parser must produce real notes, then the user sees
   note count, duration, suspicious measures, a piano-roll preview, and can save or export.

### Backend and money model

`server/cascade-scan-worker` is a Cloudflare Worker (plain JS, offline tests in
`test/run.js`). It verifies Sign in with Apple, mints session tokens, holds each
account's credit balance in KV, caches identical scans, routes to Anthropic with
Gemini fallback (or Gemini-only for a $0 setup), rate-limits, and supports
account deletion.

Credits: 1 free per Apple ID, then consumable packs bought with StoreKit 2
(`Models/ScanStore.swift`). A scan costs 1 credit per 4 pages and is capped in
model requests per credit, so provider spend per credit is bounded. Credits are
granted only after the worker verifies Apple's signature on the transaction
(`src/appstore.js`, X.509 chain to Apple Root CA G3, no libraries), once per
transaction id. `Cascade.storekit` lets you exercise the purchase UI locally.

Deployed at `https://cascade-scan.jaydfds.workers.dev`; the app points at it via
`ScanCloudConfig.baseURL`. See [docs/release-checklist.md](docs/release-checklist.md)
for the one remaining secret to set (`GEMINI_API_KEY` or `ANTHROPIC_API_KEY`).

Debug builds additionally accept a personal Anthropic key in scan settings
(bring-your-own-key) so you can develop without the worker. Release builds are
cloud-only.

## Building and testing

```bash
# App
xcodebuild -project Cascade.xcodeproj -scheme MyPianoInstructor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Unit tests (parser goldens, splitter, stitcher, measure checker)
xcodebuild -project Cascade.xcodeproj -scheme MyPianoInstructor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MyPianoInstructorTests test

# Worker tests
cd server/cascade-scan-worker && node test/run.js
```

Build settings that matter when adding code: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
(mark pure helpers `nonisolated`), `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`
(import frameworks explicitly), Swift language mode 5.

## Releasing

Follow [docs/release-checklist.md](docs/release-checklist.md). Listing copy and
review notes are in [docs/app-store-listing.md](docs/app-store-listing.md); the
privacy policy to host is [docs/privacy-policy.md](docs/privacy-policy.md).

## License

MIT for the app source. Piano.sf2 is Fluid R3 GM (MIT, Frank Wen). Starter-library
pieces are public-domain works.
