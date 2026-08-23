//
//  StoryPlayerView.swift
//  FrisFocus
//
//  The shared segmented story player. Reached from any "illuminated"
//  friend avatar on the Circles page (C3 / C3d). Designed so the
//  group-story variant (C9b) can hang off the same chrome by adding a
//  `.circle` case to `StoryPlayerMode` and a small branch in the
//  header / earned badge / bottom row — the segmented progress, tap
//  zones, long-press pause, and swipe-down dismiss are all mode-
//  agnostic.
//
//  Photos auto-advance after 5 s; videos would honour their duration
//  via `MediaAsset.durationSeconds`. Video itself is deferred (C8 ships
//  photo-only) so the timing path is in place but the renderer falls
//  back to a calm gradient + caption when a post has no usable image.
//
//  No bare numeric like counts anywhere; like + comment route through
//  `Store.toggleLike` / `Store.addComment` so the C7a contract carries
//  through unchanged from the friend-detail gesture bar.
//

import AVFoundation
import SwiftUI
import UIKit
import Combine

/// The two surfaces that share the segmented player. `.friend` reads
/// a friend's unexpired general posts (C9a). `.circle` reads a
/// circle's clips with the earned badge + a Today / Whole-journey
/// toggle (C9b). The shared mechanics (segments, gestures, media
/// renderer) live below; only the data source, header, optional
/// earned badge, and bottom row branch on the mode.
enum StoryPlayerMode {
    case friend(Friend)
    case circle(FFCircle)
    /// The current user's own unexpired general posts. Reached by
    /// tapping the "You" avatar in the stories row when at least one
    /// active post exists. Adds a delete affordance to the header.
    case mine
    /// One circle event's proofs, oldest → newest — the story strip at
    /// the top of the event page plays through here. Proofs never
    /// expire from an event, so this is the gathering's full tape.
    case event(CircleEvent)
}

/// Time slice the circle group story renders. `today` scopes to the
/// circle's clips created on the local day; `whole` walks the full
/// archive across the circle's life — the payoff of never expiring
/// circle clips.
enum CircleStoryScope {
    case today
    case whole
}

struct StoryPlayerView: View {
    @Environment(Store.self) private var store
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(ModerationService.self) private var moderation
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let mode: StoryPlayerMode
    /// Invoked when the user taps the friend identity in the header.
    /// Hosts route this to push the friend's full profile.
    var onShowFriendProfile: ((Friend) -> Void)? = nil

    // MARK: - Playback state

    /// The person whose profile is open, if any. Tapping the header
    /// identity (a friend's story, or a circle clip's author) opens
    /// their profile over the player; playback pauses while it's up.
    @State private var profileTarget: ProfileTarget?

    @State private var currentIndex: Int = 0
    /// Fill fraction of the segment currently playing, 0...1.
    /// 25 Hz segment progress, boxed so ticks re-render only the bars
    /// leaf — not this whole player (see `PlaybackClock`).
    @State private var clock = PlaybackClock()
    @State private var isPaused: Bool = false
    /// Interactive dismissal — the card scales, rounds, and follows the
    /// finger; the backdrop fades; release is velocity-aware.
    @State private var drag = PlayerDragMetrics()
    @State private var crossedDismissThreshold: Bool = false
    @State private var pressStart: Date?

    // MARK: - Reply composer

    @State private var draft: String = ""
    @FocusState private var replyFocused: Bool

    // MARK: - Circle mode state

    /// Scope toggle for `.circle` mode. Ignored in `.friend` mode.
    @State private var circleScope: CircleStoryScope = .today

    /// Cheer composer target. Set when the user taps the amber cheer
    /// pill on a circle clip whose author is a known friend. `nil`
    /// keeps the sheet dismissed.
    @State private var cheerTarget: Friend?

    /// The id of the user's own post pending a delete confirmation.
    /// Drives the `.confirmationDialog` in `.mine` mode and resumes
    /// playback on dismiss so the player doesn't sit paused forever.
    @State private var pendingDeletePostId: UUID?

    /// Drives the in-viewer "+ Add" flow in `.mine` mode — post another
    /// moment without leaving the tape.
    @State private var showAddStory: Bool = false

    /// The own-story post whose "Seen by" list is open, if any. Set by
    /// tapping the seen-by pill in `.mine` mode; pauses playback while
    /// the calm viewer sheet is up and resumes on dismiss.
    @State private var seenByPost: StoryPost?

