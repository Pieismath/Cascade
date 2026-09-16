//
//  Theme.swift
//  MyPianoInstructor
//
//  Cascade's design system. The visual idea: a dark stage on which notes fall
//  like water onto a keyboard. The falling-note colours (teal right hand, amber
//  left hand, violet black keys) are the brand — every accent in the app comes
//  from them — and each song is represented by its own "score art", a piece of
//  generated cover art drawn from its actual notes.
//
//  `AppTheme` keeps the names older views use; the new vocabulary lives in
//  `Brand`, the card/button styles, `ScoreArtView`, and `KeyboardStripView`.
//

import SwiftUI
import UIKit

// MARK: - Palette

enum Brand {
    // Accents (the note colours)
    static let teal   = Color(red: 0.24, green: 0.88, blue: 0.82)
    static let amber  = Color(red: 1.00, green: 0.64, blue: 0.28)
    static let violet = Color(red: 0.60, green: 0.46, blue: 1.00)
    static let coral  = Color(red: 1.00, green: 0.42, blue: 0.48)
    static let mint   = Color(red: 0.55, green: 0.95, blue: 0.70)

    // Stage surfaces (dark first; light mode is paper)
    static let ink         = Color(light: Color(red: 0.97, green: 0.96, blue: 0.94), dark: Color(red: 0.045, green: 0.05, blue: 0.09))
    static let ink2        = Color(light: Color(red: 0.94, green: 0.93, blue: 0.90), dark: Color(red: 0.07, green: 0.08, blue: 0.13))
    static let surface     = Color(light: .white, dark: Color(red: 0.10, green: 0.11, blue: 0.17))
    static let surfaceHigh = Color(light: Color(red: 0.99, green: 0.99, blue: 0.98), dark: Color(red: 0.14, green: 0.15, blue: 0.22))
    static let hairline    = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.09))
    static let textPrimary = Color(light: Color(red: 0.08, green: 0.08, blue: 0.12), dark: Color(red: 0.96, green: 0.96, blue: 0.98))
    static let textSecondary = Color(light: Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.58), dark: Color.white.opacity(0.58))
    static let textTertiary = Color(light: Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.38), dark: Color.white.opacity(0.36))

    static let aurora = LinearGradient(
        colors: [teal, violet],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sunrise = LinearGradient(
        colors: [amber, coral],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let stage = LinearGradient(
        colors: [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.045, green: 0.05, blue: 0.09)],
        startPoint: .top, endPoint: .bottom
    )
}

extension Color {
    /// A colour that adapts to the interface style.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Legacy names (kept so every screen picks up the new palette at once)

enum AppTheme {
    static let accent = Brand.teal
    /// Legacy inline buttons draw white text on this, so it's the deeper aurora.
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.12, green: 0.52, blue: 0.56), Brand.violet],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let heroGradient = accentGradient

    static let rightHandNote = Brand.teal.opacity(0.85)
    static let leftHandNote = Brand.amber.opacity(0.80)
    static let blackKeyNote = Brand.violet.opacity(0.9)

    static let keyHighlight = Brand.teal.opacity(0.5)
    static let keyHighlightBlack = Brand.teal

    static let cardBackground = Brand.surface
    static let subtitleColor = Brand.textSecondary

    static let correctNote = Brand.mint.opacity(0.9)
    static let missedNote = Brand.coral.opacity(0.8)
    static let loopMarker = Brand.amber
}

// MARK: - Typography

