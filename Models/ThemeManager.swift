//
//  ThemeManager.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import SwiftUI
import Observation

/// Predefined color themes for note display
enum NoteColorTheme: String, CaseIterable, Identifiable, Codable {
    case classic    = "Classic"
    case ocean      = "Ocean"
    case sunset     = "Sunset"
    case forest     = "Forest"
    case neon       = "Neon"
    case pastel     = "Pastel"
    case monochrome = "Monochrome"
    case custom     = "Custom"

    var id: String { rawValue }

    var rightHandColor: Color {
        switch self {
        case .classic:    return .cyan
        case .ocean:      return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .sunset:     return Color(red: 1.0, green: 0.4, blue: 0.3)
        case .forest:     return Color(red: 0.3, green: 0.8, blue: 0.5)
        case .neon:       return Color(red: 0.0, green: 1.0, blue: 0.8)
        case .pastel:     return Color(red: 0.6, green: 0.7, blue: 1.0)
        case .monochrome: return .white
        case .custom:     return .cyan // placeholder — overridden by ThemeManager
        }
    }

    var leftHandColor: Color {
        switch self {
        case .classic:    return .orange
        case .ocean:      return Color(red: 0.1, green: 0.4, blue: 0.7)
        case .sunset:     return Color(red: 1.0, green: 0.7, blue: 0.2)
        case .forest:     return Color(red: 0.2, green: 0.6, blue: 0.3)
        case .neon:       return Color(red: 1.0, green: 0.0, blue: 0.8)
        case .pastel:     return Color(red: 1.0, green: 0.7, blue: 0.7)
        case .monochrome: return Color(white: 0.6)
        case .custom:     return .orange // placeholder
        }
    }

    var blackKeyNoteColor: Color {
        switch self {
        case .classic:    return .purple
        case .ocean:      return Color(red: 0.15, green: 0.3, blue: 0.6)
        case .sunset:     return Color(red: 0.8, green: 0.3, blue: 0.5)
        case .forest:     return Color(red: 0.15, green: 0.5, blue: 0.25)
        case .neon:       return Color(red: 0.8, green: 0.0, blue: 1.0)
        case .pastel:     return Color(red: 0.8, green: 0.7, blue: 0.9)
        case .monochrome: return Color(white: 0.4)
        case .custom:     return .purple // placeholder
        }
    }

    var keyHighlightColor: Color {
        switch self {
        case .classic:    return .blue
        case .ocean:      return Color(red: 0.2, green: 0.5, blue: 0.8)
        case .sunset:     return Color(red: 1.0, green: 0.5, blue: 0.2)
        case .forest:     return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .neon:       return Color(red: 0.0, green: 0.9, blue: 0.9)
        case .pastel:     return Color(red: 0.5, green: 0.6, blue: 0.9)
        case .monochrome: return Color(white: 0.7)
        case .custom:     return .blue // placeholder
        }
    }

    /// Preview colors shown in the theme picker
    var previewColors: [Color] {
        [rightHandColor, leftHandColor, blackKeyNoteColor]
    }

    var icon: String {
        switch self {
        case .classic:    return "paintpalette.fill"
        case .ocean:      return "water.waves"
        case .sunset:     return "sun.horizon.fill"
        case .forest:     return "leaf.fill"
        case .neon:       return "sparkle"
        case .pastel:     return "cloud.fill"
        case .monochrome: return "circle.lefthalf.filled"
        case .custom:     return "eyedropper.full"
        }
    }
}

/// Observable object that manages the user's theme preference
@Observable class ThemeManager {
    var selectedTheme: NoteColorTheme {
        didSet { save() }
    }

    var showNoteExplosions: Bool {
        didSet { save() }
    }

    // Custom colors (only used when selectedTheme == .custom)
    var customRightHand: Color {
        didSet { save() }
    }
    var customLeftHand: Color {
        didSet { save() }
    }
    var customBlackKey: Color {
        didSet { save() }
    }

    private let themeKey = "selectedNoteTheme"
    private let explosionsKey = "showNoteExplosions"
    private let customRHKey = "customRH"
    private let customLHKey = "customLH"
    private let customBKKey = "customBK"
    private let defaults = UserDefaults.standard

    init() {
        if let raw = defaults.string(forKey: "selectedNoteTheme"),
           let theme = NoteColorTheme(rawValue: raw) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .classic
        }
        self.showNoteExplosions = defaults.object(forKey: "showNoteExplosions") as? Bool ?? true

        // Load custom colors
        self.customRightHand = Self.loadColor(key: "customRH", fallback: .cyan)
        self.customLeftHand = Self.loadColor(key: "customLH", fallback: .orange)
        self.customBlackKey = Self.loadColor(key: "customBK", fallback: .purple)
    }

    // Dynamic theme colors (used throughout the app)
    var rightHandNote: Color {
        if selectedTheme == .custom {
            return customRightHand.opacity(0.85)
        }
        return selectedTheme.rightHandColor.opacity(0.85)
    }

    var leftHandNote: Color {
        if selectedTheme == .custom {
            return customLeftHand.opacity(0.80)
        }
        return selectedTheme.leftHandColor.opacity(0.80)
    }

    var blackKeyNote: Color {
        if selectedTheme == .custom {
            return customBlackKey.opacity(0.9)
        }
        return selectedTheme.blackKeyNoteColor.opacity(0.9)
    }

    var keyHighlight: Color {
        if selectedTheme == .custom {
            return customRightHand.opacity(0.5)
        }
        return selectedTheme.keyHighlightColor.opacity(0.5)
    }

    var keyHighlightBlack: Color {
        if selectedTheme == .custom {
            return customRightHand
        }
        return selectedTheme.keyHighlightColor
    }

    /// Colors for preview (respects custom)
    var effectiveRightHand: Color {
        selectedTheme == .custom ? customRightHand : selectedTheme.rightHandColor
    }
    var effectiveLeftHand: Color {
        selectedTheme == .custom ? customLeftHand : selectedTheme.leftHandColor
    }
    var effectiveBlackKey: Color {
        selectedTheme == .custom ? customBlackKey : selectedTheme.blackKeyNoteColor
    }

    private func save() {
        defaults.set(selectedTheme.rawValue, forKey: themeKey)
        defaults.set(showNoteExplosions, forKey: explosionsKey)
        Self.saveColor(customRightHand, key: customRHKey)
        Self.saveColor(customLeftHand, key: customLHKey)
        Self.saveColor(customBlackKey, key: customBKKey)
    }

    // MARK: - Color Persistence Helpers

    private static func saveColor(_ color: Color, key: String) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let data: [CGFloat] = [r, g, b, a]
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadColor(key: String, fallback: Color) -> Color {
        guard let data = UserDefaults.standard.array(forKey: key) as? [CGFloat],
              data.count == 4 else {
            return fallback
        }
        return Color(red: Double(data[0]), green: Double(data[1]), blue: Double(data[2]), opacity: Double(data[3]))
    }
}
