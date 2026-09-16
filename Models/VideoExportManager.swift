//
//  VideoExportManager.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 1/15/26.
//

import SwiftUI
import AVFoundation
import Observation

@Observable
@MainActor
class VideoExportManager {
    var exportProgress: Double = 0
    var isExporting = false
    
    private let audioExporter = AudioExportManager()
    
    /// Main Entry Point
    func exportVideo(playbackData: PlaybackData, outputURL: URL, completion: @escaping (Bool) -> Void) {
        self.isExporting = true
        self.exportProgress = 0
        
        // Temp URLs
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_video.mp4")
        let tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_audio.m4a")
        
        // Clean up old temp files
        try? FileManager.default.removeItem(at: tempVideoURL)
        try? FileManager.default.removeItem(at: tempAudioURL)
        try? FileManager.default.removeItem(at: outputURL)
        
        print("Starting Export Process...")

        // STEP 1: Render Audio (capture values for sendable closure)
        let playback = playbackData
        let audioURL = tempAudioURL
        let videoURL = tempVideoURL
        let finalURL = outputURL

        // Capture audioExporter and self before Task.detached — accessing
        // @MainActor stored properties from a nonisolated context is not allowed in Swift 6.
        let capturedAudioExporter = audioExporter
        weak let weakSelf2 = self

        Task.detached(priority: .userInitiated) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                capturedAudioExporter.renderAudio(playback: playback, outputURL: audioURL) { audioSuccess in
                    Task { @MainActor in
                        guard let strongSelf = weakSelf2 else {
                            continuation.resume()
                            return
                        }
                        guard audioSuccess else {
                            strongSelf.finish(success: false, completion: completion)
                            continuation.resume()
                            return
                        }

                        // STEP 2: Render Video
                        strongSelf.renderVideoOnly(playbackData: playback, outputURL: videoURL) { videoSuccess in
                            guard videoSuccess else {
                                strongSelf.finish(success: false, completion: completion)
                                continuation.resume()
                                return
                            }

                            // STEP 3: Merge Audio + Video
                            strongSelf.mergeAudioAndVideo(videoURL: videoURL, audioURL: audioURL, outputURL: finalURL) { mergeSuccess in
                                strongSelf.finish(success: mergeSuccess, completion: completion)
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func finish(success: Bool, completion: @escaping (Bool) -> Void) {
        self.isExporting = false
        completion(success)
    }
    
    // MARK: - STEP 2: Render Video Only
    private func renderVideoOnly(playbackData: PlaybackData, outputURL: URL, completion: @escaping (Bool) -> Void) {
        let width: CGFloat = 1920
        let height: CGFloat = 1080
        let fps: Int32 = 60

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            completion(false)
            return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB]
        )

        if writer.canAdd(writerInput) {
            writer.add(writerInput)
        } else {
            completion(false)
            return
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(playbackData.totalDuration * Double(fps))

        // Create a dedicated ThemeManager for export rendering (once, reused across all frames)
        let exportTheme = ThemeManager()

        // Wrap non-Sendable AVFoundation objects for safe transfer to Task.detached.
        // Each is accessed only from within that single Task — no concurrent access.
        nonisolated(unsafe) let capturedInput   = writerInput
        nonisolated(unsafe) let capturedWriter  = writer
        nonisolated(unsafe) let capturedAdaptor = pixelBufferAdaptor
        // ThemeManager is Sendable — no wrapper needed.
        let capturedTheme = exportTheme

        // Capture self weakly before entering Task.detached to avoid
        // a var-in-concurrently-executing-code Swift 6 error.
        weak let weakSelf = self

        // Run the frame loop as an async Task so we can await main-actor renders
        // without blocking the main thread (replaces DispatchQueue.main.sync).
        Task.detached(priority: .userInitiated) {
            let input   = capturedInput
            let writer  = capturedWriter
            let adaptor = capturedAdaptor
            let theme   = capturedTheme

            for frameCount in 0..<totalFrames {
                // Back-pressure: yield until the writer is ready for more data
                while !input.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1 ms
                }

                let currentTime      = Double(frameCount) / Double(fps)
                let presentationTime = CMTime(value: Int64(frameCount), timescale: fps)

                // Render the SwiftUI frame on the main actor (ImageRenderer requirement).
                // This yields without blocking the main thread between frames.
                let cgImage: CGImage? = await MainActor.run {
                    guard let strongSelf = weakSelf else { return nil }
                    strongSelf.exportProgress = Double(frameCount) / Double(totalFrames)

                    let activeKeys = strongSelf.activeKeys(at: currentTime, notes: playbackData.notes)

                    let contentView = VStack(spacing: 0) {
                        FallingNotesView(notes: playbackData.notes, currentTime: currentTime, lookahead: 2.0)
                            .frame(maxHeight: .infinity)
                        // Use pure SwiftUI keyboard — ImageRenderer can't render UIViewRepresentable
                        strongSelf.exportKeyboard(highlightedPitches: activeKeys, theme: theme, width: width, height: 250)
                    }
                    .environment(theme)
                    .background(Color.black)
                    .frame(width: width, height: height)

                    let renderer = ImageRenderer(content: contentView)
                    renderer.scale = 1.0
                    return renderer.cgImage
                }

                // Append pixel buffer; pixelBufferFromCGImage is nonisolated
                if let image = cgImage,
                   let buffer = weakSelf?.pixelBufferFromCGImage(image: image, size: CGSize(width: width, height: height)) {
                    adaptor.append(buffer, withPresentationTime: presentationTime)
                }
            }

            input.markAsFinished()
            // Same nonisolated(unsafe) transfer pattern as above — the writer
            // is only touched from its own completion handler here.
            nonisolated(unsafe) let finishedWriter = writer
            writer.finishWriting {
                // Status must be checked: a failed writer still calls this
                // handler, and reporting success would share a broken file.
                let succeeded = finishedWriter.status == .completed
                if !succeeded {
                    print("Video export failed:", finishedWriter.error?.localizedDescription ?? "unknown error")
                }
                Task { @MainActor in
                    completion(succeeded)
                }
            }
        }
    }
    
    // MARK: - STEP 3: Merge Audio + Video
    private func mergeAudioAndVideo(videoURL: URL, audioURL: URL, outputURL: URL, completion: @escaping (Bool) -> Void) {
        
        Task {
            let mixComposition = AVMutableComposition()
            
            guard let videoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                completion(false)
                return
            }
            
            let videoAsset = AVURLAsset(url: videoURL)
            let audioAsset = AVURLAsset(url: audioURL)
            
            do {
                let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
                if let videoSource = videoTracks.first {
                    let videoDuration = try await videoAsset.load(.duration)
                    try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoSource, at: .zero)
                }
                
                let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                if let audioSource = audioTracks.first {
                    // Match audio duration to video duration to trim tail silence.
                    let videoDuration = try await videoAsset.load(.duration)
                    let audioDuration = try await audioAsset.load(.duration)
                    
                    let finalDuration = min(videoDuration, audioDuration)
                    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: finalDuration), of: audioSource, at: .zero)
                }
                
                guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
                    completion(false)
                    return
                }
                
                // Modern Export (iOS 18)
                if #available(iOS 18.0, *) {
                    try await exporter.export(to: outputURL, as: .mp4)
                } else {
                    exporter.outputURL = outputURL
                    exporter.outputFileType = .mp4
                    await exporter.export()
                    if exporter.status != .completed {
                        throw exporter.error ?? NSError(domain: "ExportError", code: -1, userInfo: nil)
                    }
                }
                
