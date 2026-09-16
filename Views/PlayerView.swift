//
//  PlayerView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import SwiftUI
import CoreHaptics
import TipKit

struct PlayerView: View {

    let playback: PlaybackData
    var songTitle: String = ""
    var song: Song? = nil

    @State private var clock = DisplayLinkController()
    @State private var session = PracticeSession()
    @State private var exporter = VideoExportManager()
    @State private var midiInput = MIDIInputManager()

    @State private var scheduler = NoteScheduler()
    @State private var playbackRate: Double = 1.0
    @State private var isDragging = false
    @State private var wasPlayingBeforeDrag = false
    @State private var sessionStartDate = Date()

    // Hand separation
    @State private var showRightHand = true
    @State private var showLeftHand = true

    // Touch keyboard
    @State private var touchedPitches: Set<Int> = []

    // Haptics
    @State private var hapticEngine: CHHapticEngine?
    @State private var lastHapticPitches: Set<Int> = []

    // Celebrations
    @State private var showSongComplete = false
    @State private var showAchievementCelebration = false
    @State private var sessionRecorded = false

    // Export
    @State private var showExportSheet = false
    @State private var showExportError = false
    @State private var exportedVideoURL: URL? = nil

    // Visual feedback
    @State private var keyboardFlashColor: Color? = nil

    // Listen Mode — disables touch input and accuracy tracking so student can watch/listen first
    @State private var listenModeEnabled = false

    // Audio error alert
    @State private var showAudioError = false

    // Tutorial
    @State private var showTutorial = false

    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(PracticeStatsManager.self) var statsManager
    @Environment(AchievementManager.self) var achievementManager

    private let fallLookahead: TimeInterval = 2.5
    private let availableRates: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    // MARK: - Filtered Notes (Hand Separation)

    private var filteredNotes: [NoteEvent] {
        playback.notes.filter { note in
            if note.voice == 1 && !showRightHand { return false }
            if note.voice >= 2 && !showLeftHand { return false }
            return true
        }
    }

    private var filteredPlayback: PlaybackData {
        PlaybackData(
            tempo: playback.tempo,
            totalDuration: playback.totalDuration,
            notes: filteredNotes,
            pedalEvents: playback.pedalEvents
        )
    }

