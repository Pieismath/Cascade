//
//  SongDetailView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/13/26.
//

import SwiftUI

struct SongDetailView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(ThemeManager.self) var themeManager

    let song: Song
    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int

    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    private var playback: PlaybackData {
        libraryVM.cachedPlayback(for: song)
    }

    private var analysis: DifficultyAnalyzer.Analysis {
        DifficultyAnalyzer.analyze(playback: playback)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Header Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(AppTheme.heroGradient)
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .font(.title2).bold()
                            HStack(spacing: 8) {
                                Text(song.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                DifficultyBadge(level: analysis.level)
                            }
                        }
                        Spacer()
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(16)

                // MARK: - Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()),
                    GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 12) {
                    statCard(value: formatDuration(song.durationSeconds), label: "Duration")
                    statCard(value: "\(playback.notes.count)", label: "Notes")
                    statCard(value: "\(Int(playback.tempo))", label: "BPM")
                    statCard(value: "\(playback.pedalEvents.count)", label: "Pedals")
                }

                // MARK: - Difficulty Analysis
                difficultySection

                // MARK: - Practice Tips
                if !analysis.tips.isEmpty {
                    practiceTipsSection
                }

                // MARK: - Mini Piano Roll Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note Distribution")
                        .font(.headline)

                    miniPianoRoll
                        .frame(height: 100)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(12)
                }

                // MARK: - Action Buttons
                VStack(spacing: 12) {
                    Button {
                        selectedSong = song
                        tabSelection = 2
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.accentGradient)
                            .cornerRadius(14)
                    }

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.subheadline).bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Song Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Song?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                libraryVM.deleteSong(song)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \"\(song.title)\" from your library.")
        }
    }

    // MARK: - Difficulty Section

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Difficulty Analysis")
                    .font(.headline)
                Spacer()
                DifficultyStars(level: analysis.level)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 10) {
                difficultyDetail(
                    icon: "metronome.fill",
                    label: "Note Density",
                    value: String(format: "%.1f notes/sec", analysis.noteDensity)
                )
                difficultyDetail(
                    icon: "arrow.up.and.down",
                    label: "Pitch Range",
                    value: "\(analysis.pitchRange) semitones"
                )
                difficultyDetail(
                    icon: "hand.raised.fingers.spread.fill",
                    label: "Hand Independence",
                    value: "\(Int(analysis.handIndependence * 100))%"
                )
                difficultyDetail(
                    icon: "square.stack.3d.up.fill",
                    label: "Max Chord Size",
                    value: "\(analysis.maxChordSize) notes"
                )
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    private func difficultyDetail(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(analysis.level.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption).bold()
            }
            Spacer()
        }
    }

    // MARK: - Practice Tips

    private var practiceTipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Practice Tips")
                    .font(.headline)
            }

            ForEach(analysis.tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.top, 2)
                    Text(tip)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    // MARK: - Components

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3).bold()
                .foregroundColor(AppTheme.accent)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }

    private var miniPianoRoll: some View {
        Canvas { context, size in
            let notes = playback.notes
            guard !notes.isEmpty else { return }

            let totalDuration = playback.totalDuration
            guard totalDuration > 0 else { return }

            let minPitch = notes.map(\.pitch).min() ?? 21
            let maxPitch = notes.map(\.pitch).max() ?? 108
            let pitchRange = max(1, maxPitch - minPitch)

            for note in notes {
                let xStart = CGFloat(note.startTime / totalDuration) * size.width
                let xWidth = max(2, CGFloat(note.duration / totalDuration) * size.width)
                let yPos = size.height - CGFloat(note.pitch - minPitch) / CGFloat(pitchRange) * size.height

                let rect = CGRect(x: xStart, y: yPos - 2, width: xWidth, height: 4)
                let color: Color = note.voice >= 2 ? themeManager.leftHandNote : themeManager.rightHandNote
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
