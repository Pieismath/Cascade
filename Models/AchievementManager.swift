//
//  AchievementManager.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import Foundation
import Observation

/// Represents an achievement badge
struct Achievement: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let icon: String          // SF Symbol name
    let category: Category
    let requirement: Int       // threshold to unlock
    var dateEarned: Date?

    var isEarned: Bool { dateEarned != nil }

    enum Category: String, Codable, CaseIterable {
        case practice   = "Practice"
        case mastery    = "Mastery"
        case dedication = "Dedication"
        case explorer   = "Explorer"
    }
}

/// Manages all achievement logic, checking and unlocking badges
@Observable class AchievementManager {
    var achievements: [Achievement] = []
    var recentlyUnlocked: Achievement? = nil   // triggers celebration

    private let defaults = UserDefaults.standard
    private let storageKey = "earnedAchievements"

    init() {
        achievements = Self.allAchievements
        loadEarnedDates()
    }

    // MARK: - Check Achievements

    /// Call after each session to evaluate what's been unlocked
    func evaluate(stats: PracticeStatsManager, songsInLibrary: Int, bestAccuracy: Double) {
        var newlyUnlocked: [Achievement] = []

        for i in achievements.indices {
            guard !achievements[i].isEarned else { continue }

            let met: Bool
            switch achievements[i].id {

            // Practice milestones
            case "first_session":
                met = stats.sessionsCount >= 1
            case "ten_sessions":
                met = stats.sessionsCount >= 10
            case "fifty_sessions":
                met = stats.sessionsCount >= 50
            case "century_sessions":
                met = stats.sessionsCount >= 100

            // Time milestones
            case "one_hour":
                met = stats.totalPracticeSeconds >= 3600
            case "five_hours":
                met = stats.totalPracticeSeconds >= 18000
            case "ten_hours":
                met = stats.totalPracticeSeconds >= 36000

            // Streak milestones
            case "three_day_streak":
                met = stats.currentStreak >= 3
            case "seven_day_streak":
                met = stats.currentStreak >= 7
            case "fourteen_day_streak":
                met = stats.currentStreak >= 14
            case "thirty_day_streak":
                met = stats.currentStreak >= 30

            // Song milestones
            case "first_complete":
                met = stats.songsCompleted >= 1
            case "five_complete":
                met = stats.songsCompleted >= 5
            case "twenty_complete":
                met = stats.songsCompleted >= 20

            // Library milestones
            case "library_five":
                met = songsInLibrary >= 5
            case "library_ten":
                met = songsInLibrary >= 10

            // Accuracy milestones
            case "accuracy_80":
                met = bestAccuracy >= 0.80
            case "accuracy_90":
                met = bestAccuracy >= 0.90
            case "accuracy_perfect":
                met = bestAccuracy >= 0.99

            // Speed milestones — unlocked externally via unlockSpeedDemon()
            case "speed_demon":
                met = false

            default:
                met = false
            }

            if met {
                achievements[i].dateEarned = Date()
                newlyUnlocked.append(achievements[i])
            }
        }

        if !newlyUnlocked.isEmpty {
            // Show the most significant newly unlocked achievement.
            // If recentlyUnlocked is already set (pending dismissal), don't overwrite it.
            if recentlyUnlocked == nil {
                recentlyUnlocked = newlyUnlocked.first
            }
            save()
        }
    }

    /// Mark speed_demon achievement externally
    func unlockSpeedDemon() {
        if let i = achievements.firstIndex(where: { $0.id == "speed_demon" && !$0.isEarned }) {
            achievements[i].dateEarned = Date()
            recentlyUnlocked = achievements[i]
            save()
        }
    }

    /// Dismiss the celebration popup
    func dismissCelebration() {
        recentlyUnlocked = nil
    }

    var earnedCount: Int {
        achievements.filter(\.isEarned).count
    }

    var totalCount: Int {
        achievements.count
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(earnedCount) / Double(totalCount)
    }

    // MARK: - Persistence

