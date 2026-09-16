//
//  MXLArchive.swift
//  MyPianoInstructor
//
//  Loads MusicXML text from user-picked files: plain .musicxml/.xml documents
//  in any common encoding, and compressed .mxl containers (which are ZIP
//  archives holding a META-INF/container.xml that points at the score file).
//

import Foundation
import Compression

enum MusicXMLImportError: LocalizedError {
    case notAnArchive
    case corruptArchive(String)
    case noScoreInArchive
    case unreadableText

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "This file is not a valid compressed MusicXML (.mxl) archive."
        case .corruptArchive(let detail):
            return "The .mxl archive could not be read (\(detail))."
        case .noScoreInArchive:
            return "No MusicXML score was found inside the .mxl archive."
        case .unreadableText:
            return "The file's text encoding could not be read."
        }
    }
}

enum MusicXMLImport {

    /// Returns the MusicXML text for an imported file, transparently
    /// unpacking .mxl (ZIP) containers and sniffing the text encoding.
    nonisolated static func loadString(from data: Data) throws -> String {
        if data.starts(with: [0x50, 0x4B]) {   // "PK" — a ZIP container
            let xmlData = try extractScoreData(fromArchive: data)
            return try decodeText(xmlData)
        }
        return try decodeText(data)
    }

    /// XML is UTF-8 unless a byte-order mark says otherwise.
    nonisolated private static func decodeText(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: data[data.startIndex] == 0xFF ? .utf16LittleEndian : .utf16BigEndian) {
                // Drop the decoded BOM character if present
                return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
            }
        }
        if let s = String(data: data, encoding: .utf8) {
            return s
        }
        if let s = String(data: data, encoding: .isoLatin1) {
            return s
        }
        throw MusicXMLImportError.unreadableText
    }

    // MARK: - MXL (ZIP) container

    nonisolated private static func extractScoreData(fromArchive archive: Data) throws -> Data {
        let entries = try ZipReader.entries(in: archive)

        // META-INF/container.xml names the root score file
        if let container = entries.first(where: { $0.name == "META-INF/container.xml" }),
           let containerXML = try? ZipReader.contents(of: container, in: archive),
           let text = String(data: containerXML, encoding: .utf8),
           let path = firstRootfilePath(in: text),
           let scoreEntry = entries.first(where: { $0.name == path }) {
            return try ZipReader.contents(of: scoreEntry, in: archive)
        }

        // Fallback: first XML-looking entry outside META-INF
        if let scoreEntry = entries.first(where: {
            !$0.name.hasPrefix("META-INF") && !$0.name.hasSuffix("/") &&
            ($0.name.hasSuffix(".xml") || $0.name.hasSuffix(".musicxml"))
        }) {
            return try ZipReader.contents(of: scoreEntry, in: archive)
        }

        throw MusicXMLImportError.noScoreInArchive
    }

    /// Pulls full-path="…" out of container.xml's <rootfile> element.
    nonisolated private static func firstRootfilePath(in containerXML: String) -> String? {
        guard let rootfileRange = containerXML.range(of: "<rootfile") else { return nil }
        let tail = containerXML[rootfileRange.upperBound...]
        guard let attrRange = tail.range(of: "full-path=\"") else { return nil }
        let valueStart = tail[attrRange.upperBound...]
        guard let endQuote = valueStart.firstIndex(of: "\"") else { return nil }
        return String(valueStart[..<endQuote])
    }
}

// MARK: - Minimal ZIP reader

/// Just enough of the ZIP format for .mxl files: central-directory parsing and
/// stored/deflate entries. No ZIP64, no encryption, no multi-disk archives.
private enum ZipReader {

    struct Entry {
        let name: String
        let compressionMethod: UInt16   // 0 = stored, 8 = deflate
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private nonisolated static let eocdSignature: UInt32 = 0x06054b50
    private nonisolated static let centralSignature: UInt32 = 0x02014b50
    private nonisolated static let localSignature: UInt32 = 0x04034b50

