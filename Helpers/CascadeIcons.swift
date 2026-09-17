//
//  CascadeIcons.swift
//  MyPianoInstructor
//
//  Cascade's own icon set: geometric glyphs drawn on a 24-point grid with
//  rounded 2.2-point strokes, so they match the note bars and the keyboard
//  rather than looking like stock system symbols. `CascadeIconView` draws
//  one inline; `CascadeGlyph.image()` renders one to a template image for
//  places that only accept an Image (the tab bar).
//

import SwiftUI

enum CascadeGlyph: String, CaseIterable {
    case cascade      // three falling bars over a key line — the mark
    case home, add, play, progress
    case scan, camera, pdf, importFile, theme, award, film, info, flame, clock, check, sparkle, bell, share, plus, chevronRight, xmark, keyboard, music, lock, refresh, gear, back, headphones, loop, question

    /// Path in a 24×24 box. `filled` parts are returned separately.
    func paths() -> (stroke: Path, fill: Path) {
        var s = Path()
        var f = Path()
        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
        func line(_ a: CGPoint, _ b: CGPoint) { s.move(to: a); s.addLine(to: b) }
        switch self {
        case .cascade:
            f.addPath(rr(5, 3, 3.2, 9, 1.6)); f.addPath(rr(10.4, 7, 3.2, 8, 1.6)); f.addPath(rr(15.8, 1.5, 3.2, 12, 1.6))
            line(CGPoint(x: 3, y: 19.5), CGPoint(x: 21, y: 19.5))
            line(CGPoint(x: 9, y: 19.5), CGPoint(x: 9, y: 22)); line(CGPoint(x: 15, y: 19.5), CGPoint(x: 15, y: 22))
        case .home:
            f.addPath(rr(5, 4, 3, 8, 1.5)); f.addPath(rr(10.5, 8, 3, 6, 1.5)); f.addPath(rr(16, 2.5, 3, 10, 1.5))
            s.addPath(rr(3, 16.5, 18, 5, 1.5))
            line(CGPoint(x: 9, y: 16.5), CGPoint(x: 9, y: 21.5)); line(CGPoint(x: 15, y: 16.5), CGPoint(x: 15, y: 21.5))
        case .add, .plus:
            if self == .add { s.addPath(rr(3, 3, 18, 18, 6)) }
            line(CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 16)); line(CGPoint(x: 8, y: 12), CGPoint(x: 16, y: 12))
        case .play:
            f.move(to: CGPoint(x: 7.5, y: 4.5)); f.addLine(to: CGPoint(x: 19.5, y: 12)); f.addLine(to: CGPoint(x: 7.5, y: 19.5)); f.closeSubpath()
        case .progress:
            f.addPath(rr(3.5, 13, 4, 7, 1.5)); f.addPath(rr(10, 8, 4, 12, 1.5)); f.addPath(rr(16.5, 3, 4, 17, 1.5))
        case .scan, .camera:
            // viewfinder corners
            s.move(to: CGPoint(x: 3, y: 8)); s.addLine(to: CGPoint(x: 3, y: 5)); s.addQuadCurve(to: CGPoint(x: 5, y: 3), control: CGPoint(x: 3, y: 3)); s.addLine(to: CGPoint(x: 8, y: 3))
            s.move(to: CGPoint(x: 16, y: 3)); s.addLine(to: CGPoint(x: 19, y: 3)); s.addQuadCurve(to: CGPoint(x: 21, y: 5), control: CGPoint(x: 21, y: 3)); s.addLine(to: CGPoint(x: 21, y: 8))
            s.move(to: CGPoint(x: 21, y: 16)); s.addLine(to: CGPoint(x: 21, y: 19)); s.addQuadCurve(to: CGPoint(x: 19, y: 21), control: CGPoint(x: 21, y: 21)); s.addLine(to: CGPoint(x: 16, y: 21))
            s.move(to: CGPoint(x: 8, y: 21)); s.addLine(to: CGPoint(x: 5, y: 21)); s.addQuadCurve(to: CGPoint(x: 3, y: 19), control: CGPoint(x: 3, y: 21)); s.addLine(to: CGPoint(x: 3, y: 16))
            if self == .scan {
                // staff lines inside
                for i in 0..<3 { line(CGPoint(x: 7.5, y: 9 + CGFloat(i) * 3), CGPoint(x: 16.5, y: 9 + CGFloat(i) * 3)) }
            } else {
                s.addEllipse(in: CGRect(x: 8.5, y: 8.5, width: 7, height: 7))
            }
        case .pdf, .importFile:
            s.move(to: CGPoint(x: 6, y: 3)); s.addLine(to: CGPoint(x: 14, y: 3)); s.addLine(to: CGPoint(x: 19, y: 8)); s.addLine(to: CGPoint(x: 19, y: 19))
            s.addQuadCurve(to: CGPoint(x: 17, y: 21), control: CGPoint(x: 19, y: 21)); s.addLine(to: CGPoint(x: 7, y: 21))
            s.addQuadCurve(to: CGPoint(x: 5, y: 19), control: CGPoint(x: 5, y: 21)); s.addLine(to: CGPoint(x: 5, y: 4)); s.addQuadCurve(to: CGPoint(x: 6, y: 3), control: CGPoint(x: 5, y: 3))
            s.move(to: CGPoint(x: 14, y: 3)); s.addLine(to: CGPoint(x: 14, y: 8)); s.addLine(to: CGPoint(x: 19, y: 8))
            if self == .pdf {
                line(CGPoint(x: 8.5, y: 12.5), CGPoint(x: 15.5, y: 12.5)); line(CGPoint(x: 8.5, y: 16), CGPoint(x: 13.5, y: 16))
            } else {
                line(CGPoint(x: 12, y: 11), CGPoint(x: 12, y: 17.5)); s.move(to: CGPoint(x: 9.5, y: 15)); s.addLine(to: CGPoint(x: 12, y: 17.5)); s.addLine(to: CGPoint(x: 14.5, y: 15))
            }
        case .theme:
            s.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            f.addEllipse(in: CGRect(x: 7, y: 8, width: 3.4, height: 3.4)); f.addEllipse(in: CGRect(x: 12.5, y: 6, width: 3.4, height: 3.4)); f.addEllipse(in: CGRect(x: 14.5, y: 12, width: 3.4, height: 3.4))
        case .award:
            s.move(to: CGPoint(x: 7, y: 4)); s.addLine(to: CGPoint(x: 17, y: 4)); s.addLine(to: CGPoint(x: 16.5, y: 11)); s.addQuadCurve(to: CGPoint(x: 12, y: 15), control: CGPoint(x: 16, y: 15)); s.addQuadCurve(to: CGPoint(x: 7.5, y: 11), control: CGPoint(x: 8, y: 15)); s.closeSubpath()
            s.move(to: CGPoint(x: 7, y: 6)); s.addQuadCurve(to: CGPoint(x: 5, y: 10), control: CGPoint(x: 3.5, y: 6.5))
            s.move(to: CGPoint(x: 17, y: 6)); s.addQuadCurve(to: CGPoint(x: 19, y: 10), control: CGPoint(x: 20.5, y: 6.5))
            line(CGPoint(x: 12, y: 15), CGPoint(x: 12, y: 18.5)); line(CGPoint(x: 8.5, y: 20.5), CGPoint(x: 15.5, y: 20.5))
        case .film:
            s.addPath(rr(3, 5, 18, 14, 2.5))
            line(CGPoint(x: 7.5, y: 5), CGPoint(x: 7.5, y: 19)); line(CGPoint(x: 16.5, y: 5), CGPoint(x: 16.5, y: 19))
            for y in [8.5, 12, 15.5] as [CGFloat] { line(CGPoint(x: 3, y: y), CGPoint(x: 7.5, y: y)); line(CGPoint(x: 16.5, y: y), CGPoint(x: 21, y: y)) }
        case .info:
            s.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            line(CGPoint(x: 12, y: 11), CGPoint(x: 12, y: 16.5)); f.addEllipse(in: CGRect(x: 10.7, y: 6.8, width: 2.6, height: 2.6))
        case .flame:
            f.move(to: CGPoint(x: 12, y: 2.5))
            f.addCurve(to: CGPoint(x: 18.5, y: 14), control1: CGPoint(x: 13, y: 8), control2: CGPoint(x: 18.5, y: 9))
            f.addCurve(to: CGPoint(x: 12, y: 21.5), control1: CGPoint(x: 18.5, y: 18.5), control2: CGPoint(x: 15.5, y: 21.5))
            f.addCurve(to: CGPoint(x: 5.5, y: 14), control1: CGPoint(x: 8.5, y: 21.5), control2: CGPoint(x: 5.5, y: 18.5))
            f.addCurve(to: CGPoint(x: 9, y: 8.5), control1: CGPoint(x: 5.5, y: 11.5), control2: CGPoint(x: 7.5, y: 10))
            f.addCurve(to: CGPoint(x: 12, y: 2.5), control1: CGPoint(x: 10.5, y: 7), control2: CGPoint(x: 11.5, y: 5))
            f.closeSubpath()
        case .clock:
            s.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            s.move(to: CGPoint(x: 12, y: 7)); s.addLine(to: CGPoint(x: 12, y: 12.5)); s.addLine(to: CGPoint(x: 15.5, y: 14.5))
        case .check:
            s.move(to: CGPoint(x: 5, y: 12.5)); s.addLine(to: CGPoint(x: 10, y: 17.5)); s.addLine(to: CGPoint(x: 19.5, y: 7))
        case .sparkle:
            f.move(to: CGPoint(x: 12, y: 2)); f.addQuadCurve(to: CGPoint(x: 22, y: 12), control: CGPoint(x: 13.5, y: 10.5)); f.addQuadCurve(to: CGPoint(x: 12, y: 22), control: CGPoint(x: 13.5, y: 13.5)); f.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 10.5, y: 13.5)); f.addQuadCurve(to: CGPoint(x: 12, y: 2), control: CGPoint(x: 10.5, y: 10.5)); f.closeSubpath()
        case .bell:
            s.move(to: CGPoint(x: 6, y: 16.5)); s.addLine(to: CGPoint(x: 6, y: 11)); s.addCurve(to: CGPoint(x: 18, y: 11), control1: CGPoint(x: 6, y: 3), control2: CGPoint(x: 18, y: 3)); s.addLine(to: CGPoint(x: 18, y: 16.5)); s.addLine(to: CGPoint(x: 20, y: 18.5)); s.addLine(to: CGPoint(x: 4, y: 18.5)); s.closeSubpath()
            s.move(to: CGPoint(x: 10, y: 21)); s.addQuadCurve(to: CGPoint(x: 14, y: 21), control: CGPoint(x: 12, y: 23))
        case .share:
            s.move(to: CGPoint(x: 12, y: 15)); s.addLine(to: CGPoint(x: 12, y: 3.5)); s.move(to: CGPoint(x: 8, y: 7.5)); s.addLine(to: CGPoint(x: 12, y: 3.5)); s.addLine(to: CGPoint(x: 16, y: 7.5))
            s.move(to: CGPoint(x: 5, y: 12)); s.addLine(to: CGPoint(x: 5, y: 19)); s.addQuadCurve(to: CGPoint(x: 7, y: 21), control: CGPoint(x: 5, y: 21)); s.addLine(to: CGPoint(x: 17, y: 21)); s.addQuadCurve(to: CGPoint(x: 19, y: 19), control: CGPoint(x: 19, y: 21)); s.addLine(to: CGPoint(x: 19, y: 12))
        case .chevronRight:
            s.move(to: CGPoint(x: 9.5, y: 6)); s.addLine(to: CGPoint(x: 15.5, y: 12)); s.addLine(to: CGPoint(x: 9.5, y: 18))
        case .back:
            s.move(to: CGPoint(x: 14.5, y: 6)); s.addLine(to: CGPoint(x: 8.5, y: 12)); s.addLine(to: CGPoint(x: 14.5, y: 18))
        case .xmark:
            line(CGPoint(x: 7, y: 7), CGPoint(x: 17, y: 17)); line(CGPoint(x: 17, y: 7), CGPoint(x: 7, y: 17))
        case .keyboard:
            s.addPath(rr(3, 6, 18, 12, 2))
            for x in [8, 12.5, 17] as [CGFloat] { line(CGPoint(x: x, y: 6), CGPoint(x: x, y: 18)) }
            f.addPath(rr(6.6, 6, 2.8, 6.5, 1)); f.addPath(rr(11.1, 6, 2.8, 6.5, 1)); f.addPath(rr(15.6, 6, 2.8, 6.5, 1))
        case .music:
            f.addEllipse(in: CGRect(x: 5, y: 14, width: 6, height: 5)); s.move(to: CGPoint(x: 11, y: 16.5)); s.addLine(to: CGPoint(x: 11, y: 4.5)); s.addLine(to: CGPoint(x: 18, y: 6.5)); s.addLine(to: CGPoint(x: 18, y: 10))
        case .lock:
            s.addPath(rr(5, 10.5, 14, 10.5, 2.5)); s.move(to: CGPoint(x: 8, y: 10.5)); s.addLine(to: CGPoint(x: 8, y: 8)); s.addCurve(to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 8, y: 2.5), control2: CGPoint(x: 16, y: 2.5)); s.addLine(to: CGPoint(x: 16, y: 10.5))
            f.addEllipse(in: CGRect(x: 10.7, y: 14, width: 2.6, height: 2.6))
        case .refresh:
            s.addArc(center: CGPoint(x: 12, y: 12), radius: 7.5, startAngle: .degrees(-40), endAngle: .degrees(250), clockwise: false)
            s.move(to: CGPoint(x: 14.5, y: 3.5)); s.addLine(to: CGPoint(x: 18.2, y: 7)); s.addLine(to: CGPoint(x: 14, y: 8.5))
        case .gear:
            s.addEllipse(in: CGRect(x: 8.5, y: 8.5, width: 7, height: 7))
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                let c = CGPoint(x: 12 + cos(a) * 8.2, y: 12 + sin(a) * 8.2)
                f.addEllipse(in: CGRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2))
            }
        case .headphones:
            s.move(to: CGPoint(x: 4.5, y: 15)); s.addLine(to: CGPoint(x: 4.5, y: 12)); s.addCurve(to: CGPoint(x: 19.5, y: 12), control1: CGPoint(x: 4.5, y: 2), control2: CGPoint(x: 19.5, y: 2)); s.addLine(to: CGPoint(x: 19.5, y: 15))
            f.addPath(rr(3, 13.5, 4.5, 7, 2)); f.addPath(rr(16.5, 13.5, 4.5, 7, 2))
        case .loop:
            s.move(to: CGPoint(x: 6, y: 10)); s.addLine(to: CGPoint(x: 6, y: 9)); s.addQuadCurve(to: CGPoint(x: 9, y: 6), control: CGPoint(x: 6, y: 6)); s.addLine(to: CGPoint(x: 18, y: 6))
            s.move(to: CGPoint(x: 15.5, y: 3.5)); s.addLine(to: CGPoint(x: 18, y: 6)); s.addLine(to: CGPoint(x: 15.5, y: 8.5))
            s.move(to: CGPoint(x: 18, y: 14)); s.addLine(to: CGPoint(x: 18, y: 15)); s.addQuadCurve(to: CGPoint(x: 15, y: 18), control: CGPoint(x: 18, y: 18)); s.addLine(to: CGPoint(x: 6, y: 18))
            s.move(to: CGPoint(x: 8.5, y: 15.5)); s.addLine(to: CGPoint(x: 6, y: 18)); s.addLine(to: CGPoint(x: 8.5, y: 20.5))
        case .question:
            s.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            s.move(to: CGPoint(x: 9, y: 9.5)); s.addCurve(to: CGPoint(x: 12, y: 13), control1: CGPoint(x: 9, y: 5.5), control2: CGPoint(x: 15.5, y: 6.5)); s.addLine(to: CGPoint(x: 12, y: 14.5))
            f.addEllipse(in: CGRect(x: 10.7, y: 16.5, width: 2.6, height: 2.6))
        }
        return (s, f)
    }

    /// Template image for places that only take an `Image` (tab bar).
    @MainActor
    func image(pointSize: CGFloat = 24) -> Image {
        if let cached = Self.imageCache[self] { return cached }
        let renderer = ImageRenderer(content: CascadeIconView(self, size: pointSize, color: .black))
        renderer.scale = 3
        let image: Image
        if let ui = renderer.uiImage {
            image = Image(uiImage: ui.withRenderingMode(.alwaysTemplate))
        } else {
            image = Image(systemName: "circle")
        }
        Self.imageCache[self] = image
        return image
    }

    @MainActor private static var imageCache: [CascadeGlyph: Image] = [:]
}

/// Draws a glyph at `size` points with the current foreground colour.
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
        let (stroke, fill) = glyph.paths()
        let scale = size / 24
        ZStack {
            fill.applying(CGAffineTransform(scaleX: scale, y: scale))
                .fill(color)
            stroke.applying(CGAffineTransform(scaleX: scale, y: scale))
                .stroke(color, style: StrokeStyle(lineWidth: weight * scale, lineCap: .round, lineJoin: .round))
        }
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
