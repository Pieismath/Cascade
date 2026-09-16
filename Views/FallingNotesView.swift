//
//  FallingNotesView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/20/25.
//

import SwiftUI

struct FallingNotesView: View {

    let notes: [NoteEvent]
    let currentTime: TimeInterval
    let lookahead: TimeInterval
    let maxNoteDuration: TimeInterval

    @Environment(ThemeManager.self) var themeManager

    private let noteGap: CGFloat = 4.0
    // Explosion lifetime in seconds (how long particles animate after a note hits)
    private let explosionLifetime: TimeInterval = 0.5

    init(notes: [NoteEvent], currentTime: TimeInterval, lookahead: TimeInterval) {
        self.notes = notes
        self.currentTime = currentTime
        self.lookahead = lookahead
        self.maxNoteDuration = notes.reduce(0) { max($0, $1.duration) }
    }

    var body: some View {
        GeometryReader { geo in

            let whiteKeys = PianoKeyHelper.whiteKeyMIDIs
            let whiteWidth = geo.size.width / CGFloat(whiteKeys.count)
            let height = geo.size.height
            let indexMap = PianoKeyHelper.whiteKeyIndexMap
            let pixelsPerSecond = height / CGFloat(lookahead)

            ZStack {
                // Main falling notes canvas
                TimelineView(.animation(minimumInterval: 1.0/60.0)) { _ in
                    Canvas { context, size in

                        // ---- FALLING NOTES ----
                        let startIdx = binarySearchStartIndex(
                            in: notes,
                            after: currentTime - maxNoteDuration - 0.5
                        )

                        for i in startIdx..<notes.count {
                            let note = notes[i]

                            let timeUntilStart = note.startTime - currentTime
                            if timeUntilStart > lookahead { break }

                            let noteEnd = note.startTime + note.duration
                            let timeUntilEnd = noteEnd - currentTime

                            if timeUntilEnd < -0.5 { continue }

                            let yBottom = height - CGFloat(timeUntilStart) * pixelsPerSecond
                            let yTop    = height - CGFloat(timeUntilEnd)   * pixelsPerSecond

                            let noteHeight = max(4, yBottom - yTop - noteGap)

                            if yBottom <= 0 { continue }

                            let isBlack = PianoKeyHelper.isBlack(note.pitch)
                            let noteWidth: CGFloat
                            let x: CGFloat
                            let color: Color

                            if isBlack {
                                noteWidth = whiteWidth * 0.6
                                color = themeManager.blackKeyNote

                                let lowerWhite = note.pitch - 1
                                if let index = indexMap[lowerWhite] {
                                    x = CGFloat(index + 1) * whiteWidth
                                } else {
                                    x = 0
                                }
                            } else {
                                noteWidth = whiteWidth * 0.9
                                color = note.voice >= 2 ? themeManager.leftHandNote : themeManager.rightHandNote

                                if let index = indexMap[note.pitch] {
                                    x = CGFloat(index) * whiteWidth + whiteWidth / 2
                                } else {
                                    x = 0
                                }
                            }

                            let rect = CGRect(
                                x: x - noteWidth / 2,
                                y: yTop,
                                width: noteWidth,
                                height: noteHeight
                            )

                            let path = Path(roundedRect: rect, cornerRadius: 4)
                            context.fill(path, with: .color(color))
                        }

                        // ---- EXPLOSION PARTICLES (deterministic from currentTime) ----
                        if themeManager.showNoteExplosions {
                            drawExplosions(
                                context: &context,
                                canvasWidth: size.width,
                                canvasHeight: size.height,
                                whiteKeys: whiteKeys,
                                indexMap: indexMap
                            )
                        }
                    }
                }

                // Keyboard line indicator
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(themeManager.keyHighlight.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .clipped()
    }

    // MARK: - Deterministic Explosion Rendering
    // Explosions are computed purely from currentTime so they work both in
    // live playback (TimelineView) and offline export (ImageRenderer).
    // For each note whose startTime is within [currentTime - lifetime, currentTime],
    // we compute the explosion age and draw particles using a seeded random generator
    // keyed on the note index for consistent particle shapes across frames.

    private func drawExplosions(
        context: inout GraphicsContext,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        whiteKeys: [Int],
        indexMap: [Int: Int]
    ) {
        let whiteKeyCount = CGFloat(whiteKeys.count)

        for (i, note) in notes.enumerated() {
            let age = currentTime - note.startTime
            // Only draw explosion if the note just hit (age 0..lifetime)
            guard age >= 0 && age < explosionLifetime else {
                if note.startTime > currentTime { break } // notes sorted by startTime
                continue
            }

            let progress = age / explosionLifetime

            // Compute x position (same logic as falling notes)
            let isBlack = PianoKeyHelper.isBlack(note.pitch)
            let normalizedX: CGFloat

            if isBlack {
                let lowerWhite = note.pitch - 1
                if let index = indexMap[lowerWhite] {
                    normalizedX = CGFloat(index + 1) / whiteKeyCount
                } else { continue }
            } else {
                if let index = indexMap[note.pitch] {
                    normalizedX = (CGFloat(index) + 0.5) / whiteKeyCount
                } else { continue }
            }

            let explosionX = normalizedX * canvasWidth
            let explosionY = canvasHeight - 10

            // Color
            let color: Color
            if isBlack {
                color = themeManager.selectedTheme.blackKeyNoteColor
            } else if note.voice >= 2 {
                color = themeManager.selectedTheme.leftHandColor
            } else {
                color = themeManager.selectedTheme.rightHandColor
            }

            // Generate particles deterministically from note index as seed
            let particleCount = 6 + (i % 5) // 6-10 particles, deterministic
            var rng = SeededRNG(seed: UInt64(i) &* 2654435761)

            for _ in 0..<particleCount {
                let angle = CGFloat(rng.nextDouble()) * 2.0 * .pi - .pi
                let speed = CGFloat(30.0 + rng.nextDouble() * 50.0)
                let pSize = CGFloat(2.0 + rng.nextDouble() * 3.0)
                let pOpacity = 0.6 + rng.nextDouble() * 0.4
                let isCircle = rng.nextDouble() > 0.5

                let opacity = (1.0 - progress) * pOpacity
                let spread = CGFloat(age) * speed
                let px = explosionX + cos(angle) * spread
                let py = explosionY + sin(angle) * spread - CGFloat(age * 30)
                let size = pSize * CGFloat(1.0 - progress * 0.6)

                let pRect = CGRect(x: px - size/2, y: py - size/2, width: size, height: size)
                let pPath: Path
                if isCircle {
                    pPath = Path(ellipseIn: pRect)
                } else {
                    pPath = Path(roundedRect: pRect, cornerRadius: 1)
                }
                context.opacity = opacity
                context.fill(pPath, with: .color(color))
                context.opacity = 1.0
            }
        }
    }

    // MARK: - Binary Search

    private func binarySearchStartIndex(in notes: [NoteEvent], after cutoff: TimeInterval) -> Int {
        var lo = 0, hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].startTime < cutoff {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}

// MARK: - Seeded Random Number Generator
// Produces deterministic random values so that explosion particles
// look the same across frames (and in offline export).

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble() -> Double {
        return Double(next() % 10000) / 10000.0
    }
}
