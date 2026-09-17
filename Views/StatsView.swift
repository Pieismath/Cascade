//
//  StatsView.swift
//  MyPianoInstructor
//
//  Progress: three visuals instead of a grid of boxes — the streak, a
//  fortnight of practice time, and a five-week heat calendar — then awards,
//  reminders, and sharing.
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

    // Must match the formatter that writes practice-day keys.
    private let dateFormatter = PracticeStatsManager.dayFormatter

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                header
                streakHero
                timeCard
                calendarCard
                if let day = selectedDayString {
                    dayDetail(day)
                }
                awardsStrip
                remindersRow
                Button { shareProgressCard() } label: {
                    HStack(spacing: 8) { CascadeIconView(.share, size: 16, color: Brand.textPrimary); Text("Share my progress") }
                }
                .buttonStyle(.cascadeSecondary)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .stageBackground()
        .navigationBarHidden(true)
        .onAppear {
            achievementManager.evaluate(stats: statsManager, songsInLibrary: libraryVM.songs.count, bestAccuracy: 0)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(statsManager.currentStreak > 0 ? "Keep it going" : "Every day counts").eyebrowStyle()
                Text("Progress")
                    .font(CascadeFont.display(36))
                    .foregroundStyle(Brand.textPrimary)
            }
            Spacer()
            NavigationLink {
                AchievementsView().environment(achievementManager)
            } label: {
                CascadeIconView(.award, size: 18, color: Brand.textPrimary)
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("All awards")
        }
        .padding(.top, 8)
    }

    // MARK: - 1. Streak

    private var streakHero: some View {
        let streak = statsManager.currentStreak
        let week = lastSevenDays()
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(streak)")
                        .font(CascadeFont.number(72))
                        .foregroundStyle(Brand.textPrimary)
                        .contentTransition(.numericText())
                    Text("day streak")
                        .font(CascadeFont.display(22))
                        .foregroundStyle(Brand.textSecondary)
                }
                Text(streakLine)
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)

                // Last seven days
                HStack(spacing: 8) {
                    ForEach(week, id: \.key) { day in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(day.practiced ? Brand.amber : Brand.surfaceHigh)
                                    .frame(width: 30, height: 30)
                                if day.practiced {
                                    CascadeIconView(.check, size: 13, color: Brand.ink, weight: 2.6)
                                }
                                if day.isToday {
                                    Circle().strokeBorder(Brand.amber, lineWidth: 2).frame(width: 36, height: 36)
                                }
                            }
                            .frame(width: 36, height: 36)
                            Text(day.label)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(day.isToday ? Brand.textPrimary : Brand.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Brand.surface
                    RadialGradient(colors: [Brand.amber.opacity(streak > 0 ? 0.28 : 0.08), .clear],
                                   center: .init(x: 0.92, y: 0.12), startRadius: 0, endRadius: 260)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Brand.hairline, lineWidth: 1))

            CascadeIconView(.flame, size: 64, color: Brand.amber.opacity(streak > 0 ? 1 : 0.22))
                .glow(Brand.amber, radius: 22, opacity: streak > 0 ? 0.7 : 0)
                .padding(20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streak) day streak. \(streakLine)")
    }

    private var streakLine: String {
        let s = statsManager.currentStreak
        let best = statsManager.longestStreak
        if s == 0 { return "Practice today to start a streak." }
        if s >= best && best > 1 { return "Your best ever. Don't stop now." }
        if s >= 7 { return "A full week. Best is \(best)." }
        return "Best so far: \(best) day\(best == 1 ? "" : "s")."
    }

    private struct WeekDay { let key: String; let label: String; let practiced: Bool; let isToday: Bool }

    private func lastSevenDays() -> [WeekDay] {
        let cal = Calendar.current
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = dateFormatter.string(from: date)
            return WeekDay(key: key, label: letters[cal.component(.weekday, from: date) - 1],
                           practiced: statsManager.practiceDays.contains(key), isToday: offset == 0)
        }
    }

    // MARK: - 2. Time

    private var timeCard: some View {
        let days = statsManager.recentDailySummaries
        let fortnight = days.reduce(0) { $0 + $1.totalSeconds }
        let todayKey = dateFormatter.string(from: Date())
        let peakMinutes = max(5.0, Double(days.map(\.totalSeconds).max() ?? 0) / 60.0)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last 14 days").eyebrowStyle()
                    Text(formatMinutes(fortnight))
                        .font(CascadeFont.number(36))
                        .foregroundStyle(Brand.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("All time").eyebrowStyle()
                    Text(statsManager.formattedTotalTime)
                        .font(CascadeFont.number(20))
                        .foregroundStyle(Brand.textSecondary)
                }
            }

            Chart(days) { day in
                let minutes = Double(day.totalSeconds) / 60.0
                BarMark(
                    x: .value("Day", day.date),
                    y: .value("Minutes", max(minutes, peakMinutes * 0.06))
                )
                .foregroundStyle(day.date == todayKey ? Brand.amber : (day.totalSeconds > 0 ? Brand.teal : Brand.surfaceHigh))
                .cornerRadius(4)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: 0...(peakMinutes * 1.1))
            .frame(height: 90)

            HStack {
                Text(shortDate(days.first?.date))
                Spacer()
                Text("Today")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Brand.textTertiary)

            if fortnight == 0 {
                Text("No sessions yet. Even five minutes lights up a bar.")
                    .font(.caption)
                    .foregroundStyle(Brand.textSecondary)
            } else {
                HStack(spacing: 14) {
                    inlineStat("\(statsManager.sessionsCount)", "sessions")
                    inlineStat("\(statsManager.songsCompleted)", "completed")
                    inlineStat("\(libraryVM.songs.count)", "pieces")
                }
            }
        }
        .cascadeCard(padding: 20, radius: 26)
    }

    private func inlineStat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(value).font(CascadeFont.number(15)).foregroundStyle(Brand.textPrimary)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.textTertiary)
        }
    }

    // MARK: - 3. Calendar heat map

    private var calendarCard: some View {
        let calendar = Calendar.current
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysUntilSaturday = todayWeekday == 7 ? 0 : (7 - todayWeekday)
        let thisSaturday = calendar.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
        let startDate = calendar.date(byAdding: .day, value: -34, to: thisSaturday) ?? today
        let days: [Date] = (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
        var seconds: [String: Int] = [:]
        for s in statsManager.dailySummaries { seconds[s.date] = s.totalSeconds }
        let peak = max(300, seconds.values.max() ?? 300)
        let letters = ["S", "M", "T", "W", "T", "F", "S"]

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Five weeks").eyebrowStyle()
                Spacer()
                Text("\(statsManager.practiceDays.count) days practiced")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(letters.indices, id: \.self) { i in
                    Text(letters[i])
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                }
                ForEach(days, id: \.self) { date in
                    let key = dateFormatter.string(from: date)
                    let practiced = statsManager.practiceDays.contains(key)
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = date > today
                    let intensity = min(1, Double(seconds[key] ?? (practiced ? 300 : 0)) / Double(peak))
                    let selected = selectedDayString == key

                    Button {
                        guard practiced else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedDayString = selected ? nil : key
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(practiced ? Brand.teal.opacity(0.35 + 0.65 * intensity) : (isFuture ? Color.clear : Brand.surfaceHigh))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(practiced ? Brand.ink : (isFuture ? .clear : Brand.textTertiary))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Brand.amber : (isToday ? Brand.textPrimary.opacity(0.7) : .clear), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!practiced)
                    .accessibilityLabel("\(calendar.component(.day, from: date))\(practiced ? ", practiced" : "")\(isToday ? ", today" : "")")
                }
            }
        }
        .cascadeCard(padding: 18, radius: 26)
    }

    private func dayDetail(_ key: String) -> some View {
        let entries = statsManager.songsForDay(key)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(readableDate(key)).eyebrowStyle(Brand.teal)
                Spacer()
                Button { withAnimation { selectedDayString = nil } } label: {
                    CascadeIconView(.xmark, size: 12, color: Brand.textTertiary)
                }
                .buttonStyle(.plain)
            }
            if entries.isEmpty {
                Text("Practiced, but no songs were logged that day.")
                    .font(.subheadline).foregroundStyle(Brand.textSecondary)
            } else {
                ForEach(entries) { entry in
                    HStack {
                        CascadeIconView(.music, size: 14, color: Brand.teal)
                        Text(entry.songTitle.isEmpty ? "Untitled" : entry.songTitle)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Spacer()
                        Text(formatMinutes(entry.durationSeconds))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
            }
        }
        .cascadeCard(padding: 16, radius: 20, raised: true)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - 4. Awards

    private var awardsStrip: some View {
        let all = achievementManager.achievements
        let earned = all.filter(\.isEarned).sorted { ($0.dateEarned ?? .distantPast) > ($1.dateEarned ?? .distantPast) }
        let next = Array(all.filter { !$0.isEarned }.prefix(3))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Awards · \(achievementManager.earnedCount) of \(achievementManager.totalCount)").eyebrowStyle()
                Spacer()
                NavigationLink {
                    AchievementsView().environment(achievementManager)
                } label: {
                    Text("See all")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.teal)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(earned) { a in badge(a, earned: true) }
                    ForEach(next) { a in badge(a, earned: false) }
                }
            }
        }
        .cascadeCard(padding: 18, radius: 26)
    }

    private func badge(_ a: Achievement, earned: Bool) -> some View {
        let tint = badgeColor(a)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(earned ? tint.opacity(0.18) : Brand.surfaceHigh)
                    .frame(width: 56, height: 56)
                Image(systemName: a.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(earned ? tint : Brand.textTertiary)
            }
            .glow(tint, radius: 12, opacity: earned ? 0.5 : 0)
            Text(a.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(earned ? Brand.textPrimary : Brand.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 84)
        .opacity(earned ? 1 : 0.7)
    }

    private func badgeColor(_ a: Achievement) -> Color {
        switch a.category {
        case .practice: return Brand.teal
        case .mastery: return Brand.amber
        case .dedication: return Brand.mint
        case .explorer: return Brand.violet
        }
    }

    // MARK: - 5. Reminders

    private var remindersRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                IconBadge(glyph: .bell, tint: Brand.teal, diameter: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily reminder")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(notificationManager.dailyReminderEnabled
                         ? "At \(notificationManager.reminderTime.formatted(date: .omitted, time: .shortened))"
                         : "A nudge to keep the streak")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { notificationManager.dailyReminderEnabled },
                    set: { newVal in
                        if newVal && !notificationManager.isAuthorized {
                            Task {
                                let granted = await notificationManager.requestPermission()
                                if granted { notificationManager.dailyReminderEnabled = true }
                            }
                        } else {
                            notificationManager.dailyReminderEnabled = newVal
                        }
                    }
                ))
                .labelsHidden()
                .tint(Brand.teal)
            }
            if notificationManager.dailyReminderEnabled {
                HStack {
                    Text("Time").font(.subheadline).foregroundStyle(Brand.textSecondary)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { notificationManager.reminderTime },
                        set: { notificationManager.reminderTime = $0 }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                }
            }
        }
        .cascadeCard(padding: 14, radius: 22)
    }

    // MARK: - Helpers

    private func formatMinutes(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func shortDate(_ key: String?) -> String {
        guard let key, let date = dateFormatter.date(from: key) else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func readableDate(_ key: String) -> String {
        guard let date = dateFormatter.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

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
