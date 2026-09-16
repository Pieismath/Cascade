//
//  PlayerTutorialView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/25/26.
//

import SwiftUI

/// A standalone fullscreen demo of the Player interface.
/// Shows an animated preview of falling notes + keyboard, then walks the user
/// through each feature with a spotlight tutorial.
/// Presented as a `.fullScreenCover` and forces landscape orientation.
struct PlayerTutorialView: View {
    @Binding var isPresented: Bool
    @Environment(ThemeManager.self) var themeManager

    @AppStorage("hasSeenPlayerWalkthrough") private var hasSeenWalkthrough = false

    @State private var frames: [WalkthroughStep: CGRect] = [:]
    @State private var showSpotlight = false
    @State private var demoStartDate = Date()

    // MARK: - Demo Content

    private static let loopDuration: TimeInterval = 6.2

    /// C major scale RH + simple LH chords — pure demo, never plays audio.
    private static let demoNotes: [NoteEvent] = {
        // Right hand: C major scale up and back down (voice 1)
        let rhPitches = [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60]
        let rh = rhPitches.enumerated().map { i, p in
            NoteEvent(pitch: p, startTime: Double(i) * 0.38, duration: 0.33, voice: 1)
        }
        // Left hand: broken chords (voice 2)
        let lhData: [(Int, Double, Double)] = [
            (48, 0.0, 1.4), (52, 0.0, 1.4), (55, 0.0, 1.4),
            (45, 1.5, 1.4), (48, 1.5, 1.4), (52, 1.5, 1.4),
            (43, 3.0, 1.4), (47, 3.0, 1.4), (50, 3.0, 1.4),
            (41, 4.5, 1.4), (45, 4.5, 1.4), (48, 4.5, 1.4)
        ]
        let lh = lhData.map { (p, t, dur) in NoteEvent(pitch: p, startTime: t, duration: dur, voice: 2) }
        return (rh + lh).sorted { $0.startTime < $1.startTime }
    }()

    private func highlightedKeys(at time: Double) -> Set<Int> {
        var active: Set<Int> = []
        for note in Self.demoNotes {
            let end = note.startTime + max(0.02, note.duration - 0.05)
            if time >= note.startTime && time < end {
                active.insert(note.pitch)
            }
        }
        return active
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let elapsed = context.date.timeIntervalSince(demoStartDate)
                let looped = elapsed.truncatingRemainder(dividingBy: Self.loopDuration)

                ZStack {
                    // Dark neutral background (avoids theme conflicts)
                    Color(uiColor: .systemBackground).ignoresSafeArea()

                    // Demo player layout — mirrors PlayerView's VStack
                    VStack(spacing: 0) {
                        demoTopBar
                            .padding(.horizontal)
                            .padding(.top, 8)

                        FallingNotesView(
                            notes: Self.demoNotes,
                            currentTime: looped,
                            lookahead: 2.5
                        )
                        .frame(maxHeight: .infinity)
                        .clipped()
                        .tutorialFrame(.fallingNotes)

                        PianoKeyboardView(
                            highlightedPitches: highlightedKeys(at: looped),
                            midiPressedPitches: [],
                            touchedPitches: .constant([])
                        )
                        .frame(height: 90)
                        .disabled(true)
                        .tutorialFrame(.pianoKeyboard)

                        demoScrubber(time: looped)
                            .padding(.horizontal)
                            .padding(.top, 1)
                            .tutorialFrame(.scrubber)

                        demoControlsRow
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                    }
                    .padding(.horizontal)

                    // Initial choice card (shown before the spotlight starts)
                    if !showSpotlight {
                        choiceOverlay
                    }

                    // Step-by-step spotlight walkthrough
                    if showSpotlight {
                        TutorialSpotlightOverlay(
                            isShowing: $showSpotlight,
                            frames: frames,
                            size: geo.size
                        )
                        .onChange(of: showSpotlight) { _, newVal in
                            if !newVal {
                                hasSeenWalkthrough = true
                                isPresented = false
                            }
                        }
                    }
                }
                .coordinateSpace(name: "tutorialRoot")
                .onPreferenceChange(TutorialFrameKey.self) { newFrames in
                    frames = newFrames
                }
            }
        }
        .landscapeOnly()
        .ignoresSafeArea()
        .onAppear { demoStartDate = Date() }
    }

    // MARK: - Demo Top Bar

    private var demoTopBar: some View {
        HStack(spacing: 8) {

            // Close button
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Close tutorial")

            Text("Player Tutorial")
                .font(.headline).bold()
                .lineLimit(1)

            Spacer()

            // Hand separation toggles
            HStack(spacing: 4) {
                demoHandToggle("RH", color: .cyan)
                demoHandToggle("LH", color: .orange)
            }
            .tutorialFrame(.handSeparation)

            // Notes counter (static)
            Text("8/48")
                .font(.caption).bold()
                .foregroundColor(AppTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppTheme.cardBackground)
                .cornerRadius(8)

            // Listen mode button
            Image(systemName: "headphones.circle")
                .font(.caption)
                .foregroundColor(.secondary)
                .tutorialFrame(.listenMode)
        }
    }

    private func demoHandToggle(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).bold()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.2))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 1.5))
        .foregroundColor(.primary)
    }

    // MARK: - Demo Scrubber

    private func demoScrubber(time: Double) -> some View {
        HStack(spacing: 6) {
            Text(formatTime(time))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .trailing)

            // Fake animated progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(
                            width: max(0, geo.size.width * CGFloat(time / Self.loopDuration)),
                            height: 4
                        )
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 14, height: 14)
                        .offset(
                            x: max(0, geo.size.width * CGFloat(time / Self.loopDuration)) - 7
                        )
                }
                .frame(height: 14)
                .padding(.vertical, 10)
            }

            Text(formatTime(Self.loopDuration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)
        }
        .frame(height: 34)
    }

    // MARK: - Demo Controls Row

    private var demoControlsRow: some View {
        HStack(spacing: 6) {
            // Speed buttons
            HStack(spacing: 4) {
                ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Text("\(String(format: "%g", rate))x")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(rate == 1.0 ? .white : .primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(rate == 1.0 ? AppTheme.accent : AppTheme.cardBackground)
                        .cornerRadius(6)
                }
            }
            .tutorialFrame(.speedButtons)

            Spacer()

            // Loop button
            Image(systemName: "repeat.circle")
                .font(.title3)
                .foregroundColor(.secondary)
                .tutorialFrame(.loopButton)

            // Play button (static)
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundColor(AppTheme.accent)

            // Reset button
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.title3)
                .foregroundColor(.secondary)

            // Export button
            Image(systemName: "square.and.arrow.up")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Initial Choice Overlay

    private var choiceOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 44))
                    .foregroundColor(AppTheme.accent)

                Text("Learn the Player")
                    .font(.title2).bold()
                    .foregroundColor(.white)

                Text("Take a quick tour to see how falling notes, speed control, looping, and hand separation work.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                HStack(spacing: 14) {
                    Button("Maybe Later") { dismiss() }
                        .font(.subheadline).bold()
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(14)

                    Button("Start Tour") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSpotlight = true
                        }
                    }
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppTheme.accent)
                    .cornerRadius(14)
                }
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.35), radius: 30)
        }
    }

    // MARK: - Helpers

    private func dismiss() {
        hasSeenWalkthrough = true
        isPresented = false
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