    // Combine all user-input pitches (touch + MIDI)
    private var allUserPitches: Set<Int> {
        touchedPitches.union(midiInput.pressedKeys)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {

                // MARK: Top Bar
                topBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // MARK: Falling Notes
                ZStack(alignment: .top) {
                    FallingNotesView(
                        notes: filteredNotes,
                        currentTime: clock.currentTime,
                        lookahead: fallLookahead
                    )
                    .frame(maxHeight: .infinity)
                    .clipped()
                    // Listen mode banner
                    if listenModeEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "headphones")
                                .font(.caption2)
                            Text("Listen and watch — follow the keys with your eyes")
                                .font(.caption2)
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.blue.opacity(0.55))
                        .cornerRadius(20)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .allowsHitTesting(false)
                    }
                }

                // MARK: Keyboard (tappable)
                PianoKeyboardView(
                    highlightedPitches: highlightedPitches(),
                    midiPressedPitches: allUserPitches,
                    touchedPitches: $touchedPitches
                )
                .frame(height: 90)
                .overlay(
                    Rectangle()
                        .fill(keyboardFlashColor?.opacity(0.28) ?? Color.clear)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.12), value: keyboardFlashColor)
                )
                // In listen mode, block all touch input to the keyboard
                .overlay(
                    listenModeEnabled
                        ? Color.clear.contentShape(Rectangle()).onTapGesture { }
                        : nil
                )
                .disabled(listenModeEnabled)

                // MARK: Scrubber
                scrubberSection
                    .padding(.horizontal)
                    .padding(.top, 1)

                // MARK: Coaching Tips
                TipView(SlowDownTip(), arrowEdge: .bottom)
                    .tipBackground(Color.clear)
                    .padding(.horizontal)

                // MARK: Controls
                controlsRow
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal)
            .ignoresSafeArea(.keyboard)

            // MARK: Note Recognition Streak Badge
            if session.consecutiveCorrect >= 3 && !listenModeEnabled {
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("\(session.consecutiveCorrect)")
                                    .font(.system(size: 26, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .contentTransition(.numericText())
                            }
                            Text("notes found!")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .textCase(.uppercase)
                                .tracking(1)
                            Text("keep finding them")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(streakBadgeColor(session.consecutiveCorrect))
                                .shadow(color: streakBadgeColor(session.consecutiveCorrect).opacity(0.4), radius: 6)
                        )
                    }
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.trailing, 10)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3), value: session.consecutiveCorrect)
                .allowsHitTesting(false)
            }

            // MARK: Song Complete Overlay
            if showSongComplete {
                songCompleteOverlay
                    .transition(.opacity)
            }

            // MARK: Achievement Celebration
            if showAchievementCelebration, let achievement = achievementManager.recentlyUnlocked {
                CelebrationOverlay(achievement: achievement) {
                    showAchievementCelebration = false
                    achievementManager.dismissCelebration()
                }
                .transition(.opacity)
            }

        }
        .onAppear {
            session.totalNotes = playback.notes.count
            sessionStartDate = Date()
            prepareHaptics()

            // Mark this song as the most recently played
            if let song { libraryVM.markSongPlayed(song) }
            clock.onFrame = { [scheduler] time in
                scheduler.update(currentTime: time)
            }

            // Update TipKit parameters
            HandSeparationTip.hasPlayedOnce = true
            SlowDownTip.sessionCount = statsManager.sessionsCount

            // Check for audio engine errors
            if AudioEngineManager.shared.loadError != nil {
                showAudioError = true
            }
        }
        .alert("Audio Error", isPresented: $showAudioError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(AudioEngineManager.shared.loadError ?? "An unknown audio error occurred.")
        }
        .onChange(of: clock.currentTime) { _, newTime in
            // Skip all logic while user is dragging or exporting
            guard !isDragging, !exporter.isExporting else { return }

            // Update notes-reached counter using current filtered notes
            let reached = filteredNotes.prefix(while: { $0.startTime <= newTime }).count
            if reached != session.notesReached {
                session.notesReached = reached
            }

            // Loop logic
            if let loopEnd = session.loopEnd, let loopStart = session.loopStart,
               newTime >= loopEnd, clock.isPlaying {
                _ = clock.pause()
                scheduler.cancel()
                AudioEngineManager.shared.stopAll()
                scheduler.prepare(playback: filteredPlayback, fromTime: loopStart)
                clock.start(fromTime: loopStart, rate: playbackRate)
                return
            }

            if newTime >= playback.totalDuration && clock.isPlaying {
                stop()

                // Record session for the calendar/practice log
                if !sessionRecorded {
                    let elapsed = Int(Date().timeIntervalSince(sessionStartDate))
                    if elapsed > 2 {
                        statsManager.recordSession(durationSeconds: elapsed, songTitle: songTitle)
                    }
                    statsManager.recordSongCompleted()
                    sessionRecorded = true
                }

                // Check speed demon achievement
                if playbackRate >= 2.0 {
                    achievementManager.unlockSpeedDemon()
                }

                // Evaluate achievements
                achievementManager.evaluate(
                    stats: statsManager,
                    songsInLibrary: libraryVM.songs.count,
                    bestAccuracy: session.accuracy
                )

                // Exit listen mode on completion
                listenModeEnabled = false

                // Show completion
                withAnimation(.spring(response: 0.4)) {
                    showSongComplete = true
                }
            }

            // Haptic feedback when new notes start
            fireHapticsForNewNotes()

            // Accuracy: check if user is playing the right notes
            checkAccuracy(at: newTime)

        }
        .onChange(of: showRightHand) { _, _ in restartSchedulerIfPlaying() }
        .onChange(of: showLeftHand) { _, _ in restartSchedulerIfPlaying() }
        .onChange(of: achievementManager.recentlyUnlocked) { _, newVal in
            if newVal != nil {
                withAnimation(.spring(response: 0.5)) {
                    showAchievementCelebration = true
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: session.notesReached)
        .sensoryFeedback(.success, trigger: showSongComplete)
        .onDisappear {
            stop()
        }
        .sheet(isPresented: $showExportSheet) {
            ExportProgressSheet(progress: exporter.exportProgress)
                .interactiveDismissDisabled(exporter.isExporting)
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not export the video. Make sure Piano.sf2 is in the app bundle and try again.")
        }
        .sheet(item: $exportedVideoURL) { url in
            VideoShareSheet(url: url)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showTutorial) {
            PlayerTutorialView(isPresented: $showTutorial)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {

            // Back button
            Button {
                stop()
                if !sessionRecorded {
                    let elapsed = Int(Date().timeIntervalSince(sessionStartDate))
                    if elapsed > 5 {
                        statsManager.recordSession(durationSeconds: elapsed, songTitle: songTitle)
                        achievementManager.evaluate(
                            stats: statsManager,
                            songsInLibrary: libraryVM.songs.count,
                            bestAccuracy: session.accuracy
                        )
                    }
                    sessionRecorded = true
                }
                NotificationCenter.default.post(name: .switchTab, object: 0)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Back to library")

            Text(songTitle.isEmpty ? "Player" : songTitle)
                .font(CascadeFont.display(18))
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(1)

            Spacer()

            // Hand separation toggles
            HStack(spacing: 4) {
                handToggle(label: "RH", color: Brand.teal, isOn: $showRightHand)
                handToggle(label: "LH", color: Brand.amber, isOn: $showLeftHand)
            }

            // MIDI indicator
            if midiInput.isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "pianokeys")
                        .font(.caption)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Brand.surfaceHigh, in: Capsule())
                .accessibilityLabel("MIDI keyboard connected")
            }

            // Notes progress
            Text("\(session.notesReached)/\(filteredNotes.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Brand.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Brand.teal.opacity(0.14), in: Capsule())
                .accessibilityLabel("\(session.notesReached) of \(filteredNotes.count) notes reached")

            // Accuracy ring
            if session.totalExpectedNotes > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: session.accuracy)
                        .stroke(
                            accuracyRingColor(session.accuracy),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: session.accuracy)
                    Text("\(Int(session.accuracy * 100))")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(accuracyRingColor(session.accuracy))
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("Accuracy: \(Int(session.accuracy * 100)) percent")
            }

            // Listen Mode toggle — disables touch so student can watch and absorb the piece first
            Button {
                listenModeEnabled.toggle()
                if listenModeEnabled { touchedPitches.removeAll() }
            } label: {
                Image(systemName: "headphones")
            }
            .buttonStyle(IconButtonStyle(active: listenModeEnabled))
            .accessibilityLabel(listenModeEnabled ? "Listen mode on — touch disabled" : "Listen mode off")

            // Help / tutorial button
            Button {
                showTutorial = true
            } label: {
                Image(systemName: "questionmark")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Show tutorial")

        }
    }

    private func handToggle(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption).bold()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn.wrappedValue ? color.opacity(0.2) : Brand.surfaceHigh, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn.wrappedValue ? color : Brand.hairline, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label == "RH" ? "Right hand" : "Left hand") \(isOn.wrappedValue ? "enabled" : "disabled")")
    }

    // MARK: - Scrubber

    private var scrubberSection: some View {
        VStack(spacing: 2) {

            // Loop region indicator with draggable start/end handles
            if let loopStart = session.loopStart, let loopEnd = session.loopEnd {
                GeometryReader { geo in
                    let width = geo.size.width
                    let duration = max(0.01, playback.totalDuration)
                    let startX = CGFloat(loopStart / duration) * width
                    let endX = CGFloat(loopEnd / duration) * width

                    ZStack(alignment: .leading) {
                        // Loop region fill
                        Capsule()
                            .fill(AppTheme.loopMarker.opacity(0.25))
                            .frame(width: max(0, endX - startX), height: 8)
                            .offset(x: startX)

                        // Start handle
                        Circle()
                            .fill(AppTheme.loopMarker)
                            .frame(width: 16, height: 16)
                            .offset(x: startX - 8)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        guard let currentEnd = session.loopEnd else { return }
                                        let newTime = max(0, min(
                                            currentEnd - 1.0,
                                            Double(drag.location.x / width) * duration
                                        ))
                                        session.loopStart = newTime
                                    }
                            )
                            .accessibilityLabel("Loop start handle")

                        // End handle
                        Circle()
                            .fill(AppTheme.loopMarker)
                            .frame(width: 16, height: 16)
                            .offset(x: endX - 8)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        guard let currentStart = session.loopStart else { return }
                                        let newTime = min(duration, max(
                                            currentStart + 1.0,
                                            Double(drag.location.x / width) * duration
                                        ))
                                        session.loopEnd = newTime
                                    }
                            )
                            .accessibilityLabel("Loop end handle")
                    }
                }
                .frame(height: 16)
            }

            // Main interactive slider with inline time labels
            HStack(spacing: 6) {
                Text(formatTime(clock.currentTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)

                Slider(
                    value: Binding<TimeInterval>(
                        get: { clock.currentTime },
                        set: { newValue in
                            clock.currentTime = newValue
                        }
                    ),
                    in: 0...max(0.01, playback.totalDuration),
                    onEditingChanged: { editing in
                        if editing {
                            wasPlayingBeforeDrag = clock.isPlaying
                            isDragging = true
                            if clock.isPlaying {
                                clock.pause()
                            }
                            clock.isScrubbing = true
                            scheduler.cancel()
                            AudioEngineManager.shared.stopAll()
                        } else {
                            let seekTime = clock.currentTime
                            let shouldResume = wasPlayingBeforeDrag
                            isDragging = false
                            clock.isScrubbing = false
                            wasPlayingBeforeDrag = false
                            if shouldResume {
                                startPlayback(from: seekTime)
                            } else {
                                scheduler.prepare(playback: filteredPlayback, fromTime: seekTime)
                            }
                        }
                    }
                )
                .tint(AppTheme.accent)

                Text(formatTime(playback.totalDuration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .leading)
            }
            .accessibilityLabel("Song position")
            .accessibilityValue("\(formatTime(clock.currentTime)) of \(formatTime(playback.totalDuration))")
        }
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(spacing: 6) {

            // Speed buttons
            HStack(spacing: 4) {
                ForEach(availableRates, id: \.self) { rate in
                    Button {
                        changeSpeed(to: rate)
                    } label: {
                        Text("\(String(format: "%g", rate))x")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundColor(playbackRate == rate ? Brand.ink : Brand.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(playbackRate == rate ? Brand.teal : Brand.surfaceHigh, in: Capsule())
                    }
                    .accessibilityLabel("Speed \(String(format: "%g", rate))x")
                    .accessibilityAddTraits(playbackRate == rate ? .isSelected : [])
                }
            }

            Spacer()

            // Loop toggle
            Button {
                if session.isLooping {
                    session.clearLoop()
                } else {
                    let start = max(0, clock.currentTime - 2)
                    let end = min(playback.totalDuration, clock.currentTime + 8)
                    session.loopStart = start
                    session.loopEnd = end
                }
            } label: {
                Image(systemName: "repeat")
            }
            .buttonStyle(IconButtonStyle(active: session.isLooping, tint: Brand.amber))
            .accessibilityLabel(session.isLooping ? "Loop enabled, tap to disable" : "Enable loop")

            // Play / Pause
            Button(action: togglePlay) {
                ZStack {
                    Circle().fill(.white).frame(width: 46, height: 46)
                    Image(systemName: clock.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Brand.ink)
                        .offset(x: clock.isPlaying ? 0 : 1.5)
                }
                .glow(Brand.teal, radius: 12, opacity: 0.55)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(clock.isPlaying ? "Pause" : "Play")

            // Reset
            Button {
                stop()
                session.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Reset")

            // Export
            Button {
                startExport()
            } label: {
                Image(systemName: "film")
            }
            .buttonStyle(IconButtonStyle(active: exporter.isExporting))
            .disabled(exporter.isExporting)
            .accessibilityLabel("Export video")
        }
    }

    // MARK: - Song Complete Overlay

    private var songCompleteOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismissSongComplete() }

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Song Complete!")
                    .font(.title).bold()
                    .foregroundColor(.white)

                // Accuracy score
                if session.totalExpectedNotes > 0 {
                    Text("Accuracy: \(Int(session.accuracy * 100))%")
                        .font(.title3).bold()
                        .foregroundColor(session.accuracy >= 0.9 ? .green : session.accuracy >= 0.7 ? .orange : .red)
                }

                // Smart practice tip
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.callout)
                    Text(session.practiceRecommendation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.08))
                .cornerRadius(12)
                .padding(.horizontal, 4)

                HStack(spacing: 16) {
                    Button {
                        dismissSongComplete()
                        stop()
                        session.reset()
                        sessionRecorded = false
                        sessionStartDate = Date()
                        startPlayback(from: 0)
                    } label: {
                        Label("Replay", systemImage: "arrow.counterclockwise")
                            .font(.subheadline).bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .cornerRadius(12)
                    }

                    Button {
                        dismissSongComplete()
                        NotificationCenter.default.post(name: .switchTab, object: 0)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.subheadline).bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                }
                .padding(.top, 4)
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(radius: 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Song complete")
    }

    private func dismissSongComplete() {
        withAnimation(.easeOut(duration: 0.2)) {
            showSongComplete = false
        }
    }

    // MARK: - Playback Logic

    private func togglePlay() {
        if clock.isPlaying {
            clock.pause()
            scheduler.cancel()
            AudioEngineManager.shared.stopAll()
        } else {
            startPlayback(from: clock.currentTime)
        }
    }

    private func startPlayback(from time: TimeInterval) {
        isDragging = false
        clock.isScrubbing = false
        scheduler.prepare(playback: filteredPlayback, fromTime: time)
        clock.start(fromTime: time, rate: playbackRate)
    }

    private func stop() {
        isDragging = false
        wasPlayingBeforeDrag = false
        clock.stop()
        scheduler.cancel()
        AudioEngineManager.shared.stopAll()
    }

    private func changeSpeed(to newRate: Double) {
        playbackRate = newRate
        if clock.isPlaying {
            let time = clock.pause()
            scheduler.cancel()
            AudioEngineManager.shared.stopAll()
            scheduler.prepare(playback: filteredPlayback, fromTime: time)
            clock.start(fromTime: time, rate: newRate)
        }
    }

    private func restartSchedulerIfPlaying() {
        if clock.isPlaying {
            let time = clock.pause()
            scheduler.cancel()
            AudioEngineManager.shared.stopAll()
            scheduler.prepare(playback: filteredPlayback, fromTime: time)
            clock.start(fromTime: time, rate: playbackRate)
        }
    }

    // MARK: - Key Highlight (Binary Search)

    private func highlightedPitches() -> Set<Int> {
        let time = clock.currentTime
        let releaseGap: TimeInterval = 0.05
        var active: Set<Int> = []
        let notes = filteredNotes

        if notes.isEmpty { return active }

        let maxDur = notes.reduce(0.0) { max($0, $1.duration) }
        let cutoff = time - maxDur
        var lo = 0, hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].startTime < cutoff {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        for i in lo..<notes.count {
            let n = notes[i]
            if n.startTime > time { break }
            let visualDuration = max(0.02, n.duration - releaseGap)
            if time >= n.startTime && time < (n.startTime + visualDuration) {
                active.insert(n.pitch)
            }
        }

        return active
    }

    // MARK: - Haptic Feedback

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            engine.resetHandler = { [weak engine] in
                try? engine?.start()
            }
            hapticEngine = engine
        } catch {
            print("Haptic engine failed: \(error)")
        }
    }

    private func fireHapticsForNewNotes() {
        let current = highlightedPitches()
        let newNotes = current.subtracting(lastHapticPitches)
        lastHapticPitches = current

        guard !newNotes.isEmpty, let engine = hapticEngine else { return }

        let intensity = min(1.0, Float(newNotes.count) * 0.3)
        let sharpness: Float = 0.4

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently fail — haptics are optional
        }
    }

    // MARK: - Time Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func streakBadgeColor(_ n: Int) -> Color {
        switch n {
        case 3...5:  return .blue
        case 6...9:  return .purple
        case 10...14: return .orange
        default:     return Color(red: 1, green: 0.55, blue: 0)   // gold
        }
    }

    private func accuracyRingColor(_ a: Double) -> Color {
        a >= 0.8 ? .green : a >= 0.5 ? .orange : .red
    }

    // MARK: - Export

    private func startExport() {
        // Stop playback so the audio engine is free and the main thread
        // isn't competing with the display link during video rendering.
        stop()

        let filename = ExportFileNaming.videoFileName(for: songTitle)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outputURL)
        exportedVideoURL = nil
        showExportSheet = true

        exporter.exportVideo(playbackData: playback, outputURL: outputURL) { success in
            showExportSheet = false
            // Give the progress sheet time to dismiss before presenting the
            // share sheet / alert — same-transaction swaps get dropped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if success {
                    exportedVideoURL = outputURL
                } else {
                    showExportError = true
                }
            }
        }
    }

    // MARK: - Accuracy Checking

    private func checkAccuracy(at time: TimeInterval) {
        guard !listenModeEnabled else { return }   // No grading while listening
        let tolerance: TimeInterval = 0.3
        let userPitches = allUserPitches
        let notes = filteredNotes

        // Binary search: find first note whose startTime + tolerance >= time - 0.1
        let windowStart = time - 0.1 - tolerance
        var lo = 0, hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].startTime < windowStart {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        for i in lo..<notes.count {
            let note = notes[i]
            let notePassedTime = note.startTime + tolerance
            // Past the check window — no more notes to evaluate
            if notePassedTime > time { break }
            guard time >= notePassedTime && time < notePassedTime + 0.1 else { continue }
            guard session.noteAccuracyResults[note.id] == nil else { continue }

            if userPitches.contains(note.pitch) {
                session.recordNoteResult(noteId: note.id, result: .correct)
                // Flash the keyboard green on correct note
                withAnimation(.easeIn(duration: 0.05)) { keyboardFlashColor = .green }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.25)) { keyboardFlashColor = nil }
                }
            } else {
                session.recordNoteResult(noteId: note.id, result: .missed)
            }
        }
    }

}
