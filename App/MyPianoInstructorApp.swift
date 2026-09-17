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
    @State private var scanAccount: ScanAccountManager
    @State private var scanStore: ScanStore
    /// Persisted: onboarding is shown once, on first launch.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        // One account and one store for the app's lifetime, so purchases that
        // arrive in the background are redeemed wherever the user is.
        let account = ScanAccountManager()
        _scanAccount = State(initialValue: account)
        _scanStore = State(initialValue: ScanStore(account: account))
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                RootTabView()
                    .environment(libraryVM)
                    .environment(statsManager)
                    .environment(achievementManager)
                    .environment(themeManager)
                    .environment(notificationManager)
                    .environment(scanAccount)
                    .environment(scanStore)
                    .tint(Brand.teal)
                    .onAppear {
                        _ = AudioEngineManager.shared
                        try? Tips.configure([
                            .displayFrequency(.daily)
                        ])
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .tint(Brand.teal)
                .environment(themeManager)
            }
        }
    }
}
