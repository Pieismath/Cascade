//
//  PianoKeyboardView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/17/25.
//

import SwiftUI

struct PianoKeyboardView: View {
    let highlightedPitches: Set<Int>
    var midiPressedPitches: Set<Int> = []

    /// Pitches currently being touched on screen
    @Binding var touchedPitches: Set<Int>

    @Environment(ThemeManager.self) var themeManager

    private let whiteKeys = PianoKeyHelper.whiteKeyMIDIs

    init(highlightedPitches: Set<Int>,
         midiPressedPitches: Set<Int> = [],
         touchedPitches: Binding<Set<Int>> = .constant([])) {
        self.highlightedPitches = highlightedPitches
        self.midiPressedPitches = midiPressedPitches
        self._touchedPitches = touchedPitches
    }

    var body: some View {
        GeometryReader { geo in
            let whiteWidth = geo.size.width / CGFloat(whiteKeys.count)
            let blackKeyWidth = whiteWidth * 0.65
            let blackKeyHeight = geo.size.height * 0.65

            ZStack(alignment: .topLeading) {

                // LAYER 1: WHITE KEYS (visual only)
                HStack(spacing: 0) {
                    ForEach(whiteKeys, id: \.self) { pitch in
                        ZStack {
                            let isTouched = touchedPitches.contains(pitch)
                            let isMidi = midiPressedPitches.contains(pitch)
                            let isPlayback = highlightedPitches.contains(pitch)
                            Rectangle()
                                .fill(
                                    isTouched
                                    ? LinearGradient(
                                        colors: [Color.green.opacity(0.7), Color.green.opacity(0.5)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : isMidi
                                    ? LinearGradient(
                                        colors: [Color.green.opacity(0.6), Color.green.opacity(0.5)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : isPlayback
                                    ? LinearGradient(
                                        colors: [themeManager.keyHighlight, themeManager.keyHighlight],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : LinearGradient(
                                        colors: [Color.white, Color(white: 0.95)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            Rectangle()
                                .stroke(Color.black.opacity(0.3), lineWidth: 0.5)

                            // Octave label on C keys
                            if pitch % 12 == 0 {
                                VStack {
                                    Spacer()
                                    Text("C\(pitch / 12 - 1)")
                                        .font(.system(size: 7))
                                        .foregroundColor(.gray.opacity(0.6))
                                        .padding(.bottom, 3)
                                }
                            }
                        }
                        .frame(width: whiteWidth)
                    }
                }

                // LAYER 2: BLACK KEYS (visual only)
                HStack(spacing: 0) {
                    ForEach(whiteKeys.indices, id: \.self) { i in
                        let wPitch = whiteKeys[i]
                        let nextPitch = (i + 1 < whiteKeys.count) ? whiteKeys[i+1] : nil

                        ZStack(alignment: .center) {
                            if let up = nextPitch,
                               PianoKeyHelper.hasBlackKey(between: wPitch, and: up) {
                                let blackPitch = wPitch + 1
                                let isHighlighted = highlightedPitches.contains(blackPitch)
                                let isMidiBlack = midiPressedPitches.contains(blackPitch)
                                let isTouchedBlack = touchedPitches.contains(blackPitch)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        isTouchedBlack
                                        ? LinearGradient(
                                            colors: [Color.green, Color.green.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        : isMidiBlack
                                        ? LinearGradient(
                                            colors: [Color.green, Color.green.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        : isHighlighted
                                        ? LinearGradient(
                                            colors: [themeManager.keyHighlightBlack, themeManager.keyHighlightBlack],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        : LinearGradient(
                                            colors: [Color(white: 0.2), Color.black],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: blackKeyWidth, height: blackKeyHeight)
                                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 2)
                                    .offset(x: whiteWidth / 2)
                                    .zIndex(1)
                            }
                        }
                        .frame(width: whiteWidth, height: geo.size.height, alignment: .top)
                    }
                }

                // LAYER 3: Touch overlay
                PianoTouchOverlay(
                    size: geo.size,
                    whiteKeys: whiteKeys,
                    touchedPitches: $touchedPitches
                )
            }
        }
        .clipped()
    }
}

// MARK: - Touch Overlay (UIKit multi-touch)

/// UIViewRepresentable that handles multi-touch on the keyboard
private struct PianoTouchOverlay: UIViewRepresentable {
    let size: CGSize
    let whiteKeys: [Int]
    @Binding var touchedPitches: Set<Int>

    func makeUIView(context: Context) -> PianoTouchView {
        let view = PianoTouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.whiteKeys = whiteKeys
        view.onTouchesChanged = { pitches in
            DispatchQueue.main.async {
                self.touchedPitches = pitches
            }
        }
        return view
    }

    func updateUIView(_ uiView: PianoTouchView, context: Context) {
        uiView.viewSize = size
        uiView.whiteKeys = whiteKeys
    }
}

private class PianoTouchView: UIView {
    var whiteKeys: [Int] = []
    var viewSize: CGSize = .zero
    var onTouchesChanged: ((Set<Int>) -> Void)?

    private var activePitches: Set<Int> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePitches(event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePitches(event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePitches(event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Stop all touched notes before clearing
        for pitch in activePitches {
            AudioEngineManager.shared.stop(note: pitch)
        }
        activePitches.removeAll()
        onTouchesChanged?(activePitches)
    }

    private func updatePitches(event: UIEvent?) {
        guard whiteKeys.count > 0 else { return }

        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }

        let whiteWidth = size.width / CGFloat(whiteKeys.count)
        let blackKeyWidth = whiteWidth * 0.65
        let blackKeyHeight = size.height * 0.65

        var newPitches = Set<Int>()

        if let allTouches = event?.allTouches {
            for touch in allTouches where touch.phase != .ended && touch.phase != .cancelled {
                let point = touch.location(in: self)
                if let pitch = hitTestPitch(
                    at: point,
                    size: size,
                    whiteWidth: whiteWidth,
                    blackKeyWidth: blackKeyWidth,
                    blackKeyHeight: blackKeyHeight
                ) {
                    newPitches.insert(pitch)
                }
            }
        }

        // Diff: play new notes, stop released notes
        let added = newPitches.subtracting(activePitches)
        let removed = activePitches.subtracting(newPitches)

        for pitch in added {
            AudioEngineManager.shared.play(note: pitch, velocity: 90)
        }
        for pitch in removed {
            AudioEngineManager.shared.stop(note: pitch)
        }

        activePitches = newPitches
        onTouchesChanged?(newPitches)
    }

    private func hitTestPitch(
        at point: CGPoint,
        size: CGSize,
        whiteWidth: CGFloat,
        blackKeyWidth: CGFloat,
        blackKeyHeight: CGFloat
    ) -> Int? {
        // Check black keys FIRST (they're on top)
        if point.y < blackKeyHeight {
            for i in whiteKeys.indices {
                let wPitch = whiteKeys[i]
                let nextPitch = (i + 1 < whiteKeys.count) ? whiteKeys[i + 1] : nil

                if let next = nextPitch,
                   PianoKeyHelper.hasBlackKey(between: wPitch, and: next) {
                    let blackPitch = wPitch + 1
                    let blackCenterX = CGFloat(i + 1) * whiteWidth
                    let blackLeft = blackCenterX - blackKeyWidth / 2
                    let blackRight = blackCenterX + blackKeyWidth / 2

                    if point.x >= blackLeft && point.x <= blackRight {
                        return blackPitch
                    }
                }
            }
        }

        // White keys
        let whiteIndex = Int(point.x / whiteWidth)
        if whiteIndex >= 0 && whiteIndex < whiteKeys.count {
            return whiteKeys[whiteIndex]
        }

        return nil
    }
}

// MARK: - KEY POSITION MAP (shared with FallingNotesView)

extension PianoKeyboardView {
    static func keyPositions(in size: CGSize) -> [Int: CGFloat] {
        let whiteKeys = PianoKeyHelper.whiteKeyMIDIs
        let whiteWidth = size.width / CGFloat(whiteKeys.count)
        var map: [Int: CGFloat] = [:]

        for (i, pitch) in whiteKeys.enumerated() {
            map[pitch] = CGFloat(i) * whiteWidth + whiteWidth / 2
        }

        for i in whiteKeys.indices {
            let wPitch = whiteKeys[i]
            let nextPitch = (i + 1 < whiteKeys.count) ? whiteKeys[i + 1] : nil
            if let next = nextPitch,
               PianoKeyHelper.hasBlackKey(between: wPitch, and: next) {
                let blackPitch = wPitch + 1
                let x = CGFloat(i + 1) * whiteWidth
                map[blackPitch] = x
            }
        }

        return map
    }
}
