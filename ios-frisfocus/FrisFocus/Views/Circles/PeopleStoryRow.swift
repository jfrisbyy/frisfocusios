//
//  PeopleStoryRow.swift
//  FrisFocus
//
//  The story row at the top of the People page — Snapchat-style
//  previews where the circle itself is the story:
//
//   • Unwatched story — the disc is FILLED with the story's actual
//     thumbnail, wrapped in a bright season-color ring with a small
//     gap in the stroke. Name below in normal weight.
//   • Watched story — same thumbnail fill, but the ring drops to a
//     thin neutral grey and the name fades to ~60%.
//   • No story — a plain refined avatar (subtle gradient on the
//     season color, soft inner shadow) with NO ring at all. The
//     presence of a ring IS the has-story signal.
//   • "Your story" leads the row: the user's avatar inside a dashed
//     neutral ring with a small gold "+" badge.
//
//  Stateless on routing — the parent owns every tap destination.
//

import SwiftUI
import UIKit

struct PeopleStoryRow: View {
    @Environment(Store.self) private var store
    @Environment(SocialSyncService.self) private var social
    @Environment(ModerationService.self) private var moderation

    var userInitials: String = ""
    var userPhotoURL: URL? = nil
    /// Namespace for the story players' zoom transitions.
    var zoomNamespace: Namespace.ID? = nil
    /// `(friend, hasAnyStories)` — the parent routes story vs. detail.
    let onFriendTap: (Friend, Bool) -> Void
    let onYouTap: () -> Void
    let onYouAddTap: () -> Void
    var onAddFriendTap: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                YourStoryBubble(
                    initials: userInitials,
                    photoURL: userPhotoURL,
                    thumbMedia: store.myStoryThumbMedia,
                    thumbCaption: store.myStoryThumbCaption,
                    uploadFailed: !failedMyStoryIds.isEmpty,
                    action: onYouTap,
                    addAction: onYouAddTap,
                    onRetry: {
                        let ids = failedMyStoryIds
                        Task {
                            for id in ids { await social.retryStoryUpload(postId: id) }
                        }
                    }
                )
                .zoomSource(id: "mystory", in: zoomNamespace)

                ForEach(orderedFriends) { friend in
                    FriendStoryBubble(
                        friend: friend,
                        state: ringState(for: friend),
                        thumbMedia: isMuted(friend) ? nil : store.storyThumbMedia(forFriendId: friend.id),
                        thumbCaption: isMuted(friend) ? nil : store.storyThumbCaption(forFriendId: friend.id)
                    ) {
                        // A muted friend keeps their place in the row —
                        // they are still a person you can open — but the
                        // tap lands on their profile instead of dropping
                        // you into a tape you asked not to be shown.
                        onFriendTap(friend, !isMuted(friend) && store.hasAnyActiveStories(forFriendId: friend.id))
                    }
                    .zoomSource(id: "story-\(friend.id.uuidString)", in: zoomNamespace)
                }

                if let onAddFriendTap {
                    AddPersonBubble(action: onAddFriendTap)
                }
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.vertical, 4)
        }
    }

    /// Unwatched stories lead, watched follow, story-less friends close
    /// the row — stable within each band so the order doesn't shuffle.
    private var orderedFriends: [Friend] {
        let ranked = store.friends.map { (friend: $0, rank: rankValue(for: $0)) }
        return ranked
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.rank != rhs.element.rank { return lhs.element.rank < rhs.element.rank }
                return lhs.offset < rhs.offset
            }
            .map { $0.element.friend }
    }

    private func rankValue(for friend: Friend) -> Int {
        switch ringState(for: friend) {
        case .fresh: return 0
        case .seen:  return 1
        case .none:  return 2
        }
    }

    private func ringState(for friend: Friend) -> StoryRingState {
        // Muted people read as ring-less: no bright ring calling for a
        // watch, no thumbnail, and — through `rankValue` — a seat at the
        // quiet end of the row. Nothing is removed, only turned down.
        if isMuted(friend) { return .none }
        if store.hasUnviewedStories(forFriendId: friend.id) { return .fresh }
        if store.hasAnyActiveStories(forFriendId: friend.id) { return .seen }
        return .none
    }

    private func isMuted(_ friend: Friend) -> Bool {
        moderation.mutedLocalIds.contains(friend.id)
    }

    /// My local posts whose upload failed — the bubble offers a resend.
    private var failedMyStoryIds: [UUID] {
        store.storyPosts
            .filter { $0.authorId == store.currentUserId && social.failedStoryUploadIds.contains($0.id) }
            .map(\.id)
    }
}

// MARK: - Ring states

/// The three preview states of a story bubble. Presence of a ring is
/// the has-story signal; brightness is the unwatched signal.
enum StoryRingState {
    case fresh
    case seen
    case none
}

// MARK: - "Your story" bubble

