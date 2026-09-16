//
//  PianoKeyHelper.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 12/2/25.
//

import Foundation

enum PianoKeyHelper {

    // Full MIDI range for an 88-key piano
    static let lowestMIDIPitch = 21
    static let highestMIDIPitch = 108

    // MARK: - White / Black key membership

    static func isWhite(_ midi: Int) -> Bool {
        switch (midi % 12) {
        case 0, 2, 4, 5, 7, 9, 11: return true   // C D E F G A B
        default: return false
        }
    }

    static func isBlack(_ midi: Int) -> Bool {
        !isWhite(midi)
    }

    // MARK: - White Keys List

    static var whiteKeyMIDIs: [Int] {
        (lowestMIDIPitch...highestMIDIPitch).filter { isWhite($0) }
    }

    // MARK: - Black Keys List

    static var blackKeyMIDIs: [Int] {
        (lowestMIDIPitch...highestMIDIPitch).filter { isBlack($0) }
    }

    // MARK: - Cached Index Lookups

    /// Maps each white key MIDI pitch to its index in whiteKeyMIDIs (O(1) lookup)
    static let whiteKeyIndexMap: [Int: Int] = {
        var map = [Int: Int]()
        for (i, pitch) in whiteKeyMIDIs.enumerated() {
            map[pitch] = i
        }
        return map
    }()

    // MARK: - Logic for determining when a black key exists between two whites

    static func hasBlackKey(between lowerWhite: Int, and nextWhite: Int) -> Bool {
        let candidates = (lowerWhite + 1)..<nextWhite
        return candidates.contains { isBlack($0) }
    }
}