    nonisolated static func entries(in data: Data) throws -> [Entry] {
        // End-of-central-directory record: scan backwards (trailing comment
        // can be up to 65535 bytes; the record itself is 22).
        let searchStart = max(0, data.count - 22 - 65_535)
        var eocdOffset = -1
        var i = data.count - 22
        while i >= searchStart {
            if readU32(data, at: i) == eocdSignature {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard eocdOffset >= 0 else { throw MusicXMLImportError.corruptArchive("missing end record") }

        let entryCount = Int(readU16(data, at: eocdOffset + 10))
        let centralOffset = Int(readU32(data, at: eocdOffset + 16))

        var entries: [Entry] = []
        var offset = centralOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, readU32(data, at: offset) == centralSignature else {
                throw MusicXMLImportError.corruptArchive("bad central directory")
            }
            let method = readU16(data, at: offset + 10)
            let compressedSize = Int(readU32(data, at: offset + 20))
            let uncompressedSize = Int(readU32(data, at: offset + 24))
            let nameLength = Int(readU16(data, at: offset + 28))
            let extraLength = Int(readU16(data, at: offset + 30))
            let commentLength = Int(readU16(data, at: offset + 32))
            let localOffset = Int(readU32(data, at: offset + 42))

            guard offset + 46 + nameLength <= data.count else {
                throw MusicXMLImportError.corruptArchive("truncated entry name")
            }
            let nameData = data.subdata(in: dataRange(data, offset + 46, nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""

            entries.append(Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    nonisolated static func contents(of entry: Entry, in data: Data) throws -> Data {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count, readU32(data, at: base) == localSignature else {
            throw MusicXMLImportError.corruptArchive("bad local header")
        }
        // The local header repeats name/extra with its own lengths, which can
        // differ from the central directory's — sizes, however, are taken from
        // the central directory (the local copies may be zero with descriptors).
        let nameLength = Int(readU16(data, at: base + 26))
        let extraLength = Int(readU16(data, at: base + 28))
        let dataStart = base + 30 + nameLength + extraLength

        guard dataStart + entry.compressedSize <= data.count else {
            throw MusicXMLImportError.corruptArchive("truncated entry data")
        }
        let compressed = data.subdata(in: dataRange(data, dataStart, entry.compressedSize))

        switch entry.compressionMethod {
        case 0:   // stored
            return compressed
        case 8:   // deflate
            return try inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw MusicXMLImportError.corruptArchive("unsupported compression method \(entry.compressionMethod)")
        }
    }

    /// Raw DEFLATE decompression (COMPRESSION_ZLIB in the Compression
    /// framework is the raw stream, matching ZIP's method 8).
    nonisolated private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) -> Int in
                guard let outBase = outPtr.baseAddress, let inBase = inPtr.baseAddress else { return 0 }
                return compression_decode_buffer(
                    outBase.assumingMemoryBound(to: UInt8.self), expectedSize,
                    inBase.assumingMemoryBound(to: UInt8.self), input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else {
            throw MusicXMLImportError.corruptArchive("decompression failed")
        }
        return output
    }

    // MARK: Little-endian reads (Data may be a non-zero-based slice)

    nonisolated private static func dataRange(_ data: Data, _ offset: Int, _ length: Int) -> Range<Data.Index> {
        let start = data.startIndex + offset
        return start..<(start + length)
    }

    nonisolated private static func readU16(_ data: Data, at offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        guard i >= data.startIndex, i + 2 <= data.endIndex else { return 0 }
        return UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
    }

    nonisolated private static func readU32(_ data: Data, at offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        guard i >= data.startIndex, i + 4 <= data.endIndex else { return 0 }
        return UInt32(data[i])
            | (UInt32(data[i + 1]) << 8)
            | (UInt32(data[i + 2]) << 16)
            | (UInt32(data[i + 3]) << 24)
    }
}
