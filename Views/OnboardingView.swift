//
//  OnboardingView.swift
//  MyPianoInstructor
//
//  First launch: the product on stage. A live cascade of notes runs behind
//  three short pages; one button gets you in.
//

import SwiftUI

struct OnboardingView: View {
    /// Persisted — flipped when the user finishes or skips the intro.
    @Binding var hasCompletedOnboarding: Bool

    @AppStorage("pendingTutorialShow") private var pendingTutorialShow = false
    @AppStorage("hasSeenPlayerWalkthrough") private var hasSeenWalkthrough = false
    @State private var currentPage = 0

    private let pages: [(eyebrow: String, title: String, body: String)] = [
        ("Welcome to Cascade",
         "Sheet music in.\nFalling notes out.",
         "Scan a page, import a file, or pick a starter piece. It becomes a lesson you can watch, slow down, and play along with."),
        ("Learn at your pace",
         "Loop the hard bar.\nHalf the speed.\nOne hand at a time.",
         "Note-by-note feedback on the on-screen keys or your MIDI piano, and a listen mode for studying a piece first."),
        ("Make it yours",
         "Export videos.\nKeep a streak.",
         "Render any piece as a 1080p video with real piano sound, and watch your practice calendar fill in."),
    ]

    private func dismiss() {
        if !hasSeenWalkthrough { pendingTutorialShow = true }
        withAnimation { hasCompletedOnboarding = true }
    }

    var body: some View {
        ZStack {
            StageBackground().ignoresSafeArea()

            // Live notes behind everything, dimmed so type stays readable.
            OnboardingCascade()
                .ignoresSafeArea()
                .opacity(0.5)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.42),
                            .init(color: .clear, location: 0.58),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CascadeWordmark(size: 26, animated: false)
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") { dismiss() }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(pages[index].eyebrow).eyebrowStyle(Brand.teal)
                            Text(pages[index].title)
                                .font(CascadeFont.display(36))
                                .foregroundStyle(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(pages[index].body)
                                .font(.system(size: 17))
                                .foregroundStyle(Brand.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 320)

                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? Brand.teal : Brand.textTertiary.opacity(0.5))
                            .frame(width: i == currentPage ? 22 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Continue" : "Start playing")
                }
                .buttonStyle(.cascadePrimary)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Full-screen looping cascade used as the onboarding backdrop.
private struct OnboardingCascade: View {
    @Environment(ThemeManager.self) var themeManager

    private static let loopDuration: TimeInterval = 9
    private static let demoNotes: [NoteEvent] = {
        // A gentle arpeggiated progression across both hands.
        let rh = [72, 76, 79, 83, 79, 76, 74, 77, 81, 84, 81, 77, 76, 79, 83, 86, 83, 79, 74, 77, 81, 79, 76, 72]
        let lh = [48, 55, 50, 57, 52, 59, 43, 50]
        var notes: [NoteEvent] = []
        for (i, p) in rh.enumerated() {
            notes.append(NoteEvent(pitch: p, startTime: Double(i) * 0.36, duration: 0.32, voice: 1))
        }
        for (i, p) in lh.enumerated() {
            notes.append(NoteEvent(pitch: p, startTime: Double(i) * 1.08, duration: 1.0, voice: 2))
        }
        return notes.sorted { $0.startTime < $1.startTime }
    }()

    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let looped = elapsed.truncatingRemainder(dividingBy: Self.loopDuration)
            FallingNotesView(notes: Self.demoNotes, currentTime: looped, lookahead: 5.0)
        }
        .onAppear { startDate = Date() }
    }
}
