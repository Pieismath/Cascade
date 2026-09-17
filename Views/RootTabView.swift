//  RootTabView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 11/17/25.
//

import SwiftUI

struct RootTabView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(PracticeStatsManager.self) var statsManager
    @Environment(AchievementManager.self) var achievementManager
    @Environment(ThemeManager.self) var themeManager
    @Environment(NotificationManager.self) var notificationManager
    @Environment(ScanAccountManager.self) var scanAccount
    @Environment(ScanStore.self) var scanStore

    @AppStorage("pendingTutorialShow") private var pendingTutorialShow = false
    @AppStorage("hasAskedNotificationPermission") private var hasAskedPermission = false
    @State private var selectedSong: Song? = nil
    @State private var tabSelection: Int = 0
    @State private var showTutorial = false
    @State private var showNotificationPrompt = false

    var body: some View {
        TabView(selection: $tabSelection) {

            // HOME TAB — scanning, importing and the starter pieces all live here.
            NavigationStack {
                SongLibraryView(selectedSong: $selectedSong, tabSelection: $tabSelection, showTutorial: $showTutorial)
                    .environment(libraryVM)
                    .environment(statsManager)
                    .environment(achievementManager)
                    .environment(themeManager)
                    .environment(scanAccount)
                    .environment(scanStore)
            }
            .tabItem {
                Label { Text("Home") } icon: { CascadeGlyph.home.image() }
            }
            .tag(0)

            // PLAY TAB (hidden tab bar). Tags stay 0/2/3 so existing tab jumps keep working.
            NavigationStack {
                if let selectedSong {
                    let playback = libraryVM.cachedPlayback(for: selectedSong)
                    PlayerView(playback: playback, songTitle: selectedSong.title, song: selectedSong)
                        .id(selectedSong.id)
                        .stageBackground()
                        .environment(libraryVM)
                        .environment(statsManager)
                        .environment(achievementManager)
                        .environment(themeManager)
                } else {
                    noSongSelectedView
                }
            }
            .landscapeOnly()
            .toolbar(.hidden, for: .tabBar)
            .tabItem {
                Label { Text("Play") } icon: { CascadeGlyph.play.image() }
            }
            .tag(2)

            // STATS TAB
            NavigationStack {
                StatsView()
                    .environment(statsManager)
                    .environment(libraryVM)
                    .environment(achievementManager)
                    .environment(themeManager)
                    .environment(notificationManager)
            }
            .tabItem {
                Label { Text("Progress") } icon: { CascadeGlyph.progress.image() }
            }
            .tag(3)
        }
        .tint(AppTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { notif in
            if let index = notif.object as? Int {
                tabSelection = index
            }
        }
        .task {
            // Keep the scan balance fresh and finish any purchase whose
            // redemption was interrupted.
            await scanAccount.refresh()
            _ = await scanStore.redeemPending()
        }
        .onAppear {
            if pendingTutorialShow {
                // Tutorial takes priority — clear flag and present after transition settles.
                // Notification prompt is intentionally skipped this launch to avoid collision.
                pendingTutorialShow = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showTutorial = true
                }
            } else if !hasAskedPermission {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showNotificationPrompt = true
                }
            }
        }
        .fullScreenCover(isPresented: $showTutorial) {
            PlayerTutorialView(isPresented: $showTutorial)
                .environment(themeManager)
        }
        .alert("Daily Practice Reminders", isPresented: $showNotificationPrompt) {
            Button("Enable") {
                hasAskedPermission = true
                Task {
                    let granted = await notificationManager.requestPermission()
                    if granted {
                        notificationManager.dailyReminderEnabled = true
                    }
                }
            }
            Button("Not Now", role: .cancel) {
                hasAskedPermission = true
            }
        } message: {
            Text("Would you like a daily reminder to practice piano? You can change this anytime in Progress settings.")
        }
    }

    private var noSongSelectedView: some View {
        VStack(spacing: 16) {
            CascadeIconView(.music, size: 56, color: Brand.textTertiary)
            Text("No Song Selected")
                .font(.title3).bold()
            Text("Select a song from your library to start playing")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                tabSelection = 0
            } label: {
                Label("Go to Library", systemImage: "house")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .padding()
    }
}
