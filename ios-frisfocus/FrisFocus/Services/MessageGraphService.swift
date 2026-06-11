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

// MARK: - Failed-send payload

/// Everything needed to retry a send that failed. Kept in memory keyed
/// by the failed message's local id so the thread can offer an inline
/// "Tap to retry" instead of silently dropping the message.
enum FailedSendPayload {
    case note(recipientId: String, text: String)
    case proof(recipientId: String, data: Data, mediaKind: ProofMediaKind, duration: Double?, caption: String?)
}

// MARK: - Service

@Observable
@MainActor
final class MessageGraphService {
    /// The loaded message window (the recent slice plus any older pages
    /// pulled in by threads), oldest first.
    var messages: [DirectMessage] = []
    /// Ids of optimistic messages shown in-thread before the network
    /// confirms them. The UI renders these slightly muted ("sending…").
    var pendingMessageIds: Set<UUID> = []
    /// Ids of messages whose send failed. They stay in the thread with
    /// an inline "Not sent · Tap to retry" instead of vanishing.
    var failedMessageIds: Set<UUID> = []
    /// Retry payloads for failed sends, keyed by local message id.
    @ObservationIgnored private var failedPayloads: [UUID: FailedSendPayload] = [:]
    var isLoading = false
    var isWorking = false
    /// True while an older history page is being fetched for a thread.
    var isLoadingOlder = false
    /// Byte-level progress (0...1) of an in-flight proof upload, nil
    /// when nothing is uploading. Rendered on the optimistic pill.
    var uploadProgress: Double?
    var errorMessage: String?
    var showError = false

    /// Resolved profiles for every counterpart, keyed by id. Populated
    /// by `load`; read by `conversations` and `profile(for:)`.
    @ObservationIgnored private var profilesById: [String: RemoteProfile] = [:]

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?

    // MARK: Pagination state

    /// How many recent rows the initial load pulls. Conversations stay
    /// fast no matter how much history exists — older pages stream in
    /// per-thread on demand.
    private static let recentPageSize = 200
    /// Page size for "load earlier" fetches inside one thread.
    private static let olderPageSize = 60
    /// True when the initial window already contains the user's entire
    /// history — no thread has anything older to fetch.
    @ObservationIgnored private var allHistoryLoaded = false
    /// Threads whose full history is loaded (an older-page fetch came
    /// back short), so the UI can stop offering "load earlier".
    @ObservationIgnored private var exhaustedThreads: Set<String> = []

    /// Signed URLs already minted this session, keyed by storage path.
    /// Reused until shortly before expiry so players and prefetchers
    /// never re-sign (and the URL cache stays warm).
    @ObservationIgnored private var signedURLCache: [String: (url: URL, expires: Date)] = [:]

    /// The column list every row fetch shares.
    private static let rowColumns = "id, sender_id, recipient_id, kind, body, media_path, media_kind, media_duration, created_at, read_at, watched_at"

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
        if let d = plain.date(from: raw) { return d }
        // Realtime rows can arrive without a timezone suffix — treat as UTC.
        if !raw.hasSuffix("Z"), !raw.contains("+") {
            let zulu = raw + "Z"
            if let d = isoFormatter.date(from: zulu) { return d }
            return plain.date(from: zulu)
        }
        return nil
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

