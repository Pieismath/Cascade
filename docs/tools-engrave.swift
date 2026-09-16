// Minimal sheet-music engraver for the bundled beginner songs (macOS, AppKit).
// Renders a MusicXML subset (single part, voices 1/2, quarter-note based
// rhythms) to a letter-sized PNG page so the app can ship sample "scans".
//
//   swiftc -O engrave.swift -o engrave
//   ./engrave Title Composer input.musicxml output.png

import AppKit
import Foundation

// MARK: - Parse

struct Note {
    var voice: Int
    var beat: Double        // within measure
    var beats: Double
    var isRest: Bool
    var step: String = "C"
    var octave: Int = 4
    var alter: Int = 0
    var isChord = false
}

struct Measure {
    var notes: [Note] = []
}

final class Parser: NSObject, XMLParserDelegate {
    var measures: [Measure] = []
    var divisions = 1
    var beatsPerMeasure = 4
    var text = ""
    var inNote = false
    var current = Note(voice: 1, beat: 0, beats: 0, isRest: false)
    var position = 0.0
    var lastNonChordStart = 0.0
    var inBackup = false
    var inForward = false
    var otherDuration = 0

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "measure": measures.append(Measure()); position = 0
        case "note": inNote = true; current = Note(voice: 1, beat: position, beats: 0, isRest: false)
        case "rest": current.isRest = true
        case "chord": current.isChord = true
        case "backup": inBackup = true
        case "forward": inForward = true
        default: break
        }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "divisions": divisions = Int(v) ?? 1
        case "beats": beatsPerMeasure = Int(v) ?? 4
        case "step": current.step = v
        case "octave": current.octave = Int(v) ?? 4
        case "alter": current.alter = Int(v) ?? 0
        case "voice": current.voice = Int(v) ?? 1
        case "duration":
            if inNote { current.beats = Double(Int(v) ?? 0) / Double(divisions) }
            else { otherDuration = Int(v) ?? 0 }
        case "note":
            if current.isChord { current.beat = lastNonChordStart } else { current.beat = position; lastNonChordStart = position; position += current.beats }
            measures[measures.count - 1].notes.append(current)
            inNote = false
        case "backup": position -= Double(otherDuration) / Double(divisions); inBackup = false
        case "forward": position += Double(otherDuration) / Double(divisions); inForward = false
        default: break
        }
        text = ""
    }
}

// MARK: - Layout

let args = CommandLine.arguments
guard args.count == 5 else { print("usage: engrave Title Composer in.musicxml out.png"); exit(1) }
let title = args[1], composer = args[2]
let data = try! Data(contentsOf: URL(fileURLWithPath: args[3]))
let parser = Parser()
let xml = XMLParser(data: data); xml.delegate = parser; xml.parse()

let hasBass = parser.measures.contains { $0.notes.contains { $0.voice >= 2 } }
let pageW: CGFloat = 1700, pageH: CGFloat = 2200
let margin: CGFloat = 130
let spacing: CGFloat = 15            // staff line spacing
let staffH = spacing * 4
let measuresPerSystem = 4
let staffGap: CGFloat = 90           // treble→bass within a system
let systemGap: CGFloat = 130
let clefArea: CGFloat = 150

let image = NSImage(size: NSSize(width: pageW, height: pageH))
image.lockFocusFlipped(true)
let ctx = NSGraphicsContext.current!.cgContext
ctx.setFillColor(NSColor.white.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
ctx.setShouldAntialias(true)

func drawText(_ s: String, at p: CGPoint, size: CGFloat, font: String = "Times New Roman", bold: Bool = false, center: Bool = false, right: Bool = false) {
    let f = NSFont(name: bold ? "\(font) Bold" : font, size: size) ?? NSFont.systemFont(ofSize: size)
    let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor.black]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    let x = center ? p.x - sz.width / 2 : (right ? p.x - sz.width : p.x)
    str.draw(at: CGPoint(x: x, y: p.y))
}

func drawGlyph(_ s: String, x: CGFloat, baselineY: CGFloat, size: CGFloat) {
    let f = NSFont(name: "Apple Symbols", size: size)!
    let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(str)
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: x, y: baselineY)
    ctx.scaleBy(x: 1, y: -1)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// Title
drawText(title, at: CGPoint(x: pageW / 2, y: margin - 40), size: 54, bold: true, center: true)
drawText(composer, at: CGPoint(x: pageW - margin, y: margin + 40), size: 26, right: true)

let stepIndex: [String: Int] = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6]
/// Diatonic steps above the staff's bottom line (treble: E4, bass: G2).
func staffSteps(_ n: Note, bass: Bool) -> Int {
    let abs = n.octave * 7 + stepIndex[n.step, default: 0]
    let ref = bass ? (2 * 7 + 4) : (4 * 7 + 2)
    return abs - ref
}

let systems = Int(ceil(Double(parser.measures.count) / Double(measuresPerSystem)))
let systemH = hasBass ? staffH * 2 + staffGap : staffH
var y = margin + 110

