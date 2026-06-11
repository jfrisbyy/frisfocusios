//
//  StorySeenByView.swift
//  FrisFocus
//
//  The calm, read-only "Seen by" list for one of the user's own story
//  posts. Reached by tapping "Seen by N" in the `.mine` story player.
//
//  There's no backend yet, so the viewer list is derived
//  deterministically (`Store.storyViewers`) — everyone who reacted,
//  floored to a gentle base so a fresh post still reads witnessed. A
//  soft heart marks anyone who liked the post. This is witnessing, not
//  a pressure metric: a quiet record of who saw the moment, never a
//  read-receipt nag.
//

import SwiftUI
import UIKit

struct StorySeenByView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let post: StoryPost

    /// The viewer whose profile is open, if any.
    @State private var profileTarget: ProfileTarget?

    private var viewers: [StoryViewer] { store.storyViewers(forPost: post.id) }
    private var reactionCount: Int { viewers.filter { $0.didReact }.count }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 22)
                    .padding(.bottom, 10)

                if viewers.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(viewers) { viewer in
                                viewerRow(viewer)
                            }
                        }
                        .padding(.horizontal, Theme.pageHorizontalPadding)
                        .padding(.top, 4)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationContentInteraction(.scrolls)
        .profileDestination($profileTarget, store: store)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WITNESSED")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text("Seen by \(viewers.count)")
                    .font(.serif(24, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if reactionCount > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.sans(11, weight: .medium))
                            .foregroundStyle(Color(hex: 0xED93B1))
                        Text(reactionCount == 1 ? "1 reacted" : "\(reactionCount) reacted")
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                    .padding(.top, 1)
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Viewer row

    private func viewerRow(_ viewer: StoryViewer) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            profileTarget = .friend(viewer.friend)
        } label: {
            HStack(spacing: 12) {
                FriendAvatarView(friend: viewer.friend, size: 46)

                Text(viewer.friend.displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if viewer.didReact {
                    Image(systemName: "heart.fill")
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Color(hex: 0xED93B1))
                        .accessibilityLabel("Reacted")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open \(viewer.friend.displayName)'s profile")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "eye")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
            Text("No one yet")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("When friends watch this moment, they'll show up here.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let store = Store()
    return Color.black
        .sheet(isPresented: .constant(true)) {
            if let post = store.activeMyStories.first {
                StorySeenByView(post: post).environment(store)
            } else {
                Text("No active story")
            }
        }
}