    private func save() {
        // Save only the earned dates keyed by achievement ID
        var earned: [String: Date] = [:]
        for a in achievements where a.isEarned {
            earned[a.id] = a.dateEarned
        }
        if let data = try? JSONEncoder().encode(earned) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func loadEarnedDates() {
        guard let data = defaults.data(forKey: storageKey),
              let earned = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return }

        for i in achievements.indices {
            if let date = earned[achievements[i].id] {
                achievements[i].dateEarned = date
            }
        }
    }

    // MARK: - All Achievement Definitions

    static let allAchievements: [Achievement] = [
        // Practice
        Achievement(id: "first_session", title: "First Steps", description: "Complete your first practice session", icon: "figure.walk", category: .practice, requirement: 1),
        Achievement(id: "ten_sessions", title: "Getting Serious", description: "Complete 10 practice sessions", icon: "flame", category: .practice, requirement: 10),
        Achievement(id: "fifty_sessions", title: "Dedicated Pianist", description: "Complete 50 practice sessions", icon: "flame.fill", category: .practice, requirement: 50),
        Achievement(id: "century_sessions", title: "Piano Centurion", description: "Complete 100 practice sessions", icon: "star.circle.fill", category: .practice, requirement: 100),

        // Time
        Achievement(id: "one_hour", title: "Hour of Power", description: "Practice for a total of 1 hour", icon: "clock.fill", category: .practice, requirement: 3600),
        Achievement(id: "five_hours", title: "Warming Up", description: "Practice for a total of 5 hours", icon: "clock.badge.checkmark.fill", category: .practice, requirement: 18000),
        Achievement(id: "ten_hours", title: "Time Well Spent", description: "Practice for a total of 10 hours", icon: "hourglass.bottomhalf.filled", category: .practice, requirement: 36000),

        // Streaks
        Achievement(id: "three_day_streak", title: "Hat Trick", description: "Practice 3 days in a row", icon: "3.circle.fill", category: .dedication, requirement: 3),
        Achievement(id: "seven_day_streak", title: "Full Week", description: "Practice 7 days in a row", icon: "7.circle.fill", category: .dedication, requirement: 7),
        Achievement(id: "fourteen_day_streak", title: "Fortnight Focus", description: "Practice 14 days in a row", icon: "calendar.badge.clock", category: .dedication, requirement: 14),
        Achievement(id: "thirty_day_streak", title: "Monthly Master", description: "Practice 30 days in a row", icon: "crown.fill", category: .dedication, requirement: 30),

        // Song completions
        Achievement(id: "first_complete", title: "Encore!", description: "Play through a complete song", icon: "music.note", category: .mastery, requirement: 1),
        Achievement(id: "five_complete", title: "Repertoire Builder", description: "Complete 5 different songs", icon: "music.note.list", category: .mastery, requirement: 5),
        Achievement(id: "twenty_complete", title: "Concert Ready", description: "Complete 20 songs", icon: "theatermasks.fill", category: .mastery, requirement: 20),

        // Library
        Achievement(id: "library_five", title: "Collector", description: "Add 5 songs to your library", icon: "books.vertical.fill", category: .explorer, requirement: 5),
        Achievement(id: "library_ten", title: "Music Librarian", description: "Add 10 songs to your library", icon: "building.columns.fill", category: .explorer, requirement: 10),

        // Accuracy
        Achievement(id: "accuracy_80", title: "On Target", description: "Score 80% accuracy on a song", icon: "target", category: .mastery, requirement: 80),
        Achievement(id: "accuracy_90", title: "Sharp Shooter", description: "Score 90% accuracy on a song", icon: "scope", category: .mastery, requirement: 90),
        Achievement(id: "accuracy_perfect", title: "Perfectionist", description: "Score 99%+ accuracy on a song", icon: "sparkles", category: .mastery, requirement: 99),

        // Speed
        Achievement(id: "speed_demon", title: "Speed Demon", description: "Complete a song at 2x speed", icon: "hare.fill", category: .explorer, requirement: 2),
    ]
}
