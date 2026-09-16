//
//  DisplayLinkController.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/13/26.
//

import Foundation
import QuartzCore
import Observation

@MainActor
@Observable class DisplayLinkController {
    var currentTime: TimeInterval = 0

    private var displayLink: CADisplayLink?
    private var playbackStartWallTime: CFTimeInterval? = nil
    private var playbackStartSongTime: TimeInterval = 0
    private var playbackRate: Double = 1.0
    private(set) var isPlaying: Bool = false

    /// Weak-self trampoline so CADisplayLink does not retain us.
    /// Breaks the strong reference cycle: self -> displayLink -> target -> self.
    @ObservationIgnored private var linkProxy: DisplayLinkProxy?

    /// Set to true while the user is dragging the scrub slider.
    /// The display link keeps running but stops updating currentTime,
    /// so the slider value isn't overwritten during the drag.
    var isScrubbing: Bool = false

    /// Called every frame with the current song time. Use for NoteScheduler updates.
    @ObservationIgnored var onFrame: ((TimeInterval) -> Void)?

    func start(fromTime songTime: TimeInterval, rate: Double) {
        // Tear down any existing display link without resetting currentTime
        displayLink?.invalidate()
        displayLink = nil

        playbackRate = rate
        playbackStartSongTime = songTime
        currentTime = songTime          // Show the seek position immediately
        isPlaying = true

        let proxy = DisplayLinkProxy { [weak self] link in
            self?.displayLinkFired(link)
        }
        linkProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        // Wall time will be captured on first frame
        playbackStartWallTime = nil
    }

    @discardableResult
    func pause() -> TimeInterval {
        isPlaying = false
        displayLink?.invalidate()
        displayLink = nil
        return currentTime
    }

    func stop() {
        isPlaying = false
        displayLink?.invalidate()
        displayLink = nil
        currentTime = 0
        playbackStartWallTime = nil
    }

    func changeRate(_ newRate: Double) {
        guard isPlaying else {
            playbackRate = newRate
            return
        }
        // Capture current position, restart with new rate
        let time = currentTime
        stop()
        start(fromTime: time, rate: newRate)
    }

    private func displayLinkFired(_ link: CADisplayLink) {
        // Don't update time while user is scrubbing the slider
        guard !isScrubbing else { return }

        if playbackStartWallTime == nil {
            // First frame — anchor the wall clock
            playbackStartWallTime = link.timestamp
        }

        let elapsed = link.timestamp - (playbackStartWallTime ?? link.timestamp)
        let newTime = playbackStartSongTime + elapsed * playbackRate

        currentTime = max(0, newTime)
        onFrame?(currentTime)
    }

    deinit {
        // Every reference to this @MainActor class is held on the main thread,
        // so deinit is always triggered there. assumeIsolated lets us access the
        // actor-isolated property directly, with no Sendable capture needed.
        MainActor.assumeIsolated {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}

// MARK: - Weak-Self Trampoline for CADisplayLink

/// CADisplayLink retains its target strongly, which creates a retain cycle
/// if the target is also the owner of the display link. This proxy breaks
/// the cycle by holding only a closure (which captures self weakly).
private class DisplayLinkProxy: NSObject {
    let callback: (CADisplayLink) -> Void

    init(callback: @escaping (CADisplayLink) -> Void) {
        self.callback = callback
    }

    @objc func handleDisplayLink(_ link: CADisplayLink) {
        callback(link)
    }
}
