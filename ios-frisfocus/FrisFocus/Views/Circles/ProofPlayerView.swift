//
//  ProofPlayerView.swift
//  FrisFocus
//
//  The real full-screen proof player. A single private proof is loaded
//  from the `proofs` Storage bucket via a short-lived signed URL (the
//  bucket is private, so this is the only way to fetch it). Photos
//  linger a few seconds; videos stream and play their length. A thin
//  progress bar tracks playback; tapping or swiping down leaves, and
//  the player exits on its own when the proof finishes.
//
//  Opening the player marks an incoming proof watched, which flips its
//  chat pill back in the thread to the "Reply with a proof" state.
//

import SwiftUI
import AVFoundation
import Combine
import UIKit

struct ProofPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation

    let proof: DirectMessage
    let friend: RemoteProfile
    let message: MessageGraphService
    let myUserId: String
    /// Shared thread presence — lets the sender see "watching your
    /// proof…" live while this player is up.
    var presence: ThreadPresenceService? = nil

    // MARK: Load + playback state

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading: Bool = true
    @State private var failed: Bool = false

    /// 25 Hz playback progress, boxed so ticks re-render only the bar
    /// leaf — not this whole player (see `PlaybackClock`).
    @State private var clock = PlaybackClock()
    @State private var isPaused: Bool = false
    /// Interactive dismissal — the card scales, rounds, and follows the
    /// finger; the backdrop fades; release is velocity-aware.
    @State private var drag = PlayerDragMetrics()
    @State private var crossedDismissThreshold: Bool = false
    @State private var pressStart: Date?
    @State private var reportTarget: ReportTarget?
    /// Keeps the player up briefly after a reaction so the burst lands.
    @State private var didReact: Bool = false

    private let tick: TimeInterval = 0.04
    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()
    private let photoDuration: TimeInterval = 5.0

    private var isVideo: Bool { proof.mediaKind == .video }

    /// How long this proof should hold the screen — a video's recorded
    /// length when known, otherwise the calm photo linger.
    private var currentDuration: TimeInterval {
        if isVideo, let dur = proof.mediaDuration, dur > 0 { return dur }
        return photoDuration
    }

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            ZStack {
                // The backdrop stays put and fades as the card is dragged.
                Color.black
                    .opacity(drag.backdropOpacity)
                    .ignoresSafeArea()

                playerCard(bottomInset: bottomInset)
                    .playerCardEffect(drag)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(true)
        .onReceive(timer) { _ in tickProgress() }
        .task { await loadMedia() }
        .onDisappear {
            player?.pause()
            player = nil
            presence?.setWatching(false)
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(
                reportedUserId: target.reportedUserId,
                messageId: target.messageId,
                subjectName: target.subjectName
            )
            .environment(auth)
            .environment(moderation)
        }
        .onAppear { presence?.setWatching(true) }
    }

    // MARK: - Card

    /// The full-bleed player card: media, gesture layer, and chrome.
    /// Separated from the backdrop so interactive dismissal can scale
    /// and round it as one piece.
    private func playerCard(bottomInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black

            mediaLayer

            // Transparent gesture receiver behind the chrome — tap to
            // dismiss, hold to pause, swipe down to leave.
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(unifiedGesture)

            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, 10)
                    .padding(.top, 54)

                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 12)

                Spacer()

                captionOverlay

                if !proof.isMine(myUserId) {
                    ProofReactionBar { emoji in
                        sendReaction(emoji)
                    }
                    .padding(.bottom, 18 + bottomInset)
                } else {
                    Color.clear.frame(height: bottomInset)
                }
            }
        }
    }

    // MARK: - Reactions

    /// One-tap reaction: bursts on screen, lands in the thread
    /// optimistically as a big emoji note, and pings the sender.
    private func sendReaction(_ emoji: String) {
        didReact = true
        // Give the moment a beat — pause briefly so the burst is seen.
        clock.progress = min(clock.progress, 0.85)
        Task { await message.sendNote(to: friend.id, text: emoji, myUserId: myUserId) }
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaLayer: some View {
        if let player {
            ProofVideoLayer(player: player)
        } else if let image {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2A2438), Color(hex: 0x4A3C50), Color(hex: 0x6B4D52)],
                startPoint: .top,
                endPoint: .bottom
            )

            if isLoading {
                ProgressView().tint(Theme.textCream)
            } else if failed {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.8))
                    Text("Couldn't load this proof")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textCream.opacity(0.85))
                }
            } else if let caption = proof.body, !caption.isEmpty {
                Text(caption)
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        SingleSegmentBar(clock: clock)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.displayName)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(1)
                Text(DirectShareFormat.elapsed(from: proof.createdAt))
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.75))
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    isPaused = true
                    player?.pause()
                    reportTarget = ReportTarget(reportedUserId: friend.id, messageId: proof.id, subjectName: friend.displayName)
                } label: {
                    Label("Report this proof", systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var captionOverlay: some View {
        if (image != nil || player != nil),
           let caption = proof.body?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            Text(caption)
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textCream)
                .multilineTextAlignment(.center)
                .shadow(color: Color.black.opacity(0.5), radius: 6, x: 0, y: 1)
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Loading

    private func loadMedia() async {
        // Mark watched the moment it opens — mirrors the calm story
        // player and flips the thread pill to "Reply with a proof."
        await message.markProofWatched(proof, myUserId: myUserId)

        guard let path = proof.mediaPath,
              let url = await message.signedURL(forMediaPath: path) else {
            failed = true
            isLoading = false
            return
        }

        if isVideo {
            let avPlayer = AVPlayer(url: url)
            avPlayer.actionAtItemEnd = .pause
            player = avPlayer
            isLoading = false
            avPlayer.play()
        } else {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) {
                    image = img
                } else {
                    failed = true
                }
            } catch {
                print("[ProofPlayer] Image load failed: \(error)")
                failed = true
            }
            isLoading = false
        }
    }

    // MARK: - Playback timing

    private func tickProgress() {
        guard !isPaused, !isLoading, !failed, reportTarget == nil else { return }
        clock.progress += tick / max(0.1, currentDuration)
        if clock.progress >= 1 {
            clock.progress = 1
            dismiss()
        }
    }

    // MARK: - Gesture

    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    isPaused = true
                    player?.pause()
                }
                if value.translation.height > 0 {
                    drag.translation = value.translation
                    let past = value.translation.height > 150
                    if past != crossedDismissThreshold {
                        crossedDismissThreshold = past
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    drag.translation = .zero
                }
            }
            .onEnded { value in
                let start = pressStart ?? Date()
                let pressDuration = Date().timeIntervalSince(start)
                let movement = hypot(value.translation.width, value.translation.height)
                pressStart = nil
                crossedDismissThreshold = false

                // Velocity-aware: a long pull or a quick flick both leave.
                if PlayerDragMetrics.shouldDismiss(translation: value.translation, predicted: value.predictedEndTranslation) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                    return
                }

                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { drag.translation = .zero }
                isPaused = false
                player?.play()

                // A short, low-movement release reads as a tap → leave.
                if pressDuration < 0.25 && movement < 10 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            }
    }
}

// MARK: - Video layer (no system controls)

/// A bare `AVPlayerLayer` host so a proof video fills the screen with
/// no scrubber or chrome — the calm timed bar above is the only UI.
private struct ProofVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
