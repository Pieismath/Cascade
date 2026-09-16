//
//  SongLibraryView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/17/25.
//
import SwiftUI
import TipKit

struct SongLibraryView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(PracticeStatsManager.self) var statsManager
    @Environment(ThemeManager.self) var themeManager

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int
    @Binding var showTutorial: Bool

    @State private var showAbout = false
    @State private var tutorialAfterAbout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Hero Carousel
                HomeCarouselView(selectedSong: $selectedSong, tabSelection: $tabSelection, showAbout: $showAbout)

                // MARK: - Continue Practicing
                if let lastSong = libraryVM.recentSongs.first {
                    continuePracticingCard(lastSong)
                        .padding(.horizontal)
                }

                // MARK: - Quick Actions
                HStack(spacing: 12) {
                    quickActionButton(
                        icon: "doc.badge.plus",
                        label: "Import",
                        color: .indigo
                    ) {
                        tabSelection = 1
                    }

                    quickActionButton(
                        icon: "trophy.fill",
                        label: "Achievements",
                        color: .orange
                    ) {
                        tabSelection = 3
                    }

                    // Theme shortcut with live color preview
                    NavigationLink {
                        ThemePickerView()
                            .environment(themeManager)
                    } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Circle().fill(themeManager.effectiveRightHand).frame(width: 8, height: 8)
                                Circle().fill(themeManager.effectiveLeftHand).frame(width: 8, height: 8)
                                Circle().fill(themeManager.effectiveBlackKey).frame(width: 8, height: 8)
                            }
                            Text("Theme")
                                .font(.caption).bold()
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Customize theme, currently \(themeManager.selectedTheme.rawValue)")
                }
                .padding(.horizontal)

                // MARK: - Coaching Tip
                TipView(ImportSongTip())
                    .tipBackground(AppTheme.cardBackground)
                    .padding(.horizontal)

                // MARK: - Songs List
                if libraryVM.songs.isEmpty {
                    emptyStateView
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Your Songs")
                                .font(.title3).bold()
                            Spacer()
                            Text("\(libraryVM.songs.count) song\(libraryVM.songs.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        ForEach(libraryVM.songs) { song in
                            songCard(song)
                                .scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.75))) { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1.0 : 0.0)
                                        .offset(x: phase.isIdentity ? 0 : 24)
                                        .scaleEffect(phase.isIdentity ? 1.0 : 0.96, anchor: .trailing)
                                }
                        }
                    }
                }
            }
            .padding(.top)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showAbout, onDismiss: {
            if tutorialAfterAbout {
                tutorialAfterAbout = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showTutorial = true
                }
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

    // MARK: - Components

    private func quickActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption).bold()
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.cardBackground)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 100, height: 100)
                    .background {
                        MeshGradientCard()
                            .clipShape(Circle())
                    }
                Image(systemName: "pianokeys.rectangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, isActive: true)
            }

            Text("Your Piano Journey Starts Here")
                .font(.title3).bold()
                .multilineTextAlignment(.center)

            Text("Add a free song from the Starter Library — no internet needed.\nNo piano at home? Practice right on screen.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                tabSelection = 1
            } label: {
                Label("Browse Free Songs", systemImage: "music.note.list")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.accentGradient)
                    .cornerRadius(14)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal)
    }

    private func songCard(_ song: Song) -> some View {
        let playback = libraryVM.cachedPlayback(for: song)
        let difficulty = DifficultyAnalyzer.analyze(playback: playback)
        let accent = difficulty.level.color

        return Button {
            selectedSong = song
            tabSelection = 2
        } label: {
            HStack(spacing: 0) {
                // Difficulty accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 10)
                    .padding(.trailing, 12)

                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundColor(accent)
                }
                .padding(.trailing, 12)

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.subheadline).bold()
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        DifficultyBadge(level: difficulty.level)
                        Text(formatDuration(song.durationSeconds))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .contextMenu {
            Button(role: .destructive) {
                libraryVM.deleteSong(song)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title), \(difficulty.level.label) difficulty, \(formatDuration(song.durationSeconds))")
    }

    // MARK: - Continue Practicing Card

    private func continuePracticingCard(_ song: Song) -> some View {
        Button {
            selectedSong = song
            tabSelection = 2
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(AppTheme.accent)
                    .symbolEffect(.pulse, isActive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue Practicing")
                        .font(.caption).bold()
                        .foregroundColor(.secondary)
                    Text(song.title)
                        .font(.subheadline).bold()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(AppTheme.accent.opacity(0.08))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue practicing \(song.title)")
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - About Cascade Sheet

private struct AboutCascadeSheet: View {
    @Binding var isPresented: Bool
    @Binding var triggerTutorial: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // App icon + name
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.clear)
                                .frame(width: 88, height: 88)
                                .background {
                                    MeshGradientCard()
                                        .clipShape(Circle())
                                }
                            Image(systemName: "pianokeys.rectangle.fill")
                                .font(.system(size: 38))
                                .foregroundColor(.white)
                        }

                        Text("Cascade")
                            .font(.title).bold()

                        Text("Your Piano Instructor")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    // Mission
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Our Mission", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundColor(AppTheme.accent)

                        Text("Piano lessons cost $50 to $100 an hour, putting real music education out of reach for most people. Cascade was built to change that.")
                            .font(.body)
                            .foregroundColor(.primary)

                        Text("Import any MusicXML file and it becomes an interactive falling-note lesson. Slow it down, loop a tricky section, or practice one hand at a time. Free, and no internet needed.")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("Beginner or returning player, Cascade meets you where you are.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(18)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(16)

                    // Tutorial CTA
                    VStack(spacing: 10) {
                        Label("New to the Player?", systemImage: "graduationcap.fill")
                            .font(.headline)

                        Text("Take a quick interactive tour to see how falling notes, speed control, looping, and hand separation all work.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            triggerTutorial = true
                            isPresented = false
                        } label: {
                            Label("Start Player Tour", systemImage: "play.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.accentGradient)
                                .cornerRadius(14)
                        }
                    }
                    .padding(18)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(16)

                    // Footer
                    Text("Made with ♪ for the Swift Student Challenge 2026")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("About Cascade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
