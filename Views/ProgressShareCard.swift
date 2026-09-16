//
//  ProgressShareCard.swift
//  MyPianoInstructor
//
//  A fixed-size SwiftUI view rendered offline via ImageRenderer.
//  Not presented in navigation — only used with shareProgressCard() in StatsView.
//

import SwiftUI

struct ProgressShareCard: View {
    let streak: Int
    let totalTime: String
    let songsCompleted: Int
    let achievementsEarned: Int

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                // App brand header
                HStack(spacing: 10) {
                    Image(systemName: "pianokeys")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Cascade")
                        .font(.title2).bold()
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding([.top, .horizontal], 28)

                Spacer()

                // Stats row
                HStack(spacing: 0) {
                    statBlock("\(streak)", "Day\nStreak", "flame.fill", .orange)
                    statBlock(totalTime, "Practice\nTime", "clock.fill", .cyan)
                    statBlock("\(songsCompleted)", "Songs\nLearned", "checkmark.circle.fill", .green)
                    statBlock("\(achievementsEarned)", "Achievements", "trophy.fill", .yellow)
                }
                .padding(.horizontal, 28)

                Spacer()

                // Motivational quote
                Text(quote)
                    .font(.subheadline.italic())
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)

                // Decorative piano key strip
                HStack(spacing: 2) {
                    ForEach(0..<16, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.15))
                    }
                }
                .frame(height: 28)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 800, height: 420)
        .cornerRadius(20)
    }

    private func statBlock(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var quote: String {
        if streak >= 14 { return "\"Consistency is the foundation of mastery.\"" }
        if streak >= 7  { return "\"Practice makes permanent.\"" }
        if streak >= 3  { return "\"Every expert was once a beginner.\"" }
        return "\"The journey of a thousand miles begins with a single note.\""
    }
}
