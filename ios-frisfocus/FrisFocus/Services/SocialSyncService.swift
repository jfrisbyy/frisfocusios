//
//  SocialSyncService.swift
//  FrisFocus
//
//  The bridge between the local `Store` (which every social surface
//  reads) and Supabase (where the real, shared social graph lives).
//
//  Down-sync: friends, stories (+likes/comments/views), cheers, pacts,
//  circles, and live grove presence are fetched and mirrored into the
//  Store's arrays — so every existing screen renders real, shared data
//  without changing how it reads state. Realtime subscriptions keep the
//  mirror fresh while the app is open.
//
//  Up-sync: the Store calls the `did…` hooks after each local mutation
//  (post, like, comment, cheer, pact, circle check-off, grove presence)
//  and this service writes the change through to Supabase.
//
//  Identity: remote user ids are Rork Auth strings; the Store keys
//  everything by UUID. `localId(forRemote:)` maps deterministically
//  (SHA-256) so the same remote person always resolves to the same
//  local UUID on every device — and the signed-in user maps onto the
//  Store's existing `currentUserId` so local history stays attached.
//

import CryptoKit
import Foundation
import Supabase

// MARK: - Deterministic id mapping

nonisolated enum RemoteIDMapper {
    /// Stable UUID for a remote (text) user id. SHA-256 based so every
    /// install derives the same UUID for the same person.
    static func localUUID(forRemoteId remote: String) -> UUID {
        let digest = SHA256.hash(data: Data("frisfocus-id:\(remote)".utf8))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// A warm, stable accent color hex for a remote id.
    static func accentHex(forRemoteId remote: String) -> String {
        let palette = ["C97B4B", "7B9E6B", "5B8AA6", "B5838D", "8E7CC3", "C9A227", "6B8F71", "A6674B"]
        let digest = SHA256.hash(data: Data(remote.utf8))
        let first: UInt8 = Array(digest).first ?? 0
        return palette[Int(first) % palette.count]
    }
}

// MARK: - Shared date helpers

nonisolated enum SyncDates {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parses a server timestamp. Missing or unreadable stamps fall back
    /// to `.distantPast` — NEVER "now". Stamping unparseable rows with the
    /// current time made them look freshly-arrived on every refresh, which
    /// kept resurrecting the "N new for you" badge for old activity.
    static func parse(_ s: String?) -> Date {
        guard let s else { return .distantPast }
        if let d = isoFractional.date(from: s) { return d }
        if let d = isoPlain.date(from: s) { return d }
        // Timestamps without timezone (e.g. "2026-06-11T01:02:03.456")
        if let d = isoFractional.date(from: s + "Z") { return d }
        if let d = isoPlain.date(from: s + "Z") { return d }
        if let d = day.date(from: s) { return d }
        return .distantPast
    }

    static func iso(_ d: Date) -> String { isoFractional.string(from: d) }

    static func dayKey(_ d: Date) -> String { day.string(from: d) }

    static func parseDay(_ s: String?) -> Date {
        guard let s else { return Calendar.current.startOfDay(for: Date()) }
        return day.date(from: String(s.prefix(10))) ?? Calendar.current.startOfDay(for: Date())
    }
}

/// Upsert row for my per-friend share tier.
private nonisolated struct ShareTierUpsert: Encodable, Sendable {
    let ownerId: String
    let friendId: String
    let tier: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case friendId = "friend_id"
        case tier
        case updatedAt = "updated_at"
    }
}

/// One of MY outgoing tiers, read back so the dial shows what the server
/// actually serves rather than a local default.
private nonisolated struct MyShareTierRow: Decodable, Sendable {
    let friendId: String
    let tier: String?
    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case tier
    }
}

// MARK: - Service

@Observable
@MainActor
final class SocialSyncService {
    private(set) var myUserId: String?
    private(set) var isSyncing = false

    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private(set) var remoteByLocal: [UUID: String] = [:]
    @ObservationIgnored private(set) var profilesByRemote: [String: RemoteProfile] = [:]
    /// What each friend shares with me ("quiet" / "open" / "full"), by
    /// remote id — resolved server-side by the season-card RPC, never
    /// assumed.
    @ObservationIgnored private(set) var tiersByRemote: [String: String] = [:]
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var refreshDebounces: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var activeMediaDownloads: Set<UUID> = []
    /// Story posts whose upload to the server failed — drives the
    /// "didn't send" retry affordance on the Your-story bubble.
    var failedStoryUploadIds: Set<UUID> = []
    /// Locally-created posts not yet confirmed by the server (in flight
    /// or failed). Protected from the optimistic prune and retried on
    /// launch — persisted per account so an app kill never silently
    /// drops a story.
    @ObservationIgnored var pendingStoryUploadIds: Set<UUID> = []
    /// Circles whose full archive has been pulled this session, so
    /// re-opening "Our story" doesn't re-fetch history that can't have
    /// changed. Cleared on sign-out with everything else.
    @ObservationIgnored var archivedCircleIds: Set<UUID> = []
    /// True while an archive page is in flight — "Our story" shows a
    /// quiet loading state rather than an honest-looking but truncated
    /// count.
    var isLoadingArchive = false

