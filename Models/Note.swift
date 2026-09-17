//
//  Note.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/20/25.
//

import Foundation

/// A single logical note event in the song
nonisolated struct NoteEvent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()

    let pitch: Int
    let startTime: TimeInterval
    let duration: TimeInterval
    var voice: Int = 1   // 1 = right hand (treble), 2 = left hand (bass)
}
