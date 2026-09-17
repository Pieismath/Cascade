//
//  SampleScans.swift
//  MyPianoInstructor
//
//  Bundled "try it" scans: a page image plus the transcription it produces,
//  so anyone can see the scan → falling notes → video flow instantly without
//  signing in or spending a credit. The result is prepared in advance (no
//  network call), and the UI says so.
//

import UIKit

struct SampleScan: Identifiable, Hashable {
    let id: String
    let title: String
    let composer: String
    /// Bundled page images, in order (PNG resources).
    let pageResources: [String]
    /// The MusicXML the scan produces (bundled starter-library file).
    let xmlResource: String

    /// Ordered from the most impressive to the simplest. All public domain.
    static let all: [SampleScan] = [
        SampleScan(id: "furelise", title: "Für Elise (opening)", composer: "Beethoven",
                   pageResources: ["Sample-FurElise-1", "Sample-FurElise-2"], xmlResource: "FurEliseOpening"),
        SampleScan(id: "minuet", title: "Minuet in G", composer: "Bach / Petzold",
                   pageResources: ["Sample-MinuetInG-1", "Sample-MinuetInG-2"], xmlResource: "MinuetInG"),
        SampleScan(id: "ode", title: "Ode to Joy", composer: "Beethoven",
                   pageResources: ["Sample-OdeToJoy-1"], xmlResource: "OdeToJoy"),
        SampleScan(id: "twinkle", title: "Twinkle Twinkle Little Star", composer: "Traditional",
                   pageResources: ["Sample-TwinkleTwinkle-1"], xmlResource: "TwinkleTwinkle"),
    ]

    func loadPages() -> [UIImage] {
        pageResources.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "png")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { UIImage(data: $0) }
        }
    }

    func loadMusicXML() -> String? {
        Bundle.main.url(forResource: xmlResource, withExtension: "musicxml")
            .flatMap { try? Data(contentsOf: $0) }
            .map { String(decoding: $0, as: UTF8.self) }
    }
}
