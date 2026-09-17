//
//  MusicXMLParser.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 12/2/25.
//

import Foundation

nonisolated struct MusicXMLParser {
    static func parse(data: Data) -> PlaybackData {
        let delegate = MusicXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        if parser.parse() {
            return delegate.buildPlaybackData()
        } else {
            print("MusicXML parse error:", parser.parserError?.localizedDescription ?? "unknown error")
            return delegate.fallbackPlaybackData()
        }
    }
}

nonisolated private class MusicXMLParserDelegate: NSObject, XMLParserDelegate {

    // Positions and durations are tracked in quarter-note beats (Double), not raw
    // ticks: <divisions> may change mid-piece or differ between parts in exported
    // and OMR-generated files, so ticks are converted at the moment they're read.
    private struct ParsedNote {
        var pitches: [Int]
        let startBeat: Double
        var durationBeats: Double
        var voice: Int = 1
        var staff: Int?
        var isTieStart: Bool = false
        var isTieStop: Bool = false
    }

    private struct ParsedPedal {
        let beat: Double
        let isDown: Bool
    }

    private struct TempoMark {
        let beat: Double
        let bpm: Double
    }

    /// Grace notes carry no <duration>; give them a short nominal length
    /// (0.125 beats ≈ 75 ms at 100 BPM) so they are visible and audible.
    private static let graceNoteBeats = 0.125

    private var divisions: Int = 1
    private var tempoMarks: [TempoMark] = []
    private var parsedNotes: [ParsedNote] = []
    private var parsedPedals: [ParsedPedal] = []

    private var currentBeat: Double = 0
    private var currentText: String = ""

    private var inNote = false
    private var inBackup = false
    private var inForward = false

    private var noteIsRest = false
    private var noteIsChord = false
    private var noteIsGrace = false
    private var noteStep: String?
    private var noteAlter: Int = 0
    private var noteOctave: Int?
    private var noteDurationTicks: Int = 0
    private var noteVoice: String = "1"
    private var noteStaff: String?
    private var noteIsTieStart = false
    private var noteIsTieStop = false

    private var backupDurationTicks: Int = 0
    private var forwardDurationTicks: Int = 0

    private func beats(fromTicks ticks: Int) -> Double {
        Double(ticks) / Double(max(divisions, 1))
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentText = ""

        switch name {
        case "part":
            // Parts play in parallel; each one restarts at the beginning.
            currentBeat = 0

        case "note":
            inNote = true
            noteIsRest = false
            noteIsChord = false
            noteIsGrace = false
            noteStep = nil
            noteAlter = 0
            noteOctave = nil
            noteDurationTicks = 0
            noteVoice = "1"
            noteStaff = nil
            noteIsTieStart = false
            noteIsTieStop = false

        case "backup":
            inBackup = true
            backupDurationTicks = 0

        case "forward":
            inForward = true
            forwardDurationTicks = 0

        case "sound":
            if let tempoStr = attributeDict["tempo"], let t = Double(tempoStr), t > 0 {
                tempoMarks.append(TempoMark(beat: currentBeat, bpm: t))
            }

        case "chord":
            noteIsChord = true

        case "rest":
            noteIsRest = true

        case "grace":
            noteIsGrace = true

        case "tie":
            // <tie type="start"/> or <tie type="stop"/>
            if let type = attributeDict["type"] {
                if type == "start" { noteIsTieStart = true }
                if type == "stop"  { noteIsTieStop = true }
            }

        case "pedal":
            if let type = attributeDict["type"] {
                let isDown = (type == "start")
                parsedPedals.append(ParsedPedal(beat: currentBeat, isDown: isDown))
            }

        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "divisions":
            if let d = Int(trimmed) { divisions = max(d, 1) }

        case "duration":
            if let ticks = Int(trimmed) {
                if inBackup       { backupDurationTicks = ticks }
                else if inForward { forwardDurationTicks = ticks }
                else if inNote    { noteDurationTicks = ticks }
            }

        case "step":
            if inNote { noteStep = trimmed }

        case "alter":
            if inNote, let a = Int(trimmed) { noteAlter = a }

        case "octave":
            if inNote, let o = Int(trimmed) { noteOctave = o }

        case "voice":
            if inNote && !trimmed.isEmpty { noteVoice = trimmed }

        case "staff":
            if inNote && !trimmed.isEmpty { noteStaff = trimmed }

        case "backup":
            currentBeat = max(0, currentBeat - beats(fromTicks: backupDurationTicks))
            inBackup = false

        case "forward":
            currentBeat += beats(fromTicks: forwardDurationTicks)
            inForward = false

        case "note":
            finalizeNote()
            inNote = false

        default: break
        }

        currentText = ""
    }

    private func finalizeNote() {
        var durationBeats = beats(fromTicks: noteDurationTicks)

        if noteIsRest {
            if !noteIsChord { currentBeat += durationBeats }
            return
        }
        guard let step = noteStep, let octave = noteOctave else { return }

        let midiPitch = midiNumber(step: step, alter: noteAlter, octave: octave)

        if noteIsChord {
            if var last = parsedNotes.popLast() {
                last.pitches.append(midiPitch)
                // Propagate tie info for chord notes too
                if noteIsTieStart { last.isTieStart = true }
                if noteIsTieStop  { last.isTieStop = true }
                parsedNotes.append(last)
            }
            return
        }

        // Grace notes have no duration and must not advance the timeline.
        if noteIsGrace && noteDurationTicks == 0 {
            durationBeats = Self.graceNoteBeats
        }

        parsedNotes.append(ParsedNote(
            pitches: [midiPitch],
            startBeat: currentBeat,
            durationBeats: durationBeats,
            voice: Int(noteVoice) ?? 1,
            staff: noteStaff.flatMap(Int.init),
            isTieStart: noteIsTieStart,
            isTieStop: noteIsTieStop
        ))
        if !noteIsGrace {
            currentBeat += durationBeats
        }
    }

    private func midiNumber(step: String, alter: Int, octave: Int) -> Int {
        let base: Int
        switch step {
        case "C": base = 0; case "D": base = 2; case "E": base = 4
        case "F": base = 5; case "G": base = 7; case "A": base = 9
        case "B": base = 11; default: base = 0
        }
        return max(21, min(108, 12 * (octave + 1) + base + alter))
    }

    // MARK: - Tempo Map

    /// Piecewise-constant tempo segments; converts a beat position to seconds.
    /// Multiple <sound tempo> marks (rubato, ritardando sections) are honored
    /// instead of letting the last mark rewrite the whole piece's timing.
    private struct TempoMap {
        private let beats: [Double]      // segment start beats, ascending
        private let seconds: [Double]    // cumulative seconds at each segment start
        private let secPerBeat: [Double] // seconds per beat within each segment
        let initialBPM: Double

        init(marks: [TempoMark]) {
            var sorted = marks.sorted { $0.beat < $1.beat }
            if sorted.isEmpty { sorted = [TempoMark(beat: 0, bpm: 120)] }
            // Timing before the first mark uses the first mark's tempo.
            if sorted[0].beat > 0 {
                sorted.insert(TempoMark(beat: 0, bpm: sorted[0].bpm), at: 0)
            }
            // If several marks land on the same beat, the last one wins.
            var deduped: [TempoMark] = []
            for mark in sorted {
                if let last = deduped.last, abs(last.beat - mark.beat) < 1e-9 {
                    deduped[deduped.count - 1] = mark
                } else {
                    deduped.append(mark)
                }
            }

            var beats: [Double] = []
            var seconds: [Double] = []
            var secPerBeat: [Double] = []
            var elapsed = 0.0
            for (i, mark) in deduped.enumerated() {
                if i > 0 {
                    elapsed += (mark.beat - deduped[i - 1].beat) * secPerBeat[i - 1]
                }
                beats.append(mark.beat)
                seconds.append(elapsed)
                secPerBeat.append(60.0 / mark.bpm)
            }
            self.beats = beats
            self.seconds = seconds
            self.secPerBeat = secPerBeat
            self.initialBPM = deduped[0].bpm
        }

        func time(atBeat beat: Double) -> TimeInterval {
            // Binary search for the last segment starting at or before `beat`
            var lo = 0, hi = beats.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if beats[mid] <= beat { lo = mid } else { hi = mid - 1 }
            }
            return seconds[lo] + max(0, beat - beats[lo]) * secPerBeat[lo]
        }
    }

    // MARK: - Build

    /// Decide which hand each note belongs to (1 = right, 2 = left).
    ///
    /// Different exporters encode hands differently, so the rule is chosen per
    /// file: MuseScore numbers voices 1-4 for staff 1 and 5-8 for staff 2, and
    /// cross-staff notes keep their voice while their drawn <staff> changes —
    /// so when high voices exist, voice is the truth. Otherwise (Finale-style
    /// files can reuse voice 1 on both staves) the staff decides, and files
    /// with neither convention fall back to voice 1 vs. voice 2+.
    private func handForNote(_ note: ParsedNote, fileUsesVoiceBlocks: Bool) -> Int {
        if fileUsesVoiceBlocks {
            return note.voice >= 5 ? 2 : 1
        }
        if let staff = note.staff {
            return staff >= 2 ? 2 : 1
        }
        return note.voice >= 2 ? 2 : 1
    }

    func buildPlaybackData() -> PlaybackData {
        let tempoMap = TempoMap(marks: tempoMarks)
        let fileUsesVoiceBlocks = parsedNotes.contains { $0.voice >= 5 }

        // --- Step 1: Merge tied notes ---
        // Tied notes: a note with tie-start followed by one with tie-stop on the same pitch
        // should become a single longer note. We merge by extending the tie-start note's duration
        // and removing the tie-stop note.

        // First expand chords into individual pitch entries for tie merging
        struct FlatNote {
            let pitch: Int
            let startBeat: Double
            var durationBeats: Double
            let hand: Int
            var isTieStart: Bool
            var isTieStop: Bool
        }

        var flatNotes: [FlatNote] = []
        for n in parsedNotes {
            let hand = handForNote(n, fileUsesVoiceBlocks: fileUsesVoiceBlocks)
            for pitch in n.pitches {
                flatNotes.append(FlatNote(
                    pitch: pitch,
                    startBeat: n.startBeat,
                    durationBeats: n.durationBeats,
                    hand: hand,
                    isTieStart: n.isTieStart,
                    isTieStop: n.isTieStop
                ))
            }
        }

        // Merge ties: for each tie-stop note, find the matching tie-start note
        // (same pitch, same hand, whose end beat matches this note's start beat)
        // and extend the start note's duration, then mark the stop note as consumed.
        let beatEpsilon = 1e-6
        var consumed = Set<Int>()  // indices to skip

        for i in 0..<flatNotes.count {
            if consumed.contains(i) { continue }
            if !flatNotes[i].isTieStop { continue }

            let stopNote = flatNotes[i]
            // Look backwards for the matching tie-start
            for j in stride(from: i - 1, through: 0, by: -1) {
                if consumed.contains(j) { continue }
                let candidate = flatNotes[j]
                if candidate.pitch == stopNote.pitch &&
                   candidate.hand == stopNote.hand &&
                   candidate.isTieStart {
                    // Check that the start note ends where the stop note begins
                    let startEndBeat = candidate.startBeat + candidate.durationBeats
                    if abs(startEndBeat - stopNote.startBeat) < beatEpsilon {
                        // Merge: extend the start note, consume the stop note
                        flatNotes[j].durationBeats += stopNote.durationBeats
                        // If the stop note is also a tie-start (chain), propagate
                        flatNotes[j].isTieStart = stopNote.isTieStart
                        consumed.insert(i)
                        break
                    }
                }
            }
        }

        // --- Step 2: Build NoteEvents ---
        var notes: [NoteEvent] = []
        var maxEndTime: TimeInterval = 0

        for (i, n) in flatNotes.enumerated() {
            if consumed.contains(i) { continue }

            let startSec = tempoMap.time(atBeat: n.startBeat)
            let endSec = tempoMap.time(atBeat: n.startBeat + n.durationBeats)
            let durSec = max(0, endSec - startSec)

            notes.append(NoteEvent(pitch: n.pitch, startTime: startSec, duration: durSec, voice: n.hand))
            maxEndTime = max(maxEndTime, endSec)
        }

        // --- Step 3: Build Pedals ---
        var pedals: [PedalEvent] = []
        for p in parsedPedals {
            pedals.append(PedalEvent(startTime: tempoMap.time(atBeat: p.beat), isDown: p.isDown))
        }

        let sortedNotes = notes.sorted { $0.startTime < $1.startTime }
        let sortedPedals = pedals.sorted { $0.startTime < $1.startTime }

        return PlaybackData(
            tempo: tempoMap.initialBPM,
            totalDuration: maxEndTime,
            notes: sortedNotes,
            pedalEvents: sortedPedals
        )
    }

    func fallbackPlaybackData() -> PlaybackData {
        return PlaybackData(tempo: 120, totalDuration: 1.0, notes: [NoteEvent(pitch: 60, startTime: 0, duration: 0.5)])
    }
}