private struct YourStoryBubble: View {
    let initials: String
    var photoURL: URL? = nil
    var thumbMedia: MediaAsset? = nil
    var thumbCaption: String? = nil
    var uploadFailed: Bool = false
    let action: () -> Void
    let addAction: () -> Void
    var onRetry: (() -> Void)? = nil

    private let discSize: CGFloat = 63
    private let ringSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: action) {
                    ZStack {
                        // Dashed neutral ring — the row's quiet "yours"
                        // frame, distinct from every story ring.
                        Circle()
                            .strokeBorder(
                                Theme.textPrimary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 1.4, dash: [4, 3.5])
                            )
                            .frame(width: ringSize, height: ringSize)

                        disc
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(thumbMedia != nil ? "View your story" : "Add to your story")

                Button(action: addAction) {
                    ZStack {
                        Circle()
                            .fill(Theme.sunWarm)
                            .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.8))
                        Image(systemName: "plus")
                            .font(.sans(11, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(width: 23, height: 23)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 1, y: 1)
                .accessibilityLabel("Add a story")
            }
            .overlay(alignment: .topTrailing) {
                if uploadFailed {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRetry?()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Theme.alertRed)
                                .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.8))
                            Image(systemName: "arrow.clockwise")
                                .font(.sans(10, weight: .bold))
                                .foregroundStyle(Theme.textCream)
                        }
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 2, y: -2)
                    .accessibilityLabel("Your story didn't send. Retry upload.")
                }
            }

            Text(uploadFailed ? "Didn't send" : "Your story")
                .font(.sans(11, weight: .medium))
                .foregroundStyle(uploadFailed ? Theme.alertRed : Theme.textPrimary.opacity(0.75))
                .lineLimit(1)
        }
        .frame(width: 76)
    }

    @ViewBuilder
    private var disc: some View {
        if let thumbMedia {
            MomentThumb(media: thumbMedia, accent: Theme.sunOuter, caption: thumbCaption)
                .frame(width: discSize, height: discSize)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Theme.textPrimary)
                if let photoURL {
                    CachedImage(url: photoURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        initialsText
                    }
                    .frame(width: discSize, height: discSize)
                    .clipShape(Circle())
                } else {
                    initialsText
                }
            }
            .frame(width: discSize, height: discSize)
        }
    }

    private var initialsText: some View {
        Text(initials.isEmpty ? "•" : initials)
            .font(.sans(19, weight: .medium))
            .foregroundStyle(Theme.textCream)
    }
}

// MARK: - Friend bubble

private struct FriendStoryBubble: View {
    let friend: Friend
    let state: StoryRingState
    var thumbMedia: MediaAsset? = nil
    var thumbCaption: String? = nil
    let action: () -> Void

    private let discSize: CGFloat = 63
    private let ringSize: CGFloat = 72

    private var accent: Color { Color(hex: friend.accentColorHex) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    ring
                    disc
                }
                .frame(width: ringSize, height: ringSize)

                Text(friend.displayName)
                    .font(.sans(11, weight: state == .fresh ? .medium : .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(nameOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var nameOpacity: Double {
        switch state {
        case .fresh: return 0.85
        case .seen:  return 0.55
        case .none:  return 0.7
        }
    }

    private var accessibilityText: String {
        switch state {
        case .fresh: return "\(friend.displayName), new story"
        case .seen:  return "\(friend.displayName), story watched"
        case .none:  return friend.displayName
        }
    }

    // MARK: Ring

    @ViewBuilder
    private var ring: some View {
        switch state {
        case .fresh:
            // Bright season-color ring with a small stylistic gap in
            // the stroke — the unmistakable "new" signal.
            Circle()
                .trim(from: 0.045, to: 1.0)
                .stroke(accent, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                .rotationEffect(.degrees(-64))
                .padding(1.4)
        case .seen:
            Circle()
                .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 1.2)
        case .none:
            EmptyView()
        }
    }

    // MARK: Disc

    @ViewBuilder
    private var disc: some View {
        switch state {
        case .fresh, .seen:
            MomentThumb(media: thumbMedia, accent: accent, caption: thumbCaption)
                .frame(width: discSize, height: discSize)
                .clipShape(Circle())
                .opacity(state == .seen ? 0.92 : 1)
        case .none:
            RefinedAvatarDisc(
                accent: accent,
                initials: friend.initials,
                avatarURL: friend.avatarURL,
                size: discSize,
                initialsSize: 21
            )
        }
    }
}

// MARK: - Refined avatar (no story)

/// The plain, ring-less avatar: a subtle gradient on the person's
/// season color with a soft inner shadow — refined, never flat.
struct RefinedAvatarDisc: View {
    let accent: Color
    let initials: String
    var avatarURL: URL? = nil
    var size: CGFloat = 56
    var initialsSize: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.92), accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                // Soft inner shadow — a blurred dark rim clipped back
                // into the circle.
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.16), lineWidth: 5)
                        .blur(radius: 4)
                        .clipShape(Circle())
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )

            if let avatarURL {
                CachedImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialText
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialText
            }
        }
        .frame(width: size, height: size)
    }

    private var initialText: some View {
        Text(initials)
            .font(.sans(initialsSize, weight: .medium))
            .foregroundStyle(Theme.textCream)
    }
}

