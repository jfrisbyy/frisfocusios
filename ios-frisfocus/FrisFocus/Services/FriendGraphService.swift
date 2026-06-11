//
//  FriendGraphService.swift
//  FrisFocus
//
//  The real, multiplayer friend graph backed by Supabase. This is the
//  foundation the shared surfaces (circles, pacts, stories) build on:
//  every connection here is a real signed-in account, identified by its
//  Rork Auth id — the same id stored in `profiles`.
//
//  Pure backend state: it never touches the local seeded `Store`. Views
//  read `auth.user?.id` and hand it in, so the service stays free of any
//  assumptions about who is signed in. RLS does the real enforcement;
//  the `myUserId` argument is only used to shape and label the results.
//

import Foundation
import Supabase

// MARK: - Wire types (decoded straight from Supabase rows)

/// A public profile row. Only the columns we render are decoded; any
/// extra columns present in the JSON (timestamps, etc.) are ignored.
nonisolated struct RemoteProfile: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let email: String?
    let name: String?
    let username: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, email, name, username
        case avatarUrl = "avatar_url"
    }

    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let handle { return handle }
        if let email, !email.isEmpty { return email }
        return "Someone"
    }

    /// The user's claimed handle formatted as "@name", or nil when unset.
    var handle: String? {
        guard let username = username?.trimmingCharacters(in: .whitespaces), !username.isEmpty else { return nil }
        return "@\(username)"
    }

    var initials: String {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
            if !letters.isEmpty { return String(letters).uppercased() }
        }
        if let first = email?.first { return String(first).uppercased() }
        return "?"
    }

    var photoURL: URL? {
        guard let avatarUrl, let url = URL(string: avatarUrl) else { return nil }
        return url
    }
}

private nonisolated struct FriendRequestRow: Codable, Sendable {
    let id: UUID
    let requesterId: String
    let addresseeId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
    }
}

private nonisolated struct FriendshipRow: Codable, Sendable {
    let id: UUID
    let userA: String
    let userB: String

    enum CodingKeys: String, CodingKey {
        case id
        case userA = "user_a"
        case userB = "user_b"
    }
}

private nonisolated struct FriendRequestInsert: Encodable, Sendable {
    let requesterId: String
    let addresseeId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case status
    }
}

private nonisolated struct FriendshipInsert: Encodable, Sendable {
    let userA: String
    let userB: String

    enum CodingKeys: String, CodingKey {
        case userA = "user_a"
        case userB = "user_b"
    }
}

private nonisolated struct StatusUpdate: Encodable, Sendable {
    let status: String
}

// MARK: - View model

/// A pending friend request paired with the *other* person's profile.
nonisolated struct PendingFriendRequest: Identifiable, Sendable {
    let id: UUID            // friend_requests.id
    let profile: RemoteProfile
}

/// How the signed-in user relates to another profile — drives the
/// trailing control on search results and the invite-link preview.
nonisolated enum FriendRelationship: Sendable {
    case isMe, friends, requestSent, requestReceived, none
}

/// A live friend-graph moment worth surfacing in-app: a request just
/// arrived, or someone accepted yours. Identifiable so the banner
/// overlay can animate per-event.
struct FriendBannerEvent: Identifiable, Equatable {
    enum Kind { case requestReceived, requestAccepted }
    let id = UUID()
    let kind: Kind
    let profile: RemoteProfile

    var message: String {
        switch kind {
        case .requestReceived: return "\(profile.displayName) sent you a friend request"
        case .requestAccepted: return "You and \(profile.displayName) are now friends"
        }
    }
}

// MARK: - Service

@Observable
@MainActor
final class FriendGraphService {
    var friends: [RemoteProfile] = []
    var incoming: [PendingFriendRequest] = []
    var outgoing: [PendingFriendRequest] = []

    var isLoading = false
    var errorMessage: String?
    var showError = false

    var searchResults: [RemoteProfile] = []
    var isSearching = false

    /// The most recent live event (request arrived / accepted), surfaced
    /// as an in-app banner by the home shell. Cleared by the banner.
    var banner: FriendBannerEvent?

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?

    // MARK: Change detection (banners + unseen dot)

    /// Snapshots from the previous load — nil until the first load lands
    /// so a cold start never fires a banner for old state.
    @ObservationIgnored private var knownIncomingIds: Set<UUID>?
    @ObservationIgnored private var knownFriendIds: Set<String>?
    /// People we had a pending outgoing request to — a new friendship
    /// with one of them means they accepted.
    @ObservationIgnored private var knownOutgoingTargets: Set<String> = []