for s in 0..<systems {
    let firstM = s * measuresPerSystem
    let lastM = min(parser.measures.count, firstM + measuresPerSystem)
    let count = lastM - firstM
    let left = margin, right = pageW - margin
    let staffTops: [CGFloat] = hasBass ? [y, y + staffH + staffGap] : [y]

    // staves
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(2)
    for top in staffTops {
        for i in 0..<5 {
            let ly = top + CGFloat(i) * spacing
            ctx.move(to: CGPoint(x: left, y: ly)); ctx.addLine(to: CGPoint(x: right, y: ly))
        }
    }
    ctx.strokePath()
    // system brace line
    ctx.setLineWidth(3)
    ctx.move(to: CGPoint(x: left, y: staffTops[0])); ctx.addLine(to: CGPoint(x: left, y: staffTops.last! + staffH)); ctx.strokePath()

    // clefs + time signature (first system)
    drawGlyph("\u{1D11E}", x: left + 12, baselineY: staffTops[0] + spacing * 3, size: spacing * 5.2)
    if hasBass { drawGlyph("\u{1D122}", x: left + 14, baselineY: staffTops[1] + spacing * 3, size: spacing * 4.2) }
    if s == 0 {
        for top in staffTops {
            drawText("\(parser.beatsPerMeasure)", at: CGPoint(x: left + 92, y: top - 6), size: 40, bold: true)
            drawText("4", at: CGPoint(x: left + 92, y: top + spacing * 2 - 6), size: 40, bold: true)
        }
    }

    let measureW = (right - left - clefArea) / CGFloat(measuresPerSystem)
    for m in 0..<count {
        let mx = left + clefArea + CGFloat(m) * measureW
        let measure = parser.measures[firstM + m]
        let beatW = (measureW - 50) / CGFloat(parser.beatsPerMeasure)

        // barline
        ctx.setLineWidth(2)
        let barX = mx + measureW
        let isLast = firstM + m == parser.measures.count - 1
        ctx.move(to: CGPoint(x: barX, y: staffTops[0])); ctx.addLine(to: CGPoint(x: barX, y: staffTops.last! + staffH)); ctx.strokePath()
        if isLast {
            ctx.setLineWidth(5)
            ctx.move(to: CGPoint(x: barX + 8, y: staffTops[0])); ctx.addLine(to: CGPoint(x: barX + 8, y: staffTops.last! + staffH)); ctx.strokePath()
        }

        for n in measure.notes {
            let bass = hasBass && n.voice >= 2
            let top = bass ? staffTops[1] : staffTops[0]
            let x = mx + 30 + CGFloat(n.beat) * beatW
            let bottomLine = top + staffH

            if n.isRest {
                let glyph: String
                switch n.beats {
                case 4...: glyph = "\u{1D13B}"
                case 2..<4: glyph = "\u{1D13C}"
                case 1..<2: glyph = "\u{1D13D}"
                default: glyph = "\u{1D13E}"
                }
                drawGlyph(glyph, x: x, baselineY: top + spacing * 2.5, size: spacing * 3.2)
                continue
            }

            let steps = staffSteps(n, bass: bass)
            let ny = bottomLine - CGFloat(steps) * spacing / 2
            // ledger lines
            ctx.setLineWidth(2)
            if steps < 0 {
                var st = -2
                while st >= steps { let ly = bottomLine - CGFloat(st) * spacing / 2; ctx.move(to: CGPoint(x: x - 14, y: ly)); ctx.addLine(to: CGPoint(x: x + 14, y: ly)); st -= 2 }
            } else if steps > 8 {
                var st = 10
                while st <= steps { let ly = bottomLine - CGFloat(st) * spacing / 2; ctx.move(to: CGPoint(x: x - 14, y: ly)); ctx.addLine(to: CGPoint(x: x + 14, y: ly)); st += 2 }
            }
            ctx.strokePath()

            // accidental
            if n.alter != 0 {
                drawText(n.alter > 0 ? "♯" : "♭", at: CGPoint(x: x - 34, y: ny - 22), size: 30)
            }

            // head
            ctx.saveGState()
            ctx.translateBy(x: x, y: ny)
            ctx.rotate(by: -0.35)
            let head = CGRect(x: -9, y: -6.5, width: 18, height: 13)
            if n.beats >= 2 {
                ctx.setLineWidth(3); ctx.strokeEllipse(in: head.insetBy(dx: 1.5, dy: 1.5))
            } else {
                ctx.fillEllipse(in: head)
            }
            ctx.restoreGState()

            // dot
            let dotted = abs(n.beats - 1.5) < 0.01 || abs(n.beats - 3) < 0.01 || abs(n.beats - 0.75) < 0.01
            if dotted { ctx.fillEllipse(in: CGRect(x: x + 14, y: ny - 3, width: 6, height: 6)) }

            // stem + flag
            if n.beats < 4 && !n.isChord {
                let up = steps < 4
                let sx = up ? x + 8 : x - 8
                let sy = up ? ny - spacing * 3.5 : ny + spacing * 3.5
                ctx.setLineWidth(2.2)
                ctx.move(to: CGPoint(x: sx, y: ny)); ctx.addLine(to: CGPoint(x: sx, y: sy)); ctx.strokePath()
                if n.beats < 1 {
                    ctx.setLineWidth(4)
                    ctx.move(to: CGPoint(x: sx, y: sy))
                    ctx.addQuadCurve(to: CGPoint(x: sx + 14, y: sy + (up ? 22 : -22)), control: CGPoint(x: sx + 16, y: sy + (up ? 6 : -6)))
                    ctx.strokePath()
                }
            }
        }
    }
    y += systemH + systemGap
}

// footer
drawText("Sample score for Cascade — public-domain melody", at: CGPoint(x: pageW / 2, y: pageH - margin + 20), size: 20, center: true)

image.unlockFocus()
let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[4]))
print("wrote \(args[4]) measures=\(parser.measures.count) bass=\(hasBass)")
