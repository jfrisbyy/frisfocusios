//
//  VideoLoopView.swift
//  FrisFocus
//
//  The shared chrome-less looping video player — used by the share
//  preview, the proof edit canvas, story videos, and private proof
//  playback. Plays UNMUTED and holds a `VideoPlaybackAudio` claim for
//  its lifetime so sound comes through even on silent.
//
//  Recreate the player for a new clip by changing the view's `.id`
//  (e.g. `.id(url)`); `updateUIView` only adjusts gravity and pause.
//

import AVFoundation
import SwiftUI

struct VideoLoopView: UIViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var isPaused: Bool = false

    func makeUIView(context: Context) -> LoopContainerView {
        let view = LoopContainerView()
        view.backgroundColor = .black
        view.configure(url: url, gravity: gravity)
        return view
    }

    func updateUIView(_ uiView: LoopContainerView, context: Context) {
        uiView.setGravity(gravity)
        uiView.setPaused(isPaused)
    }

    static func dismantleUIView(_ uiView: LoopContainerView, coordinator: ()) {
        uiView.teardown()
    }

    final class LoopContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private var loopPlayerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var holdsAudioClaim: Bool = false

        func configure(url: URL, gravity: AVLayerVideoGravity) {
            VideoPlaybackAudio.activate()
            holdsAudioClaim = true

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = false
            looper = AVPlayerLooper(player: player, templateItem: item)
            loopPlayerLayer.player = player
            loopPlayerLayer.videoGravity = gravity
            player.play()
            queuePlayer = player
        }

        func setGravity(_ gravity: AVLayerVideoGravity) {
            if loopPlayerLayer.videoGravity != gravity {
                loopPlayerLayer.videoGravity = gravity
            }
        }

        func setPaused(_ paused: Bool) {
            guard let queuePlayer else { return }
            if paused {
                if queuePlayer.timeControlStatus != .paused { queuePlayer.pause() }
            } else if queuePlayer.timeControlStatus == .paused {
                queuePlayer.play()
            }
        }

        func teardown() {
            queuePlayer?.pause()
            looper = nil
            queuePlayer = nil
            loopPlayerLayer.player = nil
            if holdsAudioClaim {
                holdsAudioClaim = false
                VideoPlaybackAudio.release()
            }
        }
    }
}
