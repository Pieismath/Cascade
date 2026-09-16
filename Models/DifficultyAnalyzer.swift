//
//  DifficultyAnalyzer.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import SwiftUI

/// Analyzes a song's playback data and produces a difficulty rating.
/// Factors: note density, pitch range, hand independence, tempo, chord complexity
enum DifficultyAnalyzer {

    enum Level: Int, Comparable, CaseIterable {
        case beginner = 1
        case elementary = 2
        case intermediate = 3
        case advanced = 4
        case expert = 5

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .beginner:     return "Beginner"
            case .elementary:   return "Elementary"
            case .intermediate: return "Intermediate"
            case .advanced:     return "Advanced"
            case .expert:       return "Expert"
            }
        }

        var icon: String {
            switch self {
            case .beginner:     return "leaf.fill"
            case .elementary:   return "star.fill"
            case .intermediate: return "flame.fill"
            case .advanced:     return "bolt.fill"
            case .expert:       return "crown.fill"
            }
        }

        var color: Color {
            switch self {
            case .beginner:     return .green
            case .elementary:   return .teal
            case .intermediate: return .orange
            case .advanced:     return .red
            case .expert:       return .purple
            }
        }

        var stars: Int { rawValue }
    }

    struct Analysis {
        let level: Level
        let score: Double          // 0-100 raw score
        let noteDensity: Double    // notes per second
        let pitchRange: Int        // semitones between lowest and highest note
        let handIndependence: Double // 0-1, how independent the hands are
        let maxChordSize: Int
        let tempo: Double
        let tips: [String]         // practice suggestions
    }

    // MARK: - Analyze

    static func analyze(playback: PlaybackData) -> Analysis {
        let notes = playback.notes
        guard !notes.isEmpty, playback.totalDuration > 0 else {
            return Analysis(level: .beginner, score: 0, noteDensity: 0,
                          pitchRange: 0, handIndependence: 0, maxChordSize: 0,
                          tempo: playback.tempo, tips: ["Import a song to analyze!"])
        }

        let duration = playback.totalDuration

        // 1. Note density (notes per second)
        // A simple scale has ~2 notes/sec, complex pieces have 8+
        let density = Double(notes.count) / duration
        let densityScore: Double
        switch density {
        case 0..<1.5:   densityScore = 2    // very sparse
        case 1.5..<3.0: densityScore = 6    // simple melody
        case 3.0..<5.0: densityScore = 12   // moderate
        case 5.0..<8.0: densityScore = 18   // busy
        default:        densityScore = 25   // very dense
        }

        // 2. Pitch range (semitones between lowest and highest)
        let pitches = notes.map(\.pitch)
        let minPitch = pitches.min() ?? 60
        let maxPitch = pitches.max() ?? 60
        let range = maxPitch - minPitch
        let rangeScore: Double
        switch range {
        case 0..<12:    rangeScore = 2     // within one octave
        case 12..<24:   rangeScore = 6     // two octaves
        case 24..<36:   rangeScore = 12    // three octaves
        default:        rangeScore = 20    // very wide
        }

        // 3. Hand independence (are both hands playing? how rhythmically independent are they?)
        let rhNotes = notes.filter { $0.voice == 1 }
        let lhNotes = notes.filter { $0.voice >= 2 }
        let hasBothHands = !rhNotes.isEmpty && !lhNotes.isEmpty
        let independence: Double
        if !hasBothHands {
            independence = 0.0
        } else {
            let simultaneousCount = countSimultaneousNotes(rh: rhNotes, lh: lhNotes)
            let totalBothHands = min(rhNotes.count, lhNotes.count)
            // overlapRatio → 1.0 means both hands always play at the same time (synchronised, easier).
            // independence → 1.0 means hands play at different times (independent rhythms, harder).
            let overlapRatio = totalBothHands > 0 ? Double(simultaneousCount) / Double(totalBothHands) : 0.0
            independence = 1.0 - overlapRatio
        }
        // Having both hands adds difficulty; high rhythmic independence (hands on different beats) adds more
        let independenceScore = (hasBothHands ? 5.0 : 0.0) + independence * 15.0 // 0-20

        // 4. Chord complexity (max notes at same time)
        let maxChord = findMaxChordSize(notes: notes)
        let chordScore: Double
        switch maxChord {
        case 0...1:  chordScore = 0    // single notes only
        case 2:      chordScore = 4    // occasional doubles
        case 3:      chordScore = 8    // triads
        default:     chordScore = 15   // full chords
        }

        // 5. Tempo
        let tempoScore: Double
        switch playback.tempo {
        case 0..<80:    tempoScore = 2    // slow
        case 80..<120:  tempoScore = 6    // moderate
        case 120..<150: tempoScore = 12   // fast
        default:        tempoScore = 20   // very fast
        }

        let rawScore = densityScore + rangeScore + independenceScore + chordScore + tempoScore

        let level: Level
        switch rawScore {
        case 0..<18:    level = .beginner
        case 18..<32:   level = .elementary
        case 32..<50:   level = .intermediate
        case 50..<70:   level = .advanced
        default:        level = .expert
        }

        // Generate practice tips
        var tips: [String] = []
        if independence > 0.3 {
            tips.append("Try practicing each hand separately using the RH/LH toggles")
        }
        if density > 4.0 {
            tips.append("Slow down to 0.5x speed to learn fast passages")
        }
        if maxChord >= 4 {
            tips.append("Practice chords slowly — use the loop feature on hard sections")
        }
        if range > 36 {
            tips.append("Wide range piece — watch the falling notes to anticipate hand position changes")
        }
        if playback.tempo > 140 {
            tips.append("Fast tempo — start at 0.5x and gradually increase speed")
        }
        if tips.isEmpty {
            tips.append("Great song to practice! Focus on steady rhythm")
        }

        return Analysis(
            level: level,
            score: rawScore,
            noteDensity: density,
            pitchRange: range,
            handIndependence: independence,
            maxChordSize: maxChord,
            tempo: playback.tempo,
            tips: tips
        )
    }

    // MARK: - Helpers

    /// Count how many RH notes have a LH note starting within 50ms (simultaneous)
    private static func countSimultaneousNotes(rh: [NoteEvent], lh: [NoteEvent]) -> Int {
        let threshold: TimeInterval = 0.05
        var count = 0
        var lhIdx = 0

        for rhNote in rh {
            // Advance lhIdx past LH notes that are too early for this RH note
            while lhIdx < lh.count && lh[lhIdx].startTime < rhNote.startTime - threshold {
                lhIdx += 1
            }
            // Check if the first in-range LH note is simultaneous with this RH note
            if lhIdx < lh.count && lh[lhIdx].startTime <= rhNote.startTime + threshold {
                count += 1
            }
        }
        return count
    }

    /// Find the maximum number of notes sounding at the same instant.
    /// Uses 20ms tolerance — tight enough to distinguish arpeggios from chords.
    private static func findMaxChordSize(notes: [NoteEvent]) -> Int {
        guard !notes.isEmpty else { return 0 }

        // Group notes by start time (within 20ms tolerance).
        // Track against the group's first note time, not the previous note,
        // so the window doesn't drift across large arpeggios.
        var maxSize = 1
        var currentCount = 1
        var groupStartTime = notes[0].startTime

        for i in 1..<notes.count {
            if abs(notes[i].startTime - groupStartTime) < 0.02 {
                currentCount += 1
                maxSize = max(maxSize, currentCount)
            } else {
                groupStartTime = notes[i].startTime
                currentCount = 1
            }
        }

        return maxSize
    }
}

// MARK: - Difficulty Badge View

struct DifficultyBadge: View {
    let level: DifficultyAnalyzer.Level

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
                .font(.system(size: 9))
            Text(level.label)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(level.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(level.color.opacity(0.12))
        .cornerRadius(6)
        .accessibilityLabel("Difficulty: \(level.label)")
    }
}

/// Star rating display for difficulty
struct DifficultyStars: View {
    let level: DifficultyAnalyzer.Level

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= level.stars ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundColor(star <= level.stars ? level.color : .gray.opacity(0.3))
            }
        }
        .accessibilityLabel("Difficulty \(level.stars) out of 5 stars")
    }
}
