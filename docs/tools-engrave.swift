// Sheet-music engraver for Cascade's bundled sample scans (macOS, AppKit).
// Renders the MusicXML subset the app's parser reads — two staves, chords,
// beams, ties, grace notes, dots, accidentals, key/time signatures, rests —
// to letter-sized PNG pages. Not a full engraver, but close enough to look
// like a printed score.
//
//   swiftc -O engrave.swift -o engrave
//   ./engrave "Title" "Composer" input.musicxml output-base [maxMeasureNumber]
//   → output-base-1.png, output-base-2.png, …

import AppKit
import Foundation

// MARK: - Model

struct Head {
    var step: String
    var octave: Int
    var alter: Int
    var accidental: String?     // printed accidental from the file, if any
    var tieStart = false
    var tieStop = false
}

struct Event {
    var voice: Int
    var staff: Int               // 1 = treble, 2 = bass
    var beat: Double             // quarter-note beats from measure start
    var beats: Double            // duration in quarter beats (0 for grace)
    var isRest: Bool
    var isGrace: Bool
    var heads: [Head] = []
    var beamState: String? = nil // begin / continue / end / nil
    var flagCount: Int = 0       // 1 eighth, 2 sixteenth, 3 thirty-second
    var dotted = false
    var x: CGFloat = 0           // filled during layout
}

struct Measure {
    var number: String
    var events: [Event] = []
}

// MARK: - Parse

final class Parser: NSObject, XMLParserDelegate {
    var measures: [Measure] = []
    var divisions = 1
    var beats = 4
    var beatType = 4
    var fifths = 0
    var hasStaffElements = false
    var maxMeasure: Int?

    private var text = ""
    private var inNote = false
    private var current = Event(voice: 1, staff: 1, beat: 0, beats: 0, isRest: false, isGrace: false)
    private var head = Head(step: "C", octave: 4, alter: 0)
    private var isChord = false
    private var position = 0.0
    private var lastStart = 0.0
    private var otherDuration = 0
    private var skipping = false
    private var noteType = ""

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch name {
        case "measure":
            let n = Int(a["number"] ?? "") ?? measures.count
            if let max = maxMeasure, n > max { skipping = true; return }
            measures.append(Measure(number: a["number"] ?? "\(measures.count)")); position = 0
        case "note":
            inNote = true; isChord = false; noteType = ""
            current = Event(voice: 1, staff: 1, beat: position, beats: 0, isRest: false, isGrace: false)
            head = Head(step: "C", octave: 4, alter: 0)
        case "rest": current.isRest = true
        case "chord": isChord = true
        case "grace": current.isGrace = true
        case "dot": current.dotted = true
        case "tie": if a["type"] == "start" { head.tieStart = true } else if a["type"] == "stop" { head.tieStop = true }
        case "staff": hasStaffElements = true
        default: break
        }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { text = "" }
        if skipping { if name == "measure" { skipping = false }; return }
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "divisions": divisions = Int(v) ?? 1
        case "beats": beats = Int(v) ?? 4
        case "beat-type": beatType = Int(v) ?? 4
        case "fifths": fifths = Int(v) ?? 0
        case "step": head.step = v
        case "octave": head.octave = Int(v) ?? 4
        case "alter": head.alter = Int(v) ?? 0
        case "accidental": head.accidental = v
        case "voice": current.voice = Int(v) ?? 1
        case "staff": current.staff = Int(v) ?? 1
        case "type": noteType = v
        case "beam": if current.beamState == nil { current.beamState = v }
        case "duration":
            if inNote { current.beats = Double(Int(v) ?? 0) / Double(divisions) } else { otherDuration = Int(v) ?? 0 }
        case "note":
            inNote = false
            switch noteType {
            case "eighth": current.flagCount = 1
            case "16th": current.flagCount = 2
            case "32nd": current.flagCount = 3
            case "64th": current.flagCount = 4
            default:
                if current.beats > 0 && current.beats < 1 { current.flagCount = current.beats < 0.5 ? 2 : 1 }
            }
            if isChord, var last = measures[measures.count - 1].events.popLast() {
                last.heads.append(head)
                measures[measures.count - 1].events.append(last)
                return
            }
            current.beat = position
            if !current.isRest { current.heads = [head] }
            if !current.isGrace { position += current.beats }
            measures[measures.count - 1].events.append(current)
        case "backup": position -= Double(otherDuration) / Double(divisions)
        case "forward": position += Double(otherDuration) / Double(divisions)
        default: break
        }
    }
}

