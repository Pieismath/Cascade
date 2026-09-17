//
//  StarterLibrary.swift
//  MyPianoInstructor
//
//  The bundled public-domain pieces shown on Home, plus reading MusicXML
//  files picked in Files.
//

import UIKit
import Observation
import UniformTypeIdentifiers

// MARK: - Starter pieces

enum DemoSongs {
    struct DemoSong {
        let title: String
        let resourceName: String
        let description: String
        let difficulty: String   // "Beginner", "Intermediate", or "Advanced"
        let composer: String
    }

    static let all: [DemoSong] = [
        DemoSong(title: "Für Elise", resourceName: "FurElise",
                 description: "Iconic Beethoven melody", difficulty: "Intermediate", composer: "Beethoven"),
        DemoSong(title: "Chopin Nocturne Op. 9 No. 1", resourceName: "ChopinNocturneOp9No1",
                 description: "Expressive Romantic nocturne", difficulty: "Advanced", composer: "Chopin"),
        DemoSong(title: "Minuet in G", resourceName: "MinuetInG",
                 description: "Baroque dance, two hands", difficulty: "Intermediate", composer: "Bach / Petzold"),
        DemoSong(title: "Flight of the Bumblebee", resourceName: "FlightOfTheBumblebee",
                 description: "Lightning-fast Rimsky-Korsakov", difficulty: "Advanced", composer: "Rimsky-Korsakov"),
        DemoSong(title: "Ode to Joy", resourceName: "OdeToJoy",
                 description: "Beethoven's famous theme", difficulty: "Intermediate", composer: "Beethoven"),
        DemoSong(title: "Twinkle Twinkle Little Star", resourceName: "TwinkleTwinkle",
                 description: "Classic first song", difficulty: "Beginner", composer: "Traditional"),
        DemoSong(title: "Mary Had a Little Lamb", resourceName: "MaryHadALittleLamb",
                 description: "Simple right-hand melody", difficulty: "Beginner", composer: "Traditional"),
        DemoSong(title: "Hot Cross Buns", resourceName: "HotCrossBuns",
                 description: "Three-note starter piece", difficulty: "Beginner", composer: "Traditional"),
        DemoSong(title: "C Major Scale", resourceName: "CMajorScale",
                 description: "Foundation finger exercise", difficulty: "Beginner", composer: "Exercise"),
    ]

    static func musicXML(for demo: DemoSong) -> String? {
        Bundle.main.url(forResource: demo.resourceName, withExtension: "musicxml")
            .flatMap { try? Data(contentsOf: $0) }
            .map { String(decoding: $0, as: UTF8.self) }
    }
}

extension SongLibraryViewModel {
    /// Adds a starter piece (or refreshes the copy already in the library)
    /// and returns the song to play.
    func addStarter(_ demo: DemoSongs.DemoSong) -> Song? {
        guard let xml = DemoSongs.musicXML(for: demo) else { return nil }
        if let existing = songs.first(where: { $0.title == demo.title }) {
            updateSong(existing, musicXML: xml)
            return existing
        }
        return addSong(title: demo.title, musicXML: xml)
    }
}

/// Score art and sample-page thumbnails for Home, prepared off the main
/// thread so opening the app never waits on parsing. Cards fill in as each
/// piece is ready.
@MainActor
@Observable
final class HomeArt {
    static let shared = HomeArt()

    private(set) var playbacks: [String: PlaybackData] = [:]
    private(set) var pageThumbnails: [String: UIImage] = [:]
    @ObservationIgnored private var warming = false

    func warm() {
        guard !warming else { return }
        warming = true
        let thumbnailJobs = SampleScan.all.compactMap { sample in sample.pageResources.first.map { (sample.id, $0) } }
        var scoreJobs: [String] = []
        for name in SampleScan.all.map(\.xmlResource) + DemoSongs.all.map(\.resourceName) where !scoreJobs.contains(name) {
            scoreJobs.append(name)
        }

        Task.detached(priority: .userInitiated) {
            for (id, resource) in thumbnailJobs {
                guard let thumbnail = HomeArt.renderThumbnail(resource) else { continue }
                await MainActor.run { HomeArt.shared.pageThumbnails[id] = thumbnail }
            }
            for name in scoreJobs {
                guard let playback = HomeArt.parse(name) else { continue }
                await MainActor.run { HomeArt.shared.playbacks[name] = playback }
            }
        }
    }

    nonisolated private static func parse(_ resource: String) -> PlaybackData? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "musicxml"),
              let data = try? Data(contentsOf: url) else { return nil }
        return MusicXMLParser.parse(data: data)
    }

    /// First page scaled to 360 px wide (120 pt at 3x).
    nonisolated private static func renderThumbnail(_ resource: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
              let page = UIImage(contentsOfFile: url.path), page.size.width > 0 else { return nil }
        let size = CGSize(width: 360, height: (360 * page.size.height / page.size.width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            page.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Importing score files

enum ScoreFileImport {
    enum ImportError: LocalizedError {
        case unreadable(String)
        case noNotes(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                return "\(name) couldn't be read. Export it from your notation app as MusicXML (.musicxml or .mxl) and try again."
            case .noNotes(let name):
                return "\(name) doesn't contain any piano notes Cascade can play."
            }
        }
    }

    /// Files the Import button treats as scores rather than pages to scan.
    nonisolated static func isScoreFile(_ url: URL) -> Bool {
        ["musicxml", "mxl", "xml"].contains(url.pathExtension.lowercased())
    }

    /// A readable title from a file name: "fur_elise-v2.musicxml" → "fur elise v2".
    nonisolated static func title(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    /// Reads a security-scoped MusicXML/MXL file from the Files picker.
    static func read(_ url: URL) throws -> (title: String, musicXML: String) {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(ImportError.unreadable(url.lastPathComponent))
        NSFileCoordinator().coordinate(readingItemAt: url, error: &coordinationError) { readURL in
            result = Result {
                let data = try Data(contentsOf: readURL)
                return try MusicXMLImport.loadString(from: data)
            }
        }
        if coordinationError != nil { throw ImportError.unreadable(url.lastPathComponent) }

        let xml: String
        do { xml = try result.get() } catch { throw ImportError.unreadable(url.lastPathComponent) }
        guard !MusicXMLParser.parse(data: Data(xml.utf8)).notes.isEmpty else {
            throw ImportError.noNotes(url.lastPathComponent)
        }
        return (title(for: url), xml)
    }
}

extension UTType {
    static var musicXML: UTType {
        UTType(filenameExtension: "musicxml") ?? .xml
    }

    static var compressedMusicXML: UTType {
        UTType(filenameExtension: "mxl") ?? .xml
    }
}
