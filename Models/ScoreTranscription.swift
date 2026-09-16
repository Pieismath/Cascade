//
//  ScoreTranscription.swift
//  MyPianoInstructor
//
//  The scan pipeline between "page images" and "validated MusicXML":
//
//    pages ──▶ SheetSystemSplitter ──▶ batches of system crops
//          ──▶ SheetMusicRecognizer (one request per batch, shared job id)
//          ──▶ MusicXMLStitcher (one continuous document)
//          ──▶ MeasureChecker (rhythm sanity report)
//
//  Sending individual systems instead of whole pages gives the vision model
//  several times more pixels per staff line, keeps each reply short enough to
//  avoid truncation, and removes the old "6 pages per scan" ceiling. Every
//  stage degrades gracefully: if staff detection is unsure the page is sent
//  whole, and if stitching finds nothing usable the caller falls back to a
//  whole-page pass.
//

import UIKit
import CoreGraphics

// MARK: - System Splitter

/// Finds the staff systems on a page image using a horizontal darkness
/// profile: staff lines are the only features that run across most of the
/// page width, so rows containing them stand out sharply.
nonisolated enum SheetSystemSplitter {

    struct System {
        /// Vertical band in source-image pixels, including margins.
        let rect: CGRect
        let staffCount: Int
    }

    /// Analysis width; the profile is computed on a downsampled grayscale copy.
    private static let analysisWidth = 800
    /// Fraction of the row that must be dark for the row to count as a staff line.
    private static let lineFillThreshold: CGFloat = 0.45

    /// Splits a page into system crops in reading order. Returns `[page]`
    /// unchanged when fewer than two staves are found or the layout looks
    /// unlike printed piano music, so an odd page never gets butchered.
    nonisolated static func split(page: UIImage) -> [UIImage] {
        guard let systems = detectSystems(in: page), systems.count >= 1,
              let cg = page.cgImage else { return [page] }

        // One system that spans the page is just the page.
        if systems.count == 1, systems[0].rect.height > CGFloat(cg.height) * 0.8 {
            return [page]
        }

        var crops: [UIImage] = []
        for system in systems {
            let rect = system.rect.integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            guard rect.height > 20, let cropped = cg.cropping(to: rect) else { continue }
            crops.append(UIImage(cgImage: cropped, scale: 1, orientation: .up))
        }
        return crops.isEmpty ? [page] : crops
    }

    /// Detects grand-staff systems; nil when the page doesn't look like sheet music.
    nonisolated static func detectSystems(in page: UIImage) -> [System]? {
        guard let cg = page.cgImage else { return nil }
        guard let profile = rowDarknessProfile(of: cg) else { return nil }
        let scale = CGFloat(cg.height) / CGFloat(profile.count)

        let lineRows = staffLineRows(profile: profile)
        let staves = groupIntoStaves(lineRows: lineRows)
        guard staves.count >= 2 else { return nil }

        let systems = groupIntoSystems(staves: staves, pageHeight: profile.count)
        return systems.map { band in
            System(
                rect: CGRect(x: 0, y: CGFloat(band.top) * scale,
                             width: CGFloat(cg.width), height: CGFloat(band.bottom - band.top) * scale),
                staffCount: band.staffCount
            )
        }
    }

    // MARK: Profile

    /// Per-row fraction of dark pixels, computed on a downsampled grayscale copy.
    nonisolated static func rowDarknessProfile(of image: CGImage) -> [CGFloat]? {
        let width = min(analysisWidth, image.width)
        let height = max(1, Int(CGFloat(image.height) * CGFloat(width) / CGFloat(image.width)))
        guard width > 10, height > 10 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Adaptive threshold: anything darker than halfway between the page's
        // typical brightness and black counts as ink.
        var histogram = [Int](repeating: 0, count: 256)
        for p in pixels { histogram[Int(p)] += 1 }
        var cumulative = 0
        var median = 255
        for (value, count) in histogram.enumerated() {
            cumulative += count
            if cumulative >= pixels.count / 2 { median = value; break }
        }
        let inkThreshold = UInt8(max(40, min(200, median / 2)))

        // Ignore a 4% margin on each side so page edges and shadows don't count.
        let inset = width / 25
        let usable = width - 2 * inset
        var profile = [CGFloat](repeating: 0, count: height)
        // CGContext bitmaps are bottom-up; flip so index 0 is the top row.
        for row in 0..<height {
            var dark = 0
            let base = (height - 1 - row) * width
            for x in inset..<(width - inset) where pixels[base + x] < inkThreshold {
                dark += 1
            }
            profile[row] = CGFloat(dark) / CGFloat(usable)
        }
        return profile
    }

    // MARK: Staff lines

    /// Rows whose darkness crosses the threshold, merged into single line centres.
    nonisolated static func staffLineRows(profile: [CGFloat]) -> [Int] {
        var lines: [Int] = []
        var runStart: Int? = nil
        for (row, value) in profile.enumerated() {
            if value >= lineFillThreshold {
                if runStart == nil { runStart = row }
            } else if let start = runStart {
                // A staff line is thin; thick runs are barlines' worth of text/boxes.
                if row - start <= max(3, profile.count / 150) {
                    lines.append((start + row - 1) / 2)
                }
                runStart = nil
            }
        }
        return lines
    }

    struct Staff {
        let top: Int
        let bottom: Int
        var spacing: CGFloat { CGFloat(bottom - top) / 4 }
    }

    /// Groups line centres into 5-line staves with consistent spacing.
    nonisolated static func groupIntoStaves(lineRows: [Int]) -> [Staff] {
        var staves: [Staff] = []
        var i = 0
        while i + 4 < lineRows.count {
            let candidate = Array(lineRows[i..<(i + 5)])
            let gaps = zip(candidate.dropFirst(), candidate).map { $0 - $1 }
            let mean = CGFloat(gaps.reduce(0, +)) / 4
            let consistent = mean >= 2 && gaps.allSatisfy { abs(CGFloat($0) - mean) <= max(1.5, mean * 0.35) }
            if consistent {
                staves.append(Staff(top: candidate[0], bottom: candidate[4]))
                i += 5
            } else {
                i += 1
            }
        }
        return staves
    }

    struct Band {
        var top: Int
        var bottom: Int
        var staffCount: Int
    }

    /// Groups staves into systems: staves closer together than about two
    /// staff heights belong to the same system (a piano grand staff), larger
    /// gaps separate systems. Bands extend to the midpoint of each gap.
    nonisolated static func groupIntoSystems(staves: [Staff], pageHeight: Int) -> [Band] {
        guard let first = staves.first else { return [] }
        let staffHeight = staves.map { CGFloat($0.bottom - $0.top) }.reduce(0, +) / CGFloat(staves.count)
        let joinGap = staffHeight * 2.2

        var groups: [[Staff]] = [[first]]
        for staff in staves.dropFirst() {
            let previous = groups[groups.count - 1].last!
            if CGFloat(staff.top - previous.bottom) <= joinGap {
                groups[groups.count - 1].append(staff)
            } else {
                groups.append([staff])
            }
        }

        // Piano music comes in pairs; if every group is a single staff the
        // splitter is probably looking at a lead sheet or text, and a wrong
        // split would hurt more than it helps.
        if groups.allSatisfy({ $0.count == 1 }) && groups.count > 1 {
            // Pair adjacent single staves when their gaps alternate small/large.
            return []
        }

        var bands: [Band] = []
        for (index, group) in groups.enumerated() {
            let top = group.first!.top
            let bottom = group.last!.bottom
            let margin = Int(staffHeight * 1.2)
            let upperLimit = index == 0 ? 0 : (groups[index - 1].last!.bottom + top) / 2
            let lowerLimit = index == groups.count - 1 ? pageHeight : (bottom + groups[index + 1].first!.top) / 2
            bands.append(Band(
                top: max(upperLimit, top - margin),
                bottom: min(lowerLimit, bottom + margin),
                staffCount: group.count
            ))
        }
        return bands
    }
}

