//
//  ScanPages.swift
//  MyPianoInstructor
//
//  Getting sheet-music pages into a scan: from the document camera, from
//  Photos, or from PDFs and images in Files.
//

import SwiftUI
import PDFKit
import PhotosUI

/// A scan waiting to be converted: pages in reading order and a suggested title.
struct ScanSession: Identifiable {
    let id = UUID()
    var pages: [UIImage]
    var title: String = ""
    /// Set for the bundled samples, which convert instantly and for free.
    var sample: SampleScan? = nil
}

enum ScanPageLoader {

    /// Pages from PDFs and images picked in Files, in the order picked.
    /// The title comes from the first file's name.
    static func pages(from urls: [URL]) -> (pages: [UIImage], title: String, unreadable: [String]) {
        var pages: [UIImage] = []
        var unreadable: [String] = []
        var title = ""

        for url in urls {
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

            if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                    unreadable.append(url.lastPathComponent)
                    continue
                }
                pages.append(contentsOf: rasterize(document))
            } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                pages.append(image)
            } else {
                unreadable.append(url.lastPathComponent)
                continue
            }
            if title.isEmpty { title = ScoreFileImport.title(for: url) }
        }
        return (pages, title, unreadable)
    }

    /// Photos picked in the system photo picker.
    static func pages(from items: [PhotosPickerItem]) async -> [UIImage] {
        var pages: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                pages.append(image)
            }
        }
        return pages
    }

    /// Renders PDF pages larger than the upload size so system crops keep
    /// full resolution after splitting.
    private static func rasterize(_ document: PDFDocument) -> [UIImage] {
        (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let longest = max(bounds.width, bounds.height)
            let scale = longest > 0 ? (SheetPagePrep.maxDimension * 2) / longest : 1
            return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
    }
}
