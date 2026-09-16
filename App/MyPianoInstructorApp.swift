//
//  MyPianoInstructorApp.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/17/25.
//

import SwiftUI
import TipKit

@main
struct MyPianoInstructorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var libraryVM = SongLibraryViewModel()
    @State private var statsManager = PracticeStatsManager()
    @State private var achievementManager = AchievementManager()
    @State private var themeManager = ThemeManager()
    @State private var notificationManager = NotificationManager()
    /// Persisted: onboarding is shown once, on first launch. (The legacy
    /// "suppressOnboarding" key from earlier builds is honoured too.)
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("suppressOnboarding") private var legacySuppressOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding || legacySuppressOnboarding {
                RootTabView()
                    .environment(libraryVM)
                    .environment(statsManager)
                    .environment(achievementManager)
                    .environment(themeManager)
                    .environment(notificationManager)
                    .onAppear {
                        _ = AudioEngineManager.shared
                        try? Tips.configure([
                            .displayFrequency(.daily)
                        ])
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .environment(themeManager)
            }
        }
    }
}
