//
//  SongLibraryView.swift
//  MyPianoInstructor
//
//  Home: a greeting, the piece you're working on as a large piece of score
//  art, quick actions, and the library as a list of art thumbnails.
//

import SwiftUI
import TipKit

struct SongLibraryView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(PracticeStatsManager.self) var statsManager
    @Environment(AchievementManager.self) var achievementManager
    @Environment(ThemeManager.self) var themeManager

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int
    @Binding var showTutorial: Bool

    @State private var showAbout = false
    @State private var tutorialAfterAbout = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                    .padding(.horizontal, 20)

                if let song = libraryVM.recentSongs.first {
                    upNextCard(song)
                        .padding(.horizontal, 20)
                } else {
                    emptyHero
                        .padding(.horizontal, 20)
                }

                quickActions
                    .padding(.horizontal, 20)

                if statsManager.sessionsCount > 0 {
                    momentumStrip
                        .padding(.horizontal, 20)
                }

                if !libraryVM.songs.isEmpty {
                    library
                }

                Spacer(minLength: 24)
            }
            .padding(.top, 8)
        }
        .stageBackground()
        .navigationBarHidden(true)
        .sheet(isPresented: $showAbout, onDismiss: {
            if tutorialAfterAbout {
                tutorialAfterAbout = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showTutorial = true }
            }
        }) {
            AboutCascadeSheet(isPresented: $showAbout, triggerTutorial: $tutorialAfterAbout)
        }
        .alert("Storage Error", isPresented: Binding(
            get: { libraryVM.saveError != nil },
            set: { if !$0 { libraryVM.saveError = nil } }
        )) {
            Button("OK", role: .cancel) { libraryVM.saveError = nil }
        } message: {
            Text(libraryVM.saveError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).eyebrowStyle()
                Text("Cascade")
                    .font(CascadeFont.display(36))
                    .foregroundStyle(Brand.textPrimary)
            }
            Spacer()
            if statsManager.currentStreak > 0 {
                Chip(text: "\(statsManager.currentStreak) day streak", icon: "flame.fill", tint: Brand.amber)
            }
            Button { showAbout = true } label: {
                CascadeIconView(.info, size: 18, color: Brand.textPrimary)
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("About Cascade")
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Night session"
        }
    }

    // MARK: - Up next

    private func upNextCard(_ song: Song) -> some View {
        let playback = libraryVM.cachedPlayback(for: song)
        let difficulty = DifficultyAnalyzer.analyze(playback: playback)

        return Button {
            selectedSong = song
            tabSelection = 2
        } label: {
            ZStack(alignment: .bottomLeading) {
                ScoreArtView(playback: playback, window: 16, cornerRadius: 28)
                    .frame(height: 300)

                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(song.lastPlayedAt == nil ? "Up next" : "Continue practicing")
                        .eyebrowStyle(.white.opacity(0.7))
                    Text(song.title)
                        .font(CascadeFont.display(30))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 8) {
                        Chip(text: difficulty.level.label, icon: difficulty.level.icon, tint: difficulty.level.brandColor, filled: true)
                        Chip(text: formatClock(song.durationSeconds), icon: "clock", tint: .white)
                        Spacer()
                        ZStack {
                            Circle().fill(.white).frame(width: 52, height: 52)
                            CascadeIconView(.play, size: 22, color: Brand.ink)
                                .offset(x: 2)
                        }
                        .glow(Brand.teal, radius: 14, opacity: 0.6)
                    }
                }
                .padding(22)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue practicing \(song.title)")
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScoreArtView(playback: SongLibraryView.demoPlayback, window: 10, cornerRadius: 28)
                .frame(height: 220)
                .overlay(alignment: .topLeading) {
                    Text("Your first piece goes here")
                        .eyebrowStyle(.white.opacity(0.75))
                        .padding(18)
                }
            Text("Sheet music in, falling notes out.")
                .font(CascadeFont.display(28))
                .foregroundStyle(Brand.textPrimary)
            Text("Scan a page, import a file, or grab something from the starter library. It plays here in seconds.")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
            Button {
                tabSelection = 1
            } label: {
                HStack(spacing: 8) { CascadeIconView(.plus, size: 16, color: Brand.ink); Text("Add your first song") }
            }
            .buttonStyle(.cascadePrimary)
        }
    }

    /// A little C-major figure so the empty state still shows real art.
    private static let demoPlayback: PlaybackData = {
        let pitches = [60, 64, 67, 72, 76, 72, 67, 64, 62, 65, 69, 74, 77, 74, 69, 65]
        let lh = [48, 43, 45, 41]
        var notes: [NoteEvent] = []
        for (i, p) in pitches.enumerated() {
            notes.append(NoteEvent(pitch: p, startTime: Double(i) * 0.5, duration: 0.45, voice: 1))
        }
        for (i, p) in lh.enumerated() {
            notes.append(NoteEvent(pitch: p, startTime: Double(i) * 2.0, duration: 1.9, voice: 2))
        }
        return PlaybackData(tempo: 120, totalDuration: 8, notes: notes.sorted { $0.startTime < $1.startTime })
    }()

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction("Scan", glyph: .scan, tint: Brand.teal) { tabSelection = 1 }
            quickAction("Import", glyph: .importFile, tint: Brand.amber) { tabSelection = 1 }
            NavigationLink {
                ThemePickerView().environment(themeManager)
            } label: {
                quickActionLabel("Theme", glyph: .theme, tint: Brand.violet)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize theme, currently \(themeManager.selectedTheme.rawValue)")
            quickAction("Awards", glyph: .award, tint: Brand.coral) { tabSelection = 3 }
        }
    }

    private func quickAction(_ title: String, glyph: CascadeGlyph, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            quickActionLabel(title, glyph: glyph, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func quickActionLabel(_ title: String, glyph: CascadeGlyph, tint: Color) -> some View {
        VStack(spacing: 8) {
            IconBadge(glyph: glyph, tint: tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Brand.hairline, lineWidth: 1))
    }

    // MARK: - Momentum

    private var momentumStrip: some View {
        HStack(spacing: 0) {
            momentum(statsManager.formattedTotalTime, "practiced")
            divider
            momentum("\(statsManager.sessionsCount)", "sessions")
            divider
            momentum("\(statsManager.songsCompleted)", "completed")
            divider
            momentum("\(achievementManager.earnedCount)/\(achievementManager.totalCount)", "awards")
        }
        .cascadeCard(padding: 14, radius: 20)
        .onTapGesture { tabSelection = 3 }
    }

    private var divider: some View {
        Rectangle().fill(Brand.hairline).frame(width: 1, height: 28)
    }

    private func momentum(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(CascadeFont.number(17))
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Library

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Your library", subtitle: "\(libraryVM.songs.count) piece\(libraryVM.songs.count == 1 ? "" : "s")") {
                Button { tabSelection = 1 } label: {
                    CascadeIconView(.plus, size: 18, color: Brand.textPrimary)
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Add music")
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(libraryVM.songs) { song in
                    songRow(song)
                        .scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.75))) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0)
                                .offset(y: phase.isIdentity ? 0 : 16)
                        }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func songRow(_ song: Song) -> some View {
        let playback = libraryVM.cachedPlayback(for: song)
        let difficulty = DifficultyAnalyzer.analyze(playback: playback)

        return Button {
            selectedSong = song
            tabSelection = 2
        } label: {
            HStack(spacing: 14) {
                ScoreArtView(playback: playback, window: 8, cornerRadius: 12)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(difficulty.level.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(difficulty.level.brandColor)
                        Text("·").foregroundStyle(Brand.textTertiary)
                        Text(formatClock(song.durationSeconds))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                        Text("·").foregroundStyle(Brand.textTertiary)
                        Text("\(playback.notes.count) notes")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                CascadeIconView(.play, size: 14, color: Brand.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Brand.surfaceHigh, in: Circle())
            }
            .cascadeCard(padding: 12, radius: 20)
        }
        .buttonStyle(.plain)
        .contextMenu {
            NavigationLink {
                SongDetailView(song: song, selectedSong: $selectedSong, tabSelection: $tabSelection)
                    .environment(libraryVM)
                    .environment(themeManager)
            } label: {
                Label("Details", systemImage: "info.circle")
            }
            Button(role: .destructive) {
                libraryVM.deleteSong(song)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title), \(difficulty.level.label) difficulty, \(formatClock(song.durationSeconds))")
    }
}

// MARK: - About Cascade Sheet

private struct AboutCascadeSheet: View {
    @Binding var isPresented: Bool
    @Binding var triggerTutorial: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyboardStripView(highlighted: [60, 64, 67])
                            .frame(height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Cascade")
                            .font(CascadeFont.display(40))
                            .foregroundStyle(Brand.textPrimary)
                        Text("Sheet music in. Falling notes out.")
                            .font(.headline)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why this exists").eyebrowStyle()
                        Text("Piano lessons cost $50 to $100 an hour. Cascade turns any sheet music into an interactive lesson you can slow down, loop, and play along with, for the price of a coffee or nothing at all.")
                            .font(.body)
                            .foregroundStyle(Brand.textPrimary)
                        Text("Everything except scanning works offline, and your music never leaves your device unless you scan it.")
                            .font(.subheadline)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .cascadeCard(padding: 18)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("New to the player?").eyebrowStyle()
                        Text("Take the 60-second tour: falling notes, speed, looping, and hand separation.")
                            .font(.subheadline)
                            .foregroundStyle(Brand.textSecondary)
                        Button {
                            triggerTutorial = true
                            isPresented = false
                        } label: {
                            Label("Start the tour", systemImage: "play.fill")
                        }
                        .buttonStyle(.cascadePrimary)
                    }
                    .cascadeCard(padding: 18)

                    Text("Made with ♪ · Public-domain starter library · Fluid R3 piano")
                        .font(.caption)
                        .foregroundStyle(Brand.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
            }
            .stageBackground()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }.fontWeight(.semibold)
                }
            }
        }
    }
}