    private static let seenRequestsKey = "friendgraph.seenRequestIds"

    /// Incoming request ids the user has already laid eyes on (the
    /// Friends page marks them). Persisted so the dot survives relaunch.
    @ObservationIgnored private var seenRequestIds: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: FriendGraphService.seenRequestsKey) ?? []
    )

    /// True while a request is waiting that the user hasn't seen yet —
    /// drives the red dot on the home avatar and the quick-card tile.
    var hasUnseenRequests: Bool {
        incoming.contains { !seenRequestIds.contains($0.id.uuidString) }
    }

    /// The Friends page calls this once its request list is on screen —
    /// clears the dot everywhere.
    func markRequestsSeen() {
        guard hasUnseenRequests else { return }
        for request in incoming { seenRequestIds.insert(request.id.uuidString) }
        // Trim the persisted set to ids that still matter.
        let live = Set(incoming.map { $0.id.uuidString })
        seenRequestIds = seenRequestIds.intersection(live).union(live)
        UserDefaults.standard.set(Array(seenRequestIds), forKey: Self.seenRequestsKey)
        // Touch an observed property so dots refresh immediately.
        incoming = incoming
    }

    /// Pull the whole graph for the signed-in user: accepted friends plus
    /// pending requests in both directions, with each counterpart's profile
    /// resolved in a single round-trip.
    func load(myUserId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let friendshipRows: [FriendshipRow] = try await supabase
                .from("friendships")
                .select("id, user_a, user_b")
                .or("user_a.eq.\(myUserId),user_b.eq.\(myUserId)")
                .execute()
                .value

            let requestRows: [FriendRequestRow] = try await supabase
                .from("friend_requests")
                .select("id, requester_id, addressee_id, status")
                .eq("status", value: "pending")
                .execute()
                .value

            var ids = Set<String>()
            for row in friendshipRows { ids.insert(row.userA == myUserId ? row.userB : row.userA) }
            for row in requestRows { ids.insert(row.requesterId == myUserId ? row.addresseeId : row.requesterId) }

            let profilesById = try await fetchProfiles(ids: Array(ids))

            let friendIds = Set(friendshipRows.map { $0.userA == myUserId ? $0.userB : $0.userA })
            friends = friendIds
                .compactMap { profilesById[$0] }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            incoming = requestRows
                .filter { $0.addresseeId == myUserId && !friendIds.contains($0.requesterId) }
                .compactMap { row in profilesById[row.requesterId].map { PendingFriendRequest(id: row.id, profile: $0) } }

            outgoing = requestRows
                .filter { $0.requesterId == myUserId && !friendIds.contains($0.addresseeId) }
                .compactMap { row in profilesById[row.addresseeId].map { PendingFriendRequest(id: row.id, profile: $0) } }

            detectLiveChanges()
        } catch {
            fail("Couldn't load your friends.", error)
        }
    }

    /// Diff this load against the previous snapshot and raise a banner
    /// for anything that just happened: a fresh incoming request, or an
    /// outgoing request that became a friendship (an accept).
    private func detectLiveChanges() {
        defer {
            knownIncomingIds = Set(incoming.map(\.id))
            knownFriendIds = Set(friends.map(\.id))
            knownOutgoingTargets = Set(outgoing.map { $0.profile.id })
        }
        // First load of the session — establish the baseline quietly.
        guard let previousIncoming = knownIncomingIds, let previousFriends = knownFriendIds else { return }

        if let accepted = friends.first(where: { !previousFriends.contains($0.id) && knownOutgoingTargets.contains($0.id) }) {
            banner = FriendBannerEvent(kind: .requestAccepted, profile: accepted)
        } else if let fresh = incoming.first(where: { !previousIncoming.contains($0.id) }) {
            banner = FriendBannerEvent(kind: .requestReceived, profile: fresh.profile)
        }
    }

    /// Find real accounts by @username, name, or email — a single
    /// case-insensitive search across all three. `profiles` is
    /// world-readable, so this is a plain filtered select.
    func searchPeople(query rawQuery: String, myUserId: String) async {
        let cleaned = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        // Keep only characters safe inside a PostgREST `or(...)` filter —
        // commas, parens, and wildcards would break the filter grammar.
        let safe = String(cleaned.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" || $0 == " " })
        guard safe.count >= 2 else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            let results: [RemoteProfile] = try await supabase
                .from("profiles")
                .select("id, email, name, username, avatar_url")
                .or("username.ilike.*\(safe)*,name.ilike.*\(safe)*,email.ilike.*\(safe)*")
                .limit(20)
                .execute()
                .value
            searchResults = results.filter { $0.id != myUserId }
        } catch {
            fail("Search failed.", error)
        }
    }

    /// Resolve a single profile by id — used to render an invite link's
    /// target before any relationship exists.
    func fetchProfile(id: String) async -> RemoteProfile? {
        do {
            let rows: [RemoteProfile] = try await supabase
                .from("profiles")
                .select("id, email, name, username, avatar_url")
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            print("[FriendGraph] fetchProfile failed: \(error)")
            return nil
        }
    }

    /// The current connection state to `profileId`, derived from the
    /// already-loaded graph.
    func relationship(to profileId: String, myUserId: String) -> FriendRelationship {
        if profileId == myUserId { return .isMe }
        if friends.contains(where: { $0.id == profileId }) { return .friends }
        if outgoing.contains(where: { $0.profile.id == profileId }) { return .requestSent }
        if incoming.contains(where: { $0.profile.id == profileId }) { return .requestReceived }
        return .none
    }

    func sendRequest(to profile: RemoteProfile, myUserId: String) async {
        do {
            // Upsert so re-adding someone who previously declined simply
            // resets the request to pending instead of erroring on the
            // (requester, addressee) unique constraint.
            try await supabase
                .from("friend_requests")
                .upsert(
                    FriendRequestInsert(requesterId: myUserId, addresseeId: profile.id, status: "pending"),
                    onConflict: "requester_id,addressee_id"
                )
                .execute()
            PushService.send(to: profile.id, kind: .friendRequest)
            searchResults.removeAll { $0.id == profile.id }
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't send the request.", error)
        }
    }

    func accept(_ request: PendingFriendRequest, myUserId: String) async {
        let other = request.profile.id
        let a = min(myUserId, other)
        let b = max(myUserId, other)
        do {
            // Insert the friendship while the request is still pending so the
            // RLS check (which looks for a pending/accepted request addressed
            // to me) passes, then stamp the request accepted.
            do {
                try await supabase
                    .from("friendships")
                    .insert(FriendshipInsert(userA: a, userB: b))
                    .execute()
            } catch {
                // Most likely already friends (unique violation) — safe to
                // continue and just mark the request resolved.
                print("[FriendGraph] friendship insert skipped: \(error)")
            }
            try await supabase
                .from("friend_requests")
                .update(StatusUpdate(status: "accepted"))
                .eq("id", value: request.id.uuidString)
                .execute()
            PushService.send(to: request.profile.id, kind: .friendAccept)
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't accept the request.", error)
        }
    }

    func decline(_ request: PendingFriendRequest, myUserId: String) async {
        do {
            try await supabase
                .from("friend_requests")
                .update(StatusUpdate(status: "declined"))
                .eq("id", value: request.id.uuidString)
                .execute()
            incoming.removeAll { $0.id == request.id }
        } catch {
            fail("Couldn't decline the request.", error)
        }
    }

    func unfriend(_ profile: RemoteProfile, myUserId: String) async {
        let a = min(myUserId, profile.id)
        let b = max(myUserId, profile.id)
        do {
            try await supabase
                .from("friendships")
                .delete()
                .eq("user_a", value: a)
                .eq("user_b", value: b)
                .execute()
            friends.removeAll { $0.id == profile.id }
        } catch {
            fail("Couldn't remove this friend.", error)
        }
    }

    // MARK: - Realtime

    /// Subscribe to live changes on the friend graph (friendships and
    /// friend requests). Any RLS-visible change triggers a reload, so an
    /// incoming request or a freshly accepted friend appears without a
    /// pull-to-refresh. Idempotent.
    func startRealtime(myUserId: String) {
        guard channel == nil else { return }
        let ch = supabase.channel("friends-\(myUserId)")
        let streams = ["friendships", "friend_requests"].map {
            ch.postgresChange(AnyAction.self, schema: "public", table: $0)
        }
        channel = ch
        realtimeTask = Task { [weak self] in
            await supabase.realtimeV2.setAuth()
            await ch.subscribe()
            await withTaskGroup(of: Void.self) { group in
                for stream in streams {
                    group.addTask { [weak self] in
                        for await _ in stream {
                            if Task.isCancelled { break }
                            await self?.load(myUserId: myUserId)
                        }
                    }
                }
            }
        }
    }

    /// Tear down the realtime subscription.
    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = channel {
            Task { await supabase.removeChannel(ch) }
        }
        channel = nil
    }

    // MARK: - Helpers

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
        print("[FriendGraph] \(message) \(error)")
        errorMessage = message
        showError = true
    }
}
