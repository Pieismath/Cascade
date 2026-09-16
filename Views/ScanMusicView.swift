//
//  ScanMusicView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/17/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ScanMusicView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int

    @State private var songTitle: String = ""
    @State private var isImporting = false
    @State private var statusText: String = ""
    @State private var showSheetScan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Header
                HStack {
                    Button {
                        tabSelection = 0
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                    }

                    Text("Add Music")
                        .font(.title2).bold()

                    Spacer()
                }
                .padding(.top)

                // MARK: - Scan Sheet Music (camera / PDF → falling notes)
                scanSheetMusicSection

                // MARK: - Song Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Song title")
                        .font(.subheadline).bold()
                    TextField("Enter song title", text: $songTitle)
                        .textFieldStyle(.roundedBorder)
                }

                // MARK: - File Import
                fileImportSection

                // Status
                if !statusText.isEmpty {
                    HStack {
                        Image(systemName: statusText.contains("success") || statusText.contains("Success") ? "checkmark.circle.fill" : "info.circle")
                            .foregroundColor(statusText.contains("success") || statusText.contains("Success") ? .green : .secondary)
                        Text(statusText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Free Starter Library
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free Starter Library")
                            .font(.headline)
                        Text("Ready to practice — bundled right in the app. No internet, no sheet music required.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(groupedDemos, id: \.0) { level, demos in
                        // Difficulty group header
                        let headerColor: Color = level == "Beginner" ? .green : level == "Intermediate" ? .orange : .purple
                        HStack(spacing: 6) {
                            Text(level)
                                .font(.caption).bold()
                                .foregroundColor(headerColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(headerColor.opacity(0.12))
                                .cornerRadius(8)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                        }

                        ForEach(demos, id: \.title) { demo in
                            let accent: Color = demo.difficulty == "Beginner" ? .green : demo.difficulty == "Intermediate" ? .orange : .purple
                            if demo.locked {
                                // Locked / coming-soon song
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.08))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.secondary)
                                            .font(.callout)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(demo.title)
                                            .font(.subheadline).bold()
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 4) {
                                            Text(demo.composer)
                                                .font(.caption).bold()
                                                .foregroundColor(.secondary)
                                            Text("·")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(demo.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text("Soon")
                                        .font(.caption).bold()
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .padding(12)
                                .background(AppTheme.cardBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                )
                            } else {
                                Button {
                                    importDemoSong(title: demo.title, resourceName: demo.resourceName)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(accent.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "music.note")
                                                .foregroundColor(accent)
                                                .font(.callout)
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(demo.title)
                                                .font(.subheadline).bold()
                                                .foregroundColor(.primary)
                                            HStack(spacing: 4) {
                                                Text(demo.composer)
                                                    .font(.caption).bold()
                                                    .foregroundColor(accent)
                                                Text("·")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text(demo.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(accent)
                                            .font(.title3)
                                    }
                                    .padding(12)
                                    .background(AppTheme.cardBackground)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(accent.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
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

    // MARK: - Scan Sheet Music Section

    private var scanSheetMusicSection: some View {
        Button {
            showSheetScan = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Scan Sheet Music")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("NEW")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white)
                            .cornerRadius(5)
                    }
                    Text("Photograph pages or import a PDF — no MusicXML needed")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
            }
            .padding()
            .background(AppTheme.heroGradient)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan sheet music with camera or PDF")
    }

    // MARK: - Grouped Demo Songs

    private var groupedDemos: [(String, [DemoSongs.DemoSong])] {
        let groups = Dictionary(grouping: DemoSongs.all, by: \.difficulty)
        return ["Beginner", "Intermediate", "Advanced"].compactMap { level in
            guard let songs = groups[level] else { return nil }
            return (level, songs)
        }
    }

    // MARK: - File Import Section

    private var fileImportSection: some View {
        VStack(spacing: 12) {
            Button {
                isImporting = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("Select MusicXML File")
                            .font(.headline)
                        Text(".musicxml, .xml, or .mxl formats")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundColor(.white)
                .padding()
                .background(AppTheme.accentGradient)
                .cornerRadius(14)
            }
            .disabled(songTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(songTitle.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
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

            defer {
                if gotAccess {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: selectedURL, error: &error) { url in
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                do {
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.copyItem(at: url, to: tempURL)

                    let data = try Data(contentsOf: tempURL)
                    // Handles plain XML in common encodings and .mxl ZIP containers
                    let xmlString = try MusicXMLImport.loadString(from: data)

                    DispatchQueue.main.async {
                        let title = songTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : songTitle
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

            if let error = error {
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

// MARK: - Demo Songs Data

enum DemoSongs {
    struct DemoSong {
        let title: String
        let resourceName: String
        let description: String
        let difficulty: String   // "Beginner", "Intermediate", or "Advanced"
        let composer: String
        var locked: Bool = false
    }

    static let all: [DemoSong] = [
        // MARK: Beginner
        DemoSong(title: "C Major Scale",
                 resourceName: "CMajorScale",
                 description: "Foundation finger exercise",
                 difficulty: "Beginner",
                 composer: "Exercise"),
        DemoSong(title: "Hot Cross Buns",
                 resourceName: "HotCrossBuns",
                 description: "Three-note starter piece",
                 difficulty: "Beginner",
                 composer: "Traditional"),
        DemoSong(title: "Mary Had a Little Lamb",
                 resourceName: "MaryHadALittleLamb",
                 description: "Simple right-hand melody",
                 difficulty: "Beginner",
                 composer: "Traditional"),
        DemoSong(title: "Twinkle Twinkle Little Star",
                 resourceName: "TwinkleTwinkle",
                 description: "Classic first song",
                 difficulty: "Beginner",
                 composer: "Traditional"),
        // MARK: Intermediate
        DemoSong(title: "Ode to Joy",
                 resourceName: "OdeToJoy",
                 description: "Beethoven's famous theme",
                 difficulty: "Intermediate",
                 composer: "Beethoven"),
        DemoSong(title: "Für Elise",
                 resourceName: "FurElise",
                 description: "Iconic Beethoven melody",
                 difficulty: "Intermediate",
                 composer: "Beethoven"),
        // MARK: Advanced
        DemoSong(title: "Flight of the Bumblebee",
                 resourceName: "FlightOfTheBumblebee",
                 description: "Lightning-fast Rimsky-Korsakov",
                 difficulty: "Advanced",
                 composer: "Rimsky-Korsakov"),
        DemoSong(title: "Chopin Nocturne Op. 9 No. 1",
                 resourceName: "ChopinNocturneOp9No1",
                 description: "Expressive Romantic nocturne",
                 difficulty: "Advanced",
                 composer: "Chopin"),
        DemoSong(title: "Moonlight Sonata",
                 resourceName: "MoonlightSonata",
                 description: "Beethoven's moonlit masterpiece",
                 difficulty: "Advanced",
                 composer: "Beethoven",
                 locked: true),
        DemoSong(title: "Clair de Lune",
                 resourceName: "ClairDeLune",
                 description: "Debussy's impressionist gem",
                 difficulty: "Advanced",
                 composer: "Debussy",
                 locked: true),
        DemoSong(title: "Ballade No. 1",
                 resourceName: "BalladeNo1",
                 description: "Chopin's dramatic masterwork",
                 difficulty: "Advanced",
                 composer: "Chopin",
                 locked: true),
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