    /// The report flow for the current segment, when open. Pauses
    /// playback while the sheet is up.
    @State private var reportTarget: ReportTarget?

    /// Asks for confirmation before blocking the current author.
    @State private var showBlockConfirm: Bool = false

    /// Tick rate for the progress driver. 25 fps reads as smooth
    /// without burning a re-render every vsync.
    private let tick: TimeInterval = 0.04
    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    /// Default per-photo segment length — story norm. Videos override
    /// this through `currentDuration` when their `MediaAsset` carries
    /// a duration.
    private let photoDuration: TimeInterval = 5.0

    // MARK: - Derived posts

    /// The chronological list of posts driving this story. Oldest →
    /// newest so the first segment to fill is the earliest moment the
    /// friend shared, matching the rest of the social UI's order.
    /// Posts from anyone the user has blocked vanish immediately, even
    /// before the server refresh drops them.
    private var posts: [StoryPost] {
        basePosts.filter { !isBlockedAuthor($0.authorId) }
    }

    private var basePosts: [StoryPost] {
        switch mode {
        case .friend(let friend):
            // Isolated tape: only the tapped friend's unexpired posts,
            // oldest → newest. The player closes when their last
            // segment ends — never rolling into another friend's
            // story, so opening from a profile or the friends row
            // always stays on that one person.
            return store.activeFriendStories
                .filter { $0.authorId == friend.id }
                .sorted { $0.createdAt < $1.createdAt }
        case .mine:
            return store.activeMyStories
        case .circle(let circle):
            let cal = Calendar.current
            let today = Date()
            return store.storyPosts
                .filter { post in
                    guard post.circleId == circle.id else { return false }
                    switch circleScope {
                    case .today:
                        return cal.isDate(post.createdAt, inSameDayAs: today)
                    case .whole:
                        return true
                    }
                }
                .sorted { $0.createdAt < $1.createdAt }
        case .event(let event):
            return store.eventProofs(eventId: event.id)
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var currentPost: StoryPost? {
        guard currentIndex >= 0 && currentIndex < posts.count else { return nil }
        return posts[currentIndex]
    }

    /// The author of the current segment, resolved fresh from the
    /// store so the header always shows live friend data.
    private var currentFriend: Friend? {
        guard let authorId = currentPost?.authorId else { return nil }
        return store.friend(by: authorId)
    }

    private var currentMedia: MediaAsset? {
        guard let id = currentPost?.mediaId else { return nil }
        return store.mediaAssets.first { $0.id == id }
    }

    private var currentDuration: TimeInterval {
        if let media = currentMedia, media.type == .video,
           let dur = media.durationSeconds, dur > 0 {
            return dur
        }
        return photoDuration
    }

    // MARK: - Body

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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Delete this story?",
            isPresented: Binding(
                get: { pendingDeletePostId != nil },
                set: { if !$0 { pendingDeletePostId = nil; isPaused = false } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeletePostId {
                    handleDelete(postId: id)
                }
                pendingDeletePostId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletePostId = nil
                isPaused = false
            }
        } message: {
            Text("This will remove the post from your stories. Friends won't see it anymore.")
        }
        .sheet(item: $reportTarget, onDismiss: { isPaused = false }) { target in
            ReportSheet(
                reportedUserId: target.reportedUserId,
                messageId: target.messageId,
                subjectName: target.subjectName,
                storyPostId: target.storyPostId,
                storyCommentId: target.storyCommentId
            )
        }
        .confirmationDialog(
            "Block this person?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                blockCurrentAuthor()
            }
            Button("Cancel", role: .cancel) { isPaused = false }
        } message: {
            Text("They won't be able to message you or see your days, and you won't see theirs.")
        }
        .sheet(item: $cheerTarget, onDismiss: {
            // Resume playback the moment the cheer composer is
            // dismissed so the segment doesn't sit paused forever.
            isPaused = false
        }) { friend in
            CheerComposerView(friend: friend)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .fullScreenCover(isPresented: $showAddStory, onDismiss: { isPaused = false }) {
            CaptureView(mode: .generalPost)
                .environment(store)
        }
        .sheet(item: $seenByPost, onDismiss: { isPaused = false }) { post in
            StorySeenByView(post: post)
                .environment(store)
        }
        .profileDestination($profileTarget, store: store)
        .onChange(of: profileTarget != nil) { _, profileOpen in
            // Pause the tape while a profile is open over the player,
            // resume the moment it closes so the segment doesn't run on
            // underneath it.
            isPaused = profileOpen
        }
        .onReceive(timer) { _ in
            tickProgress()
        }
        .onAppear {
            markCurrentViewed()
            if posts.isEmpty {
                // Nothing to watch — close immediately so the user
                // doesn't sit on a black screen. CirclesView's
                // illumination routing should make this rare, but
                // sharing-flag races can still land us here empty.
                DispatchQueue.main.async { dismiss() }
                return
            }
        }
        .onChange(of: currentIndex) { _, _ in
            markCurrentViewed()
        }
    }

    // MARK: - Card

    /// The full-bleed player card: media, gesture layer, and chrome.
    /// Separated from the backdrop so interactive dismissal can scale
    /// and round it as one piece.
    private func playerCard(bottomInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black

            if currentPost == nil {
                emptyState
            } else {
                // Media fills the canvas.
                mediaLayer

                // Transparent gesture receiver behind the chrome. Tap
                // zones, long-press pause and swipe-down dismiss all
                // route through this single layer; the chrome on top
                // (header, bottom row, reply field) intercepts its own
                // hits because it draws actual content.
                GeometryReader { geo in
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .gesture(unifiedGesture(width: geo.size.width))
                }

                // Chrome: progress + header at the top, caption +
                // composer at the bottom.
                VStack(spacing: 0) {
                    progressBars
                        .padding(.horizontal, 10)
                        .padding(.top, 54)

                    header
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 12)

                    if case .circle = mode {
                        circleScopeToggle
                            .padding(.top, 10)
                    }

                    Spacer(minLength: 0)

                    eventTagOverlay
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.bottom, 6)

                    earnedBadgeOverlay
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.bottom, 8)

                    captionOverlay
                        .padding(.bottom, 6)

                    bottomRow
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.bottom, 22 + bottomInset)
                }
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Nothing to watch")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textCream)
            Button("Close") {
                dismiss()
            }
            .foregroundStyle(Theme.textCream.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress bars

    /// The window of the queue the top bars represent. Every mode now
    /// plays a single owner's tape — a friend's isolated story, your
    /// own posts, or one circle's clips — so the whole queue is the
    /// window.
    private var segmentWindow: (count: Int, index: Int, ownerKey: String) {
        (posts.count, currentIndex, "single-owner")
    }

    /// Per-person segmented bars. Keyed by the current author so the
    /// handoff between people tears the old bars down and fades the new
    /// person's fresh set in — the Instagram/Snapchat reset.
    private var progressBars: some View {
        let window = segmentWindow
        return ZStack {
            SegmentedProgressBars(count: window.count, currentIndex: window.index, clock: clock)
                .id(window.ownerKey)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.22), value: window.ownerKey)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            switch mode {
            case .friend:
                if let friend = currentFriend {
                    Button {
                        showFriendProfile(friend)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            friendAvatar(friend)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(friend.displayName)
                                    .font(.sans(14, weight: .semibold))
                                    .foregroundStyle(Theme.textCream)
                                if let post = currentPost {
                                    Text(elapsedString(from: post.createdAt))
                                        .font(.sans(11, weight: .regular))
                                        .foregroundStyle(Theme.textCream.opacity(0.75))
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(friend.displayName)'s profile")
                }
            case .circle(let circle):
                if let authorId = currentPost?.authorId,
                   store.profileTarget(forMemberId: authorId) != nil {
                    Button {
                        showAuthorProfile(authorId)
                    } label: {
                        circleHeaderAvatar(for: circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open profile")
                } else {
                    circleHeaderAvatar(for: circle)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(circle.name)
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                    Text(circleDayString(for: circle))
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.75))
                }
            case .mine:
                Button {
                    showSelfProfile()
                } label: {
                    myAvatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open your profile")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your story")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                    if let post = currentPost {
                        Text(elapsedString(from: post.createdAt))
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textCream.opacity(0.75))
                    }
                }
            case .event(let event):
                if let authorId = currentPost?.authorId,
                   store.profileTarget(forMemberId: authorId) != nil {
                    Button {
                        showAuthorProfile(authorId)
                    } label: {
                        eventHeaderAvatar(for: event)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open profile")
                } else {
                    eventHeaderAvatar(for: event)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .lineLimit(1)
                    if let post = currentPost {
                        Text("\(authorName(for: post)) · \(elapsedString(from: post.createdAt))")
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textCream.opacity(0.75))
                    }
                }
            }

            Spacer()

            if case .mine = mode, let post = currentPost {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isPaused = true
                    pendingDeletePostId = post.id
                } label: {
                    Image(systemName: "trash")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete this post")
            }

            if let post = currentPost, post.authorId != store.currentUserId {
                moderationMenu(for: post)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close story")
        }
    }

    /// The "…" safety menu on someone else's segment: report the
    /// post, or block its author entirely.
    private func moderationMenu(for post: StoryPost) -> some View {
        Menu {
            Button {
                isPaused = true
                reportTarget = ReportTarget(
                    reportedUserId: socialSync.remoteId(forLocal: post.authorId),
                    messageId: nil,
                    subjectName: authorName(for: post),
                    storyPostId: post.id
                )
            } label: {
                Label("Report this story", systemImage: "flag")
            }
            if socialSync.remoteId(forLocal: post.authorId) != nil {
                Button(role: .destructive) {
                    isPaused = true
                    showBlockConfirm = true
                } label: {
                    Label("Block \(authorName(for: post))", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(Theme.textCream)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    /// The user's own avatar disc used in `.mine` mode — their real
    /// profile photo (or real initials), ringed in cream so it reads
    /// against the dark canvas.
    private var myAvatar: some View {
        MyAvatarDisc(size: 34)
            .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.5), lineWidth: 1))
    }

    private func friendAvatar(_ friend: Friend) -> some View {
        FriendAvatarView(friend: friend, size: 34)
            .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.5), lineWidth: 1))
    }

    /// The author avatar paired with the circle name in the header.
    /// Anchors the segment to a person without renaming the room.
    @ViewBuilder
    private func circleHeaderAvatar(for circle: FFCircle) -> some View {
        let authorId = currentPost?.authorId
        let isYou = authorId == store.currentUserId
        ZStack {
            if isYou {
                MyAvatarDisc(size: 34)
            } else if let id = authorId, let friend = store.friend(by: id) {
                FriendAvatarView(friend: friend, size: 34)
            } else {
                // Author isn't in the local friend graph (a circle-only
                // member). Fall back to a neutral disc tinted by the
                // circle's type so the header still reads warm.
                Circle().fill(CircleDetailHeroGradient.colors(for: circle.type).last ?? Theme.textTertiary)
            }
        }
        .frame(width: 34, height: 34)
        .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.5), lineWidth: 1))
    }

    /// The author avatar for `.event` mode — the circle avatar styling
    /// when the event's circle resolves, a neutral disc otherwise.
    @ViewBuilder
    private func eventHeaderAvatar(for event: CircleEvent) -> some View {
        if let circle = store.circle(by: event.circleId) {
            circleHeaderAvatar(for: circle)
        } else {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Theme.textCream.opacity(0.5), lineWidth: 1))
        }
    }

    /// The current segment's author as a short display name.
    private func authorName(for post: StoryPost) -> String {
        if post.authorId == store.currentUserId { return "You" }
        return store.friend(by: post.authorId)?.displayName ?? "Member"
    }

    /// Whether a local member id belongs to someone the user blocked.
    private func isBlockedAuthor(_ authorId: UUID) -> Bool {
        guard authorId != store.currentUserId,
              let remote = socialSync.remoteId(forLocal: authorId) else { return false }
        return moderation.isBlocked(remote)
    }

    /// `{circle name}` already lives on the line above; this provides
    /// the timeline anchor — `day N` from the circle's creation date.
    /// Computed from the current segment so a `Whole journey` walk
    /// reads the day each clip was taken, not today.
    private func circleDayString(for circle: FFCircle) -> String {
        let cal = Calendar.current
        let anchorDate = currentPost?.createdAt ?? Date()
        let start = cal.startOfDay(for: circle.createdAt)
        let end = cal.startOfDay(for: anchorDate)
        let comps = cal.dateComponents([.day], from: start, to: end)
        let day = max(1, (comps.day ?? 0) + 1)
        return "day \(day)"
    }

    // MARK: - Circle scope toggle

    /// A small two-segment pill at the top of the circle player.
    /// Selecting a scope re-derives `posts` and resets the playhead so
    /// the new segment count reads from the beginning.
    private var circleScopeToggle: some View {
        HStack(spacing: 0) {
            scopeChip(.today, label: "Today")
            scopeChip(.whole, label: "Whole journey")
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.textCream.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.20), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Story scope")
    }

    private func scopeChip(_ value: CircleStoryScope, label: String) -> some View {
        let isSelected = circleScope == value
        return Button {
            guard circleScope != value else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.22)) {
                circleScope = value
                currentIndex = 0
                clock.progress = 0
            }
        } label: {
            Text(label)
                .font(.sans(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textCream.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Theme.textCream : Color.clear)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(label)
    }

    // MARK: - Earned badge

    /// Renders the green check + task title pill above the caption
    /// overlay when the current clip documents a circle task. Only
    /// mounts in `.circle` mode and only when `attachedCircleTaskId`
    /// resolves on the circle's task list.
    @ViewBuilder
    private var earnedBadgeOverlay: some View {
        if case .circle(let circle) = mode,
           let post = currentPost,
           let taskId = post.attachedCircleTaskId,
           let task = circle.tasks.first(where: { $0.id == taskId }) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                Text(task.title)
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.alertGreen.opacity(0.5), lineWidth: 0.6)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A small "From <event>" tag shown on a clip that documents a
    /// circle event, so people can tell it came from an event.
    @ViewBuilder
    private var eventTagOverlay: some View {
        if let post = currentPost,
           let eventId = post.eventId,
           let event = store.event(by: eventId) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                Text(event.title)
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(Capsule(style: .continuous).strokeBorder(Color(hex: 0xD87D44).opacity(0.6), lineWidth: 0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Media layer

    @ViewBuilder
    private var mediaLayer: some View {
        if let post = currentPost {
            ZStack {
                if let media = currentMedia, let url = media.resolvedLocalURL, media.type == .video {
                    // Recorded clips play on a loop, with sound, letter-
                    // boxed to their true shape. Holding to pause stops
                    // the clip alongside the progress bar.
                    VideoLoopView(url: url, gravity: .resizeAspect, isPaused: isPaused)
                        .id(url)
                } else if let media = currentMedia,
                          let url = media.resolvedLocalURL,
                          let img = loadImage(at: url) {
                    shapeAwareImage(img)
                } else {
                    captionOnlyBackground(for: post)
                }
            }
        }
    }

    /// Shape-aware rendering: cards composed in the 9:16 story shape
    /// are NOT stretched to fill the even-taller screen (that was the
    /// over-zoom). The whole image shows centered, with a soft blurred
    /// copy of itself filling the edges.
    private func shapeAwareImage(_ img: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 42, opaque: true)
                    .overlay(Color.black.opacity(0.28))

                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func captionOnlyBackground(for post: StoryPost) -> some View {
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

            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private func loadImage(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Caption + reactions overlay

    @ViewBuilder
    private var captionOverlay: some View {
        if let post = currentPost {
            let likeSummary = store.likeSummary(postId: post.id)
            let recent = Array(
                store.comments(for: post.id)
                    .filter { !isBlockedAuthor($0.fromFriendId) }
                    .suffix(2)
            )

            // Media posts carry their caption *inside* the media itself
            // (placed text is flattened into the photo at capture time),
            // so we deliberately do not re-render the caption string here —
            // that produced a duplicate label in the corner.
            VStack(alignment: .leading, spacing: 8) {
                if let summary = likeSummary {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.sans(11, weight: .medium))
                            .foregroundStyle(Color(hex: 0xED93B1))
                        Text(summary)
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textCream.opacity(0.92))
                    }
                }

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recent) { comment in
                            inlineComment(comment)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inlineComment(_ comment: Comment) -> some View {
        (
            Text(comment.fromName)
                .font(.sans(12, weight: .semibold))
                .foregroundColor(Theme.textCream)
            + Text("  ")
            + Text(comment.text)
                .font(.sans(12, weight: .regular))
                .foregroundColor(Theme.textCream.opacity(0.88))
        )
        .lineLimit(2)
        .shadow(color: Color.black.opacity(0.45), radius: 4, x: 0, y: 1)
    }

    // MARK: - Bottom row (reply + like)

    @ViewBuilder
    private var bottomRow: some View {
        if let post = currentPost {
            if case .mine = mode {
                mineBottomRow(post)
            } else {
                friendCircleBottomRow(post)
            }
        }
    }

    /// Your own story's footer: who's seen it + reactions on the left,
    /// an "+ Add" button on the right to post another moment. Calm — a
    /// quiet count, never a pressure metric.
    private func mineBottomRow(_ post: StoryPost) -> some View {
        HStack(spacing: 14) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isPaused = true
                seenByPost = post
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye").font(.sans(13, weight: .regular))
                    Text("Seen by \(store.seenCount(forPost: post.id))")
                        .font(.sans(13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.sans(10, weight: .semibold))
                        .opacity(0.6)
                }
                .foregroundStyle(Theme.textCream.opacity(0.9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See who viewed this story. Seen by \(store.seenCount(forPost: post.id)).")

            HStack(spacing: 4) {
                Image(systemName: "heart").font(.sans(13, weight: .regular))
                Text("\(store.likes(for: post.id).count)")
                    .font(.sans(13, weight: .medium))
            }
            .foregroundStyle(Theme.textCream.opacity(0.9))

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isPaused = true
                showAddStory = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.sans(13, weight: .bold))
                    Text("Add").font(.sans(14, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule(style: .continuous).fill(Theme.sunWarm))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add another moment")
        }
    }

    @ViewBuilder
    private func friendCircleBottomRow(_ post: StoryPost) -> some View {
        let liked = store.isPostLikedByMe(post.id)
        Group {
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text(replyPlaceholder(for: post))
                        .foregroundColor(Theme.textCream.opacity(0.65)),
                    axis: .horizontal
                )
                .font(.sans(14, weight: .regular))
                .foregroundStyle(Theme.textCream)
                .tint(Theme.textCream)
                .focused($replyFocused)
                .submitLabel(.send)
                .onSubmit { submitReply(for: post) }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.textCream.opacity(0.45), lineWidth: 1)
                )
                .onChange(of: replyFocused) { _, focused in
                    // Pause playback while the user is typing so a
                    // segment doesn't auto-advance under them mid-
                    // thought.
                    isPaused = focused
                }

                if allowsCheer, let target = cheerCandidate(for: post) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isPaused = true
                        cheerTarget = target
                    } label: {
                        Image(systemName: "hands.clap.fill")
                            .font(.sans(18, weight: .semibold))
                            .foregroundStyle(Theme.textCream)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(Color(hex: 0xD87D44))
                            )
                            .overlay(
                                Circle().strokeBorder(Theme.textCream.opacity(0.4), lineWidth: 0.6)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send a cheer")
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.toggleLike(postId: post.id)
                    }
                } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.sans(22, weight: .regular))
                        .foregroundStyle(liked ? Color(hex: 0xED93B1) : Theme.textCream)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(liked ? "Unlike" : "Like")
            }
        }
    }

    /// Whether this surface offers the amber cheer pill — circle and
    /// event tapes do; a friend's own story and your own tape don't.
    private var allowsCheer: Bool {
        switch mode {
        case .circle, .event: return true
        case .friend, .mine: return false
        }
    }

    /// Resolves the cheer recipient for the current clip: the post's
    /// author if they're a known friend. Returns `nil` for the user's
    /// own clips (you can't cheer yourself) and for circle-only
    /// members not in the friend graph, so the button only mounts
    /// when there's a real person to address.
    private func cheerCandidate(for post: StoryPost) -> Friend? {
        guard post.authorId != store.currentUserId else { return nil }
        return store.friend(by: post.authorId)
    }

    private func replyPlaceholder(for post: StoryPost) -> String {
        switch mode {
        case .friend:
            return "Reply…"
        case .mine:
            return "Note to self…"
        case .circle, .event:
            if post.authorId == store.currentUserId {
                return "Reply…"
            }
            if let friend = store.friend(by: post.authorId) {
                return "Tap through to \(friend.displayName)…"
            }
            return "Reply…"
        }
    }

    /// Remove the user's own post, then either advance to the next
    /// segment or dismiss when the tape is empty. Keeps the player
    /// alive across deletes so a user can prune several at once.
    private func handleDelete(postId: UUID) {
        store.deleteMyStoryPost(postId)
        // After removal, `posts` recomputes. Clamp the playhead so we
        // never index past the end; dismiss when nothing remains.
        if posts.isEmpty {
            dismiss()
            return
        }
        if currentIndex >= posts.count {
            currentIndex = posts.count - 1
        }
        clock.progress = 0
        isPaused = false
    }

    /// Block the current segment's author: sever the relationship,
    /// refresh the mirrors, and close the player — their tape is gone.
    private func blockCurrentAuthor() {
        guard let post = currentPost,
              let remote = socialSync.remoteId(forLocal: post.authorId),
              let myId = auth.user?.id else {
            isPaused = false
            return
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task {
            await moderation.block(remote, myUserId: myId)
            await socialSync.refreshFriends()
            await socialSync.refreshStories()
            dismiss()
        }
    }

    private func submitReply(for post: StoryPost) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.addComment(postId: post.id, text: trimmed)
        draft = ""
        replyFocused = false
    }

    // MARK: - Playback

    /// Stamp the current post as watched. Friend-mode posts downgrade
    /// the rail ring from gold (new) to muted (seen); circle-mode clips
    /// — including the user's own — clear the circle card's new-story
    /// glow. `.mine` (the personal tape) never needs a stamp.
    private func markCurrentViewed() {
        guard let post = currentPost else { return }
        switch mode {
        case .mine:
            return
        case .friend:
            guard post.authorId != store.currentUserId else { return }
            store.markStoryViewed(post.id)
        case .circle, .event:
            store.markStoryViewed(post.id)
        }
    }

    private func tickProgress() {
        guard !isPaused, !replyFocused, currentPost != nil else { return }
        let increment = tick / max(0.1, currentDuration)
        clock.progress += increment
        if clock.progress >= 1 {
            advance()
        }
    }

    private func advance() {
        if currentIndex + 1 >= posts.count {
            dismiss()
            return
        }
        currentIndex += 1
        clock.progress = 0
    }

    private func goPrev() {
        if currentIndex == 0 {
            clock.progress = 0
        } else {
            currentIndex -= 1
            clock.progress = 0
        }
    }

    private func goNext() {
        advance()
    }

    // MARK: - Profile routing

    /// Open a friend's profile from the header. When a host provided
    /// `onShowFriendProfile` (the Circles page pops the player and
    /// pushes the hub onto its nav stack), defer to it; otherwise
    /// present the hub over the player and pause playback.
    private func showFriendProfile(_ friend: Friend) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let onShowFriendProfile {
            onShowFriendProfile(friend)
        } else {
            profileTarget = .friend(friend)
        }
    }

    /// Open the profile of a circle clip's author (a friend, or you).
    private func showAuthorProfile(_ authorId: UUID) {
        guard let target = store.profileTarget(forMemberId: authorId) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        profileTarget = target
    }

    /// Open the user's own profile from the `.mine` header.
    private func showSelfProfile() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        profileTarget = .me
    }

    // MARK: - Unified press / tap / drag gesture
    //
    // A single `DragGesture(minimumDistance: 0)` powers three
    // behaviours so they can't fight each other:
    //   • Touch down → pause playback.
    //   • Release with minimal movement → tap zones (left third =
    //     previous, right two-thirds = next), driven by start-location.
    //   • Drag down past the threshold → dismiss.
    //
    // The press duration check keeps long-presses (>0.25 s) from
    // counting as taps, so holding to read a caption resumes playback
    // on release rather than skipping the segment.

    private func unifiedGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    isPaused = true
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

                // Velocity-aware: a long pull or a quick flick both
                // dismiss; the card flies back into its source avatar.
                if PlayerDragMetrics.shouldDismiss(translation: value.translation, predicted: value.predictedEndTranslation) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                    return
                }

                // Snap back to rest in case we offset for a partial
                // drag.
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { drag.translation = .zero }
                isPaused = false

                // Short, low-movement release = tap. Long holds fall
                // through and just resume playback.
                if pressDuration < 0.25 && movement < 10 {
                    if value.startLocation.x < width / 3 {
                        goPrev()
                    } else {
                        goNext()
                    }
                }
            }
    }

    // MARK: - Elapsed-time string

    /// Per the locked decision: show how long ago the post was made,
    /// never a countdown to expiry. Friend stories carry the warmth of
    /// "3 hr ago," not the urgency of "21 h left."
    private func elapsedString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hr ago"
        }
        let days = hours / 24
        return days == 1 ? "1 d ago" : "\(days) d ago"
    }
}

#Preview("Friend") {
    let store = Store()
    return StoryPlayerView(mode: .friend(store.friends.first!))
        .environment(store)
}

#Preview("Circle") {
    let store = Store()
    return StoryPlayerView(mode: .circle(store.circles.first(where: { $0.type == .parallel })!))
        .environment(store)
}
