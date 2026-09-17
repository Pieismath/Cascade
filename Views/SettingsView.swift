//
//  SettingsView.swift
//  MyPianoInstructor
//
//  One place for the things that aren't practice: scans and scan packs,
//  note colours, the player tour, privacy, and the scan account.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScanAccountManager.self) private var account
    @Environment(ScanStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager

    /// Set when the user asks for the player tour; Home starts it after this sheet closes.
    @Binding var startTour: Bool

    @State private var showPrivacy = false
    @State private var message: String? = nil
    @State private var confirmDelete = false
    @State private var deleting = false

    private var cloudConfigured: Bool { ScanCloudConfig.baseURL != nil }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    scansSection
                    playerSection
                    aboutSection
                    if account.isSignedIn { accountSection }

                    Text("Starter pieces are public domain · Piano sound: FluidR3")
                        .font(.caption2)
                        .foregroundStyle(Brand.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .stageBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .task { await account.refresh() }
        .sheet(isPresented: $showPrivacy) { ScanPrivacySheet() }
        .confirmationDialog("Delete your Cascade account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                deleting = true
                Task {
                    do {
                        try await account.deleteAccount()
                    } catch {
                        message = error.localizedDescription
                    }
                    deleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your scan record from our servers and signs you out. Unused scans are lost. Songs in your library stay on this device.")
        }
        .alert("Scans", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - Scans

    private var scansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scans").eyebrowStyle()

            Group {
                if !cloudConfigured {
                    Text("Scanning isn't available in this build.")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if account.isSignedIn {
                    ScanBalanceView(remaining: account.remainingScans ?? 0)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your first scan is free")
                                .font(CascadeFont.display(22))
                                .foregroundStyle(Brand.textPrimary)
                            Text("Sign in to claim it. Apple shares an anonymous ID, never your name or email.")
                                .font(.footnote)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        ScanSignInButton(onError: { message = $0 })
                    }
                }
            }
            .cascadeCard(padding: 18)

            // Packs are credited to the account, so they're offered once signed in.
            if cloudConfigured && account.isSignedIn {
                ScanPacksList(store: store, onGranted: { message = $0 }, onError: { message = $0 })

                Button {
                    Task {
                        let granted = await store.redeemPending()
                        message = granted > 0
                            ? "Added \(granted) scan\(granted == 1 ? "" : "s")."
                            : "No unredeemed purchases were found. Your balance is up to date."
                    }
                } label: {
                    Text("Restore purchases")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Player

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Player").eyebrowStyle()
            VStack(spacing: 0) {
                NavigationLink {
                    ThemePickerView()
                        .environment(themeManager)
                        .stageBackground()
                } label: {
                    SettingsRow(icon: "paintpalette.fill", tint: Brand.violet, title: "Note colors & effects",
                                value: themeManager.selectedTheme.rawValue)
                }
                rowDivider
                Button {
                    startTour = true
                    dismiss()
                } label: {
                    SettingsRow(icon: "play.rectangle.fill", tint: Brand.teal, title: "Take the player tour")
                }
            }
            .buttonStyle(.plain)
            .settingsGroup()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About").eyebrowStyle()
            VStack(spacing: 0) {
                Button { showPrivacy = true } label: {
                    SettingsRow(icon: "lock.fill", tint: Brand.mint, title: "How scanning works")
                }
                if let url = ScanCloudConfig.privacyPolicyURL {
                    rowDivider
                    Link(destination: url) {
                        SettingsRow(icon: "hand.raised.fill", tint: Brand.amber, title: "Privacy policy", external: true)
                    }
                }
                rowDivider
                SettingsRow(icon: "info.circle.fill", tint: Brand.textTertiary, title: "Version", value: Self.versionString, chevron: false)
            }
            .buttonStyle(.plain)
            .settingsGroup()
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account").eyebrowStyle()
            VStack(spacing: 0) {
                Button { account.signOut() } label: {
                    SettingsRow(icon: "rectangle.portrait.and.arrow.right", tint: Brand.textTertiary, title: "Sign out", chevron: false)
                }
                rowDivider
                Button { confirmDelete = true } label: {
                    SettingsRow(icon: "trash.fill", tint: Brand.coral, title: "Delete account", titleColor: Brand.coral, chevron: false)
                }
                .disabled(deleting)
            }
            .buttonStyle(.plain)
            .settingsGroup()

            Text("Your account holds only an anonymous Apple ID, your scan usage, and scans you've bought.")
                .font(.caption)
                .foregroundStyle(Brand.textTertiary)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Brand.hairline).frame(height: 1).padding(.leading, 58)
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Rows

private struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    var value: String? = nil
    var titleColor: Color = Brand.textPrimary
    var chevron: Bool = true
    var external: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(titleColor)
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            if chevron {
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private extension View {
    func settingsGroup() -> some View {
        self
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Brand.hairline, lineWidth: 1))
    }
}
