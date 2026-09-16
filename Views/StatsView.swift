//
//  StatsView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/13/26.
//

import SwiftUI
import Charts

struct StatsView: View {
    @Environment(PracticeStatsManager.self) var statsManager
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(AchievementManager.self) var achievementManager
    @Environment(ThemeManager.self) var themeManager
    @Environment(NotificationManager.self) var notificationManager

    @State private var selectedDayString: String? = nil

    // Must match the formatter that writes practice-day keys, or calendar
    // squares stop lining up with recorded days.
    private let dateFormatter = PracticeStatsManager.dayFormatter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Header
                Text("Your Progress")
                    .font(.title).bold()
                    .padding(.top)

                // MARK: - Stats Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 14) {

                    statsCard(
                        icon: "clock.fill",
                        value: statsManager.formattedTotalTime,
                        label: "Practice Time",
                        color: .indigo
                    )

                    statsCard(
                        icon: "flame.fill",
                        value: "\(statsManager.currentStreak)",
                        label: "Day Streak",
                        color: .orange,
                        animateIcon: true
                    )

                    statsCard(
                        icon: "music.note.list",
                        value: "\(libraryVM.songs.count)",
                        label: "Songs",
                        color: .purple
                    )

                    statsCard(
                        icon: "checkmark.circle.fill",
                        value: "\(statsManager.songsCompleted)",
                        label: "Completed",
                        color: .green
                    )

                    statsCard(
                        icon: "play.circle.fill",
                        value: "\(statsManager.sessionsCount)",
                        label: "Sessions",
                        color: .blue
                    )

