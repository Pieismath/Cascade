//
//  PlayerWalkthroughOverlay.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/25/26.
//

import SwiftUI

// MARK: - Walkthrough Step Definitions

enum WalkthroughStep: Int, CaseIterable {
    case fallingNotes
    case pianoKeyboard
    case speedButtons
    case loopButton
    case handSeparation
    case scrubber
    case listenMode

    var title: String {
        switch self {
        case .fallingNotes:   return "Falling Notes"
        case .pianoKeyboard:  return "Piano Keyboard"
        case .speedButtons:   return "Speed Control"
        case .loopButton:     return "Loop Practice"
        case .handSeparation: return "Hand Separation"
        case .scrubber:       return "Song Timeline"
        case .listenMode:     return "Listen Mode"
        }
    }

    var description: String {
        switch self {
        case .fallingNotes:
            return "Notes fall toward the keyboard showing you exactly what to play and when. Cyan = right hand, orange = left hand."
        case .pianoKeyboard:
            return "Tap the on-screen keys to play along. Connect a MIDI keyboard for a full piano feel."
        case .speedButtons:
            return "Slow down to 0.25x to learn tricky passages note by note, then speed back up when you're ready."
        case .loopButton:
            return "Tap once to loop the current section. Drag the orange handles above the slider to set the exact start and end of your loop."
        case .handSeparation:
            return "Toggle RH and LH to practice each hand in isolation before combining them."
        case .scrubber:
            return "Drag the slider to jump to any point in the song instantly."
        case .listenMode:
            return "Listen mode plays the song without accuracy tracking — great for studying a piece before you start playing."
        }
    }

    var icon: String {
        switch self {
        case .fallingNotes:   return "music.note.list"
        case .pianoKeyboard:  return "pianokeys"
        case .speedButtons:   return "gauge.with.needle"
        case .loopButton:     return "repeat.circle"
        case .handSeparation: return "hand.raised.fingers.spread"
        case .scrubber:       return "slider.horizontal.3"
        case .listenMode:     return "headphones"
        }
    }
}

// MARK: - Frame Preference Key (CGRect-based — no coordinate space mismatch)

struct TutorialFrameKey: PreferenceKey {
    static var defaultValue: [WalkthroughStep: CGRect] = [:]
    static func reduce(
        value: inout [WalkthroughStep: CGRect],
        nextValue: () -> [WalkthroughStep: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Tags a view so the tutorial spotlight knows where it is.
    /// Uses a named coordinate space — call `.coordinateSpace(name: "tutorialRoot")`
    /// on the root container to make coordinates consistent.
    func tutorialFrame(_ step: WalkthroughStep) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TutorialFrameKey.self,
                    value: [step: geo.frame(in: .named("tutorialRoot"))]
                )
            }
        )
    }
}

// MARK: - Spotlight Overlay

/// Drop-in overlay that dims the screen and spotlights one element at a time.
/// All coordinates are in the `.named("tutorialRoot")` coordinate space —
/// the same space the `tutorialFrame()` modifier uses, so nothing is offset.
struct TutorialSpotlightOverlay: View {
    @Binding var isShowing: Bool
    let frames: [WalkthroughStep: CGRect]
    let size: CGSize          // Size of the root container (from its GeometryReader)

    @State private var currentStepIndex: Int = 0

    private var steps: [WalkthroughStep] {
        WalkthroughStep.allCases.filter { frames[$0] != nil }
    }

    private var currentStep: WalkthroughStep? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var body: some View {
        if let step = currentStep, let rect = frames[step] {
            let spotlight = rect.insetBy(dx: -10, dy: -8)
            ZStack {
                // Even-odd fill: the inner rounded rect "punches a hole"
                // in the outer full-screen rect — 100% correct positioning.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRoundedRect(
                        in: spotlight,
                        cornerSize: CGSize(width: 10, height: 10)
                    )
                }
                .fill(style: FillStyle(eoFill: true))
                .foregroundColor(.black.opacity(0.72))
                .contentShape(Rectangle())
                .onTapGesture { advance() }

                // Glowing border around the spotlight
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.accent, lineWidth: 2)
                    .frame(width: spotlight.width, height: spotlight.height)
                    .position(x: spotlight.midX, y: spotlight.midY)
                    .shadow(color: AppTheme.accent.opacity(0.5), radius: 6)

                // Tooltip
                tooltipView(step: step, spotlight: spotlight)
            }
            .animation(.easeInOut(duration: 0.3), value: currentStepIndex)
        }
    }

    // MARK: - Tooltip

    private func tooltipView(step: WalkthroughStep, spotlight: CGRect) -> some View {
        let showAbove = spotlight.midY > size.height * 0.5
        let clampedX = min(max(160, spotlight.midX), size.width - 160)
        let tipY: CGFloat = showAbove
            ? max(70, spotlight.minY - 130)
            : min(size.height - 70, spotlight.maxY + 130)

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: step.icon)
                    .font(.headline)
                    .foregroundColor(AppTheme.accent)
                Text(step.title)
                    .font(.headline).bold()
                    .foregroundColor(.white)
            }

            Text(step.description)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Button("Skip") { withAnimation { isShowing = false } }
                    .font(.caption).bold()
                    .foregroundColor(.white.opacity(0.45))

                Spacer()

                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentStepIndex ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                }

                Spacer()

                Button(currentStepIndex == steps.count - 1 ? "Done!" : "Next →") { advance() }
                    .font(.caption).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .cornerRadius(16)
        .frame(maxWidth: 310)
        .shadow(color: .black.opacity(0.4), radius: 12)
        .position(x: clampedX, y: tipY)
    }

    // MARK: - Navigation

    private func advance() {
        if currentStepIndex == steps.count - 1 {
            withAnimation { isShowing = false }
        } else {
            withAnimation { currentStepIndex += 1 }
        }
    }
}