// MARK: - Setup

let args = CommandLine.arguments
guard args.count >= 5 else { print("usage: engrave Title Composer in.musicxml out-base [maxMeasure]"); exit(1) }
let title = args[1], composer = args[2], outBase = args[4]
let parser = Parser()
if args.count >= 6 { parser.maxMeasure = Int(args[5]) }
let xml = XMLParser(data: try! Data(contentsOf: URL(fileURLWithPath: args[3])))
xml.delegate = parser
xml.parse()

// Staff assignment: explicit <staff> when the file has it, else voice ≥ 2 → bass.
for m in parser.measures.indices {
    for e in parser.measures[m].events.indices {
        if !parser.hasStaffElements {
            parser.measures[m].events[e].staff = parser.measures[m].events[e].voice >= 2 ? 2 : 1
        }
    }
}
let hasBass = parser.measures.contains { $0.events.contains { $0.staff == 2 } }
let quarterBeatsPerMeasure = Double(parser.beats) * 4.0 / Double(parser.beatType)

let pageW: CGFloat = 1700, pageH: CGFloat = 2200
let margin: CGFloat = 130
let sp: CGFloat = 15                      // staff space
let staffH = sp * 4
let staffGap: CGFloat = 95
let systemGap: CGFloat = 120
let clefArea: CGFloat = 150 + CGFloat(abs(parser.fifths)) * 16
let left = margin, right = pageW - margin

// Measures per system from note density (keeps 16ths legible).
let starts = parser.measures.map { m in Set(m.events.filter { !$0.isGrace }.map { "\($0.staff)-\($0.beat)" }).count }
let busiest = starts.sorted().dropLast(max(0, starts.count / 10)).last ?? 4
let neededWidth = CGFloat(busiest) * 34 + 60
let measuresPerSystem = max(3, min(8, Int((right - left - clefArea) / neededWidth)))

let stepIndex: [String: Int] = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6]
func staffSteps(_ h: Head, bass: Bool) -> Int {
    (h.octave * 7 + stepIndex[h.step, default: 0]) - (bass ? 18 : 30)
}
let sharpOrder = ["F", "C", "G", "D", "A", "E", "B"]
let flatOrder = ["B", "E", "A", "D", "G", "C", "F"]
func keyAlter(for step: String) -> Int {
    if parser.fifths > 0 { return sharpOrder.prefix(parser.fifths).contains(step) ? 1 : 0 }
    if parser.fifths < 0 { return flatOrder.prefix(-parser.fifths).contains(step) ? -1 : 0 }
    return 0
}
let trebleSharpSteps = [8, 5, 9, 6, 3, 7, 4], trebleFlatSteps = [4, 7, 3, 6, 2, 5, 1]
let bassSharpSteps = [6, 3, 7, 4, 1, 5, 2], bassFlatSteps = [2, 5, 1, 4, 0, 3, -1]

// MARK: - Drawing helpers

var ctx: CGContext!
func drawText(_ s: String, at p: CGPoint, size: CGFloat, font: String = "Times New Roman", bold: Bool = false, italic: Bool = false, center: Bool = false, right: Bool = false) {
    var name = font
    if bold && italic { name += " Bold Italic" } else if bold { name += " Bold" } else if italic { name += " Italic" }
    let f = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: NSColor.black])
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
func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat) {
    ctx.setLineWidth(width); ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
}
func accidentalGlyph(_ name: String) -> String? {
    switch name {
    case "sharp": return "♯"
    case "flat": return "♭"
    case "natural": return "♮"
    case "double-sharp": return "𝄪"
    case "flat-flat": return "𝄫"
    default: return nil
    }
}

// MARK: - Layout pass: assign x to every event

