//
//  ThreadPresenceService.swift
//  FrisFocus
//
//  Live presence for a 1:1 thread, carried by Supabase Realtime
//  presence. Both participants join a per-pair channel (ids sorted so
//  they resolve the same room) and track a tiny state blob — whether
//  they're in the thread, typing, or watching a proof full-screen.
//
//  The thread UI reads `friendStatus` to render "here now", an animated
//  typing indicator, or "watching your proof…" — the cues that make the
//  app feel alive. Everything is fire-and-forget; presence failures are
//  silent and never block messaging.
//

import Foundation
import Supabase

// MARK: - Status

/// What a participant is doing in the thread right now.
nonisolated enum ThreadPresenceStatus: String, Sendable {
    case here
    case typing
    case watching
}

/// The state blob tracked on the presence channel.
private nonisolated struct ThreadPresencePayload: Codable, Sendable {
    let userId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case userId = "user_id"
    }
}

// MARK: - Service

@Observable
@MainActor
final class ThreadPresenceService {
    /// The friend's live status, or nil when they're not in the thread.
    var friendStatus: ThreadPresenceStatus?

    var friendIsHere: Bool { friendStatus != nil }
    var friendIsTyping: Bool { friendStatus == .typing }
    var friendIsWatching: Bool { friendStatus == .watching }

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var typingResetTask: Task<Void, Never>?
    @ObservationIgnored private var myUserId: String = ""
    @ObservationIgnored private var friendId: String = ""
    @ObservationIgnored private var myStatus: ThreadPresenceStatus = .here

    // MARK: Lifecycle

    /// Join the pair's presence room and start tracking. Idempotent.
    func start(myUserId: String, friendId: String) async {
        guard channel == nil, !myUserId.isEmpty, !friendId.isEmpty else { return }
        self.myUserId = myUserId
        self.friendId = friendId

        let a = min(myUserId, friendId)
        let b = max(myUserId, friendId)
        let ch = supabase.channel("thread-presence-\(a)-\(b)") {
            $0.presence.key = myUserId
        }
        channel = ch

        // The stream must be created before subscribing.
        let stream = ch.presenceChange()
        listenTask = Task { [weak self] in
            for await change in stream {
                if Task.isCancelled { break }
                await self?.apply(change)
            }
        }

        await supabase.realtimeV2.setAuth()
        await ch.subscribe()
        await track(.here)
    }

    /// Leave the room and clear all state. Safe to call repeatedly.
    func stop() {
        listenTask?.cancel()
        listenTask = nil
        typingResetTask?.cancel()
        typingResetTask = nil
        if let ch = channel {
            Task {
                await ch.untrack()
                await supabase.removeChannel(ch)
            }
        }
        channel = nil
        friendStatus = nil
        myStatus = .here
    }

    // MARK: My state

    /// Call on every keystroke. Tracks "typing" once, then quietly
    /// falls back to "here" a few seconds after the last edit.
    func noteTyping() {
        typingResetTask?.cancel()
        if myStatus != .typing {
            Task { await track(.typing) }
        }
        typingResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            await self?.track(.here)
        }
    }

    /// Call right after a message goes out — drops typing immediately.
    func noteSent() {
        typingResetTask?.cancel()
        typingResetTask = nil
        Task { await track(.here) }
    }

    /// Flag that the user is watching a proof full-screen (the sender
    /// sees "watching your proof…" live in the thread).
    func setWatching(_ watching: Bool) {
        Task { await track(watching ? .watching : .here) }
    }

    // MARK: Internals

    private func track(_ status: ThreadPresenceStatus) async {
        myStatus = status
        guard let channel else { return }
        try? await channel.track(
            ThreadPresencePayload(userId: myUserId, status: status.rawValue)
        )
    }

    private func apply(_ action: any PresenceAction) {
        // Process leaves first so a re-track (leave + join pair) lands
        // on the joined state.
        if let leaves = try? action.decodeLeaves(as: ThreadPresencePayload.self) {
            for leave in leaves where leave.userId == friendId {
                friendStatus = nil
            }
        }
        if let joins = try? action.decodeJoins(as: ThreadPresencePayload.self) {
            for join in joins where join.userId == friendId {
                friendStatus = ThreadPresenceStatus(rawValue: join.status) ?? .here
            }
        }
    }
}
