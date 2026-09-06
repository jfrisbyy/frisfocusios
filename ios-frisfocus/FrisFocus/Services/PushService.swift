//
//  PushService.swift
//  FrisFocus
//
//  A tiny fire-and-forget helper that asks the `send-push` edge function
//  to notify one recipient. It's fired by the *acting* user's app right
//  after a social action lands (a sent proof/note, a friend request or
//  accept, a circle invite, a check-off or logged contribution) — at that
//  moment the sender's app is foreground and reliably online, so this is a
//  dependable trigger without any database webhooks.
//
//  All notification copy is built server-side from `kind` plus context, so
//  the client never decides wording. Calls never throw into the caller and
//  never block the UI; the backend gracefully no-ops until the Apple push
//  key is configured at publish time.
//

import Foundation
import Supabase

/// The action that prompted a push. Raw values match the `send-push`
/// function's `type` contract exactly.
///
/// `CaseIterable` so the notification settings screen can prove, in debug
/// builds, that every kind sits under one of its groups — a kind added
/// here with no group would be one nobody could ever switch off.
nonisolated enum PushKind: String, CaseIterable, Sendable {
    case proof
    case note
    case friendRequest = "friend_request"
    case friendAccept = "friend_accept"
    case circleInvite = "circle_invite"
    case circleTask = "circle_task"
    case circleProgress = "circle_progress"
    case circleMode = "circle_mode"
    case circleEvent = "circle_event"
    case goldenPost = "golden_post"
    case cheer
    case cheerReaction = "cheer_reaction"
    case storyLike = "story_like"
    case storyComment = "story_comment"
    case pactInvite = "pact_invite"
    case pactAccept = "pact_accept"
    case focusInvite = "focus_invite"
}

/// The request body the `send-push` function reads (camelCase keys, matched
/// to the function's `PushRequest`). Optional fields are omitted when nil.
nonisolated struct PushPayload: Encodable, Sendable {
    let recipientId: String
    let type: String
    let circleId: String?
    let preview: String?
    /// The direct-message row this push is about (proof/note), so the
    /// tap can deep-link straight into the player rather than the inbox.
    let messageId: String?
}

/// Lenient decode of the function's response — we only fire-and-forget, so
/// the contents are ignored beyond confirming a 2xx.
private nonisolated struct PushResponse: Decodable, Sendable {
    let ok: Bool?
}

enum PushService {
    /// Notify `recipientId` about an action. Safe to call from anywhere
    /// (including `@MainActor` services); spins off its own task and
    /// swallows all errors.
    nonisolated static func send(
        to recipientId: String,
        kind: PushKind,
        circleId: String? = nil,
        preview: String? = nil,
        messageId: String? = nil
    ) {
        guard !recipientId.isEmpty else { return }
        let payload = PushPayload(
            recipientId: recipientId,
            type: kind.rawValue,
            circleId: circleId,
            preview: preview,
            messageId: messageId
        )
        Task {
            do {
                let _: PushResponse = try await supabase.functions.invoke(
                    "send-push",
                    options: .init(body: payload)
                )
            } catch {
                print("[Push] send(\(kind.rawValue)) failed: \(error)")
            }
        }
    }
}