// MARK: - Stitcher

/// Combines per-batch MusicXML documents into one continuous score.
nonisolated enum MusicXMLStitcher {

    struct Attributes {
        var divisions: Int?
        var fifths: Int?
        var beats: Int?
        var beatType: Int?
        var tempo: Double?
        var measureCount: Int
    }

    /// Pulls the facts a continuation request needs from a batch result.
    nonisolated static func attributes(of xml: String) -> Attributes {
        Attributes(
            divisions: firstInt(in: xml, tag: "divisions"),
            fifths: firstInt(in: xml, tag: "fifths"),
            beats: firstInt(in: xml, tag: "beats"),
            beatType: firstInt(in: xml, tag: "beat-type"),
            tempo: firstTempo(in: xml),
            measureCount: measureBlocks(in: xml).count
        )
    }

    /// Concatenates the measures of `parts` (in order) under the first part's
    /// header. Measures are renumbered, and continuation batches lose a
    /// leading tempo mark that merely restates the current tempo.
    nonisolated static func stitch(_ parts: [String]) -> String? {
        guard let first = parts.first, let headerEnd = first.range(of: "<measure") else { return nil }

        var header = String(first[..<headerEnd.lowerBound])
        if header.range(of: "<part ") == nil && header.range(of: "<part>") == nil {
            return nil
        }
        if !header.contains("<?xml") {
            header = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + header
        }

        var measures: [String] = []
        var currentTempo = firstTempo(in: first)
        for (index, part) in parts.enumerated() {
            var blocks = measureBlocks(in: part)
            if index > 0, let firstBlock = blocks.first {
                if let tempo = firstTempo(in: firstBlock) {
                    if let current = currentTempo, abs(tempo - current) / current < 0.05 {
                        blocks[0] = removingTempo(from: firstBlock)
                    } else {
                        currentTempo = tempo
                    }
                }
                // Later tempo marks in the block still update the running tempo.
            }
            for block in blocks {
                if let tempo = lastTempo(in: block) { currentTempo = tempo }
            }
            measures.append(contentsOf: blocks)
        }
        guard !measures.isEmpty else { return nil }

        let renumbered = measures.enumerated().map { index, block in
            renumber(block, to: index + 1)
        }
        return header + renumbered.joined(separator: "\n") + "\n</part>\n</score-partwise>\n"
    }

    // MARK: helpers

    nonisolated static func measureBlocks(in xml: String) -> [String] {
        var blocks: [String] = []
        var searchRange = xml.startIndex..<xml.endIndex
        while let start = xml.range(of: "<measure", range: searchRange) {
            guard let end = xml.range(of: "</measure>", range: start.upperBound..<xml.endIndex) else { break }
            blocks.append(String(xml[start.lowerBound..<end.upperBound]))
            searchRange = end.upperBound..<xml.endIndex
        }
        return blocks
    }

    nonisolated private static func renumber(_ block: String, to number: Int) -> String {
        guard let tagEnd = block.range(of: ">") else { return block }
        let openTag = String(block[..<tagEnd.upperBound])
        let rest = String(block[tagEnd.upperBound...])
        let newTag: String
        if let numberRange = openTag.range(of: #"number\s*=\s*"[^"]*""#, options: .regularExpression) {
            newTag = openTag.replacingCharacters(in: numberRange, with: "number=\"\(number)\"")
        } else {
            newTag = openTag.replacingOccurrences(of: "<measure", with: "<measure number=\"\(number)\"")
        }
        return newTag + rest
    }

    nonisolated private static func removingTempo(from block: String) -> String {
        block.replacingOccurrences(of: #"<sound[^>]*\btempo\s*=\s*"[^"]*"[^>]*/>"#, with: "", options: .regularExpression)
    }

    nonisolated static func firstInt(in xml: String, tag: String) -> Int? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return Int(xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated static func firstTempo(in xml: String) -> Double? {
        tempos(in: xml).first
    }

    nonisolated static func lastTempo(in xml: String) -> Double? {
        tempos(in: xml).last
    }

    nonisolated private static func tempos(in xml: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"tempo\s*=\s*"([0-9.]+)""#) else { return [] }
        let ns = xml as NSString
        return regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)).compactMap {
            Double(ns.substring(with: $0.range(at: 1)))
        }
    }
}

