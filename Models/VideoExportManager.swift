//
//  VideoExportManager.swift
//  MyPianoInstructor
//
//  Offline export of a piece as a 1080p60 falling-notes video with audio:
//
//    1. AudioExportManager renders the piano audio offline (44.1 kHz).
//    2. ExportFrameRenderer draws every frame straight into the writer's
//       pixel buffers with CoreGraphics, entirely off the main thread. The
//       previous SwiftUI ImageRenderer approach needed a main-actor render
//       per frame, which froze the UI and took minutes for long pieces.
//    3. The two tracks are merged with AVMutableComposition.
//

import SwiftUI
import AVFoundation
import Observation

@Observable
@MainActor
final class VideoExportManager {
    var exportProgress: Double = 0
    var isExporting = false

    private let audioExporter = AudioExportManager()

    /// Renders `playbackData` to `outputURL` (MP4). `completion` runs on the
    /// main actor. The screen stays awake for the duration.
    func exportVideo(playbackData: PlaybackData, outputURL: URL, completion: @escaping (Bool) -> Void) {
        guard !isExporting else { return }
        isExporting = true
        exportProgress = 0
        UIApplication.shared.isIdleTimerDisabled = true

        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("cascade_export_video.mp4")
        let tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent("cascade_export_audio.m4a")
        try? FileManager.default.removeItem(at: tempVideoURL)
        try? FileManager.default.removeItem(at: tempAudioURL)
        try? FileManager.default.removeItem(at: outputURL)

        // Snapshot everything the background work needs as plain values.
        let playback = playbackData
        let palette = ExportPalette(theme: ThemeManager())
        let audioExporter = self.audioExporter
        weak let weakSelf = self

        Task.detached(priority: .userInitiated) {
            // STEP 1: audio (synchronous offline render).
            let audioOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                audioExporter.renderAudio(playback: playback, outputURL: tempAudioURL) { ok in
                    continuation.resume(returning: ok)
                }
            }
            guard audioOK else {
                await weakSelf?.finish(success: false, completion: completion)
                return
            }

            // STEP 2: video frames.
            let videoOK = await ExportFrameWriter.write(
                playback: playback,
                palette: palette,
                outputURL: tempVideoURL
            ) { progress in
                Task { @MainActor in weakSelf?.exportProgress = progress * 0.95 }
            }
            guard videoOK else {
                await weakSelf?.finish(success: false, completion: completion)
                return
            }

            // STEP 3: merge.
            let mergeOK = await ExportMerger.merge(videoURL: tempVideoURL, audioURL: tempAudioURL, outputURL: outputURL)
            try? FileManager.default.removeItem(at: tempVideoURL)
            try? FileManager.default.removeItem(at: tempAudioURL)
            await weakSelf?.finish(success: mergeOK, completion: completion)
        }
    }

    private func finish(success: Bool, completion: @escaping (Bool) -> Void) {
        exportProgress = success ? 1 : exportProgress
        isExporting = false
        UIApplication.shared.isIdleTimerDisabled = false
        completion(success)
    }
}

// MARK: - Palette

/// Plain-value snapshot of the theme colours, safe to hand to the render thread.
nonisolated struct ExportPalette: Sendable {
    struct RGBA: Sendable {
        var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
        var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
        func withAlpha(_ alpha: CGFloat) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }
    }

    let rightHand: RGBA
    let leftHand: RGBA
    let blackKeyNote: RGBA
    let keyHighlight: RGBA
    let keyHighlightBlack: RGBA
    let showExplosions: Bool

    @MainActor
    init(theme: ThemeManager) {
        rightHand = Self.rgba(theme.rightHandNote)
        leftHand = Self.rgba(theme.leftHandNote)
        blackKeyNote = Self.rgba(theme.blackKeyNote)
        keyHighlight = Self.rgba(theme.keyHighlight)
        keyHighlightBlack = Self.rgba(theme.keyHighlightBlack)
        showExplosions = theme.showNoteExplosions
    }

    @MainActor
    private static func rgba(_ color: Color) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: r, g: g, b: b, a: a)
    }
}

// MARK: - Frame Writer

