//
//  DiscoverService.swift
//  FrisFocus
//
//  People discovery: surfaces real accounts the signed-in user isn't
//  connected to yet, ranked friends-of-friends first (by mutual count)
//  and then newest members — which naturally lifts the live test
//  accounts for a brand-new user. Pure backend reads against the
//  world-readable `profiles` table plus the `friendships` graph; the
//  caller supplies who's already connected so nothing here depends on
//  the rest of the friend service's state.
//

import Foundation
import Supabase

/// A person worth suggesting: their public profile plus how many of the
/// user's friends they share.
nonisolated struct DiscoverSuggestion: Identifiable, Sendable, Hashable {
    let profile: RemoteProfile
    let mutualCount: Int
    var id: String { profile.id }
}

/// A friendship edge used only to count mutuals — both endpoints, no id.
private nonisolated struct FriendshipPairRow: Codable, Sendable {
    let userA: String
    let userB: String

    enum CodingKeys: String, CodingKey {
        case userA = "user_a"
        case userB = "user_b"
    }
}

@Observable
@MainActor
final class DiscoverService {
    var suggestions: [DiscoverSuggestion] = []
    var isLoading = false
    var hasLoaded = false

    /// Live as-you-type search over all profiles, local to the Discover
    /// surface so it never clobbers the Friends page's results.
    var searchResults: [RemoteProfile] = []
    var isSearching = false

    /// Opted-in people roughly in the user's coarse area.
    var nearby: [DiscoverSuggestion] = []

    /// The columns every discover read pulls — includes the opt-in
    /// Near-you area so rows can whisper "Near Austin".
    static let profileColumns = "id, email, name, username, avatar_url, header_url, area_key, area_name, season_card"

    /// How many newest-member profiles to pull as the long tail behind
    /// the friends-of-friends tier.
    private static let newestLimit = 60

    /// Rebuild the suggestion list.
    ///
    /// - Parameters:
    ///   - myUserId: the signed-in account (always excluded).
    ///   - friendIds: accepted friends (excluded, and the seed for the
    ///     friends-of-friends tier).
    ///   - excludedIds: anyone else to hide — pending requests in either
    ///     direction.
    func load(myUserId: String, friendIds: [String], excludedIds: Set<String>) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        var hidden = excludedIds
        hidden.insert(myUserId)
        hidden.formUnion(friendIds)

        do {
            // Tier 1 — friends of friends, counted by how many of my
            // friends each candidate shares.
            var mutualCounts: [String: Int] = [:]
            if !friendIds.isEmpty {
                async let sideA: [FriendshipPairRow] = supabase
                    .from("friendships")
                    .select("user_a, user_b")
                    .in("user_a", values: friendIds)
                    .execute()
                    .value
                async let sideB: [FriendshipPairRow] = supabase
                    .from("friendships")
                    .select("user_a, user_b")
                    .in("user_b", values: friendIds)
                    .execute()
                    .value

                var rows = try await sideA
                rows += try await sideB

                let friendSet = Set(friendIds)
                var countedEdges = Set<String>()
                for row in rows {
                    for (mine, peer) in [(row.userA, row.userB), (row.userB, row.userA)]
                    where friendSet.contains(mine) && !hidden.contains(peer) {
                        let edge = "\(mine)|\(peer)"
                        guard countedEdges.insert(edge).inserted else { continue }
                        mutualCounts[peer, default: 0] += 1
                    }
                }
            }

            // Tier 2 — the newest accounts on the app.
            let newest: [RemoteProfile] = try await supabase
                .from("profiles")
                .select(Self.profileColumns)
                .order("created_at", ascending: false)
                .limit(Self.newestLimit)
                .execute()
                .value

            var profilesById = Dictionary(
                newest.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            // Resolve any mutual-tier candidates the newest pull missed.
            let missingIds = mutualCounts.keys.filter { profilesById[$0] == nil }
            if !missingIds.isEmpty {
                let extra: [RemoteProfile] = try await supabase
                    .from("profiles")
                    .select(Self.profileColumns)
                    .in("id", values: Array(missingIds))
                    .execute()
                    .value
                for profile in extra { profilesById[profile.id] = profile }
            }

            // Assemble: mutuals first (most shared friends, then name),
            // then everyone else newest-first.
            let mutualTier = mutualCounts
                .compactMap { id, count in
                    profilesById[id].map { DiscoverSuggestion(profile: $0, mutualCount: count) }
                }
                .sorted {
                    if $0.mutualCount != $1.mutualCount { return $0.mutualCount > $1.mutualCount }
                    return $0.profile.displayName
                        .localizedCaseInsensitiveCompare($1.profile.displayName) == .orderedAscending
                }

            let newestTier = newest
                .filter { !hidden.contains($0.id) && mutualCounts[$0.id] == nil }
                .map { DiscoverSuggestion(profile: $0, mutualCount: 0) }

            suggestions = mutualTier + newestTier
        } catch {
            // Quiet failure — discovery is an enhancement, never a blocker.
            print("[Discover] load failed: \(error)")
        }
    }

    /// Convenience: rebuild suggestions from an already-loaded friend
    /// graph, deriving the exclusion set (pending either way) from it.
    func refresh(myUserId: String, graph: FriendGraphService) async {
        var excluded = Set(graph.incoming.map(\.profile.id))
        excluded.formUnion(graph.outgoing.map(\.profile.id))
        await load(
            myUserId: myUserId,
            friendIds: graph.friends.map(\.id),
            excludedIds: excluded
        )
    }

    // MARK: - Live search

    /// Case-insensitive as-you-type search across @username, name, and
    /// email. Same grammar-safety filtering as the Friends page search.
    func search(query rawQuery: String, myUserId: String) async {
        let cleaned = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        let safe = String(cleaned.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" || $0 == " " })
        guard safe.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let results: [RemoteProfile] = try await supabase
                .from("profiles")
                .select(Self.profileColumns)
                .or("username.ilike.*\(safe)*,name.ilike.*\(safe)*,email.ilike.*\(safe)*")
                .limit(20)
                .execute()
                .value
            searchResults = results.filter { $0.id != myUserId }
        } catch {
            print("[Discover] search failed: \(error)")
        }
    }

    // MARK: - Near you

    /// Pull opted-in people in (or adjacent to) the user's coarse area.
    /// Pass nil to clear the section (Near you off).
    func refreshNearby(myUserId: String, graph: FriendGraphService, areaKey: String?) async {
        guard let areaKey else {
            nearby = []
            return
        }
        var hidden = Set(graph.incoming.map(\.profile.id))
        hidden.formUnion(graph.outgoing.map(\.profile.id))
        hidden.formUnion(graph.friends.map(\.id))
        hidden.insert(myUserId)
        do {
            let rows: [RemoteProfile] = try await supabase
                .from("profiles")
                .select(Self.profileColumns)
                .in("area_key", values: AreaGrid.neighborKeys(of: areaKey))
                .limit(40)
                .execute()
                .value
            nearby = rows
                .filter { !hidden.contains($0.id) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                .map { DiscoverSuggestion(profile: $0, mutualCount: 0) }
        } catch {
            print("[Discover] nearby failed: \(error)")
        }
    }
}