                    statsCard(
                        icon: "trophy.fill",
                        value: "\(achievementManager.earnedCount)/\(achievementManager.totalCount)",
                        label: "Achievements",
                        color: .orange
                    )
                }

                // MARK: - Personal Best Streak
                if statsManager.longestStreak > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                            .font(.title3)
                            .symbolEffect(.bounce, value: statsManager.longestStreak)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Personal Best Streak")
                                .font(.caption).bold()
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                AnimatedCounter(value: statsManager.longestStreak, font: .title3.bold())
                                Text("days in a row")
                                    .font(.subheadline)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1.5)
                    )
                }

                // MARK: - Practice Timeline Chart
                if !statsManager.recentDailySummaries.filter({ $0.totalSeconds > 0 }).isEmpty {
                    practiceTimeChart
                }

                // MARK: - Recent Achievements
                recentAchievementsSection

                // MARK: - Quick Links
                HStack(spacing: 12) {
                    NavigationLink {
                        AchievementsView()
                            .environment(achievementManager)
                    } label: {
                        quickLinkCard(icon: "trophy.fill", label: "All Achievements", color: .orange)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ThemePickerView()
                            .environment(themeManager)
                    } label: {
                        quickLinkCard(icon: "paintpalette.fill", label: "Customize Theme", color: .purple)
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - Practice Reminders
                practiceRemindersCard

                // MARK: - Practice Calendar
                VStack(alignment: .leading, spacing: 12) {
                    Text("Practice Calendar")
                        .font(.headline)

                    practiceCalendar
                }

                // MARK: - Day Detail (songs practiced)
                if let dayStr = selectedDayString {
                    dayDetailSection(dayStr)
                }

                // MARK: - Motivational Message
                VStack(spacing: 8) {
                    Image(systemName: motivationalIcon)
                        .font(.system(size: 36))
                        .foregroundColor(AppTheme.accent)

                    Text(motivationalMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

                // MARK: - Share Progress
                Button {
                    shareProgressCard()
                } label: {
                    Label("Share My Progress", systemImage: "square.and.arrow.up")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accentGradient)
                        .cornerRadius(14)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal)
        }
        .navigationBarHidden(true)
        .onAppear {
            // Evaluate achievements whenever stats view appears
            achievementManager.evaluate(
                stats: statsManager,
                songsInLibrary: libraryVM.songs.count,
                bestAccuracy: 0
            )
        }
    }

    // MARK: - Recent Achievements

    private var recentAchievementsSection: some View {
        let recent = achievementManager.achievements
            .filter(\.isEarned)
            .sorted { ($0.dateEarned ?? .distantPast) > ($1.dateEarned ?? .distantPast) }
            .prefix(3)

        return Group {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent Achievements")
                            .font(.headline)
                        Spacer()
                        NavigationLink {
                            AchievementsView()
                                .environment(achievementManager)
                        } label: {
                            Text("See All")
                                .font(.caption).bold()
                                .foregroundColor(AppTheme.accent)
                        }
                    }

                    ForEach(Array(recent)) { achievement in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(achievementColor(achievement).opacity(0.2))
                                    .frame(width: 40, height: 40)
                                Image(systemName: achievement.icon)
                                    .foregroundColor(achievementColor(achievement))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(achievement.title)
                                    .font(.subheadline).bold()
                                Text(achievement.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let date = achievement.dateEarned {
                                Text(date, style: .date)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(14)
            }
        }
    }

    private func achievementColor(_ achievement: Achievement) -> Color {
        switch achievement.category {
        case .practice: return .indigo
        case .mastery: return .orange
        case .dedication: return .green
        case .explorer: return .purple
        }
    }

    // MARK: - Quick Link Card

    private func quickLinkCard(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(label)
                .font(.caption).bold()
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    // MARK: - Practice Reminders Card

    private var practiceRemindersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .foregroundColor(.indigo)
                Text("Practice Reminders")
                    .font(.headline)
            }

            Toggle("Daily Reminder", isOn: Binding(
                get: { notificationManager.dailyReminderEnabled },
                set: { newVal in
                    if newVal && !notificationManager.isAuthorized {
                        Task {
                            let granted = await notificationManager.requestPermission()
                            if granted {
                                notificationManager.dailyReminderEnabled = true
                            }
                        }
                    } else {
                        notificationManager.dailyReminderEnabled = newVal
                    }
                }
            ))
            .tint(AppTheme.accent)

            if notificationManager.dailyReminderEnabled {
                HStack {
                    Text("Reminder Time")
                        .font(.subheadline)
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { notificationManager.reminderTime },
                            set: { notificationManager.reminderTime = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    // MARK: - Components

    private func statsCard(icon: String, value: String, label: String, color: Color, animateIcon: Bool = false) -> some View {
        VStack(spacing: 8) {
            HStack {
                if animateIcon {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)
                        .symbolEffect(.variableColor.iterative, isActive: statsManager.currentStreak > 0)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)
                }
                Spacer()
            }

            HStack {
                Text(value)
                    .font(.title2).bold()
                Spacer()
            }

            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Practice Calendar (properly aligned to weekday columns)

    private var practiceCalendar: some View {
        let calendar = Calendar.current
        let today = Date()

        let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        let todayWeekday = calendar.component(.weekday, from: today)
        let daysUntilSaturday = todayWeekday == 7 ? 0 : (7 - todayWeekday)
        let thisSaturday = calendar.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
        let startDate = calendar.date(byAdding: .day, value: -34, to: thisSaturday) ?? today

        let days: [Date] = (0..<35).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startDate)
        }

        return VStack(spacing: 4) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(dayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2).bold()
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { date in
                    let dateStr = dateFormatter.string(from: date)
                    let practiced = statsManager.practiceDays.contains(dateStr)
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = date > today
                    let isSelected = selectedDayString == dateStr

                    Button {
                        if practiced {
                            if selectedDayString == dateStr {
                                selectedDayString = nil
                            } else {
                                selectedDayString = dateStr
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                practiced
                                ? Color.green
                                : isFuture
                                    ? Color.clear
                                    : Color.gray.opacity(0.15)
                            )
                            .frame(height: 32)
                            .overlay(
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.caption2).bold()
                                    .foregroundColor(
                                        practiced ? .white
                                        : isFuture ? .clear
                                        : .secondary
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        isSelected ? AppTheme.accent
                                        : isToday && selectedDayString == nil ? AppTheme.accent
                                        : .clear,
                                        lineWidth: 2.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!practiced)
                    .accessibilityLabel("\(calendar.component(.day, from: date))\(practiced ? ", practiced" : "")\(isToday ? ", today" : "")")
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    // MARK: - Day Detail Section

    private func dayDetailSection(_ dateStr: String) -> some View {
        let entries = statsManager.songsForDay(dateStr)
        let displayDate = readableDate(dateStr)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundColor(.green)
                Text(displayDate)
                    .font(.headline)
                Spacer()
                Button {
                    selectedDayString = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            if entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundColor(.secondary)
                    Text("Practiced this day (no song details recorded)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(entries) { entry in
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.accent.opacity(0.1))
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.songTitle)
                                .font(.subheadline).bold()
                            Text(formatSessionDuration(entry.durationSeconds))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    // MARK: - Helpers

    private func readableDate(_ dateStr: String) -> String {
        guard let date = PracticeStatsManager.dayFormatter.date(from: dateStr) else { return dateStr }

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        return outputFormatter.string(from: date)
    }

    private func formatSessionDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    private var motivationalIcon: String {
        let streak = statsManager.currentStreak
        if streak >= 7 { return "star.fill" }
        if streak >= 3 { return "hand.thumbsup.fill" }
        if streak >= 1 { return "music.note" }
        return "pianokeys"
    }

    private var motivationalMessage: String {
        let streak = statsManager.currentStreak
        if streak >= 7 { return "Amazing! \(streak)-day streak! You're a dedicated pianist!" }
        if streak >= 3 { return "Great job! \(streak) days in a row. Keep it up!" }
        if streak >= 1 { return "Nice! You practiced today. Consistency is key!" }
        return "Start a practice session to begin your journey!"
    }

    // MARK: - Animated Counter

    private struct AnimatedCounter: View {
        let value: Int
        let font: Font
        @State private var displayed: Int = 0

        var body: some View {
            Text("\(displayed)")
                .font(font)
                .contentTransition(.numericText())
                .onAppear {
                    withAnimation(.easeOut(duration: 1.0)) { displayed = value }
                }
                .onChange(of: value) { _, n in
                    withAnimation(.easeOut(duration: 0.6)) { displayed = n }
                }
        }
    }

    // MARK: - Practice Time Chart

    private var practiceTimeChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Practice Time (14 days)")
                .font(.headline)

            Chart(statsManager.recentDailySummaries) { summary in
                BarMark(
                    x: .value("Date", shortDateLabel(summary.date)),
                    y: .value("Minutes", Double(summary.totalSeconds) / 60.0)
                )
                .foregroundStyle(AppTheme.accentGradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { AxisValueLabel().font(.system(size: 9)) }
            }
            .chartYAxisLabel("min")
            .frame(height: 130)
            .animation(.easeOut(duration: 0.8), value: statsManager.recentDailySummaries.map(\.totalSeconds))
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    private func shortDateLabel(_ dateStr: String) -> String {
        guard let d = PracticeStatsManager.dayFormatter.date(from: dateStr) else { return dateStr }
        let o = DateFormatter()
        o.dateFormat = "M/d"
        return o.string(from: d)
    }

    // MARK: - Share Progress Card

    @MainActor
    private func shareProgressCard() {
        let card = ProgressShareCard(
            streak: statsManager.currentStreak,
            totalTime: statsManager.formattedTotalTime,
            songsCompleted: statsManager.songsCompleted,
            achievementsEarned: achievementManager.earnedCount
        )
        let renderer = ImageRenderer(content: card)
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        renderer.scale = scene?.screen.scale ?? 3.0
        guard let image = renderer.uiImage else { return }
        let vc = UIActivityViewController(
            activityItems: [image, "I've been learning piano with Cascade! 🎹"],
            applicationActivities: nil
        )
        if let root = scene?.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }
}