// MARK: - Measure Checker

/// Rhythm sanity check on transcribed MusicXML: every measure's longest voice
/// should add up to the time signature. Measures that don't are the usual
/// symptom of a misread dot, tuplet, or beam, so they're reported to the user
/// and used to decide whether a higher-quality pass is worth it.
nonisolated enum MeasureChecker {

    struct Report: Equatable {
        var measureCount: Int
        var suspectMeasures: [Int]
        var suspectFraction: Double {
            measureCount == 0 ? 0 : Double(suspectMeasures.count) / Double(measureCount)
        }
    }

    nonisolated static func check(musicXML: String) -> Report {
        let delegate = Delegate()
        let parser = XMLParser(data: Data(musicXML.utf8))
        parser.delegate = delegate
        parser.parse()
        return Report(measureCount: delegate.measureCount, suspectMeasures: delegate.suspects)
    }

    private nonisolated final class Delegate: NSObject, XMLParserDelegate {
        var measureCount = 0
        var suspects: [Int] = []

        private var divisions = 1
        private var beats = 4
        private var beatType = 4
        private var seenTimeSignature = false

        private var position = 0
        private var maxPosition = 0
        private var inNote = false
        private var noteIsChord = false
        private var noteIsGrace = false
        private var noteDuration = 0
        private var inBackup = false
        private var inForward = false
        private var otherDuration = 0
        private var text = ""
        private var inFirstPart = true
        private var partCount = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "part":
                partCount += 1
                inFirstPart = partCount == 1
            case "measure":
                position = 0; maxPosition = 0
            case "note":
                inNote = true; noteIsChord = false; noteIsGrace = false; noteDuration = 0
            case "chord": noteIsChord = true
            case "grace": noteIsGrace = true
            case "backup": inBackup = true; otherDuration = 0
            case "forward": inForward = true; otherDuration = 0
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "divisions": divisions = max(1, Int(value) ?? divisions)
            case "beats": beats = Int(value) ?? beats; seenTimeSignature = true
            case "beat-type": beatType = Int(value) ?? beatType
            case "duration":
                if inNote { noteDuration = Int(value) ?? 0 } else if inBackup || inForward { otherDuration = Int(value) ?? 0 }
            case "note":
                if !noteIsChord && !noteIsGrace {
                    position += noteDuration
                    maxPosition = max(maxPosition, position)
                }
                inNote = false
            case "backup":
                position = max(0, position - otherDuration); inBackup = false
            case "forward":
                position += otherDuration; maxPosition = max(maxPosition, position); inForward = false
            case "measure":
                guard inFirstPart else { break }
                measureCount += 1
                guard seenTimeSignature, beatType > 0 else { break }
                let expected = beats * 4 * divisions / beatType
                // Pickup and final measures are legitimately short; anything
                // else off by more than an eighth note is suspicious.
                let tolerance = max(1, divisions / 2)
                let isEdge = measureCount == 1
                if maxPosition > expected + tolerance || (!isEdge && maxPosition < expected - tolerance) {
                    suspects.append(measureCount)
                }
            default: break
            }
            text = ""
        }

        func parserDidEndDocument(_ parser: XMLParser) {
            // A short final measure pairs with a pickup; don't flag it.
            if let last = suspects.last, last == measureCount, measureCount > 1 {
                suspects.removeLast()
            }
        }
    }
}

