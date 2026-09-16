//
//  AchievementsView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementManager.self) var achievementManager

    @State private var selectedCategory: Achievement.Category? = nil

    private var filteredAchievements: [Achievement] {
        if let cat = selectedCategory {
            return achievementManager.achievements.filter { $0.category == cat }
        }
        return achievementManager.achievements
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Header with progress ring
                headerSection

                // MARK: - Category Filter
                categoryFilter

                // MARK: - Achievement Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(filteredAchievements) { achievement in
                        achievementCard(achievement)
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 20) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: achievementManager.progressFraction)
                    .stroke(
                        AppTheme.accentGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: achievementManager.progressFraction)

                VStack(spacing: 0) {
                    Text("\(achievementManager.earnedCount)")
                        .font(.title2).bold()
                    Text("/\(achievementManager.totalCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Achievements")
                    .font(.title2).bold()
                Text("Unlock badges by practicing, completing songs, and building streaks!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .padding(.top)
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "All", category: nil)
                ForEach(Achievement.Category.allCases, id: \.self) { cat in
                    categoryChip(label: cat.rawValue, category: cat)
                }
            }
        }
    }

    private func categoryChip(label: String, category: Achievement.Category?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            Text(label)
                .font(.caption).bold()
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : AppTheme.cardBackground)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Achievement Card

    private func achievementCard(_ achievement: Achievement) -> some View {
        let earned = achievement.isEarned

        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(earned
                          ? categoryColor(achievement.category).opacity(0.2)
                          : Color.gray.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: achievement.icon)
                    .font(.title3)
                    .foregroundColor(earned
                                     ? categoryColor(achievement.category)
                                     : .gray.opacity(0.4))
                    .symbolEffect(.bounce, value: achievement.isEarned)
                    .symbolRenderingMode(earned ? .multicolor : .monochrome)
            }

            Text(achievement.title)
                .font(.caption).bold()
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(achievement.description)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if earned, let date = achievement.dateEarned {
                Text(date, style: .date)
                    .font(.system(size: 8))
                    .foregroundColor(categoryColor(achievement.category))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(earned ? categoryColor(achievement.category).opacity(0.05) : AppTheme.cardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(earned ? categoryColor(achievement.category).opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .opacity(earned ? 1.0 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title). \(achievement.description). \(earned ? "Earned" : "Locked")")
    }

    private func categoryColor(_ category: Achievement.Category) -> Color {
        switch category {
        case .practice: return .indigo
        case .mastery: return .orange
        case .dedication: return .green
        case .explorer: return .purple
        }
    }
}
