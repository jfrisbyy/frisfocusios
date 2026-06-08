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
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, email, name
        case avatarUrl = "avatar_url"
    }

    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        return "Someone"
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
        } catch {
            fail("Couldn't load your friends.", error)
        }
    }

    /// Look up real accounts by the exact email they signed up with
    /// (case-insensitive). `profiles` is world-readable, so this is a
    /// plain filtered select.
    func search(email rawEmail: String, myUserId: String) async {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            let results: [RemoteProfile] = try await supabase
                .from("profiles")
                .select("id, email, name, avatar_url")
                .ilike("email", pattern: email)
                .execute()
                .value
            searchResults = results.filter { $0.id != myUserId }
        } catch {
            fail("Search failed.", error)
        }
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

    private func fetchProfiles(ids: [String]) async throws -> [String: RemoteProfile] {
        guard !ids.isEmpty else { return [:] }
        let rows: [RemoteProfile] = try await supabase
            .from("profiles")
            .select("id, email, name, avatar_url")
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
