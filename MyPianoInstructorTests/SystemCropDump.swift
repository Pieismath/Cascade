//
//  SystemCropDump.swift
//  MyPianoInstructorTests
//
//  Dev tool, not a check: writes the system crops the scan pipeline would
//  actually upload for a page, so recognition quality can be measured on the
//  same input the app sends (see server/cascade-scan-worker/tools/try-scan.mjs).
//
//  Run with a destination and, optionally, a page:
//    CROP_DIR=/tmp/crops xcodebuild test -only-testing:MyPianoInstructorTests/SystemCropDump
//

import Testing
import UIKit
@testable import MyPianoInstructor

struct SystemCropDump {

    @Test func dumpSystemCrops() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["CROP_DIR"], !directory.isEmpty else { return }

        let pages = (environment["CROP_PAGE"].map { [$0] } ?? SampleScan.all.flatMap(\.pageResources))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        for pageResource in pages {
            guard let url = Bundle.main.url(forResource: pageResource, withExtension: "png"),
                  let page = UIImage(contentsOfFile: url.path) else {
                Issue.record("page \(pageResource).png is not in the test bundle")
                continue
            }

            let crops = SheetSystemSplitter.split(page: page)
            for (index, crop) in crops.enumerated() {
                guard let data = SheetPagePrep.jpegData(from: crop) else { continue }
                let name = String(format: "%@-system-%02d.jpg", pageResource, index + 1)
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
            print("CROPS \(pageResource): \(crops.count)")
        }
        print("CROPS written to \(directory)")
    }
}
