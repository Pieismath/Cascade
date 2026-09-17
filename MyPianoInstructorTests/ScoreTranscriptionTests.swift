//
//  ScoreTranscriptionTests.swift
//  MyPianoInstructorTests
//
//  Offline tests for the scan pipeline pieces that don't need a model:
//  staff-system detection, stitching of per-batch MusicXML, and the
//  measure-length sanity check.
//

import Testing
import UIKit
@testable import MyPianoInstructor

// MARK: - Fixtures

/// Draws a synthetic page: `systems` grand staves (two 5-line staves each).
private func syntheticPage(systems: Int, size: CGSize = CGSize(width: 1200, height: 1600)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        UIColor.black.setStroke()

        let lineSpacing: CGFloat = 9
        let staffHeight = lineSpacing * 4
        let staffGap: CGFloat = 40          // within a system
        let systemHeight = staffHeight * 2 + staffGap
        let topMargin: CGFloat = 120
        let available = size.height - topMargin * 2
        let systemPitch = available / CGFloat(systems)

        for s in 0..<systems {
            let systemTop = topMargin + CGFloat(s) * systemPitch + (systemPitch - systemHeight) / 2
            for staff in 0..<2 {
                let staffTop = systemTop + CGFloat(staff) * (staffHeight + staffGap)
                for line in 0..<5 {
                    let y = staffTop + CGFloat(line) * lineSpacing
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: 80, y: y))
                    path.addLine(to: CGPoint(x: size.width - 80, y: y))
                    path.lineWidth = 2
                    path.stroke()
                }
            }
            // A few "notes" so the page isn't just lines.
            for n in 0..<8 {
                let x = 150 + CGFloat(n) * 120
                UIColor.black.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: systemTop + 10, width: 12, height: 9))
            }
        }
    }
}

private let measureXML: (Int, String) -> String = { number, body in
    "<measure number=\"\(number)\">\(body)</measure>"
}