enum CascadeFont {
    /// Editorial serif for titles — the one thing that immediately reads as "not a template".
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func number(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let eyebrow: Font = .system(size: 11, weight: .bold)
}

extension View {
    /// Small tracked-out label above a section or number.
    func eyebrowStyle(_ color: Color = Brand.textTertiary) -> some View {
        self.font(CascadeFont.eyebrow).tracking(1.4).textCase(.uppercase).foregroundStyle(color)
    }
}

// MARK: - Surfaces

struct CascadeCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var raised: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(raised ? Brand.surfaceHigh : Brand.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func cascadeCard(padding: CGFloat = 16, radius: CGFloat = 22, raised: Bool = false) -> some View {
        modifier(CascadeCardModifier(padding: padding, radius: radius, raised: raised))
    }

    /// Soft coloured glow — used sparingly on primary actions and art.
    func glow(_ color: Color, radius: CGFloat = 18, opacity: Double = 0.45) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 6)
    }

    /// The app background: ink with a faint stage light at the top.
    func stageBackground() -> some View {
        self.background(StageBackground().ignoresSafeArea())
    }
}

struct StageBackground: View {
    var body: some View {
        ZStack {
            Brand.ink
            RadialGradient(
                colors: [Brand.violet.opacity(0.22), .clear],
                center: .init(x: 0.2, y: -0.1), startRadius: 0, endRadius: 520
            )
            RadialGradient(
                colors: [Brand.teal.opacity(0.14), .clear],
                center: .init(x: 1.0, y: 0.1), startRadius: 0, endRadius: 420
            )
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Brand.aurora
    var glowColor: Color = Brand.teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.03, green: 0.04, blue: 0.08))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gradient, in: Capsule())
            .glow(glowColor, radius: configuration.isPressed ? 6 : 16, opacity: 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Brand.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Brand.surfaceHigh, in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small round icon button used in player chrome and headers.
struct IconButtonStyle: ButtonStyle {
    var active: Bool = false
    var tint: Color = Brand.teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? Color(red: 0.03, green: 0.04, blue: 0.08) : Brand.textPrimary)
            .frame(width: 36, height: 36)
            .background(active ? tint : Brand.surfaceHigh, in: Circle())
            .overlay(Circle().strokeBorder(active ? .clear : Brand.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var cascadePrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var cascadeSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Chips

struct Chip: View {
    var text: String
    var icon: String? = nil
    var tint: Color = Brand.teal
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(filled ? Color(red: 0.03, green: 0.04, blue: 0.08) : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(filled ? tint : tint.opacity(0.16), in: Capsule())
    }
}

/// Section header with an editorial title and optional trailing action.
struct SectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CascadeFont.display(24))
                    .foregroundStyle(Brand.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

// MARK: - Score art

/// Generated cover art for a song: its opening notes drawn as glowing bars
/// cascading onto a keyboard. Deterministic, unique per piece, and instantly
/// tells you whether a song is sparse and slow or dense and fast.
struct ScoreArtView: View {
    let playback: PlaybackData
    /// Seconds of music shown top-to-bottom.
    var window: TimeInterval = 12
    var showKeyboard: Bool = true
    var cornerRadius: CGFloat = 16

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let keyboardH: CGFloat = showKeyboard ? max(8, size.height * 0.16) : 0
            let fieldH = size.height - keyboardH
            let notes = playback.notes.filter { $0.startTime < window }
            // Zoom the pitch axis to the range this piece actually uses (plus a
            // little air) so sparse pieces don't collapse into a thin stripe.
            let usedLow = notes.map(\.pitch).min() ?? 48
            let usedHigh = notes.map(\.pitch).max() ?? 84
            let span = max(24, usedHigh - usedLow + 6)
            let lowest = max(21, min(usedLow - 3, 108 - span + 1))
            let highest = min(108, lowest + span - 1)
            let keyW = size.width / CGFloat(highest - lowest + 1)

            // Background stage
            let bg = Path(CGRect(origin: .zero, size: size))
            context.fill(bg, with: .linearGradient(
                Gradient(colors: [Color(red: 0.12, green: 0.14, blue: 0.26), Color(red: 0.05, green: 0.06, blue: 0.11)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            guard !notes.isEmpty else { return }
            let pps = fieldH / CGFloat(window)

            func rect(for n: NoteEvent) -> CGRect {
                guard n.pitch >= lowest, n.pitch <= highest else { return .null }
                let x = CGFloat(n.pitch - lowest) * keyW
                // Later notes are higher up (they haven't "fallen" yet), like the player.
                let yBottom = fieldH - CGFloat(n.startTime) * pps
                let h = max(keyW * 0.9, CGFloat(min(n.duration, 4)) * pps - 1.5)
                return CGRect(x: x + keyW * 0.12, y: yBottom - h, width: max(2, keyW * 0.76), height: h)
            }
            func color(for n: NoteEvent) -> Color {
                if PianoKeyHelper.isBlack(n.pitch) { return Brand.violet }
                return n.voice >= 2 ? Brand.amber : Brand.teal
            }

            // Glow pass
            var glow = context
            glow.addFilter(.blur(radius: 4))
            glow.opacity = 0.7
            for n in notes {
                let r = rect(for: n)
                if r.isNull { continue }
                glow.fill(Path(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3), with: .color(color(for: n)))
            }
            // Crisp pass
            for n in notes {
                let r = rect(for: n)
                if r.isNull { continue }
                context.fill(Path(roundedRect: r, cornerRadius: min(3, r.width / 2)), with: .color(color(for: n).opacity(0.95)))
            }

            // Keyboard strip for the same pitch range, so columns line up with keys.
            if showKeyboard {
                let top = fieldH
                context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: keyboardH)), with: .color(.white.opacity(0.92)))
                let whites = (lowest...highest).filter { PianoKeyHelper.isWhite($0) }
                for (i, p) in whites.enumerated() {
                    let x = CGFloat(p - lowest) * keyW
                    if i > 0 {
                        context.fill(Path(CGRect(x: x, y: top, width: 0.7, height: keyboardH)), with: .color(.black.opacity(0.25)))
                    }
                }
                for p in lowest...highest where PianoKeyHelper.isBlack(p) {
                    let x = CGFloat(p - lowest) * keyW + keyW * 0.1
                    context.fill(Path(roundedRect: CGRect(x: x, y: top, width: keyW * 0.8, height: keyboardH * 0.62), cornerRadius: 1), with: .color(Color(red: 0.08, green: 0.08, blue: 0.12)))
                }
                context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: 1.2)), with: .color(Brand.teal.opacity(0.7)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Decorative keyboard strip for headers and empty states.
struct KeyboardStripView: View {
    var highlighted: Set<Int> = []
    var body: some View {
        Canvas { context, size in
            let whites = PianoKeyHelper.whiteKeyMIDIs
            let ww = size.width / CGFloat(whites.count)
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(.white.opacity(0.9)))
            for (i, p) in whites.enumerated() {
                if highlighted.contains(p) {
                    context.fill(Path(CGRect(x: CGFloat(i) * ww, y: 0, width: ww, height: size.height)), with: .color(Brand.teal.opacity(0.6)))
                }
                if i > 0 {
                    context.fill(Path(CGRect(x: CGFloat(i) * ww, y: 0, width: 0.7, height: size.height)), with: .color(.black.opacity(0.22)))
                }
            }
            for (i, p) in whites.enumerated() where i + 1 < whites.count && PianoKeyHelper.hasBlackKey(between: p, and: whites[i + 1]) {
                let x = CGFloat(i + 1) * ww - ww * 0.3
                let isHi = highlighted.contains(p + 1)
                context.fill(Path(roundedRect: CGRect(x: x, y: 0, width: ww * 0.6, height: size.height * 0.62), cornerRadius: 1),
                             with: .color(isHi ? Brand.violet : Color(red: 0.08, green: 0.08, blue: 0.12)))
            }
        }
    }
}

// MARK: - Misc

extension DifficultyAnalyzer.Level {
    /// Brand colour for difficulty (replaces the traffic-light look).
    var brandColor: Color {
        switch self {
        case .beginner: return Brand.mint
        case .elementary: return Brand.teal
        case .intermediate: return Brand.amber
        case .advanced: return Brand.coral
        case .expert: return Brand.violet
        }
    }
}

func formatClock(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}
