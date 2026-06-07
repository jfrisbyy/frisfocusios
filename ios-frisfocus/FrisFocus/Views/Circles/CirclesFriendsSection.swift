//
//  CirclesFriendsSection.swift
//  FrisFocus
//
//  The "Friends today" section that lives below the moonlit hero on
//  the Circles page. Three stacked pieces in one editorial column:
//
//   • Section header — serif title, a chevron that rotates with the
//     section's expanded state, and a friend count on the right. The
//     whole row is a tappable target that toggles collapse via the
//     parent.
//   • Stories row — horizontally-scrolling 50 pt avatars with three
//     illumination states (fresh gold ring / plain dim / quiet dashed
//     dim). Leads with the user's own avatar carrying a small `+`
//     badge for posting.
//   • One-line cards — the first two friends as compact summary rows,
//     with a "View N more friends" toggle that expands the rest inline
//     and flips to "Show less" once all are visible.
//
//  Freshness is derived from `friend.lastSignalAt` per the spec:
//  today = fresh, 3+ days ago = quiet, otherwise plain. Story-badge
//  presence on the friend cards is based on whether the friend has an
//  unexpired general post in `store.activeFriendStories`.
//
//  C3d wired this section's interactions: the parent owns the expand /
//  collapse state and supplies the four tap callbacks (header, avatar,
//  card, your-own `+`). All routing decisions — including the
//  illumination-based fresh-vs-detail branch — live in `CirclesView`.
//

import SwiftUI
import UIKit

struct CirclesFriendsSection: View {
    @Environment(Store.self) private var store

    @Binding var isExpanded: Bool
    let onHeaderTap: () -> Void
    let onFriendTap: (Friend, Bool) -> Void
    let onYouTap: () -> Void
    var onYouAddTap: (() -> Void)? = nil
    var onDirectTap: (() -> Void)? = nil
    /// Jump straight to a friend's 1:1 proof/message thread.
    var onMessageTap: ((Friend) -> Void)? = nil

    /// The default-collapsed visible count before the "View N more"
    /// row expands the list. Two reads as editorially balanced on
    /// the page; expansion shows the rest inline.
    private let collapsedCardCount: Int = 2

    @State private var friendsAllShown: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 24)

            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    // MARK: - Expanded body

    @ViewBuilder
    private var expandedBody: some View {
        storiesRow
            .padding(.top, 16)

        VStack(spacing: 10) {
            ForEach(visibleFriends) { friend in
                FriendCardRow(
                    friend: friend,
                    hasFreshStory: hasFreshStory(for: friend),
                    onTap: {
                        onFriendTap(friend, illumination(for: friend) == .fresh)
                    },
                    onMessageTap: { onMessageTap?(friend) }
                )
            }
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 14)

        if hiddenFriendCount > 0 || friendsAllShown {
            viewMoreRow
                .padding(.top, 14)
                .padding(.horizontal, Theme.pageHorizontalPadding)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: onHeaderTap) {
                HStack(spacing: 6) {
                    Text("Friends today")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Image(systemName: "chevron.down")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Friends today, \(store.friends.count) friends")
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")

            Spacer()

            HStack(spacing: 12) {
                if let onDirectTap {
                    directButton(onDirectTap)
                }

                Text("\(store.friends.count) FRIENDS")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
        }
    }

    /// Paper-plane entry to the Direct surface, with a quiet dot when
    /// there are unopened incoming shares.
    private func directButton(_ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "paperplane")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))

                if store.unreadDirectCount > 0 {
                    Circle()
                        .fill(Theme.alertRed)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.unreadDirectCount > 0 ? "Direct, \(store.unreadDirectCount) new" : "Direct")
    }

    // MARK: - Stories row

    private var storiesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 13) {
                // Leading "You" avatar with the small `+` badge.
                YouStoryAvatar(
                    initials: userInitials,
                    hasActiveStories: store.hasActiveMyStories,
                    action: onYouTap,
                    addAction: { (onYouAddTap ?? onYouTap)() }
                )

                ForEach(store.friends) { friend in
                    FriendStoryAvatar(
                        friend: friend,
                        illumination: illumination(for: friend)
                    ) {
                        onFriendTap(friend, illumination(for: friend) == .fresh)
                    }
                }
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.vertical, 4)
        }
    }

    // MARK: - View more row

    private var viewMoreRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.28)) {
                friendsAllShown.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewMoreLabel)
                    .font(.sans(13, weight: .regular))
                Image(systemName: "chevron.down")
                    .font(.sans(11, weight: .medium))
                    .rotationEffect(.degrees(friendsAllShown ? 180 : 0))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewMoreLabel)
    }

    // MARK: - Derived

    private var userInitials: String { "J" }

    private var visibleFriends: [Friend] {
        if friendsAllShown {
            return store.friends
        }
        return Array(store.friends.prefix(collapsedCardCount))
    }

    /// Number of friends still hidden behind the "View more" affordance
    /// when the section is in its default collapsed-list state.
    private var hiddenFriendCount: Int {
        max(0, store.friends.count - collapsedCardCount)
    }

    private var viewMoreLabel: String {
        if friendsAllShown {
            return "Show less"
        }
        return "View \(hiddenFriendCount) more friends"
    }

    /// Maps a friend's last-signal recency onto the three illumination
    /// states the spec defines. The mid-band (anything fresher than 3
    /// days but not today) renders as plain dim — a story that has
    /// already been seen or that was never fresh enough to glow.
    private func illumination(for friend: Friend) -> AvatarIllumination {
        if store.hasUnviewedStories(forFriendId: friend.id) { return .fresh }
        if store.hasAnyActiveStories(forFriendId: friend.id) { return .seen }
        return .none
    }

    /// True when the friend has an unexpired general post visible in
    /// `store.activeFriendStories`. Used to decide whether the small
    /// play badge sits on the friend card avatar.
    private func hasFreshStory(for friend: Friend) -> Bool {
        store.activeFriendStories.contains { $0.authorId == friend.id }
    }
}

