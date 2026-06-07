//
//  DirectShareModels.swift
//  FrisFocus
//
//  A privately-sent photo/video — the counterpart to a public 24h
//  StoryPost. Where a StoryPost broadcasts to every friend, a
//  DirectShare goes to exactly one destination: a single friend or a
//  whole circle. Picking several friends in the composer does NOT make
//  a group thread — it writes one DirectShare per friend, so each
//  person gets their own private copy.
//
//  Pure data, Codable, no UI dependencies. The Store owns the array
//  and persists it alongside the rest of the social layer.
//

import Foundation

/// One private send. `authorId` is who sent it (the current user for
/// outgoing shares; a friend for the seeded incoming examples).
/// Exactly one of `recipientFriendId` / `circleId` is set:
///   • `recipientFriendId` — a one-to-one send to that friend.
///   • `circleId` — a send to everyone in that circle.
/// `mediaId` points at a `MediaAsset`; nil renders as a calm
/// caption-only card (used by the seeded incoming examples).
struct DirectShare: Codable, Identifiable {
    var id: UUID = UUID()
    var authorId: UUID
    var recipientFriendId: UUID?
    var circleId: UUID?
    var caption: String?
    var mediaId: UUID?
    var createdAt: Date = Date()

    /// When the current user opened an *incoming* share. Drives the
    /// "new" dot on the Direct entry. Outgoing shares leave this nil.
    var readAt: Date?

    /// When the current user actually *watched* this proof in the
    /// full-screen player. Distinct from `readAt` (which clears the
    /// conversation's unread badge the moment the thread is opened):
    /// a proof stays "unwatched" until it has played, so the chat pill
    /// can flip from "Tap to view" to "Reply with a proof." Notes and
    /// outgoing shares leave this nil. Optional so shares persisted
    /// before this landed still decode cleanly.
    var viewedAt: Date?

    /// True when the destination is a circle rather than a single
    /// friend.
    var isToCircle: Bool { circleId != nil }

    /// A *proof* carries media; a caption-only share is a lightweight
    /// *message* (note) in the 1:1 thread. Same data type, different
    /// presentation — no mechanic change.
    var isProof: Bool { mediaId != nil }

    /// True once the current user has watched this proof in the
    /// full-screen viewer. Drives the chat pill's view → reply flip.
    var isProofWatched: Bool { viewedAt != nil }
}

/// One row in the Proofs inbox — a person you've privately traded
/// proofs/notes with, plus the most recent exchange (for the preview
/// line + timestamp) and how many of their sends are still unread.
/// Derived from `DirectShare`s on demand; never persisted.
struct DirectConversation: Identifiable {
    let friend: Friend
    let latest: DirectShare
    let unreadCount: Int
    var id: UUID { friend.id }
}
