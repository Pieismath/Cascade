# Cascade (MyPianoInstructor)

Cascade is an interactive piano-learning app built with SwiftUI.  
Users can scan sheet music, automatically generate a playable transcription, and learn pieces through a real-time piano keyboard visualization.

This project aims to make reading complex sheet music easier for beginners and intermediate players by providing a “Synthesia-style” playback experience directly on iOS.

---

## 📷 Sheet Music Scanning (OMR)

The Add tab's **Scan Sheet Music** flow turns printed sheet music into a playable falling-note lesson:

1. **Capture** — VisionKit document camera (auto-crop, perspective correction) or PDF/image import (PDFKit rasterizes pages).
2. **Recognize** — pages are downscaled and sent to the Claude vision API, which returns MusicXML constrained to the subset `MusicXMLParser` supports (`Models/SheetMusicRecognition.swift`). The backend sits behind the `SheetMusicRecognizer` protocol, so a self-hosted Audiveris server or an on-device model can replace it without UI changes.
3. **Validate & preview** — the result is parsed by the app's own `MusicXMLParser`; garbage is rejected, and the user previews note count/duration/piano-roll before saving.
4. **Play** — the saved song flows through the exact same MusicXML → `PlaybackData` → falling-notes pipeline as any imported file.

**Two ways to power recognition:**

- **Cascade Cloud (for shipping to real users):** deploy the bundled backend once — see [server/cascade-scan-worker/README.md](server/cascade-scan-worker/README.md) — and set `ScanCloudConfig.baseURL` in `Models/ScanCloud.swift`. Users then just **Sign in with Apple** and get free scans (default 5, `FREE_SCANS` in `wrangler.toml`); your provider keys stay server-side, quota is per Apple account, identical scans are cached, and Anthropic outages fall back to Gemini automatically. Requires the Sign in with Apple capability on the app target (entitlements file is already wired; enable the capability for your team in Signing & Capabilities).
- **Bring-your-own-key (default in this repo, good for development/TestFlight):** with `ScanCloudConfig.baseURL = nil`, the scan screen asks for an Anthropic API key (gear menu, stored in Keychain) and calls the API directly. When cloud mode is on, an own key still works as an "Advanced" fallback for users who run out of free scans.

A typical scan costs a few cents. Everything else in the app remains fully offline.

---

## 🚀 Features (In Progress)

### ✔️ App Architecture (MVVM)
- `Song` model for metadata  
- `SongLibraryViewModel` with `@Published` song storage  
- EnvironmentObject state shared across all screens  

### ✔️ Tab-Based Navigation
A clean `TabView` with:
- **Home** – full song library
- **Scan** – upload or capture sheet music (mock flow)
- **Play** – playback UI using selected or newly scanned song

### ✔️ Song Library UI
- Displays all songs created by the user  
- Shows recently scanned songs  
- Tapping a song loads it directly into PlaybackView  

### ✔️ Sheet Music Scanning (Mocked)
- UI for uploading or photographing sheet music  
- Input prompt for song title  
- Adds new song to library and jumps to playback  

### ✔️ Playback Screen
Includes:
- Selected song title  
- Mock sheet music preview  
- Play / Pause / Jump buttons  
- Progress bar  
- Animated piano keyboard that highlights keys over time  

### ✔️ Piano Keyboard Component
Reusable `PianoKeyboardView` that:
- Draws a horizontal keyboard  
- Highlights one key at a time based on playback animation  
- Built with GeometryReader + variable key sizing  

---

## 🎯 Current Architecture

```plaintext
MyPianoInstructor/
│
├── MyPianoInstructorApp.swift
├── RootTabView.swift
│
├── Models/
│   └── Song.swift
│
├── ViewModels/
│   └── SongLibraryViewModel.swift
│
└── Views/
    ├── SongLibraryView.swift
    ├── ScanMusicView.swift
    ├── PlaybackView.swift
    └── PianoKeyboardView.swift
```
---

## 🔧 Tech Stack

- **SwiftUI**
- **MVVM Architecture**
- **ObservableObject + EnvironmentObject**
- **Timer-based animations**
- **(Future) AVAudioEngine for MIDI playback**
- **(Future) OMR (Optical Music Recognition) API for sheet music parsing**

---

## 🛣️ Roadmap

### Short-Term
- Add realistic black/white keys to the keyboard  
- Add basic audio playback for each highlighted note  
- Add real persistence (SwiftData or CoreData)  
- Improve UI layout and spacing  

### Medium-Term
- Integrate real OMR (Optical Music Recognition)  
- Parse MusicXML into a playable timeline  
- Display falling-note animation instead of simple highlights  

### Long-Term
- Export videos of playback  
- Allow custom tempo and looping  
- Cloud sync for scanned songs  
- Learn-mode with slowing, pausing, and note isolation  

---

## 📸 Screenshots / Wireframes

(Soon: add your hand-drawn sketches or simulator screenshots)

---

## 🤝 Contributing

Pull requests are welcome as the project evolves.  
For major changes, please open an issue first to discuss what you’d like to change.

---

## 📜 License

This project is open-source under the MIT license.