// MARK: - Avatar illumination states

/// The three illumination states for a friend avatar in the stories
/// row. They carry meaning, not decoration:
///
///   • `fresh` — a gradient gold ring; the friend has at least one
///     unwatched story.
///   • `seen`  — a solid muted ring; the friend has active stories
///     but the user has already watched all of them.
///   • `none`  — no ring, slightly dimmed; the friend has no active
///     story to play.
enum AvatarIllumination {
    case fresh
    case seen
    case none

    var avatarOpacity: Double {
        switch self {
        case .fresh: return 1.0
        case .seen:  return 0.85
        case .none:  return 0.7
        }
    }
}

// MARK: - "You" stories avatar

private struct YouStoryAvatar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let initials: String
    let hasActiveStories: Bool
    let action: () -> Void
    let addAction: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: action) {
                    avatarDisc.contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasActiveStories ? "View your story" : "Add a story")

                // `+` badge — the add affordance. Prominent when empty
                // (the only action), a secondary add once a story exists.
                Button(action: addAction) {
                    ZStack {
                        Circle()
                            .fill(Theme.sunWarm)
                            .overlay(Circle().strokeBorder(Theme.warmWheat, lineWidth: 1.5))
                        Image(systemName: "plus")
                            .font(.sans(9, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: 2)
                .accessibilityLabel("Add a story")
            }

            Text(hasActiveStories ? "You" : "Add story")
                .font(.sans(11, weight: hasActiveStories ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .lineLimit(1)
        }
        .frame(width: 60)
        .onAppear {
            guard hasActiveStories, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    /// Dark disc with the user's initial. A lit gold story ring is
    /// added only once a story is posted — consistent with friends'
    /// rings; empty state shows no ring so the "+" is the clear action.
    private var avatarDisc: some View {
        ZStack {
            Circle().fill(Theme.textPrimary)
            Text(initials)
                .font(.sans(18, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
        .frame(width: 50, height: 50)
        .overlay { ring }
    }

    @ViewBuilder
    private var ring: some View {
        if hasActiveStories {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.sunWarm, Theme.sunOuter],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.4
                )
                .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.6))
        } else {
            EmptyView()
        }
    }
}

// MARK: - Friend stories avatar

private struct FriendStoryAvatar: View {
    let friend: Friend
    let illumination: AvatarIllumination
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                avatarDisc
                    .frame(width: 50, height: 50)
                    .overlay { ringOverlay }

                Text(friend.displayName)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 60)
            .opacity(illumination.avatarOpacity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(friend.displayName)
    }

    private var avatarDisc: some View {
        ZStack {
            Circle().fill(Color(hex: friend.accentColorHex))
            Text(friend.initials)
                .font(.sans(18, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }

    @ViewBuilder
    private var ringOverlay: some View {
        switch illumination {
        case .fresh:
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.sunWarm, Theme.sunOuter],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        case .seen:
            Circle()
                .strokeBorder(Theme.textPrimary.opacity(0.28), lineWidth: 1.2)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - One-line friend card

private struct FriendCardRow: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let friend: Friend
    let hasFreshStory: Bool
    let onTap: () -> Void
    var onMessageTap: (() -> Void)? = nil

    @State private var glow: Bool = false

    private var unread: Int { store.unreadCount(fromFriendId: friend.id) }
    private var latestUnread: DirectShare? { store.latestUnread(fromFriendId: friend.id) }
    private var hasProofUnread: Bool { latestUnread?.isProof == true }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: 12) {
                    cardAvatar

                    VStack(alignment: .leading, spacing: 3) {
                        titleLine
                        Text(subtitleText)
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(hasProofUnread ? Theme.alertGreen.opacity(0.9) : Theme.textPrimary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friend.displayName), \(store.headlineFromFriend(friend))")

            messageAffordance
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card)
    }

    // MARK: Avatar

    private var cardAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(Color(hex: friend.accentColorHex))
                Text(friend.initials)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textCream)
            }
            .frame(width: 38, height: 38)
            .overlay { avatarRing }

            if hasFreshStory {
                ZStack {
                    Circle()
                        .fill(Theme.alertRed)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    Image(systemName: "play.fill")
                        .font(.sans(7, weight: .black))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 13, height: 13)
                .offset(x: 1, y: 1)
            }
        }
    }

    @ViewBuilder
    private var avatarRing: some View {
        switch illumination {
        case .fresh:
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.sunWarm, Theme.sunOuter],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.8
                )
        case .seen:
            Circle()
                .strokeBorder(Theme.textPrimary.opacity(0.28), lineWidth: 1.1)
        case .none:
            EmptyView()
        }
    }

    private var illumination: AvatarIllumination {
        if store.hasUnviewedStories(forFriendId: friend.id) { return .fresh }
        if store.hasAnyActiveStories(forFriendId: friend.id) { return .seen }
        return .none
    }

    // MARK: Title line

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(friend.displayName)
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if let season = seasonShortName, let day = friend.currentSeasonDay {
                Text("·")
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                Text("\(season) · day \(day)")
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    /// "Heal Season" → "Heal", "Build Season" → "Build". Friends share
    /// the same naming pattern as the homepage so the short form
    /// matches editorial copy.
    private var seasonShortName: String? {
        guard let full = friend.currentSeasonName else { return nil }
        let trimmed = full.replacingOccurrences(of: " Season", with: "")
        return trimmed.isEmpty ? full : trimmed
    }

    // MARK: Subtitle + message affordance

    private var subtitleText: String {
        if hasProofUnread, let u = latestUnread {
            return "\u{1F4F7} sent you a proof · \(FriendRowFormat.elapsed(from: u.createdAt))"
        }
        return store.headlineFromFriend(friend)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
    }

    /// Quiet until this friend reaches out, then it lights up (filled in
    /// their color, unread count, OPEN/VIEW label) with a gentle glow.
    /// Tapping jumps straight to the thread — never a detour. Calm: a
    /// lit glyph, never a screaming pile of red.
    @ViewBuilder
    private var messageAffordance: some View {
        if unread > 0 {
            Button { onMessageTap?() } label: {
                VStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: friend.accentColorHex))
                            Image(systemName: hasProofUnread ? "camera.fill" : "bubble.left.and.bubble.right.fill")
                                .font(.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.textCream)
                        }
                        .frame(width: 46, height: 46)
                        .shadow(color: Color(hex: friend.accentColorHex).opacity(glow ? 0.45 : 0.0), radius: 8)

                        Text("\(unread)")
                            .font(.sans(10, weight: .bold))
                            .foregroundStyle(Theme.textCream)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(Theme.alertRed))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                    Text(hasProofUnread ? "VIEW" : "OPEN")
                        .font(.sans(9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color(hex: friend.accentColorHex))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
            }
            .accessibilityLabel(hasProofUnread ? "View proof from \(friend.displayName)" : "Open message from \(friend.displayName)")
        } else {
            Button { onMessageTap?() } label: {
                ZStack {
                    Circle().fill(Theme.textPrimary.opacity(0.05))
                    Image(systemName: "bubble.left")
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
                .frame(width: 38, height: 38)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message \(friend.displayName)")
        }
    }
}

// MARK: - Friend row formatting

private enum FriendRowFormat {
    static func elapsed(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return days == 1 ? "1d ago" : "\(days)d ago"
    }
}

#Preview {
    ScrollView {
        CirclesFriendsSection(
            isExpanded: .constant(true),
            onHeaderTap: {},
            onFriendTap: { _, _ in },
            onYouTap: {}
        )
        .environment(Store())
    }
    .background(Theme.warmWheat)
}
