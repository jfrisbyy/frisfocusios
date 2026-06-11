//
//  DiscoverPersonRow.swift
//  FrisFocus
//
//  One suggested person — avatar, name, @username, and a small mutual
//  count when shared friends exist — with a one-tap Add that flips to
//  Pending in place. Used by the Friends page's "Discover people"
//  section and the full Discover screen, so both stay identical.
//

import SwiftUI
import UIKit

struct DiscoverPersonRow: View {
    let suggestion: DiscoverSuggestion
    /// The live connection state — drives the trailing control and is
    /// re-read from the friend graph, so an Add flips to Pending the
    /// moment the request lands.
    let relationship: FriendRelationship
    /// Tap on the person themselves → open their profile preview.
    let onOpen: () -> Void
    /// Tap on Add → send the real friend request.
    let onAdd: () -> Void
    /// Slightly larger treatment — used when Discover leads the page
    /// for a zero-friend user.
    var prominent: Bool = false

    private var profile: RemoteProfile { suggestion.profile }

    private var avatarSize: CGFloat { prominent ? 52 : 44 }

    private var secondaryText: String? {
        var parts: [String] = []
        if let handle = profile.handle ?? profile.email, handle != profile.displayName {
            parts.append(handle)
        }
        if suggestion.mutualCount > 0 {
            parts.append("\(suggestion.mutualCount) mutual")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.sans(prominent ? 16 : 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let secondaryText {
                            Text(secondaryText)
                                .font(.sans(prominent ? 13 : 12, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(profile.displayName)'s profile")

            trailing
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: relationship)
        }
        .padding(prominent ? 14 : 12)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: prominent ? 16 : 14))
    }

    @ViewBuilder
    private var trailing: some View {
        switch relationship {
        case .none:
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdd()
            } label: {
                DiscoverPill(title: "Add", filled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(profile.displayName)")
        case .requestSent:
            DiscoverPill(title: "Pending", filled: false)
                .opacity(0.55)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        case .friends:
            DiscoverPill(title: "Friends", filled: false)
                .opacity(0.55)
        case .requestReceived, .isMe:
            EmptyView()
        }
    }

    private var avatar: some View {
        ZStack {
            if let url = profile.photoURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsDisc
                }
            } else {
                initialsDisc
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private var initialsDisc: some View {
        ZStack {
            Theme.textPrimary
            Text(profile.initials)
                .font(.sans(prominent ? 17 : 15, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }
}

/// The Friends-surface action pill, shared by the discover row and the
/// profile preview sheet.
struct DiscoverPill: View {
    let title: String
    let filled: Bool

    var body: some View {
        Text(title)
            .font(.sans(13, weight: .semibold))
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(filled ? Theme.textPrimary : Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.textPrimary.opacity(filled ? 0 : 0.15), lineWidth: 1)
            )
    }
}
