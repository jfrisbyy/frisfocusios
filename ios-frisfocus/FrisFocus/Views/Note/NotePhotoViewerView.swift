//
//  NotePhotoViewerView.swift
//  FrisFocus
//
//  Full-screen media viewer for note attachments. Swipe between
//  pages — photos pinch to zoom (double-tap toggles), video clips
//  loop with sound — close with the ×. Presented as a
//  fullScreenCover from the photo grid.
//

import AVFoundation
import SwiftUI
import UIKit

struct NotePhotoViewerView: View {
    let photos: [NotePhoto]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Group {
                        if photo.kind == .video {
                            NoteVideoPageView(photo: photo, isActive: currentIndex == index)
                        } else {
                            ZoomablePhotoView(photo: photo)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            .padding(.top, 8)
            .accessibilityLabel("Close photo viewer")
        }
        .onAppear {
            currentIndex = min(max(0, startIndex), max(0, photos.count - 1))
        }
        .statusBarHidden(true)
    }
}

// MARK: - Video page

/// One video page — loops with sound while it's the visible page,
/// pauses the moment the user swipes away.
private struct NoteVideoPageView: View {
    let photo: NotePhoto
    let isActive: Bool

    var body: some View {
        if let url = photo.url, FileManager.default.fileExists(atPath: url.path) {
            VideoLoopView(url: url, gravity: .resizeAspect, isPaused: !isActive)
                .id(url)
                .ignoresSafeArea()
        } else {
            VStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Still syncing…")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Zoomable page

/// One photo page with pinch-to-zoom and pan. Double-tap toggles
/// between fit and 2.5×. Zoom resets when swiping to another page.
private struct ZoomablePhotoView: View {
    let photo: NotePhoto

    @State private var image: UIImage? = nil
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoomGesture)
                        .simultaneousGesture(scale > 1.01 ? panGesture : nil)
                        .onTapGesture(count: 2) { toggleZoom() }
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .task(id: photo.filename) {
            let target = photo
            image = await Task.detached(priority: .userInitiated) {
                NotePhotoStore.image(for: target)
            }.value
        }
        .onDisappear { resetZoom() }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, min(5, lastScale * value.magnification))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.02 { resetZoom() }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if scale > 1.01 {
                resetZoomAnimatedBody()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        resetZoomAnimatedBody()
    }

    private func resetZoomAnimatedBody() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

#Preview {
    NotePhotoViewerView(photos: [NotePhoto(filename: "missing.jpg")], startIndex: 0)
}