private func doc(_ measures: [String], attributes: String = "<attributes><divisions>2</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time></attributes>", tempo: Double? = 100) -> String {
    var body = ""
    for (i, m) in measures.enumerated() {
        let prefix = i == 0 ? attributes + (tempo.map { "<sound tempo=\"\($0)\"/>" } ?? "") : ""
        body += measureXML(i + 1, prefix + m)
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1">
    \(body)
    </part></score-partwise>
    """
}

private func note(_ step: String, _ octave: Int, _ duration: Int, voice: Int = 1, staff: Int = 1) -> String {
    "<note><pitch><step>\(step)</step><octave>\(octave)</octave></pitch><duration>\(duration)</duration><voice>\(voice)</voice><staff>\(staff)</staff></note>"
}

// MARK: - Splitter

/// Two systems crowded into the top third of a tall page. Nothing about this
/// page is symmetric, so a profile read upside down, or bands that drift,
/// cannot pass unnoticed.
private func topHeavyPage(size: CGSize = CGSize(width: 1200, height: 2400)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        UIColor.black.setStroke()

        let lineSpacing: CGFloat = 9
        let staffHeight = lineSpacing * 4
        let staffGap: CGFloat = 40      // inside a grand staff
        let systemGap: CGFloat = 90     // between systems
        var staffTop: CGFloat = 100

        for system in 0..<2 {
            for staff in 0..<2 {
                for line in 0..<5 {
                    let y = staffTop + CGFloat(line) * lineSpacing
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: 80, y: y))
                    path.addLine(to: CGPoint(x: size.width - 80, y: y))
                    path.lineWidth = 2
                    path.stroke()
                }
                staffTop += staffHeight + (staff == 0 ? staffGap : systemGap)
            }
            _ = system
        }
    }
}

@Suite("SheetSystemSplitter")
struct SheetSystemSplitterTests {

    @Test("Detects each grand staff on a synthetic page")
    func detectsSystems() throws {
        let page = syntheticPage(systems: 4)
        let systems = try #require(SheetSystemSplitter.detectSystems(in: page))
        #expect(systems.count == 4)
        #expect(systems.allSatisfy { $0.staffCount == 2 })
        // Bands are in reading order and don't overlap.
        for (a, b) in zip(systems, systems.dropFirst()) {
            #expect(a.rect.maxY <= b.rect.minY + 1)
        }
    }

    @Test("Split produces one crop per system, each shorter than the page")
    func splitCrops() {
        let page = syntheticPage(systems: 3)
        let crops = SheetSystemSplitter.split(page: page)
        #expect(crops.count == 3)
        #expect(crops.allSatisfy { $0.size.height < page.size.height / 2 })
        #expect(crops.allSatisfy { $0.size.width == page.size.width })
    }

    @Test("Blank and non-music pages are passed through whole")
    func fallbackOnBlank() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
        }
        let crops = SheetSystemSplitter.split(page: blank)
        #expect(crops.count == 1)
        #expect(crops[0].size == blank.size)
    }

    @Test("Systems are found where the music actually is, right way up")
    func bandsMatchPagePosition() throws {
        let page = topHeavyPage()
        let systems = try #require(SheetSystemSplitter.detectSystems(in: page))
        #expect(systems.count == 2)
        #expect(systems.allSatisfy { $0.staffCount == 2 })
        // Everything drawn sits above y=500 of a 2400pt page; reading the
        // profile bottom-up used to land the bands at the other end.
        #expect(systems[0].rect.minY < 120)
        #expect(systems.last!.rect.maxY < 700)
    }

    @Test("A staff missing a line is still a staff")
    func staffWithMissingLine() throws {
        // First staff has four of its five lines (the middle one is gone).
        let rows = [100, 110, 130, 140, 300, 310, 320, 330, 340]
        let staves = SheetSystemSplitter.groupIntoStaves(lineRows: rows)
        try #require(staves.count == 2)
        #expect(staves[0].top == 100 && staves[0].bottom == 140)
        #expect(staves[1].top == 300 && staves[1].bottom == 340)
    }

    @Test("Staff grouping requires five evenly spaced lines")
    func staffGrouping() {
        let rows = [100, 110, 120, 130, 140, 300, 310, 320, 330, 340, 500, 600]
        let staves = SheetSystemSplitter.groupIntoStaves(lineRows: rows)
        #expect(staves.count == 2)
        #expect(staves[0].top == 100 && staves[0].bottom == 140)
    }
}

// MARK: - Stitcher

@Suite("MusicXMLStitcher")
struct MusicXMLStitcherTests {

    @Test("Stitches two batches into one document with renumbered measures")
    func stitchesAndRenumbers() throws {
        let first = doc([note("C", 4, 8), note("D", 4, 8)])
        let second = doc([note("E", 4, 8), note("F", 4, 8)], tempo: 100)
        let stitched = try #require(MusicXMLStitcher.stitch([first, second]))

        #expect(MusicXMLStitcher.measureBlocks(in: stitched).count == 4)
        #expect(stitched.components(separatedBy: "<score-partwise").count == 2)
        #expect(stitched.components(separatedBy: "</score-partwise>").count == 2)
        for n in 1...4 {
            #expect(stitched.contains("<measure number=\"\(n)\">"))
        }
        // The continuation's restated tempo is dropped; the original stays.
        #expect(stitched.components(separatedBy: "<sound tempo=").count == 2)

        let playback = MusicXMLParser.parse(data: Data(stitched.utf8))
        #expect(playback.notes.count == 4)
        #expect(abs(playback.totalDuration - 16 * 60 / 100) < 0.01)
    }

    @Test("A genuine tempo change in a continuation batch is kept")
    func keepsTempoChange() throws {
        let first = doc([note("C", 4, 8)])
        let second = doc([note("E", 4, 8)], tempo: 140)
        let stitched = try #require(MusicXMLStitcher.stitch([first, second]))
        #expect(stitched.contains("tempo=\"140.0\""))
    }

    @Test("Attributes are extracted for continuation context")
    func attributes() {
        let a = MusicXMLStitcher.attributes(of: doc([note("C", 4, 8), note("D", 4, 8), note("E", 4, 8)]))
        #expect(a.divisions == 2)
        #expect(a.fifths == 0)
        #expect(a.beats == 4)
        #expect(a.beatType == 4)
        #expect(a.tempo == 100)
        #expect(a.measureCount == 3)
    }

    @Test("Context tells later batches where to continue")
    func continuationContext() {
        let attrs = MusicXMLStitcher.attributes(of: doc([note("C", 4, 8), note("D", 4, 8)]))
        let first = ScoreTranscriptionJob.context(batchIndex: 0, batchCount: 1, isSystemCrops: false, attributes: nil, nextMeasure: 1)
        #expect(first == nil)
        let later = ScoreTranscriptionJob.context(batchIndex: 1, batchCount: 3, isSystemCrops: true, attributes: attrs, nextMeasure: 3)
        #expect(later?.contains("part 2 of 3") == true)
        #expect(later?.contains("number the first measure 3") == true)
        #expect(later?.contains("<divisions>2</divisions>") == true)
        #expect(later?.contains("systems") == true)
    }
}

// MARK: - Measure checker

@Suite("MeasureChecker")
struct MeasureCheckerTests {

    @Test("Correct measures pass")
    func correct() {
        let xml = doc([
            note("C", 4, 2) + note("D", 4, 2) + note("E", 4, 2) + note("F", 4, 2),
            note("G", 4, 8),
        ])
        let report = MeasureChecker.check(musicXML: xml)
        #expect(report.measureCount == 2)
        #expect(report.suspectMeasures.isEmpty)
    }

    @Test("Overlong and short middle measures are flagged")
    func flagsBadMeasures() {
        let xml = doc([
            note("C", 4, 8),
            note("C", 4, 8) + note("D", 4, 2),   // 5 beats in 4/4
            note("E", 4, 4),                      // 2 beats in 4/4
            note("F", 4, 8),
        ])
        let report = MeasureChecker.check(musicXML: xml)
        #expect(report.suspectMeasures == [2, 3])
        #expect(abs(report.suspectFraction - 0.5) < 0.001)
    }

    @Test("Two-hand measures with backup are measured by the longest voice")
    func backupHandling() {
        let twoHands = note("C", 5, 8, voice: 1, staff: 1)
            + "<backup><duration>8</duration></backup>"
            + note("C", 3, 4, voice: 5, staff: 2) + note("G", 3, 4, voice: 5, staff: 2)
        let report = MeasureChecker.check(musicXML: doc([twoHands, twoHands]))
        #expect(report.suspectMeasures.isEmpty)
    }

    @Test("Pickup and final short measures are tolerated")
    func pickupTolerated() {
        let xml = doc([
            note("G", 4, 2),        // pickup
            note("C", 4, 8),
            note("C", 4, 6),        // final measure completes the pickup
        ])
        let report = MeasureChecker.check(musicXML: xml)
        #expect(report.suspectMeasures.isEmpty)
    }
}

// MARK: - Export helpers

@Suite("ExportFileNaming")
struct ExportFileNamingTests {
    @Test func namesAreSafe() {
        #expect(ExportFileNaming.videoFileName(for: "Für Elise (Beethoven)") == "Fur-Elise-Beethoven.mp4")
        #expect(ExportFileNaming.videoFileName(for: "   ") == "Cascade-Export.mp4")
        #expect(ExportFileNaming.videoFileName(for: "a/b:c") == "a-b-c.mp4")
    }
}