nonisolated enum ExportFrameWriter {
    static let width = 1920
    static let height = 1080
    static let fps: Int32 = 60
    static let keyboardHeight: CGFloat = 250
    static let lookahead: TimeInterval = 2.5

    /// Writes the silent video track. Returns false on any writer failure.
    static func write(
        playback: PlaybackData,
        palette: ExportPalette,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else { return false }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else {
            print("Video export: startWriting failed:", writer.error?.localizedDescription ?? "unknown")
            return false
        }
        writer.startSession(atSourceTime: .zero)

        let renderer = ExportFrameRenderer(playback: playback, palette: palette,
                                           size: CGSize(width: width, height: height))
        // Trailing second lets the last notes land and the last explosions fade.
        let totalFrames = max(1, Int((playback.totalDuration + 1.0) * Double(fps)))

        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { return false }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else { return false }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) {
                // Flip to a top-left origin so the maths matches the live view.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                renderer.draw(into: context, at: Double(frame) / Double(fps))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            let time = CMTime(value: Int64(frame), timescale: fps)
            if !adaptor.append(buffer, withPresentationTime: time) {
                print("Video export: append failed:", writer.error?.localizedDescription ?? "unknown")
                return false
            }
            if frame % 15 == 0 { progress(Double(frame) / Double(totalFrames)) }
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            print("Video export failed:", writer.error?.localizedDescription ?? "unknown error")
            return false
        }
        progress(1)
        return true
    }
}

// MARK: - Frame Renderer