    // MARK: Lifecycle

    /// Begin syncing for the signed-in user. Idempotent per user id.
    func start(myUserId: String, store: Store) async {
        if self.myUserId == myUserId, self.store === store { return }
        stop()
        self.myUserId = myUserId
        self.store = store
        store.social = self
        registerMapping(remote: myUserId, local: store.currentUserId)
        loadStoryUploadState(for: myUserId)

        isSyncing = true
        await migratePendingLocalStories()
        await refreshAll()
        isSyncing = false
        // Re-attempt any story upload a previous session left unconfirmed
        // (killed mid-flight or failed) — nothing evaporates silently.
        await retryPendingStoryUploads()
        startRealtime()
    }

    /// Tear down on sign-out. The mirrored social data is cleared so a
    /// different account never sees the previous user's graph.
    func stop() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = channel {
            Task { await supabase.removeChannel(ch) }
        }
        channel = nil
        for (_, task) in refreshDebounces { task.cancel() }
        refreshDebounces = [:]
        guard myUserId != nil else { return }
        myUserId = nil
        failedStoryUploadIds = []
        pendingStoryUploadIds = []
        archivedCircleIds = []
        isLoadingArchive = false
        if let store {
            store.friends = []
            store.storyPosts = []
            store.likes = []
            store.comments = []
            store.cheers = []
            store.pacts = []
            store.pactCompletions = []
            store.circles = []
            store.circleTaskCompletions = []
            store.circleContributions = []
            store.circleEvents = []
            store.eventRSVPs = []
            store.eventCheckIns = []
            store.storyViewerIds = [:]
            store.focusPresences = []
            store.persistAll()
        }
    }

    // MARK: Id mapping

    func localId(forRemote remote: String) -> UUID {
        if remote == myUserId, let store { return store.currentUserId }
        let local = RemoteIDMapper.localUUID(forRemoteId: remote)
        remoteByLocal[local] = remote
        return local
    }

    func remoteId(forLocal local: UUID) -> String? {
        if let store, local == store.currentUserId { return myUserId }
        return remoteByLocal[local]
    }

    func registerMapping(remote: String, local: UUID) {
        remoteByLocal[local] = remote
    }

    func profile(forLocal local: UUID) -> RemoteProfile? {
        guard let remote = remoteId(forLocal: local) else { return nil }
        return profilesByRemote[remote]
    }

    // MARK: Full refresh

    func refreshAll() async {
        await refreshFriends()
        async let a: Void = refreshStories()
        async let b: Void = refreshCheers()
        async let c: Void = refreshPacts()
        async let d: Void = refreshCircles()
        async let e: Void = refreshGrove()
        async let f: Void = refreshEvents()
        _ = await (a, b, c, d, e, f)
    }

    /// Batch-resolve profiles into the cache, registering id mappings.
    func ensureProfiles(remoteIds: [String]) async {
        let missing = Set(remoteIds).filter { profilesByRemote[$0] == nil }
        guard !missing.isEmpty else {
            for id in remoteIds { _ = localId(forRemote: id) }
            return
        }
        do {
            let rows: [RemoteProfile] = try await supabase
                .from("profiles")
                .select("id, name, username, avatar_url, header_url")
                .in("id", values: Array(missing))
                .execute()
                .value
            for row in rows {
                // Keep any RPC-delivered season card already cached — the
                // profiles table no longer carries cards.
                var merged = row
                merged.seasonCard = profilesByRemote[row.id]?.seasonCard
                profilesByRemote[row.id] = merged
                _ = localId(forRemote: row.id)
            }
        } catch {
            print("[SocialSync] profile fetch failed: \(error)")
        }
        for id in remoteIds { _ = localId(forRemote: id) }
    }

    /// Re-fetch these profiles unconditionally (overwriting the cache)
    /// so live-updating fields — the season card, avatar, header —
    /// stay fresh across a session. Used by the friends refresh.
    func refreshProfiles(remoteIds: [String]) async {
        let ids = Array(Set(remoteIds))
        guard !ids.isEmpty else { return }
        do {
            let rows: [RemoteProfile] = try await supabase
                .from("profiles")
                .select("id, name, username, avatar_url, header_url")
                .in("id", values: ids)
                .execute()
                .value
            for row in rows {
                var merged = row
                merged.seasonCard = profilesByRemote[row.id]?.seasonCard
                profilesByRemote[row.id] = merged
                _ = localId(forRemote: row.id)
            }
        } catch {
            print("[SocialSync] profile refresh failed: \(error)")
        }
        for id in remoteIds { _ = localId(forRemote: id) }
    }

    // MARK: Season cards (friend-gated via RPC)

    private nonisolated struct SeasonCardRPCRow: Codable, Sendable {
        let userId: String
        let card: String?
        let tier: String?
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case card, tier
        }
    }

    /// Fetch friend-gated season cards + share tiers through the
    /// `get_season_cards` RPC — the server enforces friendship, blocks,
    /// and quiet-tier trimming, so a non-friend can never read a card
    /// no matter what the client asks for.
    func refreshSeasonCards(remoteIds: [String]) async {
        let ids = Array(Set(remoteIds))
        guard !ids.isEmpty else { return }
        do {
            let rows: [SeasonCardRPCRow] = try await supabase
                .rpc("get_season_cards", params: ["target_ids": ids])
                .execute()
                .value
            for row in rows {
                // A row with no tier lands on Open: for a privacy dial
                // the safe fallback is the middle rung, never the widest.
                tiersByRemote[row.userId] = row.tier ?? VisibilityTier.open.rawValue
                if var profile = profilesByRemote[row.userId] {
                    profile.seasonCard = row.card
                    profilesByRemote[row.userId] = profile
                }
            }
        } catch {
            print("[SocialSync] season card fetch failed: \(error)")
        }
    }

    /// Read back the tiers I have set for other people. `setShareTier`
    /// pushes these but nothing used to read them, so a reinstall left the
    /// sharing dial showing a local default while the server kept serving
    /// the tier the person actually chose — the UI claiming "Open" while a
    /// friend still received the full day. A miss is not an error: it just
    /// means this person has never been dialled.
    private func fetchMyOutgoingTiers(myUserId: String) async -> [String: String] {
        do {
            let rows: [MyShareTierRow] = try await supabase
                .from("share_tiers")
                .select("friend_id, tier")
                .eq("owner_id", value: myUserId)
                .execute()
                .value
            return rows.reduce(into: [:]) { acc, row in
                if let tier = row.tier { acc[row.friendId] = tier }
            }
        } catch {
            print("[SocialSync] outgoing tier read failed: \(error)")
            return [:]
        }
    }

    /// Push my per-friend tier server-side, so THEIR device receives the
    /// correspondingly trimmed season card — every rung of the dial
    /// becomes a data promise, not just a rendering choice.
    func setShareTier(forRemote remoteId: String, tier: VisibilityTier) async {
        guard let myUserId else { return }
        do {
            try await supabase
                .from("share_tiers")
                .upsert(ShareTierUpsert(
                    ownerId: myUserId,
                    friendId: remoteId,
                    tier: tier.rawValue,
                    updatedAt: SyncDates.iso(Date())
                ), onConflict: "owner_id,friend_id")
                .execute()
        } catch {
            print("[SocialSync] share tier push failed: \(error)")
        }
    }

    /// Display name for a remote id ("You" for the signed-in user).
    func displayName(forRemote remote: String) -> String {
        if remote == myUserId { return "You" }
        return profilesByRemote[remote]?.displayName ?? "Friend"
    }

    func initials(forRemote remote: String) -> String {
        if remote == myUserId { return "Y" }
        return profilesByRemote[remote]?.initials ?? "?"
    }

    // MARK: Friends

    private nonisolated struct FriendshipRowS: Codable, Sendable {
        let userA: String
        let userB: String
        let createdAt: String?
        enum CodingKeys: String, CodingKey {
            case userA = "user_a"
            case userB = "user_b"
            case createdAt = "created_at"
        }
    }

    func refreshFriends() async {
        guard let myUserId, let store else { return }
        do {
            let rows: [FriendshipRowS] = try await supabase
                .from("friendships")
                .select("user_a, user_b, created_at")
                .or("user_a.eq.\(myUserId),user_b.eq.\(myUserId)")
                .execute()
                .value

            let counterparts = rows.map { row -> (id: String, since: Date) in
                let other = row.userA == myUserId ? row.userB : row.userA
                return (other, SyncDates.parse(row.createdAt))
            }
            await refreshProfiles(remoteIds: counterparts.map { $0.id })
            await refreshSeasonCards(remoteIds: counterparts.map { $0.id })
            let myOutgoingTiers = await fetchMyOutgoingTiers(myUserId: myUserId)

            let existingById = Dictionary(store.friends.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var mapped: [Friend] = []
            for (remote, since) in counterparts {
                guard let profile = profilesByRemote[remote] else { continue }
                let lid = localId(forRemote: remote)
                // Anything unrecognised (or absent) resolves to Open
                // rather than Full — degrading a privacy control has to
                // fall toward less exposure, never more.
                let tier = VisibilityTier(rawValue: tiersByRemote[remote] ?? "") ?? .open
                var friend = existingById[lid] ?? Friend(
                    id: lid,
                    displayName: profile.displayName,
                    initials: profile.initials,
                    accentColorHex: RemoteIDMapper.accentHex(forRemoteId: remote),
                    sharesWithMe: SharingSettings.from(tier: tier)
                )
                friend.displayName = profile.displayName
                friend.initials = profile.initials
                friend.avatarURL = profile.photoURL
                friend.headerURL = profile.headerURL
                // Their published season card drives the poster profile:
                // chosen accent, season name + day, intention, chapters.
                let card = profile.card
                friend.seasonCard = card
                friend.currentSeasonName = card?.seasonName ?? friend.currentSeasonName
                friend.currentSeasonDay = card?.currentDay ?? friend.currentSeasonDay
                friend.accentColorHex = card?.accentHex ?? RemoteIDMapper.accentHex(forRemoteId: remote)
                if friend.connectedAt == nil { friend.connectedAt = since }
                // The server-resolved tier — what THEY chose to share
                // with me. Quiet friends arrive with a trimmed card too.
                friend.sharesWithMe = SharingSettings.from(tier: tier)
                // And the other direction: what I share with THEM lives
                // in share_tiers, so the dial survives a reinstall. Only
                // a row that actually exists overwrites the local value —
                // a friend never dialled is left at the local default
                // rather than being silently rewritten.
                if let raw = myOutgoingTiers[remote],
                   let mine = VisibilityTier(rawValue: raw) {
                    friend.theirClearanceToMyData = SharingSettings.from(
                        tier: mine,
                        showOpenItemsAtFull: friend.theirClearanceToMyData.showOpenItemsAtFull
                    )
                }
                mapped.append(friend)
            }
            mapped.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            store.friends = mapped
            store.persistAll()
        } catch {
            print("[SocialSync] friends refresh failed: \(error)")
        }
    }

    // MARK: Realtime

    private func startRealtime() {
        guard channel == nil, let myUserId else { return }
        let ch = supabase.channel("social-sync-\(myUserId)")

        let tableDomains: [(table: String, domain: String)] = [
            ("friendships", "friends"),
            ("story_posts", "stories"),
            ("story_likes", "stories"),
            ("story_comments", "stories"),
            ("story_views", "stories"),
            ("cheers", "cheers"),
            ("pacts", "pacts"),
            ("pact_tasks", "pacts"),
            ("pact_completions", "pacts"),
            ("circles", "circles"),
            ("circle_members", "circles"),
            ("circle_tasks", "circles"),
            ("circle_task_completions", "circles"),
            ("circle_contributions", "circles"),
            ("circle_events", "events"),
            ("circle_event_rsvps", "events"),
            ("circle_event_checkins", "events"),
            ("focus_blocks", "grove"),
            ("focus_participants", "grove")
        ]
        let streams = tableDomains.map { pair in
            (pair.domain, ch.postgresChange(AnyAction.self, schema: "public", table: pair.table))
        }
        channel = ch
        realtimeTask = Task { [weak self] in
            await supabase.realtimeV2.setAuth()
            await ch.subscribe()
            await withTaskGroup(of: Void.self) { group in
                for (domain, stream) in streams {
                    group.addTask { [weak self] in
                        for await _ in stream {
                            if Task.isCancelled { break }
                            await self?.scheduleRefresh(domain)
                        }
                    }
                }
            }
        }
    }

    /// Debounced per-domain refetch so a burst of realtime events
    /// collapses into one round-trip.
    func scheduleRefresh(_ domain: String) {
        refreshDebounces[domain]?.cancel()
        refreshDebounces[domain] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            switch domain {
            case "friends":
                await self?.refreshFriends()
                await self?.refreshStories()
            case "stories": await self?.refreshStories()
            case "cheers": await self?.refreshCheers()
            case "pacts": await self?.refreshPacts()
            case "circles": await self?.refreshCircles()
            case "events": await self?.refreshEvents()
            case "grove": await self?.refreshGrove()
            default: break
            }
        }
    }

}
