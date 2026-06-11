//
//  MessageGraphService.swift
//  FrisFocus
//
//  Real, private 1:1 messaging backed by Supabase — the foundation the
//  Proofs inbox and 1:1 threads build on. Every conversation is between
//  two real signed-in accounts, keyed to `profiles.id` (the Rork Auth
//  id), the same identity the friend graph and circles use.
//
//  Like `FriendGraphService` and `CircleGraphService`, this is pure
//  backend state: it never touches the local seeded `Store`. RLS does
//  the real enforcement — a row is readable only by its sender and
//  recipient — and `myUserId` is passed in by views purely to shape and
//  label results.
//
//  Two message shapes share one table:
//   • note  — a quiet text message (`body`).
//   • proof — a photo/video captured of a real moment, uploaded to the
//             private `proofs` bucket; `body` is its optional caption.
//
//  Proof media lives in a private Storage bucket under a per-pair folder
//  (`{idA}/{idB}/…`), so a signed URL is needed to load it and only the
//  two participants can ever fetch one. Live delivery comes from a
//  Realtime subscription on `direct_messages`.
//

import Foundation
import Supabase

// MARK: - Message shape

nonisolated enum DirectMessageKind: String, Codable, Sendable {
    case note
    case proof
}

nonisolated enum ProofMediaKind: String, Codable, Sendable {
    case photo
    case video
}

// MARK: - Wire rows (decoded straight from Supabase)
//
// Timestamps are decoded as `String` and parsed lazily so we never
// depend on the SDK's date-decoding strategy. Ordering is done in SQL.

private nonisolated struct DirectMessageRow: Codable, Sendable {
    let id: UUID
    let senderId: String
    let recipientId: String
    let kind: String
    let body: String?
    let mediaPath: String?
    let mediaKind: String?
    let mediaDuration: Double?
    let createdAt: String
    let readAt: String?
    let watchedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case mediaDuration = "media_duration"
        case createdAt = "created_at"
        case readAt = "read_at"
        case watchedAt = "watched_at"
    }
}

// MARK: - Insert / update payloads

private nonisolated struct DirectMessageInsert: Encodable, Sendable {
    let senderId: String
    let recipientId: String
    let kind: String
    let body: String?
    let mediaPath: String?
    let mediaKind: String?
    let mediaDuration: Double?

    enum CodingKeys: String, CodingKey {
        case kind, body
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case mediaPath = "media_path"
        case mediaKind = "media_kind"
        case mediaDuration = "media_duration"
    }
}

private nonisolated struct ReadStamp: Encodable, Sendable {
    let readAt: String
    enum CodingKeys: String, CodingKey { case readAt = "read_at" }
}

private nonisolated struct WatchStamp: Encodable, Sendable {
    let watchedAt: String
    enum CodingKeys: String, CodingKey { case watchedAt = "watched_at" }
}

// MARK: - Assembled view models

/// One private message, ready to render. `readAt` / `watchedAt` are
/// `var` so the UI can apply an optimistic edit (mark read on open,
/// mark watched after the player) before a refresh confirms it.
struct DirectMessage: Identifiable, Hashable {
    let id: UUID
    let senderId: String
    let recipientId: String
    let kind: DirectMessageKind
    let body: String?
    let mediaPath: String?
    let mediaKind: ProofMediaKind?
    let mediaDuration: Double?
    let createdAt: Date
    var readAt: Date?
    var watchedAt: Date?

    /// A proof carries media; a note is text-only — same row, different
    /// presentation.
    var isProof: Bool { kind == .proof }

    func isMine(_ myUserId: String) -> Bool { senderId == myUserId }

    /// The *other* person in this message, from `myUserId`'s view.
    func counterpartId(_ myUserId: String) -> String {
        senderId == myUserId ? recipientId : senderId
    }

    /// True once the recipient has watched this proof in the full-screen
    /// player — drives the chat pill's "Tap to view" → "Reply" flip.
    var isWatched: Bool { watchedAt != nil }
}

/// One row in the Proofs inbox — a person you've privately traded with,
/// plus the latest exchange (for the preview line + timestamp) and how
/// many of their sends are still unread. Derived on demand.
struct DirectConversationSummary: Identifiable {
    let friend: RemoteProfile
    let latest: DirectMessage
    let unreadCount: Int
    var id: String { friend.id }
}

