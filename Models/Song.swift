//  Song.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/17/25.
//

import Foundation

struct Song: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var durationSeconds: Int

    /// Full MusicXML as a UTF-8 string
    var musicXML: String

    /// Tracks when this song was last practiced/played.
    var lastPlayedAt: Date?

    static func mock(title: String, musicXML: String = "") -> Song {
        Song(
            id: UUID(),
            title: title,
            createdAt: Date(),
            durationSeconds: Int.random(in: 60...360),
            musicXML: musicXML,
            lastPlayedAt: nil
        )
    }
}
