//
//  CascadeIcons.swift
//  MyPianoInstructor
//
//  One place that names every icon the app uses. Icons are SF Symbols; the
//  `CascadeGlyph` cases keep call sites readable and make it a one-line change
//  to swap any symbol app-wide.
//

import SwiftUI

enum CascadeGlyph: String, CaseIterable {
    case cascade
    case home, add, play, progress
    case scan, camera, pdf, importFile, theme, award, film, info, flame, clock, check, sparkle, bell, share, plus, chevronRight, xmark, keyboard, music, lock, refresh, gear, back, headphones, loop, question

    /// The SF Symbol behind each glyph.
    var symbolName: String {
        switch self {
        case .cascade:      return "pianokeys"
        case .home:         return "house.fill"
        case .add:          return "plus.circle.fill"
        case .play:         return "play.fill"
        case .progress:     return "chart.bar.fill"
        case .scan:         return "camera.viewfinder"
        case .camera:       return "camera.viewfinder"
        case .pdf:          return "doc.richtext"
        case .importFile:   return "doc.badge.plus"
        case .theme:        return "paintpalette"
        case .award:        return "trophy"
        case .film:         return "film"
        case .info:         return "info"
        case .flame:        return "flame.fill"
        case .clock:        return "clock"
        case .check:        return "checkmark"
        case .sparkle:      return "sparkles"
        case .bell:         return "bell"
        case .share:        return "square.and.arrow.up"
        case .plus:         return "plus"
        case .chevronRight: return "chevron.right"
        case .xmark:        return "xmark"
        case .keyboard:     return "pianokeys"
        case .music:        return "music.note"
        case .lock:         return "lock"
        case .refresh:      return "arrow.counterclockwise"
        case .gear:         return "gearshape"
        case .back:         return "chevron.left"
        case .headphones:   return "headphones"
        case .loop:         return "repeat"
        case .question:     return "questionmark"
        }
    }

    /// Image for places that only take an `Image` (the tab bar).
    @MainActor
    func image(pointSize: CGFloat = 24) -> Image {
        switch self {
        case .play: return Image(systemName: "play.circle.fill")
        default: return Image(systemName: symbolName)
        }
    }
}

/// Draws a glyph at roughly `size` points in the given colour.
struct CascadeIconView: View {
    let glyph: CascadeGlyph
    var size: CGFloat = 20
    var color: Color = Brand.textPrimary
    var weight: CGFloat = 2.2

    init(_ glyph: CascadeGlyph, size: CGFloat = 20, color: Color = Brand.textPrimary, weight: CGFloat = 2.2) {
        self.glyph = glyph
        self.size = size
        self.color = color
        self.weight = weight
    }

    var body: some View {
        Image(systemName: glyph.symbolName)
            .font(.system(size: size * 0.86, weight: weight > 2.4 ? .bold : .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Icon in a tinted circle — the standard "action" treatment.
struct IconBadge: View {
    let glyph: CascadeGlyph
    var tint: Color = Brand.teal
    var diameter: CGFloat = 44
    var body: some View {
        CascadeIconView(glyph, size: diameter * 0.46, color: tint)
            .frame(width: diameter, height: diameter)
            .background(tint.opacity(0.14), in: Circle())
    }
}
