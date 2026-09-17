//
//  CascadeWordmark.swift
//  MyPianoInstructor
//
//  The wordmark: "Cascade" in the display serif, with notes falling onto its
//  letters and lighting them up the way keys light up in the player.
//

import SwiftUI
import UIKit
import CoreText

struct CascadeWordmark: View {
    var size: CGFloat = 34
    /// Loops the falling notes. Off, or with Reduce Motion, it holds one pose.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false
    @State private var epoch = Date()

    var body: some View {
        let metrics = WordmarkMetrics.at(size)
        Group {
            if animated && !reduceMotion && onScreen && scenePhase == .active {
                TimelineView(.animation) { timeline in
                    WordmarkCanvas(metrics: metrics, time: timeline.date.timeIntervalSince(epoch))
                }
            } else {
                WordmarkCanvas(metrics: metrics, time: WordmarkScore.poseTime)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        // Notes emerge out of nothing instead of being cut off at the top edge.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: metrics.headroom * 0.8 / metrics.height),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .onAppear {
            // Start from the resting pose so appearing never jumps.
            epoch = Date().addingTimeInterval(-WordmarkScore.poseTime)
            onScreen = true
        }
        .onDisappear { onScreen = false }
        .accessibilityElement()
        .accessibilityLabel("Cascade")
        .accessibilityAddTraits(.isHeader)
        // Line up with neighbours by the letters, not the note headroom above them.
        .alignmentGuide(VerticalAlignment.center) { _ in metrics.baseline - metrics.size * 0.36 }
    }
}

// MARK: - Score

/// The little loop the wordmark plays: which letter each note lands on, when,
/// and for how long. Right hand is teal, left hand amber, like the player.
enum WordmarkScore {
    struct Note {
        let letter: Int
        let land: Double
        let length: Double
        let leftHand: Bool
    }

    static let period: Double = 9

    // C0 a1 s2 c3 a4 d5 e6
    static let notes: [Note] = [
        Note(letter: 1, land: 0.00, length: 1.8, leftHand: false),
        Note(letter: 5, land: 0.45, length: 2.1, leftHand: true),
        Note(letter: 3, land: 2.60, length: 0.5, leftHand: false),
        Note(letter: 6, land: 3.30, length: 0.6, leftHand: false),
        Note(letter: 2, land: 4.20, length: 1.4, leftHand: true),
        Note(letter: 0, land: 5.60, length: 0.9, leftHand: false),
        Note(letter: 4, land: 6.80, length: 1.2, leftHand: true),
    ]

    /// A moment where "a" and "d" are both held — the static logo.
    static let poseTime: Double = 1.0
}

// MARK: - Metrics

/// Letter positions measured with the same font `CascadeFont.display` uses,
/// so the per-letter drawing matches a normally set word, kerning included.
struct WordmarkMetrics {
    let size: CGFloat
    let letters: [String]
    /// Left edge of each letter's advance.
    let x: [CGFloat]
    /// Where a note lands: the letter's ink top (y) and stem centre (x).
    let landing: [CGPoint]
    let headroom: CGFloat
    let baseline: CGFloat
    let width: CGFloat
    let height: CGFloat

    var fallSpeed: CGFloat { size * 0.75 }
    var barWidth: CGFloat { max(3, (size * 0.11).rounded()) }

    @MainActor private static var cache: [CGFloat: WordmarkMetrics] = [:]

    @MainActor static func at(_ size: CGFloat) -> WordmarkMetrics {
        if let hit = cache[size] { return hit }
        let made = WordmarkMetrics(size: size)
        cache[size] = made
        return made
    }

