//
//  SharePreviewView.swift
//  FrisFocus
//
//  Post-capture preview — the composed moment with two destinations:
//
//   • "Your People" — posts as an in-app story (24 h ring). The card is
//     CLEAN: no attribution line, no wordmark; identity is implicit.
//   • "Share outside" — the native iOS share sheet (Instagram,
//     iMessage, save to camera roll). The composite ALWAYS carries the
//     attribution line: orb glyph + "@USERNAME · FRISFOCUS".
//
//  One renderer, a destination parameter — identical overlay
//  composition, attribution added only for external/save. Everything
//  composites locally; zero API calls.
//

import AVFoundation
import SwiftUI
import UIKit

struct SharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let result: CaptureResult
    let context: ShareDayContext
    let options: ShareOverlayOptions
    let username: String
    /// Called after a successful post/share so the camera dismisses too.
    let onFinished: () -> Void

    @State private var isWorking: Bool = false
    @State private var sharePayload: SharePayload?
    @State private var postedConfirmation: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The captured media, story-framed, with the live overlay on
            // top — previewing the attributed (external) version.
            mediaLayer
                .overlay {
                    ShareOverlayView(
                        context: context,
                        options: options,
                        mode: .render(attributed: true),
                        username: username,
                        bottomPadding: 118
                    )
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                destinationBar
            }

            if isWorking {
                workingVeil
            }

            if postedConfirmation {
                postedToast
            }
        }
        .statusBarHidden()
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaLayer: some View {
        switch result {
        case .photo(let image):
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        case .video(let url, _, _):
            LoopingPlayerView(url: url)
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .accessibilityLabel("Retake")

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var destinationBar: some View {
        HStack(spacing: 12) {
            Button {
                postToYourPeople()
            } label: {
                Text("Your People")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule().fill(Color.white.opacity(0.16))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Post to Your People")
            .accessibilityHint("Shares as an in-app story, without the watermark")

            Button {
                shareOutside()
            } label: {
                HStack(spacing: 7) {
                    Text("Share outside")
                        .font(.sans(15, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0x2C2C2A))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(Color(hex: 0xFAEEDA)))
            }
            .accessibilityLabel("Share outside")
            .accessibilityHint("Opens the share sheet with your attributed card")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .disabled(isWorking)
    }

    private var workingVeil: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Composing…")
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .transition(.opacity)
    }

    private var postedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: 0xFFC668))
                Text("Posted to your people")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .padding(.bottom, 110)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Destinations

    /// In-app story — clean composite, no attribution, no wordmark.
    private func postToYourPeople() {
        guard !isWorking else { return }
        isWorking = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            switch result {
            case .photo(let image):
                let composed = ShareCardRenderer.compositePhoto(
                    image,
                    context: context,
                    options: options,
                    username: username,
                    attributed: false
                )
                guard let data = composed?.jpegData(compressionQuality: 0.9) else {
                    isWorking = false
                    return
                }
                store.postMedia(
                    imageData: data,
                    type: .photo,
                    caption: nil,
                    circleId: nil,
                    attachedCircleTaskId: nil
                )

            case .video(let url, _, let duration):
                let composedURL = await ShareCardRenderer.compositeVideo(
                    at: url,
                    context: context,
                    options: options,
                    username: username,
                    attributed: false,
                    animated: !reduceMotion
                )
                guard
                    let finalURL = composedURL ?? Optional(url),
                    let data = try? Data(contentsOf: finalURL)
                else {
                    isWorking = false
                    return
                }
                store.postMedia(
                    imageData: data,
                    type: .video,
                    caption: nil,
                    circleId: nil,
                    attachedCircleTaskId: nil,
                    durationSeconds: duration
                )
            }

            isWorking = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.25)) { postedConfirmation = true }
            try? await Task.sleep(for: .seconds(0.9))
            onFinished()
        }
    }

    /// External — attributed composite into the native share sheet
    /// (which also covers save-to-camera-roll, equally attributed).
    private func shareOutside() {
        guard !isWorking else { return }
        isWorking = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            switch result {
            case .photo(let image):
                let composed = ShareCardRenderer.compositePhoto(
                    image,
                    context: context,
                    options: options,
                    username: username,
                    attributed: true
                )
                isWorking = false
                if let composed {
                    sharePayload = SharePayload(items: [composed])
                }

            case .video(let url, _, _):
                let composedURL = await ShareCardRenderer.compositeVideo(
                    at: url,
                    context: context,
                    options: options,
                    username: username,
                    attributed: true,
                    animated: !reduceMotion
                )
                isWorking = false
                if let composedURL {
                    sharePayload = SharePayload(items: [composedURL])
                } else {
                    // Compositing unavailable (no hardware decode path) —
                    // never strand the user; share the raw clip.
                    sharePayload = SharePayload(items: [url])
                }
            }
        }
    }
}

// MARK: - Share sheet plumbing

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Looping video preview

private struct LoopingPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.teardown()
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(url: URL) {
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: item)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            player.play()
            queuePlayer = player
        }

        func teardown() {
            queuePlayer?.pause()
            looper = nil
            queuePlayer = nil
            playerLayer.player = nil
        }
    }
}
