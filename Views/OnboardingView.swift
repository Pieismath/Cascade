//
//  OnboardingView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/13/26.
//

import SwiftUI

struct OnboardingView: View {
    /// Persisted — only written when user checks "Don't show again"
    @Binding var suppressOnboarding: Bool
    /// Session flag — set to false to dismiss onboarding this launch
    @Binding var showOnboarding: Bool

    @AppStorage("pendingTutorialShow") private var pendingTutorialShow = false
    @AppStorage("hasSeenPlayerWalkthrough") private var hasSeenWalkthrough = false
    @State private var currentPage = 0
    @State private var dontShowAgain = false

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        ("person.3.sequence.fill", "Piano for Everyone",
         "Piano lessons cost $50 to $100 per hour. Cascade brings professional-quality guidance to anyone with a phone, completely free."),
        ("doc.badge.plus", "Any Sheet Music, Instantly",
         "Import any MusicXML file, the open standard used by composers worldwide, and watch it transform into a visual falling-note lesson in seconds."),
        ("hand.tap.fill", "Learn at Your Pace",
         "Slow down to 25%, practice one hand at a time, loop tricky sections, and use Listen Mode to study a piece before you play it."),
        ("chart.bar.fill", "Track Your Journey",
         "Your practice calendar, streaks, and accuracy scores show real progress over time. The same evidence-based feedback professional teachers use."),
        ("person.3.fill", "Share Your Progress",
         "Celebrate milestones with beautiful share cards. Inspire a friend to start learning. Piano education is more powerful when we grow together.")
    ]

    private func dismiss() {
        if dontShowAgain { suppressOnboarding = true }
        // Only queue the tutorial on the very first run — once seen it shouldn't
        // block the notification prompt on every subsequent onboarding dismissal.
        if !hasSeenWalkthrough {
            pendingTutorialShow = true
        }
        withAnimation { showOnboarding = false }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    onboardingPage(pages[index], index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // "Don't show again" toggle — only visible on the last page
            if currentPage == pages.count - 1 {
                Button {
                    dontShowAgain.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                            .foregroundColor(dontShowAgain ? AppTheme.accent : .secondary)
                            .font(.body)
                        Text("Don't show again")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }

            // Bottom button
            Button {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.accentGradient)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)

            if currentPage < pages.count - 1 {
                Button("Skip") { dismiss() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 20)
            }
        }
        .background {
            MeshGradientBackground()
                .opacity(0.3)
        }
    }

    private func onboardingPage(_ page: (icon: String, title: String, subtitle: String), index: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 120, height: 120)
                    .background {
                        MeshGradientCard()
                            .clipShape(Circle())
                    }

                Image(systemName: page.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.white)
            }

            // Live falling-notes mini demo on the "Any Sheet Music" slide
            if index == 1 {
                MiniDemoView()
                    .padding(.horizontal, 30)
            }

            Text(page.title)
                .font(.title).bold()
                .multilineTextAlignment(.center)

            Text(page.subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Mini Live Demo View (used in onboarding slide 2)

private struct MiniDemoView: View {
    @Environment(ThemeManager.self) var themeManager

    private static let loopDuration: TimeInterval = 4.5
    private static let demoNotes: [NoteEvent] = {
        // A simple C major arpeggio for visual demonstration
        let pitches = [60, 64, 67, 72, 67, 64, 60, 64, 67, 72, 60, 67]
        return pitches.enumerated().map { i, p in
            NoteEvent(
                pitch: p,
                startTime: Double(i) * 0.38,
                duration: 0.33,
                voice: i % 4 == 0 ? 2 : 1
            )
        }
    }()

    // Reference date used to compute elapsed time, looped
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let looped = elapsed.truncatingRemainder(dividingBy: Self.loopDuration)
            FallingNotesView(notes: Self.demoNotes, currentTime: looped, lookahead: 2.0)
        }
        .frame(height: 100)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onAppear { startDate = Date() }
    }
}
