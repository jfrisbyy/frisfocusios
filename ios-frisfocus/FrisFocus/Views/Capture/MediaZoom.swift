//
//  MediaZoom.swift
//  FrisFocus
//
//  Pinch-to-zoom + drag-to-reframe for an edit canvas's media layer.
//  Shared by the proof editor (CaptureReviewView) and the overlay-post
//  preview (SharePreviewView).
//
//  The committed zoom lives in the host as a `MediaZoom` value; the
//  gesture modifier composes the in-flight pinch / pan on top of its
//  own steady baselines and writes the live result back through the
//  binding. The host applies `.scaleEffect(zoom.scale).offset(zoom.offset)`
//  to the media layer ONLY — captions, stickers, drawing, and chrome
//  stay in screen space — and feeds the same values into the export
//  renderers so the final media matches the framing exactly.
//

import SwiftUI
import UIKit

/// The committed zoom applied to the media beneath an edit canvas.
/// `scale` is anchored at the canvas center; `offset` pans the scaled
/// media in canvas points. Identity (scale 1, no offset) means the
/// media sits exactly as captured.
struct MediaZoom: Equatable {
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero

    var isIdentity: Bool { scale <= 1.0001 && offset == .zero }

    /// The largest pan that keeps the media covering the canvas at
    /// `scale` — the media can never be dragged off its frame.
    static func clampedOffset(_ proposed: CGSize, scale: CGFloat, canvas: CGSize) -> CGSize {
        let maxX = max(0, (scale - 1) * canvas.width / 2)
        let maxY = max(0, (scale - 1) * canvas.height / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }
}

/// Attaches pinch-to-zoom and (while zoomed) one-finger pan to an edit
/// canvas. Attached with plain `.gesture`, so caption / sticker blocks
/// — children with their own gestures — keep winning touches that
/// start on them: pinching a block still resizes the block; the media
/// only zooms from open canvas. Over-pinching past the 1x–4x range is
/// allowed in flight and gently springs back on release.
struct MediaZoomGestureModifier: ViewModifier {
    @Binding var zoom: MediaZoom
    let canvasSize: CGSize
    var isEnabled: Bool = true

    private static let maxScale: CGFloat = 4.0

    /// Gesture-stable baselines the in-flight pinch / pan compose onto.
    @State private var steadyScale: CGFloat = 1.0
    @State private var steadyOffset: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .gesture(
                magnifyGesture.simultaneously(with: panGesture),
                including: isEnabled ? .all : .subviews
            )
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Soft over-pinch: the live scale may drift slightly
                // past the clamp range; release snaps it back.
                let live = min(Self.maxScale * 1.3, max(0.85, steadyScale * value.magnification))
                zoom = MediaZoom(
                    scale: live,
                    offset: MediaZoom.clampedOffset(steadyOffset, scale: live, canvas: canvasSize)
                )
            }
            .onEnded { value in
                let target = min(Self.maxScale, max(1.0, steadyScale * value.magnification))
                steadyScale = target
                steadyOffset = MediaZoom.clampedOffset(steadyOffset, scale: target, canvas: canvasSize)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    zoom = MediaZoom(scale: target, offset: steadyOffset)
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard steadyScale > 1.001 else { return }
                let proposed = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
                zoom.offset = MediaZoom.clampedOffset(proposed, scale: zoom.scale, canvas: canvasSize)
            }
            .onEnded { value in
                guard steadyScale > 1.001 else { return }
                let proposed = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
                steadyOffset = MediaZoom.clampedOffset(proposed, scale: steadyScale, canvas: canvasSize)
                zoom.offset = steadyOffset
            }
    }
}