// MARK: - Transcription Job

/// Runs a complete transcription: splits pages into systems, sends batches,
/// stitches, and validates. One instance per scan attempt.
nonisolated struct ScoreTranscriptionJob {

    enum Strategy {
        /// Crop each page into systems and send a few systems per request.
        case systems(perBatch: Int)
        /// Send whole pages, a few per request.
        case wholePages(perBatch: Int)
    }

    let recognizer: SheetMusicRecognizer
    let pages: [UIImage]
    var strategy: Strategy = .systems(perBatch: 4)
    /// Shared by every request of one scan (and by its retry passes) so the
    /// worker charges a single credit for the whole thing.
    var jobID: String = UUID().uuidString.lowercased()

    /// Human-readable progress ("Reading part 2 of 5…").
    typealias Progress = @Sendable (String) -> Void

    @concurrent func run(progress: Progress? = nil) async throws -> RecognizedScore {
        progress?("Preparing pages…")
        let images: [UIImage]
        let perBatch: Int
        switch strategy {
        case .systems(let n):
            images = pages.flatMap { SheetSystemSplitter.split(page: $0) }
            perBatch = max(1, n)
        case .wholePages(let n):
            images = pages
            perBatch = max(1, n)
        }

        let jpegs = images.compactMap { SheetPagePrep.jpegData(from: $0) }
        guard jpegs.count == images.count, !jpegs.isEmpty else {
            throw SheetMusicRecognitionError.imageEncodingFailed
        }

        let batches = stride(from: 0, to: jpegs.count, by: perBatch).map {
            Array(jpegs[$0..<min($0 + perBatch, jpegs.count)])
        }
        let isSystemCrops: Bool
        if case .systems = strategy { isSystemCrops = images.count > pages.count } else { isSystemCrops = false }

        var results: [String] = []
        var attributes: MusicXMLStitcher.Attributes? = nil
        var measuresSoFar = 0

        for (index, batch) in batches.enumerated() {
            try Task.checkCancellation()
            if batches.count > 1 {
                progress?("Reading part \(index + 1) of \(batches.count)…")
            } else {
                progress?("Reading the notation…")
            }
            let context = Self.context(
                batchIndex: index, batchCount: batches.count,
                isSystemCrops: isSystemCrops, attributes: attributes, nextMeasure: measuresSoFar + 1
            )
            let xml = try await recognizer.recognize(pages: batch, pageCount: pages.count, context: context, jobID: jobID)
            try Task.checkCancellation()

            let batchAttributes = MusicXMLStitcher.attributes(of: xml)
            if attributes == nil { attributes = batchAttributes }
            measuresSoFar += batchAttributes.measureCount
            results.append(xml)
        }

        progress?("Assembling the score…")
        let musicXML: String
        if results.count == 1 {
            musicXML = results[0]
        } else {
            guard let stitched = MusicXMLStitcher.stitch(results) else {
                throw SheetMusicRecognitionError.unreadableScore(
                    "The transcription came back in a form the app couldn't assemble. Please try scanning again."
                )
            }
            musicXML = stitched
        }
        let finalXML = musicXML
        return try await MainActor.run { try SheetMusicValidator.validate(musicXML: finalXML) }
    }

    /// The per-request guidance that lets a batch continue seamlessly from
    /// the previous one without seeing it.
    nonisolated static func context(
        batchIndex: Int, batchCount: Int, isSystemCrops: Bool,
        attributes: MusicXMLStitcher.Attributes?, nextMeasure: Int
    ) -> String? {
        var lines: [String] = []
        if isSystemCrops {
            lines.append("The images are consecutive systems (groups of staves) cropped from the same printed score, in reading order — not full pages. Transcribe them as one continuous passage.")
        }
        if batchCount > 1 {
            lines.append("This is part \(batchIndex + 1) of \(batchCount) of the same piece.")
        }
        if batchIndex > 0 {
            lines.append("Continue directly from the previous part: number the first measure \(nextMeasure). Include a complete <attributes> block (divisions, key, time, staves, clefs) in your first measure so the document is self-contained.")
            if let a = attributes {
                var facts: [String] = []
                if let d = a.divisions { facts.append("<divisions>\(d)</divisions>") }
                if let f = a.fifths { facts.append("key fifths \(f)") }
                if let b = a.beats, let t = a.beatType { facts.append("time \(b)/\(t)") }
                if let tempo = a.tempo { facts.append("tempo \(Int(tempo.rounded())) BPM") }
                if !facts.isEmpty {
                    lines.append("Established so far: " + facts.joined(separator: ", ") + ". Keep the same divisions value; only emit <sound tempo> if the image shows a tempo change.")
                }
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}
