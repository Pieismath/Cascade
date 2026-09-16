//
//  PracticeStats.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/13/26.
//

import Foundation
import Observation

/// Represents a single practice entry for a specific day
struct DayPracticeEntry: Codable, Identifiable {
    let id: UUID
    let songTitle: String
    let durationSeconds: Int

    init(songTitle: String, durationSeconds: Int) {
        self.id = UUID()
        self.songTitle = songTitle
        self.durationSeconds = durationSeconds
    }

    // Custom decoder to migrate from the old String-based id format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else {
            // Old format had a computed String id — assign a fresh UUID
            self.id = UUID()
        }
        self.songTitle = try container.decode(String.self, forKey: .songTitle)
        self.durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
    }
}

/// Persistent record for charting practice over time
struct DailyPracticeSummary: Identifiable, Codable {
    var id: String { date }
    let date: String        // "yyyy-MM-dd"
    var totalSeconds: Int
    var sessionCount: Int
}

@Observable class PracticeStatsManager {
    var totalPracticeSeconds: Int = 0
    var sessionsCount: Int = 0
    var practiceDays: Set<String> = [] {
        didSet { _cachedStreak = nil }
    }
    var songsCompleted: Int = 0
    var longestStreak: Int = 0

    // Cached streak value — invalidated whenever practiceDays changes.
    // @ObservationIgnored because this is just a performance cache, not observable state.
    @ObservationIgnored private var _cachedStreak: Int?

    // Shared day-key formatter, also used by StatsView's calendar so keys always
    // match. POSIX locale + Gregorian calendar keep the keys stable — with the
    // device's own locale, digits and year numbering can vary (e.g. Buddhist
    // calendar years), silently breaking streaks and the calendar when settings
    // change.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Maps "yyyy-MM-dd" -> list of songs practiced that day
    var daySongLog: [String: [DayPracticeEntry]] = [:]

    /// Daily summaries for Swift Charts
    var dailySummaries: [DailyPracticeSummary] = []

    private let defaults = UserDefaults.standard
    private let totalTimeKey = "practiceTime"
    private let sessionsKey = "practiceSessions"
    private let daysKey = "practiceDays"
    private let songsKey = "songsCompleted"
    private let daySongLogKey = "daySongLog"
    private let dailySummariesKey = "dailySummaries"
    private let longestStreakKey = "longestStreak"

    init() {
        load()
    }

    func recordSession(durationSeconds: Int, songTitle: String = "") {
        totalPracticeSeconds += durationSeconds
        sessionsCount += 1

        let today = Self.dayFormatter.string(from: Date())
        practiceDays.insert(today)

        // Update longest streak record
        let streakNow = currentStreak
        if streakNow > longestStreak { longestStreak = streakNow }

        // Log this song for today
        if !songTitle.isEmpty {
            let entry = DayPracticeEntry(songTitle: songTitle, durationSeconds: durationSeconds)
            var entries = daySongLog[today] ?? []
            entries.append(entry)
            daySongLog[today] = entries
        }

        // Update daily summary for charts
        if let idx = dailySummaries.firstIndex(where: { $0.date == today }) {
            dailySummaries[idx].totalSeconds += durationSeconds
            dailySummaries[idx].sessionCount += 1
        } else {
            dailySummaries.append(DailyPracticeSummary(
                date: today,
                totalSeconds: durationSeconds,
                sessionCount: 1
            ))
        }

        save()
    }

    func recordSongCompleted() {
        songsCompleted += 1
        save()
    }

    /// Get all songs practiced on a specific date string ("yyyy-MM-dd")
    func songsForDay(_ dateString: String) -> [DayPracticeEntry] {
        daySongLog[dateString] ?? []
    }

    var formattedTotalTime: String {
        let hours = totalPracticeSeconds / 3600
        let mins = (totalPracticeSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    var currentStreak: Int {
        if let cached = _cachedStreak { return cached }
        let computed = computeStreak()
        _cachedStreak = computed
        return computed
    }

    private func computeStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var date = Date()

        while streak < 3650 {
            let dateStr = Self.dayFormatter.string(from: date)
            if practiceDays.contains(dateStr) {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { break }
                date = previousDay
            } else {
                break
            }
        }
        return streak
    }

    /// Get recent daily summaries for charts (last 14 days)
    var recentDailySummaries: [DailyPracticeSummary] {
        let calendar = Calendar.current

        var summaries: [DailyPracticeSummary] = []
        for dayOffset in stride(from: -13, through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            let dateStr = Self.dayFormatter.string(from: date)
            if let existing = dailySummaries.first(where: { $0.date == dateStr }) {
                summaries.append(existing)
            } else {
                summaries.append(DailyPracticeSummary(
                    date: dateStr,
                    totalSeconds: 0,
                    sessionCount: 0
                ))
            }
        }
        return summaries
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(totalPracticeSeconds, forKey: totalTimeKey)
        defaults.set(sessionsCount, forKey: sessionsKey)
        defaults.set(songsCompleted, forKey: songsKey)
        if let data = try? JSONEncoder().encode(Array(practiceDays)) {
            defaults.set(data, forKey: daysKey)
        }
        if let logData = try? JSONEncoder().encode(daySongLog) {
            defaults.set(logData, forKey: daySongLogKey)
        }
        if let summaryData = try? JSONEncoder().encode(dailySummaries) {
            defaults.set(summaryData, forKey: dailySummariesKey)
        }
        defaults.set(longestStreak, forKey: longestStreakKey)
    }

    private func load() {
        totalPracticeSeconds = defaults.integer(forKey: totalTimeKey)
        sessionsCount = defaults.integer(forKey: sessionsKey)
        songsCompleted = defaults.integer(forKey: songsKey)
        if let data = defaults.data(forKey: daysKey),
           let days = try? JSONDecoder().decode([String].self, from: data) {
            practiceDays = Set(days)
        }
        if let logData = defaults.data(forKey: daySongLogKey),
           let log = try? JSONDecoder().decode([String: [DayPracticeEntry]].self, from: logData) {
            daySongLog = log
        }
        if let summaryData = defaults.data(forKey: dailySummariesKey),
           let summaries = try? JSONDecoder().decode([DailyPracticeSummary].self, from: summaryData) {
            dailySummaries = summaries
        }
        longestStreak = defaults.integer(forKey: longestStreakKey)
    }
}
