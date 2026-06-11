//
//  ProofLibraryView.swift
//  FrisFocus
//
//  The permanent archive of every proof the user saved or posted —
//  posted story cards stay here even after the 24h story expires, and
//  circle clips are archived too. Privately-sent proofs never appear.
//  A three-column grid of story-shaped thumbnails, newest first; a tap
//  opens the full card with its date, how it entered the library, and
//  everywhere it was pinned. Videos loop in the viewer.
//

import AVFoundation
import SwiftUI
import UIKit

struct ProofLibraryView: View {
    @Environment(Store.self) private var store

    @State private var viewerItem: ProofLibraryItem?
    @State private var pendingDelete: ProofLibraryItem?

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            Theme.paperCream.ignoresSafeArea()

            if store.proofLibraryNewestFirst.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(store.proofLibraryNewestFirst) { item in
                            tile(item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Proof library")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewerItem) { item in
            ProofLibraryViewerView(item: item)
                .environment(store)
        }
        .confirmationDialog(
            "Remove this proof from your library?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from library", role: .destructive) {
                if let item = pendingDelete {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    store.deleteProofLibraryItem(item.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Pins and posts made from it are not affected.")
        }
    }

    // MARK: - Tiles

    @ViewBuilder
    private func tile(_ item: ProofLibraryItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewerItem = item
        } label: {
            Color.black.opacity(0.15)
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .overlay {
                    ProofLibraryThumb(item: item)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: item.source == .posted ? "paperplane.fill" : "square.and.arrow.down")
                            .font(.system(size: 8, weight: .semibold))
                        Text(shortDate(item.createdAt))
                            .font(.sans(9, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(6)
                    .allowsHitTesting(false)
                }
                .overlay {
                    if item.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.sunWarm.opacity(0.4), lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("Remove from library", systemImage: "trash")
            }
        }
        .accessibilityLabel("Proof from \(shortDate(item.createdAt))")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.35))
            Text("No proofs archived yet")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
            Text("Every proof you post or save lands here —\neven after it leaves your story.")
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Thumbnail

/// Lazily-loaded thumbnail for a library tile — a frame for videos,
/// the downscaled photo otherwise.
private struct ProofLibraryThumb: View {
    let item: ProofLibraryItem

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind == .video ? "video" : "photo")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .task(id: item.filename) {
            image = await load()
        }
    }

    private func load() async -> UIImage? {
        guard let url = item.url else { return nil }
        if item.kind == .video {
            return await VideoThumbnailService.thumbnail(for: url, maxDimension: 360)
        }
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}

// MARK: - Viewer

/// Full-screen viewer for one archived proof — the composed card on a
/// dark backdrop with its date, source, and everywhere it was pinned.
struct ProofLibraryViewerView: View {
    let item: ProofLibraryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            media
                .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fullDate)
                            .font(.sans(13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(sourceLine)
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.45)))

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

                if !item.pinnedLabels.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(45))
                        Text("Pinned to \(item.pinnedLabels.joined(separator: " · "))")
                            .font(.sans(12, weight: .medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.bottom, 28)
                }
            }
        }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var media: some View {
        if item.kind == .video, let url = item.url {
            VideoLoopView(url: url, gravity: .resizeAspect)
                .id(url)
        } else if let url = item.url, let image = UIImage(contentsOfFile: url.path) {
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

    private var fullDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: item.createdAt)
    }

    private var sourceLine: String {
        item.source == .posted ? "Posted" : "Saved on this device"
    }
}

#Preview {
    NavigationStack {
        ProofLibraryView()
            .environment(Store())
    }
}