/// Draws one frame of falling notes + keyboard with CoreGraphics. Mirrors
/// FallingNotesView / the export keyboard so the video matches live playback.
nonisolated final class ExportFrameRenderer {
    private let notes: [NoteEvent]
    private let palette: ExportPalette
    private let size: CGSize
    private let fallHeight: CGFloat
    private let whiteKeys: [Int]
    private let whiteWidth: CGFloat
    private let indexMap: [Int: Int]
    private let maxNoteDuration: TimeInterval
    private let pixelsPerSecond: CGFloat

    private let releaseGap: TimeInterval = 0.05
    private let explosionLifetime: TimeInterval = 0.5
    private let noteGap: CGFloat = 4

    init(playback: PlaybackData, palette: ExportPalette, size: CGSize) {
        self.notes = playback.notes
        self.palette = palette
        self.size = size
        self.fallHeight = size.height - ExportFrameWriter.keyboardHeight
        self.whiteKeys = PianoKeyHelper.whiteKeyMIDIs
        self.whiteWidth = size.width / CGFloat(whiteKeys.count)
        self.indexMap = PianoKeyHelper.whiteKeyIndexMap
        self.maxNoteDuration = playback.notes.reduce(0) { max($0, $1.duration) }
        self.pixelsPerSecond = fallHeight / CGFloat(ExportFrameWriter.lookahead)
    }

    func draw(into ctx: CGContext, at time: TimeInterval) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        drawFallingNotes(ctx, time: time)
        if palette.showExplosions { drawExplosions(ctx, time: time) }

        // Keyboard line indicator
        ctx.setFillColor(palette.keyHighlight.withAlpha(0.3).cgColor)
        ctx.fill(CGRect(x: 0, y: fallHeight - 2, width: size.width, height: 2))

        drawKeyboard(ctx, active: activeKeys(at: time))
    }

    // MARK: Notes

    private func drawFallingNotes(_ ctx: CGContext, time: TimeInterval) {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: fallHeight))
        let start = firstIndex(after: time - maxNoteDuration - 0.5)

        for i in start..<notes.count {
            let note = notes[i]
            let timeUntilStart = note.startTime - time
            if timeUntilStart > ExportFrameWriter.lookahead { break }
            let timeUntilEnd = note.startTime + note.duration - time
            if timeUntilEnd < -0.5 { continue }

            let yBottom = fallHeight - CGFloat(timeUntilStart) * pixelsPerSecond
            let yTop = fallHeight - CGFloat(timeUntilEnd) * pixelsPerSecond
            if yBottom <= 0 { continue }
            let noteHeight = max(4, yBottom - yTop - noteGap)

            guard let (x, noteWidth, color) = geometry(for: note) else { continue }
            let rect = CGRect(x: x - noteWidth / 2, y: yTop, width: noteWidth, height: noteHeight)
            ctx.setFillColor(color.cgColor)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// Centre x, width and colour for a note column; nil for pitches off the keyboard.
    private func geometry(for note: NoteEvent) -> (CGFloat, CGFloat, ExportPalette.RGBA)? {
        if PianoKeyHelper.isBlack(note.pitch) {
            guard let index = indexMap[note.pitch - 1] else { return nil }
            return (CGFloat(index + 1) * whiteWidth, whiteWidth * 0.6, palette.blackKeyNote)
        } else {
            guard let index = indexMap[note.pitch] else { return nil }
            let color = note.voice >= 2 ? palette.leftHand : palette.rightHand
            return (CGFloat(index) * whiteWidth + whiteWidth / 2, whiteWidth * 0.9, color)
        }
    }

    // MARK: Explosions (deterministic, same generator as the live view)

    private func drawExplosions(_ ctx: CGContext, time: TimeInterval) {
        let start = firstIndex(after: time - explosionLifetime)
        for i in start..<notes.count {
            let note = notes[i]
            let age = time - note.startTime
            if age < 0 { break }
            guard age < explosionLifetime, let (x, _, baseColor) = geometry(for: note) else { continue }

            let progress = age / explosionLifetime
            let originY = fallHeight - 10
            let color = baseColor.withAlpha(1)
            let particleCount = 6 + (i % 5)
            var rng = SeededRNG(seed: UInt64(i) &* 2654435761)

            for _ in 0..<particleCount {
                let angle = CGFloat(rng.nextDouble()) * 2.0 * .pi - .pi
                let speed = CGFloat(30.0 + rng.nextDouble() * 50.0)
                let pSize = CGFloat(2.0 + rng.nextDouble() * 3.0)
                let pOpacity = 0.6 + rng.nextDouble() * 0.4
                let isCircle = rng.nextDouble() > 0.5

                let opacity = (1.0 - progress) * pOpacity
                let spread = CGFloat(age) * speed
                let px = x + cos(angle) * spread
                let py = originY + sin(angle) * spread - CGFloat(age * 30)
                let s = pSize * CGFloat(1.0 - progress * 0.6)
                let rect = CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)

                ctx.setFillColor(color.withAlpha(CGFloat(opacity)).cgColor)
                if isCircle {
                    ctx.fillEllipse(in: rect)
                } else {
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 1, cornerHeight: 1, transform: nil))
                    ctx.fillPath()
                }
            }
        }
    }

    // MARK: Keyboard

    private func drawKeyboard(_ ctx: CGContext, active: Set<Int>) {
        let top = fallHeight
        let keyHeight = ExportFrameWriter.keyboardHeight
        let blackWidth = whiteWidth * 0.65
        let blackHeight = keyHeight * 0.65

        // White keys
        for (i, pitch) in whiteKeys.enumerated() {
            let rect = CGRect(x: CGFloat(i) * whiteWidth, y: top, width: whiteWidth, height: keyHeight)
            if active.contains(pitch) {
                // White key with the translucent highlight laid over it,
                // matching the live keyboard.
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(rect)
                ctx.setFillColor(palette.keyHighlight.cgColor)
                ctx.fill(rect)
            } else {
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(rect)
                // Subtle shading at the bottom edge for depth.
                ctx.setFillColor(CGColor(gray: 0.93, alpha: 1))
                ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 14, width: rect.width, height: 14))
            }
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.3))
            ctx.setLineWidth(1)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }

        // Black keys
        for i in whiteKeys.indices {
            let pitch = whiteKeys[i]
            guard i + 1 < whiteKeys.count, PianoKeyHelper.hasBlackKey(between: pitch, and: whiteKeys[i + 1]) else { continue }
            let blackPitch = pitch + 1
            let rect = CGRect(x: CGFloat(i + 1) * whiteWidth - blackWidth / 2, y: top,
                              width: blackWidth, height: blackHeight)
            let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: CGColor(gray: 0, alpha: 0.4))
            ctx.setFillColor(active.contains(blackPitch) ? palette.keyHighlightBlack.cgColor : CGColor(gray: 0.08, alpha: 1))
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()

            if !active.contains(blackPitch) {
                // Highlight strip on the key top
                ctx.setFillColor(CGColor(gray: 0.22, alpha: 1))
                ctx.fill(CGRect(x: rect.minX + 2, y: rect.minY, width: rect.width - 4, height: rect.height * 0.75))
            }
        }
    }

    // MARK: Helpers

    /// Same algorithm as PlayerView.highlightedPitches().
    private func activeKeys(at time: TimeInterval) -> Set<Int> {
        var active: Set<Int> = []
        guard !notes.isEmpty else { return active }
        for i in firstIndex(after: time - maxNoteDuration)..<notes.count {
            let n = notes[i]
            if n.startTime > time { break }
            let visualDuration = max(0.02, n.duration - releaseGap)
            if time >= n.startTime && time < n.startTime + visualDuration {
                active.insert(n.pitch)
            }
        }
        return active
    }

    private func firstIndex(after cutoff: TimeInterval) -> Int {
        var lo = 0, hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].startTime < cutoff { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

/// Deterministic xorshift generator — identical to the live view's so
/// explosion particles look the same in the video.
private nonisolated struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextDouble() -> Double { Double(next() % 10000) / 10000.0 }
}

// MARK: - Merge

nonisolated enum ExportMerger {
    static func merge(videoURL: URL, audioURL: URL, outputURL: URL) async -> Bool {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return false
        }

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        do {
            let videoDuration = try await videoAsset.load(.duration)
            if let source = try await videoAsset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: source, at: .zero)
            }
            if let source = try await audioAsset.loadTracks(withMediaType: .audio).first {
                let audioDuration = try await audioAsset.load(.duration)
                let finalDuration = min(videoDuration, audioDuration)
                try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: finalDuration), of: source, at: .zero)
            }

            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                return false
            }
            try await exporter.export(to: outputURL, as: .mp4)
            return true
        } catch {
            print("Merge failed: \(error)")
            return false
        }
    }
}
