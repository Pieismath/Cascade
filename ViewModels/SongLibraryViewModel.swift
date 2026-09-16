//
//  SongLibraryViewModel.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/17/25.
//
import SwiftUI
import Observation

@MainActor
@Observable class SongLibraryViewModel {
    var songs: [Song] = []

    // Parsed playback data for each song id. A pure derived cache — kept out of
    // observation because cachedPlayback(for:) populates it during view body
    // evaluation, and observable writes there trigger needless re-renders.
    @ObservationIgnored private var playbackDataBySongID: [UUID: PlaybackData] = [:]

    /// Set when a disk save or load fails; observe in SwiftUI views to show an alert.
    var saveError: String? = nil

    private let storageURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("songs.json")
    }()

    private let saveQueue = DispatchQueue(label: "com.mypianoinstructor.save", qos: .utility)

    init() {
        load()
    }

    func addSong(title: String, musicXML: String) -> Song {
        let playback = MusicXMLParser.parse(data: Data(musicXML.utf8))
        let newSong = Song(
            id: UUID(),
            title: title,
            createdAt: Date(),
            durationSeconds: Int(playback.totalDuration),
            musicXML: musicXML
        )
        songs.append(newSong)
        save()
        return newSong
    }

    func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        playbackDataBySongID.removeValue(forKey: song.id)
        save()
    }

    /// Refresh an existing song's MusicXML (e.g. when re-importing a bundled demo).
    /// Re-parses duration and clears the playback cache so the next access is fresh.
    func updateSong(_ song: Song, musicXML: String) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        let playback = MusicXMLParser.parse(data: Data(musicXML.utf8))
        songs[index].musicXML = musicXML
        songs[index].durationSeconds = Int(playback.totalDuration)
        playbackDataBySongID.removeValue(forKey: song.id)
        save()
    }

    func deleteSong(at offsets: IndexSet) {
        let toDelete = offsets.map { songs[$0] }
        for song in toDelete {
            playbackDataBySongID.removeValue(forKey: song.id)
        }
        songs.remove(atOffsets: offsets)
        save()
    }

    var recentSongs: [Song] {
        let played = songs.filter { $0.lastPlayedAt != nil }
        if played.isEmpty {
            // Fallback: no songs have been played yet, sort by creation date
            return Array(
                songs.sorted { $0.createdAt > $1.createdAt }
                    .prefix(5)
            )
        }
        return Array(
            played
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
                .prefix(5)
        )
    }

    /// Mark a song as just-played and persist the change.
    func markSongPlayed(_ song: Song) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[index].lastPlayedAt = Date()
        save()
    }

    func setPlaybackData(_ data: PlaybackData, for song: Song) {
        playbackDataBySongID[song.id] = data
    }

    func playbackData(for song: Song?) -> PlaybackData? {
        guard let song else { return nil }
        return playbackDataBySongID[song.id]
    }

    /// Returns cached PlaybackData for a song, parsing and caching if needed.
    func cachedPlayback(for song: Song) -> PlaybackData {
        if let cached = playbackDataBySongID[song.id] {
            return cached
        }
        let data: PlaybackData
        if let xmlData = song.musicXML.data(using: .utf8) {
            data = MusicXMLParser.parse(data: xmlData)
        } else {
            data = PlaybackData(tempo: 120, totalDuration: 0, notes: [])
        }
        playbackDataBySongID[song.id] = data
        return data
    }

    // MARK: - Persistence

    private func save() {
        let snapshot = songs
        let url = storageURL
        saveQueue.async { [weak self] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                let msg = "Could not save your songs: \(error.localizedDescription)"
                print(msg)
                DispatchQueue.main.async { self?.saveError = msg }
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            songs = try JSONDecoder().decode([Song].self, from: data)
        } catch {
            let msg = "Could not load your songs: \(error.localizedDescription)"
            print(msg)
            saveError = msg
        }
    }
}
