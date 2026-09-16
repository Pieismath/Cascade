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

    static let all: [SampleScan] = [
        SampleScan(id: "twinkle", title: "Twinkle Twinkle Little Star", composer: "Traditional",
                   pageResources: ["Sample-TwinkleTwinkle-1"], xmlResource: "TwinkleTwinkle"),
        SampleScan(id: "ode", title: "Ode to Joy", composer: "Beethoven",
                   pageResources: ["Sample-OdeToJoy-1"], xmlResource: "OdeToJoy"),
        SampleScan(id: "mary", title: "Mary Had a Little Lamb", composer: "Traditional",
                   pageResources: ["Sample-MaryHadALittleLamb-1"], xmlResource: "MaryHadALittleLamb"),
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

    /// Small preview for the sample picker.
    func thumbnail() -> UIImage? {
        loadPages().first
    }
}
