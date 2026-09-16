//
//  MIDIInputManager.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import Foundation
import CoreMIDI
import Observation

@Observable
class MIDIInputManager {

    var pressedKeys: Set<Int> = []
    var isConnected: Bool = false
    var deviceName: String = ""

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0

    init() {
        setupMIDI()
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }

    // MARK: - Setup

    private func setupMIDI() {
        let clientStatus = MIDIClientCreateWithBlock("MyPianoInstructor" as CFString, &midiClient) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }
        guard clientStatus == noErr else {
            print("MIDI client creation failed: \(clientStatus)")
            return
        }

        let portStatus = MIDIInputPortCreateWithProtocol(
            midiClient,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIEventList(eventList)
        }
        guard portStatus == noErr else {
            print("MIDI input port creation failed: \(portStatus)")
            return
        }

        connectSources()
    }

    // MARK: - Source Connection

    private func connectSources() {
        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else {
            DispatchQueue.main.async {
                self.isConnected = false
                self.deviceName = ""
            }
            return
        }

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, source, nil)
        }

        // Get name of first source
        let firstSource = MIDIGetSource(0)
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(firstSource, kMIDIPropertyDisplayName, &name)
        let sourceName = (name?.takeRetainedValue() as String?) ?? "MIDI Device"

        DispatchQueue.main.async {
            self.isConnected = true
            self.deviceName = sourceName
        }
    }

    // MARK: - Notification Handling

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged:
            // A device was connected or disconnected — reconnect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.connectSources()
            }
        default:
            break
        }
    }

    // MARK: - MIDI Event Parsing

    private func handleMIDIEventList(_ eventListPtr: UnsafePointer<MIDIEventList>) {
        // MIDIEventList is a variable-length structure — copying `pointee` only
        // copies the first packet, so walking MIDIEventPacketNext over a copy
        // reads out-of-bounds memory when numPackets > 1. unsafeSequence()
        // iterates the original buffer safely.
        for packetPtr in eventListPtr.unsafeSequence() {
            parseUniversalPacket(packetPtr.pointee)
        }
    }

    private func parseUniversalPacket(_ packet: MIDIEventPacket) {
        // A packet can carry several Universal MIDI Packet messages back to
        // back (e.g. the notes of a chord); walk every word, advancing by each
        // message's size, rather than reading only the first.
        let wordCount = min(Int(packet.wordCount), 64)
        guard wordCount > 0 else { return }

        withUnsafeBytes(of: packet.words) { rawWords in
            let words = rawWords.bindMemory(to: UInt32.self)
            var index = 0
            while index < wordCount {
                let word = words[index]
                let messageType = (word >> 28) & 0xF

                if messageType == 0x2 { // MIDI 1.0 Channel Voice
                    handleMIDI1ChannelVoice(word)
                }

                // UMP message sizes in 32-bit words, by message type
                switch messageType {
                case 0x3, 0x4:  index += 2   // data / MIDI 2.0 channel voice
                case 0x5:       index += 4   // 128-bit data
                default:        index += 1   // utility, system, MIDI 1.0
                }
            }
        }
    }

    private func handleMIDI1ChannelVoice(_ word: UInt32) {
        let status = (word >> 20) & 0xF
        let note = Int((word >> 8) & 0x7F)
        let velocity = Int(word & 0x7F)

        // Validate MIDI note is in the standard 0-127 range
        guard note >= 0 && note <= 127 else { return }

        switch status {
        case 0x9: // Note On
            if velocity > 0 {
                DispatchQueue.main.async {
                    AudioEngineManager.shared.play(note: note, velocity: UInt8(velocity))
                    self.pressedKeys.insert(note)
                }
            } else {
                // Note-on with velocity 0 = note-off
                DispatchQueue.main.async {
                    AudioEngineManager.shared.stop(note: note)
                    self.pressedKeys.remove(note)
                }
            }

        case 0x8: // Note Off
            DispatchQueue.main.async {
                AudioEngineManager.shared.stop(note: note)
                self.pressedKeys.remove(note)
            }

        default:
            break
        }
    }
}
