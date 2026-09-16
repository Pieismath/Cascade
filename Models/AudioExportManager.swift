//
//  AudioExportManager.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 1/16/26.
//

import Foundation
import AVFoundation

class AudioExportManager {
    
    // Audio Settings
    private let sampleRate: Double = 44100.0
    
    /// Renders the MIDI notes to a .m4a audio file.
    /// This method runs a synchronous render loop on whatever thread calls it.
    nonisolated func renderAudio(playback: PlaybackData, outputURL: URL, completion: @escaping (Bool) -> Void) {
        
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let reverb = AVAudioUnitReverb()
        
        engine.attach(sampler)
        engine.attach(reverb)
        
        // Reverb Settings
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 35
        
        engine.connect(sampler, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        
        // Load Piano
        guard let sf2URL = Bundle.main.url(forResource: "Piano", withExtension: "sf2") else {
            print("AudioExport: Piano.sf2 not found")
            completion(false)
            return
        }
        
        do {
            try sampler.loadSoundBankInstrument(at: sf2URL, program: 0, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
        } catch {
            print("AudioExport: Failed to load SoundFont: \(error)")
            completion(false)
            return
        }
        
        // Configure Offline Rendering (High Precision 5ms buffer)
        let maxFrames: AVAudioFrameCount = 256

        // The render format must match the sample rate used for the frame math
        // below. Deriving it from mainMixerNode picks up the hardware rate
        // (usually 48 kHz), which made exports run ~9% fast and drift out of
        // sync with the video.
        guard let renderFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            print("AudioExport: Could not create render format")
            completion(false)
            return
        }

        do {
            try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: maxFrames)
            try engine.start()
        } catch {
            print("AudioExport: Engine start failed: \(error)")
            completion(false)
            return
        }
        
        guard let audioFile = try? AVAudioFile(forWriting: outputURL, settings: engine.manualRenderingFormat.settings) else {
            print("AudioExport: Could not create output file")
            completion(false)
            return
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames) else {
            print("AudioExport: Could not create PCM buffer")
            engine.stop()
            completion(false)
            return
        }
        
        // Sustain-pedal extension must match live playback (NoteScheduler),
        // otherwise exported audio sounds dry and choppy on pedaled pieces.
        let sortedPedals = playback.pedalEvents.sorted { $0.startTime < $1.startTime }
        let noteEnds: [UUID: TimeInterval] = Dictionary(uniqueKeysWithValues: playback.notes.map {
            ($0.id, PlaybackData.pedalExtendedEnd(of: $0, sortedPedals: sortedPedals))
        })
        let lastNoteEnd = noteEnds.values.max() ?? playback.totalDuration

        let totalDuration = max(playback.totalDuration, lastNoteEnd) + 1.0
        let totalFrames = Int64(totalDuration * sampleRate)
        var currentFrame: Int64 = 0

        // Reference-counted active notes: tracks how many overlapping instances
        // of each pitch are sounding. Only sends note-off when count drops to 0.
        // This matches the live NoteScheduler approach and prevents overlapping
        // same-pitch notes from losing their first note-off.
        var activeNoteCounts: [Int: Int] = [:]
        var activeNoteEndTimes: [Int: [TimeInterval]] = [:]
        var notesToProcess = playback.notes.sorted { $0.startTime < $1.startTime }

        print("Starting Audio Render...")

        while engine.manualRenderingSampleTime < totalFrames {

            let framesToRender = min(AVAudioFrameCount(totalFrames - currentFrame), maxFrames)

            // Compute the end-time of this render chunk
            let nextTime = Double(currentFrame + Int64(framesToRender)) / sampleRate

            // Note Ons
            while let nextNote = notesToProcess.first, nextNote.startTime < nextTime {
                let pitch = nextNote.pitch
                let count = activeNoteCounts[pitch, default: 0]
                if count == 0 {
                    sampler.startNote(UInt8(pitch), withVelocity: 100, onChannel: 0)
                } else {
                    // Re-trigger for fresh attack on repeated same-pitch notes
                    sampler.stopNote(UInt8(pitch), onChannel: 0)
                    sampler.startNote(UInt8(pitch), withVelocity: 100, onChannel: 0)
                }
                activeNoteCounts[pitch] = count + 1
                activeNoteEndTimes[pitch, default: []].append(noteEnds[nextNote.id] ?? (nextNote.startTime + nextNote.duration))
                notesToProcess.removeFirst()
            }

            // Note Offs — check each pitch's end times individually
            for (pitch, endTimes) in activeNoteEndTimes {
                let expired = endTimes.filter { $0 < nextTime }
                let remaining = endTimes.filter { $0 >= nextTime }
                if !expired.isEmpty {
                    let count = activeNoteCounts[pitch, default: 0]
                    let newCount = max(0, count - expired.count)
                    activeNoteCounts[pitch] = newCount
                    activeNoteEndTimes[pitch] = remaining
                    if newCount == 0 {
                        sampler.stopNote(UInt8(pitch), onChannel: 0)
                        activeNoteCounts.removeValue(forKey: pitch)
                        activeNoteEndTimes.removeValue(forKey: pitch)
                    }
                }
            }
            
            // Render
            do {
                let status = try engine.renderOffline(framesToRender, to: buffer)
                if status == .success {
                    try audioFile.write(from: buffer)
                } else {
                    print("AudioExport: Render error")
                }
            } catch {
                print("AudioExport: Write error: \(error)")
                completion(false)
                return
            }
            
            currentFrame += Int64(framesToRender)
        }
        
        sampler.stopAllNotes()
        engine.stop()
        print("Audio Render Complete")
        completion(true)
    }
}

extension AVAudioUnitSampler {
    nonisolated func stopAllNotes() {
        self.sendController(123, withValue: 0, onChannel: 0)
        self.sendController(120, withValue: 0, onChannel: 0)
    }
}
