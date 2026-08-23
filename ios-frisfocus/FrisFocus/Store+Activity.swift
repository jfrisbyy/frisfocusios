//
//  Store+Activity.swift
//  FrisFocus
//
//  The "recent activity" read model: every like and comment that landed
//  on the user's own stories plus every cheer they received, folded into
//  one chronological list. Backs the unseen badge on the home and the
//  Recent Activity sheet. Derived entirely from synced state — nothing
//  new is persisted except the last-seen stamp (device-local).
//

import Foundation

// MARK: - Model

enum ActivityKind {
    case like
    case comment
    case cheer
}

/// One engagement row. `postId` links story likes/comments back to the
/// user's own tape; `cheerId` links a cheer to its history entry.
struct ActivityItem: Identifiable {
    let id: String
    let kind: ActivityKind
    let actorName: String
    let actorInitials: String
    /// The comment body or cheer message; nil for likes.
    let detail: String?
    let date: Date
    let postId: UUID?
    let cheerId: UUID?

    /// The verb line — "liked your story", "commented", "cheered you on".
    var verbLine: String {
        switch kind {
        case .like: return "liked your story"
        case .comment: return "commented"
        case .cheer: return "cheered you on"
        }
    }
}

// MARK: - Store accessors

extension Store {
    /// Engagements on me from the last 7 days, newest first, capped.
    var activityItems: [ActivityItem] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let myPostIds = Set(
            storyPosts
                .filter { $0.authorId == currentUserId }
                .map(\.id)
        )

        var items: [ActivityItem] = []

        for like in likes
        where myPostIds.contains(like.postId)
            && like.fromFriendId != currentUserId
            && like.createdAt > cutoff {
            items.append(ActivityItem(
                id: "like-\(like.id.uuidString)",
                kind: .like,
                actorName: like.fromName,
                actorInitials: Self.initials(from: like.fromName),
                detail: nil,
                date: like.createdAt,
                postId: like.postId,
                cheerId: nil
            ))
        }

        for comment in comments
        where myPostIds.contains(comment.postId)
            && comment.fromFriendId != currentUserId
            && comment.createdAt > cutoff {
            items.append(ActivityItem(
                id: "comment-\(comment.id.uuidString)",
                kind: .comment,
                actorName: comment.fromName,
                actorInitials: comment.fromInitials,
                detail: comment.text,
                date: comment.createdAt,
                postId: comment.postId,
                cheerId: nil
            ))
        }

        for cheer in receivedCheers where cheer.sentAt > cutoff {
            items.append(ActivityItem(
                id: "cheer-\(cheer.id.uuidString)",
                kind: .cheer,
                actorName: cheer.fromName,
                actorInitials: cheer.fromInitials,
                detail: cheer.message,
                date: cheer.sentAt,
                postId: nil,
                cheerId: cheer.id
            ))
        }

        return Array(items.sorted { $0.date > $1.date }.prefix(60))
    }

    /// How many engagements arrived since the person last opened the
    /// Recent Activity sheet — drives the quiet badges.
    var unseenActivityCount: Int {
        let seen = activityLastSeenAt
        return activityItems.filter { $0.date > seen }.count
    }

    /// Clear the badge (the list itself keeps its short history).
    func markActivitySeen() {
        activityLastSeenAt = Date()
    }

    private static func initials(from name: String) -> String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