let measureW = (right - left - clefArea) / CGFloat(measuresPerSystem)
let systemCount = Int(ceil(Double(parser.measures.count) / Double(measuresPerSystem)))
let systemH = hasBass ? staffH * 2 + staffGap : staffH
let firstSystemY = margin + 120
let systemsPerPage = max(1, Int((pageH - firstSystemY - margin) / (systemH + systemGap)))
let pageCount = Int(ceil(Double(systemCount) / Double(systemsPerPage)))

for s in 0..<systemCount {
    let firstM = s * measuresPerSystem
    let lastM = min(parser.measures.count, firstM + measuresPerSystem)
    for m in firstM..<lastM {
        let mx = left + clefArea + CGFloat(m - firstM) * measureW
        // Space by beat but reserve room for grace notes and accidentals.
        let beatW = (measureW - 44) / CGFloat(quarterBeatsPerMeasure)
        for e in parser.measures[m].events.indices {
            let ev = parser.measures[m].events[e]
            var x = mx + 30 + CGFloat(ev.beat) * beatW
            if ev.isGrace { x -= 20 }
            parser.measures[m].events[e].x = x
        }
    }
}

// MARK: - Render pages

struct TieStart { var x: CGFloat; var y: CGFloat; var up: Bool }
var openTies: [String: TieStart] = [:]     // key: "\(staff)-\(voice)-\(pitch)"

