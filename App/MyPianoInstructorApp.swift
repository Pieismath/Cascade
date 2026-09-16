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
    // Persisted: only true when user explicitly checks "Don't show again"
    @AppStorage("suppressOnboarding") private var suppressOnboarding = false

    // Session-only: always starts as true so onboarding shows every launch
    // (unless suppressed). Set to false when user dismisses onboarding.
    @State private var showOnboarding = true

    var body: some Scene {
        WindowGroup {
            if !showOnboarding || suppressOnboarding {
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
                OnboardingView(
                    suppressOnboarding: $suppressOnboarding,
                    showOnboarding: $showOnboarding
                )
                .environment(themeManager)
            }
        }
    }
}