// MARK: - Service

@Observable
@MainActor
final class MessageGraphService {
    /// Every message the signed-in user is part of, oldest first.
    var messages: [DirectMessage] = []
    /// Ids of optimistic messages shown in-thread before the network
    /// confirms them. The UI renders these slightly muted ("sending…").
    var pendingMessageIds: Set<UUID> = []
    var isLoading = false
    var isWorking = false
    var errorMessage: String?
    var showError = false

    /// Resolved profiles for every counterpart, keyed by id. Populated
    /// by `load`; read by `conversations` and `profile(for:)`.
    @ObservationIgnored private var profilesById: [String: RemoteProfile] = [:]

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?

    // MARK: Date helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func isoString(_ date: Date) -> String { isoFormatter.string(from: date) }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let d = isoFormatter.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private func mapRow(_ r: DirectMessageRow) -> DirectMessage? {
        guard let created = Self.parseDate(r.createdAt) else { return nil }
        return DirectMessage(
            id: r.id,
            senderId: r.senderId,
            recipientId: r.recipientId,
            kind: DirectMessageKind(rawValue: r.kind) ?? .note,
            body: r.body,
            mediaPath: r.mediaPath,
            mediaKind: r.mediaKind.flatMap { ProofMediaKind(rawValue: $0) },
            mediaDuration: r.mediaDuration,
            createdAt: created,
            readAt: Self.parseDate(r.readAt),
            watchedAt: Self.parseDate(r.watchedAt)
        )
    }

    // MARK: Load

    /// Pull every message the user is part of (sent or received) and
    /// resolve each counterpart's profile in a single round-trip.
    func load(myUserId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [DirectMessageRow] = try await supabase
                .from("direct_messages")
                .select("id, sender_id, recipient_id, kind, body, media_path, media_kind, media_duration, created_at, read_at, watched_at")
                .or("sender_id.eq.\(myUserId),recipient_id.eq.\(myUserId)")
                .order("created_at", ascending: true)
                .execute()
                .value

            let counterpartIds = Set(rows.map { $0.senderId == myUserId ? $0.recipientId : $0.senderId })
            profilesById = try await fetchProfiles(ids: Array(counterpartIds))

            messages = rows.compactMap(mapRow)
        } catch {
            fail("Couldn't load your messages.", error)
        }
    }

    // MARK: Derived views

    /// The Proofs inbox, regrouped by person: one entry per friend the
    /// user has traded with, newest conversation first.
    func conversations(myUserId: String) -> [DirectConversationSummary] {
        var latestByPerson: [String: DirectMessage] = [:]
        for message in messages {
            let other = message.counterpartId(myUserId)
            if let existing = latestByPerson[other], existing.createdAt >= message.createdAt { continue }
            latestByPerson[other] = message
        }
        return latestByPerson.compactMap { other, latest -> DirectConversationSummary? in
            guard let friend = profilesById[other] else { return nil }
            return DirectConversationSummary(
                friend: friend,
                latest: latest,
                unreadCount: unreadCount(fromFriendId: other, myUserId: myUserId)
            )
        }
        .sorted { $0.latest.createdAt > $1.latest.createdAt }
    }

    /// Every message in the 1:1 thread with `friendId`, oldest first.
    func thread(withFriendId friendId: String, myUserId: String) -> [DirectMessage] {
        messages
            .filter {
                ($0.senderId == myUserId && $0.recipientId == friendId) ||
                ($0.senderId == friendId && $0.recipientId == myUserId)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// How many messages this friend sent the user that are still unread.
    func unreadCount(fromFriendId friendId: String, myUserId: String) -> Int {
        messages.filter { $0.senderId == friendId && $0.recipientId == myUserId && $0.readAt == nil }.count
    }

    /// A resolved counterpart profile, for labeling threads / the viewer.
    func profile(for id: String) -> RemoteProfile? { profilesById[id] }

    /// True while a message is optimistic — shown but not yet confirmed.
    func isPending(_ id: UUID) -> Bool { pendingMessageIds.contains(id) }

    // MARK: Send

    /// Send a quiet text note to a friend. Optimistic: the note appears
    /// in the thread instantly and is swapped for the server row once
    /// the insert confirms (or removed with an error if it fails).
    func sendNote(to recipientId: String, text: String, myUserId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let temp = DirectMessage(
            id: UUID(),
            senderId: myUserId,
            recipientId: recipientId,
            kind: .note,
            body: trimmed,
            mediaPath: nil,
            mediaKind: nil,
            mediaDuration: nil,
            createdAt: Date(),
            readAt: nil,
            watchedAt: nil
        )
        appendOptimistic(temp)

        do {
            let created: DirectMessageRow = try await supabase
                .from("direct_messages")
                .insert(DirectMessageInsert(
                    senderId: myUserId,
                    recipientId: recipientId,
                    kind: DirectMessageKind.note.rawValue,
                    body: trimmed,
                    mediaPath: nil,
                    mediaKind: nil,
                    mediaDuration: nil
                ))
                .select("id, sender_id, recipient_id, kind, body, media_path, media_kind, media_duration, created_at, read_at, watched_at")
                .single()
                .execute()
                .value
            confirmOptimistic(tempId: temp.id, with: created)
            PushService.send(to: recipientId, kind: .note, preview: trimmed, messageId: created.id.uuidString)
        } catch {
            removeOptimistic(tempId: temp.id)
            fail("Couldn't send your message.", error)
        }
    }

    /// Capture a proof: upload the media privately, then write the row.
    /// The media lands under a stable per-pair folder so storage RLS lets
    /// only the two participants read it.
    func sendProof(
        to recipientId: String,
        data: Data,
        mediaKind: ProofMediaKind,
        durationSeconds: Double?,
        caption: String?,
        myUserId: String
    ) async {
        isWorking = true
        defer { isWorking = false }

        let path = Self.mediaPath(myUserId: myUserId, recipientId: recipientId, kind: mediaKind)
        let contentType = mediaKind == .video ? "video/mp4" : "image/jpeg"
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Optimistic pill: "You sent a proof" appears in the thread the
        // moment the capture is confirmed, while the upload runs.
        let temp = DirectMessage(
            id: UUID(),
            senderId: myUserId,
            recipientId: recipientId,
            kind: .proof,
            body: (trimmedCaption?.isEmpty == false) ? trimmedCaption : nil,
            mediaPath: nil,
            mediaKind: mediaKind,
            mediaDuration: durationSeconds,
            createdAt: Date(),
            readAt: nil,
            watchedAt: nil
        )
        appendOptimistic(temp)

        do {
            _ = try await supabase.storage
                .from("proofs")
                .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: contentType, upsert: false))

            let created: DirectMessageRow = try await supabase
                .from("direct_messages")
                .insert(DirectMessageInsert(
                    senderId: myUserId,
                    recipientId: recipientId,
                    kind: DirectMessageKind.proof.rawValue,
                    body: (trimmedCaption?.isEmpty == false) ? trimmedCaption : nil,
                    mediaPath: path,
                    mediaKind: mediaKind.rawValue,
                    mediaDuration: durationSeconds
                ))
                .select("id, sender_id, recipient_id, kind, body, media_path, media_kind, media_duration, created_at, read_at, watched_at")
                .single()
                .execute()
                .value
            confirmOptimistic(tempId: temp.id, with: created)
            PushService.send(to: recipientId, kind: .proof, preview: trimmedCaption, messageId: created.id.uuidString)
        } catch {
            removeOptimistic(tempId: temp.id)
            fail("Couldn't send your proof.", error)
        }
    }

    /// A stable, per-pair storage path: `{idA}/{idB}/{uuid}.{ext}` with
    /// the ids sorted so both participants resolve the same folder.
    private static func mediaPath(myUserId: String, recipientId: String, kind: ProofMediaKind) -> String {
        let a = min(myUserId, recipientId)
        let b = max(myUserId, recipientId)
        let ext = kind == .video ? "mp4" : "jpg"
        return "\(a)/\(b)/\(UUID().uuidString).\(ext)"
    }

    private func appendIfNew(_ row: DirectMessageRow) {
        guard let message = mapRow(row), !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        messages.sort { $0.createdAt < $1.createdAt }
    }

    // MARK: Optimistic plumbing

    private func appendOptimistic(_ message: DirectMessage) {
        pendingMessageIds.insert(message.id)
        messages.append(message)
        messages.sort { $0.createdAt < $1.createdAt }
    }

    /// Swap the optimistic placeholder for the confirmed server row.
    /// Order matters: remove the temp first so the list never shows a
    /// duplicate frame.
    private func confirmOptimistic(tempId: UUID, with row: DirectMessageRow) {
        pendingMessageIds.remove(tempId)
        messages.removeAll { $0.id == tempId }
        appendIfNew(row)
    }

    private func removeOptimistic(tempId: UUID) {
        pendingMessageIds.remove(tempId)
        messages.removeAll { $0.id == tempId }
    }

    // MARK: Read / watched

    /// Clear the unread dot for a thread: stamp every unread message from
    /// this friend as read. Optimistic, then writes through.
    func markThreadRead(withFriendId friendId: String, myUserId: String) async {
        let unread = messages.filter { $0.senderId == friendId && $0.recipientId == myUserId && $0.readAt == nil }
        guard !unread.isEmpty else { return }

        let now = Date()
        for id in unread.map(\.id) {
            if let idx = messages.firstIndex(where: { $0.id == id }) { messages[idx].readAt = now }
        }

        do {
            try await supabase
                .from("direct_messages")
                .update(ReadStamp(readAt: Self.isoString(now)))
                .in("id", values: unread.map { $0.id.uuidString })
                .execute()
        } catch {
            fail("Couldn't update your messages.", error)
            await load(myUserId: myUserId)
        }
    }

    /// Stamp a single incoming proof watched — flips its chat pill to the
    /// "Reply with a proof" state. Optimistic, then writes through.
    func markProofWatched(_ message: DirectMessage, myUserId: String) async {
        guard message.recipientId == myUserId, message.watchedAt == nil else { return }
        let now = Date()
        if let idx = messages.firstIndex(where: { $0.id == message.id }) { messages[idx].watchedAt = now }
        do {
            try await supabase
                .from("direct_messages")
                .update(WatchStamp(watchedAt: Self.isoString(now)))
                .eq("id", value: message.id.uuidString)
                .execute()
        } catch {
            fail("Couldn't update this proof.", error)
        }
    }

    // MARK: Media

    /// A short-lived signed URL for a proof's private media, or nil on
    /// failure. The bucket is private, so this is the only way to load it.
    func signedURL(forMediaPath path: String, expiresIn seconds: Int = 3600) async -> URL? {
        do {
            return try await supabase.storage
                .from("proofs")
                .createSignedURL(path: path, expiresIn: seconds)
        } catch {
            print("[MessageGraph] Signed URL failed for \(path): \(error)")
            return nil
        }
    }

    // MARK: Realtime

    /// Subscribe to live changes on `direct_messages`. Any insert/update/
    /// delete the signed-in user is allowed to see (RLS-scoped) triggers
    /// a refresh, so new messages and read/watched flips arrive without a
    /// manual reload. Idempotent — a second call is a no-op.
    func startRealtime(myUserId: String) {
        guard channel == nil else { return }
        let ch = supabase.channel("direct-messages-\(myUserId)")
        let changes = ch.postgresChange(AnyAction.self, schema: "public", table: "direct_messages")
        channel = ch
        realtimeTask = Task { [weak self] in
            // Authorize the realtime socket with the Rork Auth JWT so
            // RLS-scoped postgres changes are delivered to this user.
            await supabase.realtimeV2.setAuth()
            await ch.subscribe()
            for await _ in changes {
                if Task.isCancelled { break }
                await self?.load(myUserId: myUserId)
            }
        }
    }

    /// Tear down the realtime subscription. Call when the messaging
    /// surface goes away.
    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = channel {
            Task { await supabase.removeChannel(ch) }
        }
        channel = nil
    }

    // MARK: Helpers

    private func fetchProfiles(ids: [String]) async throws -> [String: RemoteProfile] {
        guard !ids.isEmpty else { return [:] }
        let rows: [RemoteProfile] = try await supabase
            .from("profiles")
            .select("id, email, name, username, avatar_url")
            .in("id", values: ids)
            .execute()
            .value
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func fail(_ message: String, _ error: Error) {
        print("[MessageGraph] \(message) \(error)")
        errorMessage = message
        showError = true
    }
}
