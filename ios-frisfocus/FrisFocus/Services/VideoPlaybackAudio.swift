//
//  VideoPlaybackAudio.swift
//  FrisFocus
//
//  A ref-counted claim on the playback audio session so on-screen
//  video is audible even with the silent switch on. Each player calls
//  `activate()` when it starts and `release()` when it tears down; the
//  session deactivates only when the last claim is gone, so stacked
//  players (a story over a thread, a preview over the camera) never
//  fight each other.
//

import AVFoundation

@MainActor
enum VideoPlaybackAudio {
    private static var claims: Int = 0

    /// Claim the playback session. Safe to call repeatedly — only the
    /// first claim touches the shared `AVAudioSession`.
    static func activate() {
        claims += 1
        guard claims == 1 else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[VideoPlaybackAudio] activate failed: \(error.localizedDescription)")
        }
    }

    /// Drop one claim. The session deactivates (notifying other apps)
    /// when nothing on screen is playing video anymore.
    static func release() {
        claims = max(0, claims - 1)
        guard claims == 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Non-fatal — another audio owner may already hold the session.
        }
    }
}