for page in 0..<pageCount {
    let image = NSImage(size: NSSize(width: pageW, height: pageH))
    image.lockFocusFlipped(true)
    ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
    ctx.setShouldAntialias(true)
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setFillColor(NSColor.black.cgColor)

    var y = firstSystemY
    if page == 0 {
        drawText(title, at: CGPoint(x: pageW / 2, y: margin - 40), size: 54, bold: true, center: true)
        drawText(composer, at: CGPoint(x: right, y: margin + 40), size: 26, right: true)
    } else {
        drawText("\(title) — \(page + 1)", at: CGPoint(x: right, y: margin - 60), size: 22, italic: true, right: true)
        y = margin + 30
    }

    let firstSystem = page * systemsPerPage
    let lastSystem = min(systemCount, firstSystem + systemsPerPage)

    for s in firstSystem..<lastSystem {
        let firstM = s * measuresPerSystem
        let lastM = min(parser.measures.count, firstM + measuresPerSystem)
        let staffTops: [CGFloat] = hasBass ? [y, y + staffH + staffGap] : [y]

        // Staff lines + left brace line
        for top in staffTops {
            for i in 0..<5 { line(CGPoint(x: left, y: top + CGFloat(i) * sp), CGPoint(x: right, y: top + CGFloat(i) * sp), width: 1.8) }
        }
        line(CGPoint(x: left, y: staffTops[0]), CGPoint(x: left, y: staffTops.last! + staffH), width: 3)
        if hasBass {
            // Bracket joining the two staves (drawn; the brace glyph isn't in Apple Symbols).
            let topY = staffTops[0], botY = staffTops[1] + staffH
            line(CGPoint(x: left - 14, y: topY - 4), CGPoint(x: left - 14, y: botY + 4), width: 7)
            ctx.setLineWidth(7)
            ctx.move(to: CGPoint(x: left - 14, y: topY - 4)); ctx.addQuadCurve(to: CGPoint(x: left + 6, y: topY - 16), control: CGPoint(x: left - 2, y: topY - 6)); ctx.strokePath()
            ctx.move(to: CGPoint(x: left - 14, y: botY + 4)); ctx.addQuadCurve(to: CGPoint(x: left + 6, y: botY + 16), control: CGPoint(x: left - 2, y: botY + 6)); ctx.strokePath()
        }

        // Clefs
        drawGlyph("\u{1D11E}", x: left + 12, baselineY: staffTops[0] + sp * 3, size: sp * 5.2)
        if hasBass { drawGlyph("\u{1D122}", x: left + 14, baselineY: staffTops[1] + sp * 3, size: sp * 4.2) }

        // Key signature
        let count = abs(parser.fifths)
        for (i, top) in staffTops.enumerated() {
            let bass = i == 1
            let steps = parser.fifths > 0 ? (bass ? bassSharpSteps : trebleSharpSteps) : (bass ? bassFlatSteps : trebleFlatSteps)
            for k in 0..<count {
                let ky = top + staffH - CGFloat(steps[k]) * sp / 2
                drawText(parser.fifths > 0 ? "♯" : "♭", at: CGPoint(x: left + 88 + CGFloat(k) * 16, y: ky - 24), size: 30)
            }
        }
        // Time signature (first system only)
        if s == 0 {
            for top in staffTops {
                let tx = left + 92 + CGFloat(count) * 16
                drawText("\(parser.beats)", at: CGPoint(x: tx, y: top - 6), size: 40, bold: true)
                drawText("\(parser.beatType)", at: CGPoint(x: tx, y: top + sp * 2 - 6), size: 40, bold: true)
            }
        }

        for m in firstM..<lastM {
            let mx = left + clefArea + CGFloat(m - firstM) * measureW
            let measure = parser.measures[m]
            let barX = mx + measureW
            let isLast = m == parser.measures.count - 1
            line(CGPoint(x: barX, y: staffTops[0]), CGPoint(x: barX, y: staffTops.last! + staffH), width: 1.8)
            if isLast { line(CGPoint(x: barX + 8, y: staffTops[0]), CGPoint(x: barX + 8, y: staffTops.last! + staffH), width: 5) }
            if s == 0 && m == firstM || (m == firstM) {
                drawText(measure.number, at: CGPoint(x: mx + 2, y: staffTops[0] - 34), size: 16)
            }

            // Beam groups per (staff, voice): consecutive events begin…end.
            var beamGroups: [[Int]] = []
            var open: [String: [Int]] = [:]
            for (i, ev) in measure.events.enumerated() where !ev.isRest && !ev.isGrace && ev.flagCount > 0 {
                let key = "\(ev.staff)-\(ev.voice)"
                switch ev.beamState {
                case "begin": open[key] = [i]
                case "continue": open[key]?.append(i)
                case "end":
                    open[key]?.append(i)
                    if let g = open[key], g.count > 1 { beamGroups.append(g) }
                    open[key] = nil
                default:
                    if ev.beamState == nil {
                        // No beam info in the file: group flagged notes within the same quarter beat.
                        let unit = "\(key)-\(Int(floor(ev.beat)))"
                        open[unit, default: []].append(i)
                    }
                }
            }
            for (k, g) in open where k.split(separator: "-").count == 3 && g.count > 1 { beamGroups.append(g) }
            var beamedIndex = Set(beamGroups.flatMap { $0 })
            var stemUpFor: [Int: Bool] = [:]
            for g in beamGroups {
                let avg = g.map { i -> Int in
                    let ev = measure.events[i]
                    return staffSteps(ev.heads[0], bass: ev.staff == 2)
                }.reduce(0, +) / g.count
                for i in g { stemUpFor[i] = avg < 4 }
            }

            // Draw events
            var stemEnds: [Int: CGPoint] = [:]
            for (i, ev) in measure.events.enumerated() {
                let bass = ev.staff == 2
                let top = bass ? staffTops[1] : staffTops[0]
                let bottomLine = top + staffH
                let x = ev.x

                if ev.isRest {
                    // Rests of a second voice sit lower so they don't collide.
                    let offset: CGFloat = (ev.voice == 2 || ev.voice == 6) ? sp * 1.2 : 0
                    let mid = top + sp * 2 + offset          // middle line
                    switch ev.beats {
                    case 4...:                                 // whole: hangs below the 4th line
                        ctx.fill(CGRect(x: x - 10, y: mid - sp, width: 20, height: sp * 0.55))
                    case 2..<4:                                // half: sits on the middle line
                        ctx.fill(CGRect(x: x - 10, y: mid - sp * 0.55, width: 20, height: sp * 0.55))
                    case 1..<2:                                // quarter: zigzag
                        ctx.setLineWidth(3.2)
                        ctx.move(to: CGPoint(x: x - 4, y: mid - sp * 1.6))
                        ctx.addLine(to: CGPoint(x: x + 6, y: mid - sp * 0.6))
                        ctx.addLine(to: CGPoint(x: x - 3, y: mid + sp * 0.3))
                        ctx.addLine(to: CGPoint(x: x + 5, y: mid + sp * 1.2))
                        ctx.addQuadCurve(to: CGPoint(x: x - 4, y: mid + sp * 1.5), control: CGPoint(x: x - 6, y: mid + sp * 0.6))
                        ctx.strokePath()
                    default:                                   // eighth / 16th / 32nd: hooks + slanted stroke
                        let hooks = max(1, ev.flagCount == 0 ? (ev.beats < 0.5 ? 2 : 1) : ev.flagCount)
                        ctx.setLineWidth(2.4)
                        let topY = mid - sp * 0.8
                        ctx.move(to: CGPoint(x: x + 7, y: topY))
                        ctx.addLine(to: CGPoint(x: x - 6, y: topY + sp * (1.4 + CGFloat(hooks - 1) * 0.8)))
                        ctx.strokePath()
                        for h in 0..<hooks {
                            let hy = topY + CGFloat(h) * sp * 0.8
                            let hx = x + 7 - CGFloat(h) * 4
                            ctx.fillEllipse(in: CGRect(x: hx - 12, y: hy - 3, width: 7, height: 7))
                            ctx.setLineWidth(2.4)
                            ctx.move(to: CGPoint(x: hx - 8, y: hy + 1)); ctx.addQuadCurve(to: CGPoint(x: hx, y: hy), control: CGPoint(x: hx - 4, y: hy + 5)); ctx.strokePath()
                        }
                    }
                    if ev.dotted { ctx.fillEllipse(in: CGRect(x: x + 14, y: mid - sp * 0.6, width: 5, height: 5)) }
                    continue
                }
                guard !ev.heads.isEmpty else { continue }
                let scale: CGFloat = ev.isGrace ? 0.65 : 1
                var headYs: [CGFloat] = []
                var minSteps = Int.max, maxSteps = Int.min

                for h in ev.heads {
                    let steps = staffSteps(h, bass: bass)
                    minSteps = min(minSteps, steps); maxSteps = max(maxSteps, steps)
                    let ny = bottomLine - CGFloat(steps) * sp / 2
                    headYs.append(ny)
                    // ledger lines
                    if steps < 0 {
                        var st = -2
                        while st >= steps { let ly = bottomLine - CGFloat(st) * sp / 2; line(CGPoint(x: x - 14 * scale, y: ly), CGPoint(x: x + 14 * scale, y: ly), width: 1.8); st -= 2 }
                    } else if steps > 8 {
                        var st = 10
                        while st <= steps { let ly = bottomLine - CGFloat(st) * sp / 2; line(CGPoint(x: x - 14 * scale, y: ly), CGPoint(x: x + 14 * scale, y: ly), width: 1.8); st += 2 }
                    }
                    // accidental
                    var acc: String? = nil
                    if let printed = h.accidental { acc = accidentalGlyph(printed) }
                    else if !parser.hasStaffElements || true {
                        let expected = keyAlter(for: h.step)
                        if h.alter != expected {
                            acc = h.alter == 0 ? "♮" : (h.alter > 0 ? "♯" : "♭")
                        }
                    }
                    if let acc { drawText(acc, at: CGPoint(x: x - 34 * scale - (ev.isGrace ? 4 : 0), y: ny - 22 * scale), size: 30 * scale) }
                    // head
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: ny)
                    ctx.rotate(by: -0.35)
                    let head = CGRect(x: -9 * scale, y: -6.5 * scale, width: 18 * scale, height: 13 * scale)
                    if ev.beats >= 2 && !ev.isGrace { ctx.setLineWidth(3); ctx.strokeEllipse(in: head.insetBy(dx: 1.5, dy: 1.5)) }
                    else { ctx.fillEllipse(in: head) }
                    ctx.restoreGState()
                    if ev.dotted { ctx.fillEllipse(in: CGRect(x: x + 14 * scale, y: ny - 3, width: 6, height: 6)) }

                    // ties
                    let key = "\(ev.staff)-\(ev.voice)-\(h.step)\(h.octave)\(h.alter)"
                    let stemUp = stemUpFor[i] ?? ((minSteps + maxSteps) / 2 < 4)
                    if h.tieStop, let start = openTies[key], abs(start.y - ny) < 1 || true {
                        let dir: CGFloat = start.up ? 1 : -1
                        ctx.setLineWidth(2.2)
                        ctx.move(to: CGPoint(x: start.x + 10, y: start.y + 6 * dir))
                        ctx.addQuadCurve(to: CGPoint(x: x - 10, y: ny + 6 * dir), control: CGPoint(x: (start.x + x) / 2, y: ny + 22 * dir))
                        ctx.strokePath()
                        openTies[key] = nil
                    }
                    if h.tieStart { openTies[key] = TieStart(x: x, y: ny, up: !stemUp) }
                }

                // stem (+ flags unless beamed)
                if ev.beats < 4 || ev.isGrace {
                    let up = stemUpFor[i] ?? ((minSteps + maxSteps) / 2 < 4)
                    let sx = up ? x + 8 * scale : x - 8 * scale
                    let fromY = up ? headYs.max()! : headYs.min()!      // outer head on the stem side
                    let toHead = up ? headYs.min()! : headYs.max()!
                    let sy = toHead + (up ? -sp * 3.5 : sp * 3.5) * scale
                    line(CGPoint(x: sx, y: fromY), CGPoint(x: sx, y: sy), width: 2.2 * scale)
                    stemEnds[i] = CGPoint(x: sx, y: sy)
                    if ev.isGrace {
                        // slash through the grace stem
                        line(CGPoint(x: sx - 8, y: sy + 14), CGPoint(x: sx + 8, y: sy + 4), width: 1.8)
                    }
                    if !beamedIndex.contains(i) && ev.flagCount > 0 {
                        for f in 0..<ev.flagCount {
                            let fy = sy + CGFloat(f) * 9 * (up ? 1 : -1)
                            ctx.setLineWidth(3.6 * scale)
                            ctx.move(to: CGPoint(x: sx, y: fy))
                            ctx.addQuadCurve(to: CGPoint(x: sx + 14 * scale, y: fy + (up ? 22 : -22) * scale), control: CGPoint(x: sx + 16 * scale, y: fy + (up ? 6 : -6) * scale))
                            ctx.strokePath()
                        }
                    }
                }
            }

            // Beams: a straight line through the stem ends, thick, with secondary beams.
            for g in beamGroups {
                guard let first = stemEnds[g.first!], let last = stemEnds[g.last!] else { continue }
                let up = stemUpFor[g.first!] ?? true
                // Flatten: use the extreme stem end so no stem is shorter than 2.5 spaces.
                let ends = g.compactMap { stemEnds[$0] }
                let beamY = up ? ends.map { $0.y }.min()! : ends.map { $0.y }.max()!
                for i in g {
                    guard let e = stemEnds[i] else { continue }
                    let ev = measure.events[i]
                    let head = ev.heads.map { staffSteps($0, bass: ev.staff == 2) }
                    let bottomLine = (ev.staff == 2 ? staffTops[1] : staffTops[0]) + staffH
                    let hy = bottomLine - CGFloat(up ? head.min()! : head.max()!) * sp / 2
                    line(CGPoint(x: e.x, y: hy), CGPoint(x: e.x, y: beamY), width: 2.2)
                }
                line(CGPoint(x: first.x, y: beamY), CGPoint(x: last.x, y: beamY), width: 6)
                // secondary beams between neighbours that both have ≥ 2 flags, etc.
                for level in 2...4 {
                    for (a, b) in zip(g, g.dropFirst()) {
                        if measure.events[a].flagCount >= level && measure.events[b].flagCount >= level,
                           let ea = stemEnds[a], let eb = stemEnds[b] {
                            let off = CGFloat(level - 1) * 10 * (up ? 1 : -1)
                            line(CGPoint(x: ea.x, y: beamY + off), CGPoint(x: eb.x, y: beamY + off), width: 6)
                        }
                    }
                }
            }
        }
        y += systemH + systemGap
    }

    if page == pageCount - 1 {
        drawText("Sample score for Cascade — public-domain work", at: CGPoint(x: pageW / 2, y: pageH - margin + 20), size: 20, center: true)
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    let out = "\(outBase)-\(page + 1).png"
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out) systems=\(lastSystem - firstSystem) measuresPerSystem=\(measuresPerSystem)")
}
