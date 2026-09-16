//
//  PracticeSession.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/13/26.
//

import Foundation
import Observation

@Observable class PracticeSession {
    var loopStart: TimeInterval?
    var loopEnd: TimeInterval?
    var notesReached: Int = 0
    var totalNotes: Int = 0

    // Accuracy tracking
    var correctHits: Int = 0
    var totalExpectedNotes: Int = 0
    var missedNotes: Int = 0
    var noteAccuracyResults: [UUID: NoteAccuracyResult] = [:]

    // Consecutive correct notes (in-session streak)
    var consecutiveCorrect: Int = 0
    var bestConsecutive: Int = 0

    var isLooping: Bool {
        loopStart != nil && loopEnd != nil
    }

    var progress: Double {
        guard totalNotes > 0 else { return 0 }
        return Double(notesReached) / Double(totalNotes)
    }

    var accuracy: Double {
        guard totalExpectedNotes > 0 else { return 0 }
        return Double(correctHits) / Double(totalExpectedNotes)
    }

    /// One actionable tip generated from what happened during the session
    var practiceRecommendation: String {
        guard totalExpectedNotes > 0 else {
            return "Try Listen Mode first to learn the melody, then play along."
        }
        if accuracy < 0.5 {
            return "Try slowing to 0.5x speed to get comfortable with the notes."
        }
        if accuracy > 0.85 {
            return "Excellent note recognition! Try a harder song or faster speed next."
        }
        return "Try Listen Mode first next time to learn the melody before playing."
    }

    func recordNoteResult(noteId: UUID, result: NoteAccuracyResult) {
        noteAccuracyResults[noteId] = result
        totalExpectedNotes += 1
        if result == .correct {
            correctHits += 1
            consecutiveCorrect += 1
            if consecutiveCorrect > bestConsecutive { bestConsecutive = consecutiveCorrect }
        } else {
            missedNotes += 1
            consecutiveCorrect = 0
        }
    }

    func reset() {
        notesReached = 0
        correctHits = 0
        totalExpectedNotes = 0
        missedNotes = 0
        noteAccuracyResults.removeAll()
        consecutiveCorrect = 0
        bestConsecutive = 0
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
    }
}

enum NoteAccuracyResult: Equatable {
    case correct
    case missed
    case wrong
}
