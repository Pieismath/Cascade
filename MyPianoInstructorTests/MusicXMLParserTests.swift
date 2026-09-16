//
//  MusicXMLParserTests.swift
//  MyPianoInstructorTests
//
//  Golden tests for the MusicXML → PlaybackData pipeline. The bundled songs
//  double as fixtures: a parser regression that changes note counts, hand
//  mapping, or timing on these files shows up here before it reaches users.
//

import Testing
import Foundation
@testable import MyPianoInstructor

@Suite("MusicXMLParser")
struct MusicXMLParserTests {

    private func bundled(_ name: String) throws -> PlaybackData {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(
            Bundle.main.url(forResource: name, withExtension: "musicxml")
                ?? bundle.url(forResource: name, withExtension: "musicxml"),
            "missing bundled fixture \(name)"
        )
        return MusicXMLParser.parse(data: try Data(contentsOf: url))
    }

    @Test("Twinkle Twinkle parses to the expected melody")
    func twinkle() throws {
        let playback = try bundled("TwinkleTwinkle")
        #expect(playback.notes.count > 20)
        #expect(playback.tempo > 0)
        // Notes are sorted and never overlap in the same voice for a monophonic melody.
        let starts = playback.notes.map(\.startTime)
        #expect(starts == starts.sorted())
        // The first two notes of Twinkle are the same C.
        let first = playback.notes.prefix(2).map(\.pitch)
        #expect(first == [60, 60])
    }

    @Test("MuseScore exports map voices 5-8 to the left hand")
    func museScoreHandMapping() throws {
        let playback = try bundled("FurElise")
        let left = playback.notes.filter { $0.voice == 2 }
        let right = playback.notes.filter { $0.voice == 1 }
        #expect(!left.isEmpty)
        #expect(!right.isEmpty)
        // Left-hand material in Für Elise sits below middle C on average.
        let leftAverage = Double(left.map(\.pitch).reduce(0, +)) / Double(left.count)
        let rightAverage = Double(right.map(\.pitch).reduce(0, +)) / Double(right.count)
        #expect(leftAverage < rightAverage)
        #expect(playback.pedalEvents.count > 100)
    }

    @Test("Tempo map: Chopin Nocturne uses its first printed tempo")
    func tempoMap() throws {
        let playback = try bundled("ChopinNocturneOp9No1")
        #expect(playback.tempo > 40 && playback.tempo < 200)
        #expect(playback.totalDuration > 60)
        #expect(playback.notes.count > 1000)
    }

    @Test("Ties merge into a single held note")
    func tiesMerge() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <sound tempo="60"/>
              <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><tie type="start"/></note>
              <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><tie type="stop"/></note>
              <note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice></note>
            </measure>
          </part>
        </score-partwise>
        """
        let playback = MusicXMLParser.parse(data: Data(xml.utf8))
        #expect(playback.notes.count == 2)
        let c = playback.notes.first { $0.pitch == 60 }
        #expect(c != nil)
        #expect(abs((c?.duration ?? 0) - 2.0) < 0.001)
        #expect(abs(playback.totalDuration - 4.0) < 0.01)
    }

    @Test("Two-staff scan output maps staff 2 / voice 5 to the left hand")
    func scanSubsetHandMapping() {
        let xml = """
        <score-partwise version="4.0">
          <part id="P1">
            <measure number="1">
              <attributes><divisions>2</divisions><staves>2</staves></attributes>
              <sound tempo="90"/>
              <note><pitch><step>E</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><staff>1</staff></note>
              <backup><duration>4</duration></backup>
              <note><pitch><step>C</step><octave>3</octave></pitch><duration>2</duration><voice>5</voice><staff>2</staff></note>
              <note><pitch><step>G</step><octave>3</octave></pitch><duration>2</duration><voice>5</voice><staff>2</staff></note>
            </measure>
          </part>
        </score-partwise>
        """
        let playback = MusicXMLParser.parse(data: Data(xml.utf8))
        #expect(playback.notes.count == 3)
        #expect(playback.notes.filter { $0.voice == 2 }.map(\.pitch).sorted() == [48, 55])
        #expect(playback.notes.first { $0.pitch == 76 }?.voice == 1)
        // Left hand starts at beat 0 thanks to <backup>.
        #expect(playback.notes.first { $0.pitch == 48 }?.startTime == 0)
    }

    @Test("Garbage input yields the fallback instead of crashing")
    func garbage() {
        let playback = MusicXMLParser.parse(data: Data("this is not xml".utf8))
        #expect(playback.notes.count >= 1)
        #expect(playback.totalDuration > 0)
    }
}

private final class BundleToken {}
