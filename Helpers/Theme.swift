//
//  Theme.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/13/26.
//

import SwiftUI

enum AppTheme {
    // Primary brand colors
    static let accent = Color.indigo
    static let accentGradient = LinearGradient(
        colors: [Color.indigo, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Note colors
    static let rightHandNote = Color.cyan.opacity(0.85)
    static let leftHandNote = Color.orange.opacity(0.80)
    static let blackKeyNote = Color.purple.opacity(0.9)

    // Keyboard
    static let keyHighlight = Color.blue.opacity(0.5)
    static let keyHighlightBlack = Color.blue

    // Cards & surfaces
    static let cardBackground = Color(.systemGray6)
    static let heroGradient = LinearGradient(
        colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Text
    static let subtitleColor = Color.secondary

    // Practice mode
    static let correctNote = Color.green.opacity(0.8)
    static let missedNote = Color.red.opacity(0.7)
    static let loopMarker = Color.orange
}
