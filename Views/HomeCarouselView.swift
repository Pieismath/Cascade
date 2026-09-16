//
//  HomeCarouselView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/22/26.
//

import SwiftUI
import Combine

/// A swipeable widget carousel for the home screen hero section.
/// Shows contextual pages: Welcome, Streak & Stats, Latest Achievement, Last Practiced.
/// Page indicator dots appear on the right side.
struct HomeCarouselView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(PracticeStatsManager.self) var statsManager
    @Environment(AchievementManager.self) var achievementManager
    @Environment(ThemeManager.self) var themeManager

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int
    @Binding var showAbout: Bool

    @State private var currentPage: Int = 0
    @State private var lastManualSwipe: Date = .distantPast

    private let cardHeight: CGFloat = 180

    // Computed page set based on available data
    private var pages: [CarouselPage] {
        var result: [CarouselPage] = [.welcome]

        if statsManager.currentStreak >= 1 || statsManager.sessionsCount > 0 {
            result.append(.streakStats)
        }

        if achievementManager.earnedCount > 0 {
            result.append(.achievement)
        }

        if libraryVM.recentSongs.first != nil {
            result.append(.lastPracticed)
        }

        return result
    }

    var body: some View {
        ZStack {
            // Continuous gradient background
            MeshGradientCard()
                .frame(height: cardHeight)
                .cornerRadius(20)

            // Horizontal swipeable pages (native TabView, dots hidden — we draw our own)
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                    pageContent(for: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Bottom page indicator dots
            if pages.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.white : Color.white.opacity(0.35))
                                .frame(width: index == currentPage ? 8 : 6,
                                       height: index == currentPage ? 8 : 6)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }
                    .padding(.bottom, 10)
                }
                .frame(height: cardHeight)
                .allowsHitTesting(false)
            }
        }
        .frame(height: cardHeight)
        .padding(.horizontal)
        .onReceive(
            Timer.publish(every: 6, on: .main, in: .common).autoconnect()
        ) { _ in
            guard pages.count > 1 else { return }
            guard Date().timeIntervalSince(lastManualSwipe) > 10 else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                currentPage = (currentPage + 1) % pages.count
            }
        }
        .onChange(of: pages.count) { _, newCount in
            // Clamp currentPage so it stays in bounds if pages shrink
            if currentPage >= newCount {
                currentPage = max(0, newCount - 1)
            }
        }
        .onChange(of: currentPage) { _, _ in
            lastManualSwipe = Date()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard carousel, page \(currentPage + 1) of \(pages.count)")
    }

    // MARK: - Page Content Router

    @ViewBuilder
    private func pageContent(for page: CarouselPage) -> some View {
        switch page {
        case .welcome:
            welcomePage
        case .streakStats:
            streakStatsPage
        case .achievement:
            achievementPage
        case .lastPracticed:
            lastPracticedPage
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "pianokeys")
                    .font(.title)
                    .foregroundColor(.white)
                Text("Cascade")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                Spacer()
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.75))
                }
                .accessibilityLabel("About Cascade")
            }

            Text(welcomeSubtitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)

            Spacer(minLength: 0)

            // Mini stat pills (only if user has stats)
            if statsManager.sessionsCount > 0 {
                HStack(spacing: 8) {
                    statPill(icon: "clock.fill", text: statsManager.formattedTotalTime)
                    statPill(icon: "checkmark.circle.fill", text: "\(statsManager.songsCompleted) completed")
                    statPill(icon: "music.note.list", text: "\(libraryVM.songs.count) songs")
                }
            }
        }
        .padding(20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cascade. \(welcomeSubtitle)")
    }

    private var welcomeSubtitle: String {
        if libraryVM.songs.isEmpty {
            return "Turn sheet music into interactive piano lessons"
        }
        if statsManager.sessionsCount > 0 && statsManager.currentStreak == 0 {
            return "Welcome back! Start a session to rebuild your streak"
        }
        if statsManager.sessionsCount == 0 {
            return "You have \(libraryVM.songs.count) song\(libraryVM.songs.count == 1 ? "" : "s") ready to practice!"
        }
        return "Turn sheet music into interactive piano lessons"
    }

    // MARK: - Page 2: Streak & Stats

    private var streakStatsPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            if statsManager.currentStreak >= 1 {
                // Streak display
                HStack(spacing: 10) {
                    PhaseAnimator([1.0, 1.18, 1.0], trigger: statsManager.currentStreak) { scale in
                        Text(streakEmoji)
                            .font(.system(size: 38))
                            .scaleEffect(scale)
                    } animation: { phase in
                        phase > 1.0
                            ? .spring(response: 0.25, dampingFraction: 0.45)
                            : .easeOut(duration: 0.3)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(statsManager.currentStreak)")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .contentTransition(.numericText())
                            Text("day streak")
                                .font(.subheadline).bold()
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Text(streakHeadline)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            } else {
                // No streak but has sessions
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Your Journey")
                            .font(.title3).bold()
                            .foregroundColor(.white)
                    }
                    Text("Practice today to start a new streak!")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Spacer(minLength: 0)

            // 3-stat footer row
            HStack(spacing: 0) {
                statColumn(value: statsManager.formattedTotalTime, label: "Practice Time")
                Spacer()
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 28)
                Spacer()
                statColumn(value: "\(statsManager.sessionsCount)", label: "Sessions")
                Spacer()
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 28)
                Spacer()
                statColumn(value: "\(statsManager.songsCompleted)", label: "Completed")
            }
        }
        .padding(20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statsManager.currentStreak) day streak. \(streakHeadline). Practice time \(statsManager.formattedTotalTime). \(statsManager.sessionsCount) sessions.")
    }

    // MARK: - Page 3: Latest Achievement

    private var achievementPage: some View {
        let latest = achievementManager.achievements
            .filter(\.isEarned)
            .sorted { ($0.dateEarned ?? .distantPast) > ($1.dateEarned ?? .distantPast) }
            .first

        return Button {
            tabSelection = 3
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LATEST ACHIEVEMENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1)

                    if let achievement = latest {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(categoryColor(achievement).opacity(0.35))
                                    .frame(width: 44, height: 44)
                                Image(systemName: achievement.icon)
                                    .font(.title3)
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(achievement.title)
                                    .font(.headline).bold()
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(achievement.description)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(2)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    // Progress bar at bottom
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(achievementManager.earnedCount)/\(achievementManager.totalCount) achievements")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.2))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.8))
                                    .frame(width: geo.size.width * achievementManager.progressFraction, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest achievement: \(latest?.title ?? ""). \(achievementManager.earnedCount) of \(achievementManager.totalCount) achievements earned. Tap to view all.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Page 4: Last Practiced Song

    private var lastPracticedPage: some View {
        let song = libraryVM.recentSongs.first

        return Button {
            if let song {
                selectedSong = song
                tabSelection = 2
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("CONTINUE PRACTICING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1)

                if let song {
                    let playback = libraryVM.cachedPlayback(for: song)
                    let difficulty = DifficultyAnalyzer.analyze(playback: playback)

                    Text(song.title)
                        .font(.title3).bold()
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: difficulty.level.icon)
                                .font(.system(size: 9))
                            Text(difficulty.level.label)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2))
                        .cornerRadius(6)

                        Text(formatDuration(song.durationSeconds))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Text("\(playback.notes.count) notes")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer(minLength: 0)

                    // Mini piano roll preview
                    miniPianoRoll(playback: playback)
                        .frame(height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(20)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Continue practicing: \(song?.title ?? ""). Tap to play.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Mini Waveform Canvas

    /// Draws a clean waveform-style bar visualization bucketed across the song duration.
    private func miniPianoRoll(playback: PlaybackData) -> some View {
        Canvas { context, size in
            let notes = playback.notes
            guard !notes.isEmpty else { return }

            let totalDuration = playback.totalDuration
            guard totalDuration > 0 else { return }

            // Bucket notes into bars
            let barCount = Int(size.width / 3) // ~3pt per bar
            guard barCount > 0 else { return }
            let bucketWidth = totalDuration / Double(barCount)

            // Compute density per bucket (how many notes start in each time slice)
            var buckets = [Int](repeating: 0, count: barCount)
            for note in notes {
                let index = min(barCount - 1, Int(note.startTime / bucketWidth))
                buckets[index] += 1
            }

            let maxDensity = CGFloat(buckets.max() ?? 1)
            let barWidth: CGFloat = max(1.5, (size.width / CGFloat(barCount)) - 1)
            let midY = size.height / 2

            for (i, count) in buckets.enumerated() {
                guard count > 0 else { continue }
                let fraction = CGFloat(count) / maxDensity
                // Height grows from center, min 2pt
                let barHeight = max(2, fraction * (size.height - 4))
                let x = CGFloat(i) / CGFloat(barCount) * size.width
                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                let opacity = 0.4 + fraction * 0.5
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
    }

    // MARK: - Components

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.18))
        .cornerRadius(8)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline).bold()
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Streak Helpers

    private var streakEmoji: String {
        switch statsManager.currentStreak {
        case 1...2: return "🎹"
        case 3...6: return "🔥"
        case 7...13: return "⚡️"
        default:    return "🏆"
        }
    }

    private var streakHeadline: String {
        if statsManager.currentStreak >= 7 { return "You're unstoppable! Keep the momentum going." }
        if statsManager.currentStreak >= 3 { return "\(statsManager.currentStreak) days in a row. Keep it up!" }
        return "You practiced today. Great start!"
    }

    // MARK: - Helpers

    private func categoryColor(_ achievement: Achievement) -> Color {
        switch achievement.category {
        case .practice:   return .indigo
        case .mastery:    return .orange
        case .dedication: return .green
        case .explorer:   return .purple
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Carousel Page Type

private enum CarouselPage: Hashable {
    case welcome
    case streakStats
    case achievement
    case lastPracticed
}
