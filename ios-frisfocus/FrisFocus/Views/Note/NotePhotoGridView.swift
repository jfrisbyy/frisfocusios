//
//  NotePhotoGridView.swift
//  FrisFocus
//
//  Rounded photo thumbnails for a note, laid out on the paper. Used by
//  the composer and editor (with a remove ×) and read-only inside
//  entry rows. Tapping a thumbnail opens the full-screen viewer with
//  pinch-to-zoom.
//

import SwiftUI
import UIKit

struct NotePhotoGridView: View {
    let photos: [NotePhoto]
    /// Provide to render the × remove badge. Nil = read-only.
    let onRemove: ((NotePhoto) -> Void)?

    @State private var viewerIndex: Int? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 94, maximum: 160), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                NotePhotoThumbView(photo: photo)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewerIndex = index
                    }
                    .overlay(alignment: .topTrailing) {
                        if let onRemove {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onRemove(photo)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18, weight: .regular))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Theme.textPrimary.opacity(0.75))
                                    .padding(5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove photo")
                        }
                    }
            }
        }
        .fullScreenCover(item: viewerBinding) { wrapper in
            NotePhotoViewerView(photos: photos, startIndex: wrapper.index)
        }
    }

    /// `fullScreenCover(item:)` needs Identifiable — wrap the index.
    private var viewerBinding: Binding<ViewerTarget?> {
        Binding(
            get: { viewerIndex.map(ViewerTarget.init) },
            set: { viewerIndex = $0?.index }
        )
    }
}

private struct ViewerTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Single thumbnail

/// One rounded media tile — a photo, or a video poster with a play
/// badge and duration. Proof attachments carry the thin
/// signature-color edge. Loads off the main render pass; shows a quiet
/// paper placeholder while loading or when the file is still
/// downloading from sync.
struct NotePhotoThumbView: View {
    let photo: NotePhoto

    @State private var image: UIImage? = nil

    /// Proofs read as round badges with the warm signature edge so they
    /// stand apart from ordinary rectangular photos; everything else
    /// keeps the rounded-rect tile.
    private var tileShape: AnyShape {
        photo.isProof
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var body: some View {
        Color.white.opacity(0.55)
            .frame(height: 96)
            .aspectRatio(photo.isProof ? 1 : nil, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: photo.kind == .video ? "video" : "photo")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.textPrimary.opacity(0.25))
                }
            }
            .clipShape(tileShape)
            .overlay {
                if photo.isProof {
                    Circle()
                        .strokeBorder(Theme.sunWarm.opacity(0.85), lineWidth: 1.4)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
                }
            }
            .overlay {
                if photo.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.45), radius: 2)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.kind == .video, let duration = photo.duration, duration > 0 {
                    Text(duration.voiceMemoTimeString)
                        .font(.sans(9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task(id: photo.filename) {
                image = await loadImage()
            }
    }

    private func loadImage() async -> UIImage? {
        let target = photo
        if target.kind == .video {
            guard let url = target.url else { return nil }
            return await VideoThumbnailService.thumbnail(for: url, maxDimension: 480)
        }
        return await Task.detached(priority: .userInitiated) {
            NotePhotoStore.image(for: target)
        }.value
    }
}

#Preview {
    NotePhotoGridView(photos: [NotePhoto(filename: "missing.jpg")], onRemove: { _ in })
        .padding()
        .background(Theme.paperCream)
}
