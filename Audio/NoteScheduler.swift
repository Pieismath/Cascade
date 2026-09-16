//
//  NoteScheduler.swift
//  MyPianoInstructor
//
//  Created by Jason Fang
//

import Foundation

/// All methods must be called from the main thread (driven by CADisplayLink).
@MainActor
class NoteScheduler {

    private struct AudioEvent: Comparable {
        let time: TimeInterval
        let pitch: Int
        let isNoteOn: Bool

        static func < (lhs: AudioEvent, rhs: AudioEvent) -> Bool {
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            // At the same time: note-ON first, then note-OFF.
            // This ensures chords all start before anything is released,
            // and re-triggered notes sound before the previous instance ends.
            if lhs.isNoteOn != rhs.isNoteOn { return lhs.isNoteOn }
            return lhs.pitch < rhs.pitch
        }
    }

    private var events: [AudioEvent] = []
    private var nextIndex: Int = 0

    // Reference-counted active notes: a pitch stays on until ALL overlapping
    // instances have sent note-off. This prevents one note's off from killing
    // another note on the same pitch that is still being held (e.g. pedal sustain).
    private var activeNoteCounts: [Int: Int] = [:]

    /// Prepare all audio events for the given playback data, starting from `fromTime`.
    func prepare(playback: PlaybackData, fromTime: TimeInterval) {
        cancel()

        let sortedPedals = playback.pedalEvents.sorted { $0.startTime < $1.startTime }
        var allEvents: [AudioEvent] = []

        for note in playback.notes {
            let noteStart = note.startTime

            // Effective end with sustain-pedal extension (shared with export)
            let effectiveEnd = PlaybackData.pedalExtendedEnd(of: note, sortedPedals: sortedPedals)
            // No legatoBuffer — rely on the natural sustain of the SoundFont

            // Skip events that have already fully passed
            if effectiveEnd <= fromTime { continue }

            // Only schedule note-on if it hasn't started yet
            if noteStart >= fromTime {
                allEvents.append(AudioEvent(time: noteStart, pitch: note.pitch, isNoteOn: true))
            } else {
                // Note already started but not ended — play immediately
                allEvents.append(AudioEvent(time: fromTime, pitch: note.pitch, isNoteOn: true))
            }

            allEvents.append(AudioEvent(time: effectiveEnd, pitch: note.pitch, isNoteOn: false))
        }

        events = allEvents.sorted()
        nextIndex = 0
    }

    /// Called every frame by DisplayLinkController. Fires any events up to `currentTime`.
    func update(currentTime: TimeInterval) {
        while nextIndex < events.count {
            let event = events[nextIndex]
            if event.time > currentTime { break }

            if event.isNoteOn {
                let count = activeNoteCounts[event.pitch, default: 0]
                if count == 0 {
                    // First instance of this pitch — send MIDI note-on
                    AudioEngineManager.shared.play(note: event.pitch)
                } else {
                    // Pitch is already active — re-trigger so the new note
                    // gets a fresh attack (e.g. repeated same-pitch notes)
                    AudioEngineManager.shared.stop(note: event.pitch)
                    AudioEngineManager.shared.play(note: event.pitch)
                }
                activeNoteCounts[event.pitch] = count + 1
            } else {
                let count = activeNoteCounts[event.pitch, default: 0]
                let newCount = max(0, count - 1)
                activeNoteCounts[event.pitch] = newCount
                if newCount == 0 {
                    // Last instance released — send MIDI note-off
                    AudioEngineManager.shared.stop(note: event.pitch)
                }
            }
            nextIndex += 1
        }
    }

    func cancel() {
        events.removeAll()
        nextIndex = 0
        for (pitch, count) in activeNoteCounts where count > 0 {
            AudioEngineManager.shared.stop(note: pitch)
        }
        activeNoteCounts.removeAll()
    }
}