// MARK: - Moment thumbnail

/// Fills a story bubble with the story's actual frame. Tries the local
/// thumbnail / file first (resolved by file name so previews survive
/// app updates), then any remote URL through the shared image cache;
/// video posts without a poster get one generated on the spot. Falls
/// back to a mini caption card when the post has a caption but no
/// usable image, and to a warm "moment frame" gradient last — so the
/// disc never reads as a meaningless dot.
struct MomentThumb: View {
    let media: MediaAsset?
    let accent: Color
    var caption: String? = nil

    @Environment(Store.self) private var store
    @State private var localImage: UIImage?

    var body: some View {
        ZStack {
            if let localImage {
                Color.clear
                    .overlay(
                        Image(uiImage: localImage)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipped()
            } else if let remote = remoteCandidate {
                CachedImage(url: remote) { image in
                    Color.clear
                        .overlay(image.resizable().scaledToFill())
                        .clipped()
                } placeholder: {
                    fallbackFrame
                }
            } else {
                fallbackFrame
            }
        }
        .task(id: media?.id) {
            // Reset before reloading — otherwise a previously loaded
            // frame sticks around when the newest post changes.
            localImage = nil
            loadLocal()
            // Older video posts never got a poster frame — generate
            // one now, persist it, and re-read.
            if localImage == nil, let media, media.type == .video {
                await store.ensureVideoPoster(mediaId: media.id)
                loadLocal()
            }
        }
    }

    /// A remote (http) URL worth fetching through the cache.
    private var remoteCandidate: URL? {
        let candidates = [media?.remoteURL, media?.thumbnailURL]
        return candidates
            .compactMap { $0 }
            .first { $0.scheme?.hasPrefix("http") == true }
    }

    private func loadLocal() {
        // Re-read from the Store so a freshly generated poster (which
        // updates the asset's thumbnailURL) is picked up even though
        // our `media` value is a pre-poster copy.
        guard let fresh = media.flatMap({ store.media(by: $0.id) }) ?? media else { return }
        var candidates: [URL] = []
        if let thumb = fresh.resolvedThumbnailURL, thumb.isFileURL {
            candidates.append(thumb)
        }
        // Only photos are displayable straight from the main file —
        // a video's bytes need the poster above.
        if fresh.type == .photo, let local = fresh.resolvedLocalURL, local.isFileURL {
            candidates.append(local)
        }
        for url in candidates {
            if let img = UIImage(contentsOfFile: url.path) {
                localImage = img
                return
            }
        }
    }

    /// What fills the disc when no image exists: a mini caption card
    /// (the story player's warm gradient + a snippet of the caption)
    /// when the post has words, the season-color moment frame last.
    @ViewBuilder
    private var fallbackFrame: some View {
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            captionCard(caption)
        } else {
            momentFrame
        }
    }

    /// A 56-pt echo of the player's caption-only canvas — same dusk
    /// gradient, tiny serif snippet — so a caption-only post previews
    /// as an actual story.
    private func captionCard(_ caption: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1830),
                    Color(hex: 0x3A2F48),
                    Color(hex: 0x6B4D52)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Text(caption)
                .font(.serif(8, weight: .medium))
                .foregroundStyle(Theme.textCream)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 8)
        }
    }

    /// The fallback frame — a season-color dusk with a soft glow, so a
    /// caption-only or still-uploading moment still reads as a moment.
    private var momentFrame: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.85), accent],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.sunCore.opacity(0.75),
                            Theme.sunCore.opacity(0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .offset(y: 7)
            LinearGradient(
                colors: [Color.black.opacity(0.18), .clear, Color.black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Add person bubble

private struct AddPersonBubble: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.sunWarm.opacity(0.12))
                    Circle().strokeBorder(
                        Theme.textPrimary.opacity(0.28),
                        style: StrokeStyle(lineWidth: 1.4, dash: [4, 3.5])
                    )
                    Image(systemName: "plus")
                        .font(.sans(20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))
                }
                .frame(width: 72, height: 72)

                Text("Add")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add friend")
        .accessibilityHint("Find and add friends")
    }
}

#Preview {
    ScrollView {
        PeopleStoryRow(
            userInitials: "J",
            onFriendTap: { _, _ in },
            onYouTap: {},
            onYouAddTap: {}
        )
        .environment(Store())
        .environment(SocialSyncService())
        .environment(ModerationService())
    }
    .background(Theme.warmWheat)
}
