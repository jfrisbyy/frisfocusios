//
//  AudioPlayerService.swift
//  FrisFocus
//
//  Single-clip playback wrapper around `AVAudioPlayer`. Loads a file
//  by URL, plays / pauses / seeks, and publishes the live state so
//  SwiftUI views can drive their UI from `isPlaying`, `progress`,
//  `currentTime`, and `duration`.
//
//  Use one instance per voice memo card or detail screen. The audio
//  session is configured for `.playback` on every `load(url:)` so a
//  Bluetooth-output route doesn't get stuck on `.record`.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class AudioPlayerService: NSObject, AVAudioPlayerDelegate {
    /// True while audio is currently producing output.
    private(set) var isPlaying: Bool = false

    /// Seconds into the clip. Updated 20×/s while playing.
    private(set) var currentTime: TimeInterval = 0

    /// Full length of the currently-loaded clip. 0 when nothing is
    /// loaded or when the file failed to open.
    private(set) var duration: TimeInterval = 0

    /// True once `load(url:)` has succeeded for some clip. Used by
    /// the inline player to know whether to render the controls at all.
    private(set) var hasClip: Bool = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    /// 0…1 progress, useful for ProgressView / custom bars.
    var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }

    /// Load a clip from disk. Returns true on success. Idempotent —
    /// calling with the same URL twice keeps playback state intact.
    @discardableResult
    func load(url: URL) -> Bool {
        // Same URL already loaded → leave it alone so the user's
        // scrub position isn't lost when the view body re-renders.
        if let player, player.url == url {
            hasClip = true
            return true
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal — playback may still work on built-in speaker.
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
            currentTime = 0
            isPlaying = false
            hasClip = true
            return true
        } catch {
            player = nil
            duration = 0
            currentTime = 0
            hasClip = false
            isPlaying = false
            return false
        }
    }

    /// Start (or resume) playback. No-op if nothing is loaded.
    func play() {
        guard let player else { return }
        if player.play() {
            isPlaying = true
            startTimer()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    /// Toggle play/pause. Convenient for tap-to-play buttons.
    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    /// Move the play head to the given time (seconds).
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(duration, time))
        player.currentTime = clamped
        currentTime = clamped
    }

    // MARK: - Internal

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
    }

    // MARK: - Delegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.stopTimer()
        }
    }
}

// MARK: - Time formatting

extension TimeInterval {
    /// Lowest-friction `mm:ss` formatter for player UI. Negative or NaN
    /// inputs fall back to `0:00` so corrupt clip durations don't crash.
    var voiceMemoTimeString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
