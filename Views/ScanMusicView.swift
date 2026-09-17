//
//  ScanMusicView.swift
//  MyPianoInstructor
//
//  The Add tab: scan sheet music, import a MusicXML file, or pick from the
//  starter library. Every starter piece shows its own score art.
//

import SwiftUI
import UniformTypeIdentifiers

struct ScanMusicView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int

    @State private var isImporting = false
    @State private var statusText: String = ""
    @State private var showSheetScan = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bring a piece in").eyebrowStyle()
                    Text("Add music")
                        .font(CascadeFont.display(36))
                        .foregroundStyle(Brand.textPrimary)
                }
                .padding(.top, 8)

                scanHero

                importRow

                if !statusText.isEmpty {
                    HStack(spacing: 8) {
                        CascadeIconView(statusText.localizedCaseInsensitiveContains("success") ? .check : .info, size: 16,
                                        color: statusText.localizedCaseInsensitiveContains("success") ? Brand.mint : Brand.textSecondary)
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(Brand.textSecondary)
                    }
                }

                starterLibrary

                Spacer(minLength: 30)
            }
            .padding(.horizontal, 20)
        }
        .stageBackground()
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.xml, .musicXML, .compressedMusicXML],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fullScreenCover(isPresented: $showSheetScan) {
            SheetScanView(selectedSong: $selectedSong, tabSelection: $tabSelection)
                .environment(libraryVM)
        }
    }

    // MARK: - Scan hero

    private var scanHero: some View {
        Button {
            showSheetScan = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Brand.stage)
                    .frame(height: 210)

                // A few falling bars on the right, landing on a keyboard — the product in one glance.
                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 7) {
                        Spacer()
                        ForEach(0..<9, id: \.self) { i in
                            let h: CGFloat = [22, 44, 16, 58, 30, 66, 26, 48, 34][i]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 3 ? Brand.violet : (i % 3 == 1 ? Brand.amber : Brand.teal))
                                .frame(width: 10, height: h)
                                .glow(i % 3 == 1 ? Brand.amber : Brand.teal, radius: 8, opacity: 0.45)
                        }
                    }
                    .padding(.trailing, 26)
                    .padding(.bottom, 2)
                    KeyboardStripView(highlighted: [76, 79])
                        .frame(height: 26)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 2)
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CascadeIconView(.scan, size: 16, color: Brand.teal)
                        Text("Scan sheet music").eyebrowStyle(Brand.teal)
                    }
                    Text("Point your camera\nat a page.")
                        .font(CascadeFont.display(26))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Falling notes and a video, in a minute.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                }
                .padding(22)
                .frame(height: 210, alignment: .topLeading)
            }
            .overlay(alignment: .bottomLeading) {
                Chip(text: "Try a free sample", tint: Brand.teal, filled: true)
                    .padding(.leading, 20)
                    .padding(.bottom, 40)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan sheet music with camera or PDF")
    }

    // MARK: - Import

    private var importRow: some View {
        Button {
            isImporting = true
        } label: {
            HStack(spacing: 14) {
                IconBadge(glyph: .importFile, tint: Brand.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import a MusicXML file")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(".musicxml, .xml or .mxl from MuseScore, Finale, Sibelius…")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                CascadeIconView(.chevronRight, size: 16, color: Brand.textTertiary)
            }
            .cascadeCard(padding: 12, radius: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Starter library

    private var starterLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Starter library", subtitle: "Free, offline, public domain")

            ForEach(groupedDemos, id: \.0) { level, demos in
                let tint: Color = level == "Beginner" ? Brand.mint : level == "Intermediate" ? Brand.amber : Brand.coral
                HStack(spacing: 10) {
                    Chip(text: level, tint: tint)
                    Rectangle().fill(Brand.hairline).frame(height: 1)
                }
                .padding(.top, 4)

                ForEach(demos, id: \.title) { demo in
                    demoRow(demo, tint: tint)
                }
            }
        }
    }

    private func demoRow(_ demo: DemoSongs.DemoSong, tint: Color) -> some View {
        Button {
            importDemoSong(title: demo.title, resourceName: demo.resourceName)
        } label: {
            HStack(spacing: 14) {
                if let playback = DemoArtCache.playback(for: demo.resourceName) {
                    ScoreArtView(playback: playback, window: 8, cornerRadius: 12)
                        .frame(width: 60, height: 60)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Brand.surfaceHigh).frame(width: 60, height: 60)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(demo.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(demo.composer)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                        Text("·").foregroundStyle(Brand.textTertiary)
                        Text(demo.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                CascadeIconView(libraryVM.songs.contains { $0.title == demo.title } ? .check : .plus, size: 16, color: Brand.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Brand.surfaceHigh, in: Circle())
            }
            .cascadeCard(padding: 12, radius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(demo.title) by \(demo.composer)")
    }

    private var groupedDemos: [(String, [DemoSongs.DemoSong])] {
        let groups = Dictionary(grouping: DemoSongs.all, by: \.difficulty)
        return ["Beginner", "Intermediate", "Advanced"].compactMap { level in
            guard let songs = groups[level] else { return nil }
            return (level, songs)
        }
    }

    // MARK: - File Import Handler

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            statusText = "Import failed: \(error.localizedDescription)"

        case .success(let urls):
            guard let selectedURL = urls.first else {
                statusText = "No file selected."
                return
            }

            let gotAccess = selectedURL.startAccessingSecurityScopedResource()
            defer { if gotAccess { selectedURL.stopAccessingSecurityScopedResource() } }

            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: selectedURL, error: &error) { url in
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                do {
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    let data = try Data(contentsOf: tempURL)
                    let xmlString = try MusicXMLImport.loadString(from: data)

                    DispatchQueue.main.async {
                        let title = url.deletingPathExtension().lastPathComponent
                            .replacingOccurrences(of: "_", with: " ")
                            .replacingOccurrences(of: "-", with: " ")
                        let newSong = libraryVM.addSong(title: title, musicXML: xmlString)
                        selectedSong = newSong
                        statusText = "Imported successfully!"
                        tabSelection = 2
                    }
                } catch {
                    DispatchQueue.main.async {
                        statusText = "Failed to read file: \(error.localizedDescription)"
                    }
                }
            }

            if let error {
                statusText = "Coordinator error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Demo Song Import

    private func importDemoSong(title: String, resourceName: String) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "musicxml") else {
            statusText = "Demo file not found in bundle."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let xmlString = String(decoding: data, as: UTF8.self)
            if let existing = libraryVM.songs.first(where: { $0.title == title }) {
                libraryVM.updateSong(existing, musicXML: xmlString)
                selectedSong = existing
                statusText = "Refreshed \"\(title)\" successfully!"
            } else {
                let newSong = libraryVM.addSong(title: title, musicXML: xmlString)
                selectedSong = newSong
                statusText = "Imported \"\(title)\" successfully!"
            }
            tabSelection = 2
        } catch {
            statusText = "Failed to load demo: \(error.localizedDescription)"
        }
    }
}

// MARK: - Score art cache for bundled pieces

/// Parses each bundled piece once so the library rows can show real art.
@MainActor
enum DemoArtCache {
    private static var cache: [String: PlaybackData] = [:]

    static func playback(for resourceName: String) -> PlaybackData? {
        if let cached = cache[resourceName] { return cached }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "musicxml"),
              let data = try? Data(contentsOf: url) else { return nil }
        let playback = MusicXMLParser.parse(data: data)
        cache[resourceName] = playback
        return playback
    }
}

// MARK: - Demo Songs Data

enum DemoSongs {
    struct DemoSong {
        let title: String
        let resourceName: String
        let description: String
        let difficulty: String   // "Beginner", "Intermediate", or "Advanced"
        let composer: String
    }

    static let all: [DemoSong] = [
        DemoSong(title: "C Major Scale", resourceName: "CMajorScale",
                 description: "Foundation finger exercise", difficulty: "Beginner", composer: "Exercise"),
        DemoSong(title: "Hot Cross Buns", resourceName: "HotCrossBuns",
                 description: "Three-note starter piece", difficulty: "Beginner", composer: "Traditional"),
        DemoSong(title: "Mary Had a Little Lamb", resourceName: "MaryHadALittleLamb",
                 description: "Simple right-hand melody", difficulty: "Beginner", composer: "Traditional"),
        DemoSong(title: "Twinkle Twinkle Little Star", resourceName: "TwinkleTwinkle",
                 description: "Classic first song", difficulty: "Beginner", composer: "Traditional"),
        DemoSong(title: "Ode to Joy", resourceName: "OdeToJoy",
                 description: "Beethoven's famous theme", difficulty: "Intermediate", composer: "Beethoven"),
        DemoSong(title: "Minuet in G", resourceName: "MinuetInG",
                 description: "Baroque dance, two hands", difficulty: "Intermediate", composer: "Bach / Petzold"),
        DemoSong(title: "Für Elise", resourceName: "FurElise",
                 description: "Iconic Beethoven melody", difficulty: "Intermediate", composer: "Beethoven"),
        DemoSong(title: "Flight of the Bumblebee", resourceName: "FlightOfTheBumblebee",
                 description: "Lightning-fast Rimsky-Korsakov", difficulty: "Advanced", composer: "Rimsky-Korsakov"),
        DemoSong(title: "Chopin Nocturne Op. 9 No. 1", resourceName: "ChopinNocturneOp9No1",
                 description: "Expressive Romantic nocturne", difficulty: "Advanced", composer: "Chopin"),
    ]
}

// MARK: - File Types Extension

extension UTType {
    static var musicXML: UTType {
        UTType(filenameExtension: "musicxml") ?? .xml
    }

    static var compressedMusicXML: UTType {
        UTType(filenameExtension: "mxl") ?? .xml
    }
}