    /// Pull the *recent* window of messages (newest `recentPageSize`)
    /// and resolve each counterpart's profile in a single round-trip.
    /// Older history streams in per-thread via `loadOlderMessages`.
    func load(myUserId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [DirectMessageRow] = try await supabase
                .from("direct_messages")
                .select(Self.rowColumns)
                .or("sender_id.eq.\(myUserId),recipient_id.eq.\(myUserId)")
                .order("created_at", ascending: false)
                .limit(Self.recentPageSize)
                .execute()
                .value

            allHistoryLoaded = rows.count < Self.recentPageSize

            let counterpartIds = Set(rows.map { $0.senderId == myUserId ? $0.recipientId : $0.senderId })
            profilesById = try await fetchProfiles(ids: Array(counterpartIds))

            // Local-only rows (still sending, or failed and awaiting a
            // retry) must survive a reload — they don't exist server-side.
            let localOnly = messages.filter { failedMessageIds.contains($0.id) || pendingMessageIds.contains($0.id) }
            messages = (rows.reversed().compactMap(mapRow) + localOnly)
                .sorted { $0.createdAt < $1.createdAt }
            syncBadge(myUserId: myUserId)
            prefetchMedia(myUserId: myUserId)
        } catch {
            fail("Couldn't load your messages.", error)
        }
    }

    // MARK: Older history (per-thread pages)

    /// Whether this thread might still have earlier messages to pull.
    func canLoadOlder(withFriendId friendId: String) -> Bool {
        !allHistoryLoaded && !exhaustedThreads.contains(friendId)
    }

    /// Fetch the next older page for one thread and merge it in. Marks
    /// the thread exhausted when a short page comes back.
    func loadOlderMessages(withFriendId friendId: String, myUserId: String) async {
        guard !isLoadingOlder, canLoadOlder(withFriendId: friendId) else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        let oldest = thread(withFriendId: friendId, myUserId: myUserId).first?.createdAt ?? Date()
        do {
            let rows: [DirectMessageRow] = try await supabase
                .from("direct_messages")
                .select(Self.rowColumns)
                .or("and(sender_id.eq.\(myUserId),recipient_id.eq.\(friendId)),and(sender_id.eq.\(friendId),recipient_id.eq.\(myUserId))")
                .lt("created_at", value: Self.isoString(oldest))
                .order("created_at", ascending: false)
                .limit(Self.olderPageSize)
                .execute()
                .value

            if rows.count < Self.olderPageSize {
                exhaustedThreads.insert(friendId)
            }
            let existing = Set(messages.map(\.id))
            let fresh = rows.compactMap(mapRow).filter { !existing.contains($0.id) }
            guard !fresh.isEmpty else { return }
            messages.append(contentsOf: fresh)
            messages.sort { $0.createdAt < $1.createdAt }
        } catch {
            fail("Couldn't load earlier messages.", error)
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

    /// True when a message's send failed and a retry is available.
    func isFailed(_ id: UUID) -> Bool { failedMessageIds.contains(id) }

    /// Total unread across every conversation — drives the persistent
    /// badge on the Home navigation and the Circles paper-plane dot.
    func totalUnread(myUserId: String) -> Int {
        messages.filter { $0.recipientId == myUserId && $0.readAt == nil }.count
    }

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
            print("[MessageGraph] Note send failed: \(error)")
            markFailed(tempId: temp.id, payload: .note(recipientId: recipientId, text: trimmed))
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

        // Hard ceiling — clips are transcoded before they reach here, so
        // anything still over the cap is refused with a friendly message
        // rather than silently burning the user's data plan.
        guard data.count <= VideoTranscoder.maxUploadBytes else {
            isWorking = false
            fail("That clip is too large to send. Try a shorter one.", StorageUploadError.badResponse(status: 413))
            return
        }

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
            // Direct upload with real byte-level progress for the pill.
            uploadProgress = 0
            try await StorageUploadClient.upload(
                data: data,
                bucket: "proofs",
                path: path,
                contentType: contentType
            ) { [weak self] progress in
                Task { @MainActor in self?.uploadProgress = progress }
            }
            uploadProgress = nil

            // Seed the local media cache with the bytes we just sent so
            // "watch again" replays instantly and for free.
            ProofMediaCache.store(data, forMediaPath: path, kind: mediaKind)

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
            print("[MessageGraph] Proof send failed: \(error)")
            uploadProgress = nil
            markFailed(tempId: temp.id, payload: .proof(
                recipientId: recipientId,
                data: data,
                mediaKind: mediaKind,
                duration: durationSeconds,
                caption: trimmedCaption
            ))
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

    /// Flip an optimistic message into the failed state — it stays in
    /// the thread, rendered with an inline "Tap to retry".
    private func markFailed(tempId: UUID, payload: FailedSendPayload) {
        pendingMessageIds.remove(tempId)
        failedMessageIds.insert(tempId)
        failedPayloads[tempId] = payload
    }

    /// Re-attempt a failed send. The failed placeholder is removed and a
    /// fresh optimistic send takes its place.
    func retrySend(_ id: UUID, myUserId: String) async {
        guard let payload = failedPayloads[id] else { return }
        failedPayloads[id] = nil
        failedMessageIds.remove(id)
        messages.removeAll { $0.id == id }
        switch payload {
        case .note(let recipientId, let text):
            await sendNote(to: recipientId, text: text, myUserId: myUserId)
        case .proof(let recipientId, let data, let mediaKind, let duration, let caption):
            await sendProof(
                to: recipientId,
                data: data,
                mediaKind: mediaKind,
                durationSeconds: duration,
                caption: caption,
                myUserId: myUserId
            )
        }
    }

    /// Throw away a failed send the user no longer wants to retry.
    func discardFailed(_ id: UUID) {
        failedPayloads[id] = nil
        failedMessageIds.remove(id)
        messages.removeAll { $0.id == id }
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

        syncBadge(myUserId: myUserId)

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

    /// A signed URL for a proof's private media, or nil on failure.
    /// Cached by storage path and reused until shortly before expiry,
    /// so repeated opens never re-sign (and downstream URL-keyed caches
    /// stay warm).
    func signedURL(forMediaPath path: String, expiresIn seconds: Int = 3600) async -> URL? {
        if let hit = signedURLCache[path], hit.expires > Date().addingTimeInterval(120) {
            return hit.url
        }
        do {
            let url = try await supabase.storage
                .from("proofs")
                .createSignedURL(path: path, expiresIn: seconds)
            signedURLCache[path] = (url, Date().addingTimeInterval(TimeInterval(seconds)))
            return url
        } catch {
            print("[MessageGraph] Signed URL failed for \(path): \(error)")
            return nil
        }
    }

    // MARK: Prefetch

    /// Quietly warm the caches for what the user is most likely to tap
    /// next: every counterpart's avatar plus the latest incoming proof
    /// in each recent conversation. Best-effort and fully detached —
    /// failures are invisible.
    private func prefetchMedia(myUserId: String) {
        let avatarURLs = profilesById.values.compactMap(\.photoURL)
        let targets: [(path: String, kind: ProofMediaKind)] = conversations(myUserId: myUserId)
            .prefix(6)
            .compactMap { convo in
                let latestIncoming = thread(withFriendId: convo.friend.id, myUserId: myUserId)
                    .last { $0.isProof && !$0.isMine(myUserId) && $0.mediaPath != nil }
                guard let path = latestIncoming?.mediaPath, let kind = latestIncoming?.mediaKind else { return nil }
                return (path, kind)
            }

        Task { [weak self] in
            for url in avatarURLs {
                await ImageCache.prefetch(url)
            }
            for target in targets {
                guard let self else { return }
                if ProofMediaCache.cachedFileURL(forMediaPath: target.path, kind: target.kind) != nil { continue }
                guard let url = await self.signedURL(forMediaPath: target.path) else { continue }
                await ProofMediaCache.download(from: url, forMediaPath: target.path, kind: target.kind)
            }
        }
    }

    // MARK: Badge

    /// Keep the app icon badge equal to the real unread count as
    /// messages arrive and threads are read.
    private func syncBadge(myUserId: String) {
        let unread = messages.filter { $0.recipientId == myUserId && $0.readAt == nil }.count
        NotificationManager.syncBadge(unread)
    }

    // MARK: Realtime

    /// Subscribe to live changes on `direct_messages`. Each event is
    /// applied *incrementally* — one insert appends one message, one
    /// update touches one row — instead of refetching the whole history,
    /// so live delivery stays O(1) no matter how big the thread gets.
    /// Idempotent — a second call is a no-op.
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
            for await change in changes {
                if Task.isCancelled { break }
                await self?.apply(change, myUserId: myUserId)
            }
        }
    }

    /// Fold one realtime event into local state. A decode failure falls
    /// back to a full reload — correctness over cleverness.
    private func apply(_ change: AnyAction, myUserId: String) async {
        switch change {
        case .insert(let action):
            guard let row = try? action.decodeRecord(as: DirectMessageRow.self, decoder: JSONDecoder()) else {
                await load(myUserId: myUserId)
                return
            }
            // A brand-new conversation may involve a profile we've never
            // resolved — fetch it before the row renders nameless.
            let counterpart = row.senderId == myUserId ? row.recipientId : row.senderId
            if profilesById[counterpart] == nil, counterpart != myUserId {
                if let fetched = try? await fetchProfiles(ids: [counterpart]) {
                    profilesById.merge(fetched) { current, _ in current }
                }
            }
            appendIfNew(row)
            syncBadge(myUserId: myUserId)
            // Warm the cache for an incoming proof so the tap that
            // follows the banner opens instantly.
            if row.senderId != myUserId,
               let path = row.mediaPath,
               let kind = row.mediaKind.flatMap({ ProofMediaKind(rawValue: $0) }) {
                Task { [weak self] in
                    guard let self,
                          ProofMediaCache.cachedFileURL(forMediaPath: path, kind: kind) == nil,
                          let url = await self.signedURL(forMediaPath: path) else { return }
                    await ProofMediaCache.download(from: url, forMediaPath: path, kind: kind)
                }
            }
        case .update(let action):
            guard let row = try? action.decodeRecord(as: DirectMessageRow.self, decoder: JSONDecoder()) else {
                await load(myUserId: myUserId)
                return
            }
            if let idx = messages.firstIndex(where: { $0.id == row.id }) {
                messages[idx].readAt = Self.parseDate(row.readAt)
                messages[idx].watchedAt = Self.parseDate(row.watchedAt)
            } else {
                appendIfNew(row)
            }
            syncBadge(myUserId: myUserId)
        case .delete(let action):
            if let raw = action.oldRecord["id"]?.stringValue, let id = UUID(uuidString: raw) {
                messages.removeAll { $0.id == id }
            }
        default:
            break
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
            .select("id, email, name, username, avatar_url, header_url")
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