    private init(size: CGFloat) {
        self.size = size
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        let word = Array("Cascade")
        letters = word.map(String.init)

        func advance(upTo n: Int) -> CGFloat {
            n == 0 ? 0 : NSAttributedString(string: String(word[0..<n]), attributes: [.font: font]).size().width
        }

        let inset: CGFloat = 2
        headroom = (size * 0.9).rounded()
        baseline = headroom + ceil(font.capHeight) + 3

        var xs: [CGFloat] = []
        var lands: [CGPoint] = []
        let ctFont = font as CTFont
        for (i, ch) in word.enumerated() {
            let left = inset + advance(upTo: i)
            xs.append(left)

            var units = Array(String(ch).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            CTFontGetGlyphsForCharacters(ctFont, &units, &glyphs, units.count)
            var ink = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyphs, &ink, 1)

            // A "d" catches its note on the ascender, not the bowl.
            let stemX = ch == "d" ? ink.maxX - size * 0.075 : ink.midX
            lands.append(CGPoint(x: left + stemX, y: baseline - ink.maxY))
        }
        x = xs
        landing = lands
        width = ceil(inset * 2 + advance(upTo: word.count))
        height = ceil(baseline + size * 0.2)
    }
}

// MARK: - Drawing

private struct WordmarkCanvas: View {
    let metrics: WordmarkMetrics
    let time: TimeInterval

    private static let tealHead = Color(red: 0.78, green: 1.0, blue: 0.97)
    private static let amberHead = Color(red: 1.0, green: 0.90, blue: 0.68)

    var body: some View {
        Canvas { context, _ in
            let m = metrics
            let t = time.truncatingRemainder(dividingBy: WordmarkScore.period)
            var lit = [Double](repeating: 0, count: m.letters.count)
            var litLeft = [Bool](repeating: false, count: m.letters.count)
            let gap: CGFloat = 2

            // Notes: each is checked against this loop and its neighbours so
            // bars and releases carry across the wrap.
            for note in WordmarkScore.notes {
                for cycle in [-1.0, 0, 1] {
                    let since = t - (note.land + cycle * WordmarkScore.period)
                    let land = m.landing[note.letter]
                    let lineY = land.y - gap
                    let lengthPts = CGFloat(note.length) * m.fallSpeed
                    let bottom = lineY + CGFloat(since) * m.fallSpeed
                    let top = bottom - lengthPts
                    let visibleTop = max(top, 0)
                    let visibleBottom = min(bottom, lineY)

                    if visibleBottom - visibleTop > 1 {
                        let rect = CGRect(x: land.x - m.barWidth / 2, y: visibleTop,
                                          width: m.barWidth, height: visibleBottom - visibleTop)
                        let body = note.leftHand ? Brand.amber : Brand.teal
                        let head = note.leftHand ? Self.amberHead : Self.tealHead
                        context.drawLayer { layer in
                            layer.addFilter(.shadow(color: body.opacity(0.8), radius: m.size * 0.14))
                            layer.fill(
                                Path(roundedRect: rect, cornerRadius: m.barWidth / 2),
                                with: .linearGradient(
                                    Gradient(stops: [
                                        .init(color: body.opacity(0.5), location: 0),
                                        .init(color: body, location: 0.6),
                                        .init(color: head, location: 1),
                                    ]),
                                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                        }
                    }

                    // Key light: quick flash on impact, held while the note
                    // sounds, then a short release.
                    let level: Double
                    if since < 0 {
                        level = 0
                    } else if since < note.length {
                        level = 0.82 + 0.18 * exp(-since * 8)
                    } else {
                        level = 0.82 * exp(-(since - note.length) * 7)
                    }
                    if level > lit[note.letter] {
                        lit[note.letter] = level
                        litLeft[note.letter] = note.leftHand
                    }
                }
            }

            // Letters
            let font = CascadeFont.display(m.size)
            for (i, letter) in m.letters.enumerated() {
                var resolved = context.resolve(Text(letter).font(font))
                let size = resolved.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
                // Drawn at a point, not in a rect, so the glow isn't clipped to a box.
                let origin = CGPoint(x: m.x[i], y: m.baseline - resolved.firstBaseline(in: size))
                let level = lit[i]
                if level > 0.01 {
                    let head = litLeft[i] ? Self.amberHead : Self.tealHead
                    let glow = litLeft[i] ? Brand.amber : Brand.teal
                    resolved.shading = .color(Color.white.mix(with: head, by: level))
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: glow.opacity(0.9 * level), radius: m.size * 0.24))
                        layer.draw(resolved, at: origin, anchor: .topLeading)
                    }
                } else {
                    resolved.shading = .color(.white)
                    context.draw(resolved, at: origin, anchor: .topLeading)
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 30) {
        CascadeWordmark()
        CascadeWordmark(size: 26, animated: false)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.ink)
}
