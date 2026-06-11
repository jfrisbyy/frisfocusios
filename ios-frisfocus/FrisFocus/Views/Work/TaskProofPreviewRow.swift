//
//  TaskProofPreviewRow.swift
//  FrisFocus
//
//  A compact row of round mini previews of the proof(s) pinned to a
//  task or to-do for today. Tucked under the card's title so the card
//  stays small when there's nothing to show. Each thumbnail carries the
//  warm signature proof ring; tapping one opens it full-screen.
//

import AVFoundation
import SwiftUI
import UIKit

/// Horizontal strip of circular proof thumbnails. Renders nothing when
/// `pins` is empty so callers can place it unconditionally.
struct TaskProofPreviewRow: View {
    let pins: [ProofPin]
    /// Primary ink of the host card (charcoal on paper, cream on sky)
    /// so the "+N" overflow pill reads correctly in both contexts.
    var ink: Color = Theme.textPrimary

    @State private var viewerPin: ProofPin?

    private let diameter: CGFloat = 30
    private let maxVisible: Int = 4

    var body: some View {
        if !pins.isEmpty {
            let visible = Array(pins.prefix(maxVisible))
            let remainder = max(0, pins.count - visible.count)

            HStack(spacing: 6) {
                ForEach(visible) { pin in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewerPin = pin
                    } label: {
                        ProofPinThumbView(pin: pin, diameter: diameter)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View pinned proof")
                }

                if remainder > 0 {
                    ZStack {
                        Circle().fill(ink.opacity(0.10))
                        Text("+\(remainder)")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.7))
                    }
                    .frame(width: diameter, height: diameter)
                    .overlay(Circle().strokeBorder(Theme.sunWarm.opacity(0.6), lineWidth: 1))
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .fullScreenCover(item: $viewerPin) { pin in
                ProofPinViewerView(pin: pin)
            }
        }
    }
}

/// A single circular proof thumbnail with the warm signature edge.
struct ProofPinThumbView: View {
    let pin: ProofPin
    var diameter: CGFloat = 30

    @State private var image: UIImage?

    var body: some View {
        Color.black.opacity(0.2)
            .frame(width: diameter, height: diameter)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: pin.kind == .video ? "video" : "photo")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.sunWarm.opacity(0.85), lineWidth: 1.4))
            .overlay {
                if pin.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.4), radius: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .task(id: pin.filename) {
                image = await loadThumbnail()
            }
    }

    private func loadThumbnail() async -> UIImage? {
        guard let url = pin.url else { return nil }
        if pin.kind == .video {
            return await VideoThumbnailService.thumbnail(for: url, maxDimension: 240)
        }
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}

/// Full-screen viewer for a single pinned proof — the composed clean
/// card, photo or looping clip, on a dimmed backdrop with a close
/// button.
struct ProofPinViewerView: View {
    let pin: ProofPin
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            media
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close proof")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var media: some View {
        if pin.kind == .video, let url = pin.url {
            VideoLoopView(url: url, gravity: .resizeAspect)
                .id(url)
        } else if let url = pin.url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                Text("Proof unavailable")
                    .font(.sans(13, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.6))
        }
    }
}
