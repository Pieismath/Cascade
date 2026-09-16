//
//  PianoTips.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/17/26.
//

import TipKit

/// Tip shown when user first opens the song library
struct ImportSongTip: Tip {
    var title: Text {
        Text("Import Your First Song")
    }
    var message: Text? {
        Text("Tap the Add tab to import a MusicXML file or try a built-in demo song to get started.")
    }
    var image: Image? {
        Image(systemName: "doc.badge.plus")
    }
}

/// Tip shown on the player view about hand separation
struct HandSeparationTip: Tip {
    @Parameter
    static var hasPlayedOnce: Bool = false

    var title: Text {
        Text("Practice Each Hand Separately")
    }
    var message: Text? {
        Text("Tap RH or LH to isolate one hand at a time. This is how my students at Platt learn tricky passages!")
    }
    var image: Image? {
        Image(systemName: "hand.raised.fingers.spread.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$hasPlayedOnce) { $0 == true }
    }
}

/// Tip shown about speed controls
struct SlowDownTip: Tip {
    @Parameter
    static var sessionCount: Int = 0

    var title: Text {
        Text("Slow It Down")
    }
    var message: Text? {
        Text("Struggling with a passage? Try 0.5x or 0.25x speed. Even concert pianists practice slowly!")
    }
    var image: Image? {
        Image(systemName: "tortoise.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$sessionCount) { $0 >= 2 }
    }
}

/// Tip shown about loop feature
struct LoopTip: Tip {
    @Parameter
    static var hasUsedSpeedControl: Bool = false

    var title: Text {
        Text("Loop Tricky Sections")
    }
    var message: Text? {
        Text("Tap the loop button to repeat a section until you nail it. Combine with slow speed for best results.")
    }
    var image: Image? {
        Image(systemName: "repeat.circle")
    }

    var rules: [Rule] {
        #Rule(Self.$hasUsedSpeedControl) { $0 == true }
    }
}

/// Tip about MIDI keyboard support
struct MIDITip: Tip {
    var title: Text {
        Text("Connect a Piano")
    }
    var message: Text? {
        Text("Connect a MIDI keyboard via USB or Bluetooth for the best learning experience with real-time accuracy tracking.")
    }
    var image: Image? {
        Image(systemName: "pianokeys")
    }
}

/// Tip about wait mode
struct WaitModeTip: Tip {
    @Parameter
    static var hasCompletedSong: Bool = false

    var title: Text {
        Text("Try Wait Mode")
    }
    var message: Text? {
        Text("Enable Wait Mode and the app pauses until you play the right note — just like having a patient tutor by your side.")
    }
    var image: Image? {
        Image(systemName: "pause.circle.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$hasCompletedSong) { $0 == true }
    }
}

/// Tip about checking stats
struct CheckStatsTip: Tip {
    @Parameter
    static var practiceMinutes: Int = 0

    var title: Text {
        Text("Track Your Progress")
    }
    var message: Text? {
        Text("Visit the Progress tab to see your practice charts, streaks, and earned achievements!")
    }
    var image: Image? {
        Image(systemName: "chart.bar.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$practiceMinutes) { $0 >= 5 }
    }
}