                print("Export completed successfully")
                completion(true)
                
            } catch {
                print("Merge failed: \(error)")
                completion(false)
            }
        }
    }
    
    // MARK: - Helpers (Binary Search Optimized)
    // Matches the same algorithm as PlayerView.highlightedPitches() to ensure
    // exported video key highlighting is identical to live playback.
    private func activeKeys(at currentTime: TimeInterval, notes: [NoteEvent]) -> Set<Int> {
        var active: Set<Int> = []
        let releaseGap: TimeInterval = 0.05

        if notes.isEmpty { return active }

        // Use max duration as lookback window (same approach as PlayerView)
        let maxDur = notes.reduce(0.0) { max($0, $1.duration) }
        let cutoff = currentTime - maxDur

        // Binary search: find first note whose startTime >= cutoff
        var lo = 0, hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].startTime < cutoff {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // Walk forward until startTime > currentTime
        for i in lo..<notes.count {
            let n = notes[i]
            if n.startTime > currentTime { break }
            let visualDuration = max(0.02, n.duration - releaseGap)
            if currentTime >= n.startTime && currentTime < (n.startTime + visualDuration) {
                active.insert(n.pitch)
            }
        }
        return active
    }
    
    // MARK: - Pure SwiftUI Piano Keyboard for Export
    // ImageRenderer cannot render UIViewRepresentable (shows 🚫 yellow block).
    // This is a lightweight, pure-SwiftUI keyboard used only for video frames.

    private func exportKeyboard(highlightedPitches: Set<Int>, theme: ThemeManager, width: CGFloat, height: CGFloat) -> some View {
        let whiteKeys = PianoKeyHelper.whiteKeyMIDIs
        let whiteWidth = width / CGFloat(whiteKeys.count)
        let blackKeyWidth = whiteWidth * 0.65
        let blackKeyHeight = height * 0.65

        return ZStack(alignment: .topLeading) {
            // WHITE KEYS
            HStack(spacing: 0) {
                ForEach(whiteKeys, id: \.self) { pitch in
                    let isPlayback = highlightedPitches.contains(pitch)
                    ZStack {
                        Rectangle()
                            .fill(
                                isPlayback
                                ? LinearGradient(
                                    colors: [theme.keyHighlight, theme.keyHighlight],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [Color.white, Color(white: 0.95)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Rectangle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                    }
                    .frame(width: whiteWidth)
                }
            }

            // BLACK KEYS
            HStack(spacing: 0) {
                ForEach(whiteKeys.indices, id: \.self) { i in
                    let wPitch = whiteKeys[i]
                    let nextPitch = (i + 1 < whiteKeys.count) ? whiteKeys[i + 1] : nil

                    ZStack(alignment: .center) {
                        if let up = nextPitch,
                           PianoKeyHelper.hasBlackKey(between: wPitch, and: up) {
                            let blackPitch = wPitch + 1
                            let isHighlighted = highlightedPitches.contains(blackPitch)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    isHighlighted
                                    ? LinearGradient(
                                        colors: [theme.keyHighlightBlack, theme.keyHighlightBlack],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : LinearGradient(
                                        colors: [Color(white: 0.2), Color.black],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: blackKeyWidth, height: blackKeyHeight)
                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 2)
                                .offset(x: whiteWidth / 2)
                                .zIndex(1)
                        }
                    }
                    .frame(width: whiteWidth, height: height, alignment: .top)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    nonisolated private func pixelBufferFromCGImage(image: CGImage, size: CGSize) -> CVPixelBuffer? {
        var pxbuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, options as CFDictionary, &pxbuffer)
        
        guard let buffer = pxbuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pxdata, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

