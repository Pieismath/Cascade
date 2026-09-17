//
//  PlaybackData.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/20/25.
//

import Foundation

// Pedal Info (Audio Only)
// Stored separately so we don't stretch the visual notes.
nonisolated struct PedalEvent: Codable, Hashable, Sendable {
    let startTime: TimeInterval
    let isDown: Bool
}

/// All the timing + pitch info needed for playback & visualization
nonisolated struct PlaybackData: Codable, Hashable, Sendable {
    /// Tempo in beats per minute
    let tempo: Double

    /// Total length of the piece in seconds
    let totalDuration: TimeInterval

    /// The sequence of notes in this song
    let notes: [NoteEvent]

    /// The sequence of pedal events (default empty for backwards compatibility)
    var pedalEvents: [PedalEvent] = []
}

extension PlaybackData {
    /// When a note ends while the sustain pedal is held, it keeps ringing until
    /// the next pedal-up. Shared by live playback (NoteScheduler) and offline
    /// audio export so both render the same sustain.
    /// `sortedPedals` must be `pedalEvents` sorted by startTime.
    /// Nonisolated: also called from the offline audio-export render thread.
    nonisolated static func pedalExtendedEnd(of note: NoteEvent, sortedPedals: [PedalEvent]) -> TimeInterval {
        let noteEnd = note.startTime + note.duration
        // Find the last pedal event (up or down) at or before the note's end time.
        guard let lastPedalEvent = sortedPedals.last(where: { $0.startTime <= (noteEnd + 0.05) }),
              lastPedalEvent.isDown else {
            return noteEnd
        }
        // Pedal is genuinely held when the note ends — extend to the next pedal-up
        if let nextUp = sortedPedals.first(where: { $0.startTime > noteEnd && !$0.isDown }) {
            return nextUp.startTime
        }
        return noteEnd + 2.0
    }
}
