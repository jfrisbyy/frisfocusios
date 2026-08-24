//
//  ModerationService.swift
//  FrisFocus
//
//  Safety tools required for a social app: blocking, reporting, and
//  hiding. Block is symmetric — once you block someone the friendship
//  is severed, any pending requests are cleared, and RLS stops either
//  of you from messaging or re-requesting the other. Reporting files a
//  row for out-of-band review. Hiding is quieter: one piece of content
//  (a story post, a proof) disappears from this account's surfaces
//  without touching the relationship — persisted per account so sync
//  refreshes can never resurrect it.
//
//  Injected once at the app root so every surface can read `blockedIds`
//  to hide a blocked person, and call `block` / `report` / `hideStory`
//  / `hideProof` from their "..." menus.
//

import Foundation
import Supabase

// MARK: - Wire payloads

private nonisolated struct BlockRow: Codable, Sendable {
    let blockedId: String
    enum CodingKeys: String, CodingKey { case blockedId = "blocked_id" }
}

private nonisolated struct BlockInsert: Encodable, Sendable {
    let blockerId: String
    let blockedId: String
    enum CodingKeys: String, CodingKey {
        case blockerId = "blocker_id"
        case blockedId = "blocked_id"
    }
}

private nonisolated struct ReportInsert: Encodable, Sendable {
    let reporterId: String
    let reportedUserId: String?
    let messageId: String?
    let storyPostId: String?
    let storyCommentId: String?
    let reason: String
    let details: String?

    enum CodingKeys: String, CodingKey {
        case reporterId = "reporter_id"
        case reportedUserId = "reported_user_id"
        case messageId = "message_id"
        case storyPostId = "story_post_id"
        case storyCommentId = "story_comment_id"
        case reason
        case details
    }
}

// MARK: - Service

@Observable
@MainActor
final class ModerationService {
    /// Account ids the signed-in user has blocked. Surfaces read this to
    /// hide blocked people from lists, search, and conversations.
    var blockedIds: Set<String> = []
    /// Story posts this account chose to hide — filtered from every tape
    /// and dropped at sync ingest so refreshes can't bring them back.
    var hiddenStoryPostIds: Set<UUID> = []
    /// Direct proofs this account chose to hide from their threads.
    var hiddenProofIds: Set<UUID> = []
    /// Golden Hour captures this account chose to hide from its walls.
    var hiddenGoldenHourPostIds: Set<UUID> = []
    var isWorking = false
    var errorMessage: String?
    var showError = false

    /// The account the hidden sets were loaded for — persistence key
    /// namespace, so two sign-ins on one device never share hides.
    @ObservationIgnored private var hiddenOwnerUserId: String?

    func isBlocked(_ id: String) -> Bool { blockedIds.contains(id) }
    func isStoryHidden(_ postId: UUID) -> Bool { hiddenStoryPostIds.contains(postId) }
    func isProofHidden(_ messageId: UUID) -> Bool { hiddenProofIds.contains(messageId) }
    func isGoldenHourHidden(_ postId: UUID) -> Bool { hiddenGoldenHourPostIds.contains(postId) }

    // MARK: Load

    func loadBlocks(myUserId: String) async {
        hiddenOwnerUserId = myUserId
        hiddenStoryPostIds = Self.persistedHiddenStories(userId: myUserId)
        hiddenProofIds = Self.persistedHiddenProofs(userId: myUserId)
        hiddenGoldenHourPostIds = Self.persistedHiddenGoldenHour(userId: myUserId)
        do {
            let rows: [BlockRow] = try await supabase
                .from("blocks")
                .select("blocked_id")
                .eq("blocker_id", value: myUserId)
                .execute()
                .value
            blockedIds = Set(rows.map { $0.blockedId })
        } catch {
            print("[Moderation] loadBlocks failed: \(error)")
        }
    }

    func clear() {
        blockedIds = []
        hiddenStoryPostIds = []
        hiddenProofIds = []
        hiddenGoldenHourPostIds = []
        hiddenOwnerUserId = nil
    }

    // MARK: Hide (quiet, per-account, local)

    private static func hiddenStoriesKey(_ userId: String) -> String { "moderation.hiddenStories.\(userId)" }
    private static func hiddenProofsKey(_ userId: String) -> String { "moderation.hiddenProofs.\(userId)" }
    private static func hiddenGoldenHourKey(_ userId: String) -> String { "moderation.hiddenGoldenHour.\(userId)" }

    /// The persisted hidden-story ids for an account — readable by sync
    /// services at ingest without holding the live instance.
    static func persistedHiddenStories(userId: String) -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: hiddenStoriesKey(userId)) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    /// The persisted hidden-proof ids for an account.
    static func persistedHiddenProofs(userId: String) -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: hiddenProofsKey(userId)) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    /// The persisted hidden Golden Hour capture ids for an account.
    static func persistedHiddenGoldenHour(userId: String) -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: hiddenGoldenHourKey(userId)) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    /// Hide one story post from every surface on this account. Quiet
    /// and instant — no confirmation, nothing sent to the author.
    func hideStory(_ postId: UUID) {
        hiddenStoryPostIds.insert(postId)
        guard let userId = hiddenOwnerUserId else { return }
        UserDefaults.standard.set(
            hiddenStoryPostIds.map(\.uuidString),
            forKey: Self.hiddenStoriesKey(userId)
        )
    }

    /// Hide one direct proof from this account's threads.
    func hideProof(_ messageId: UUID) {
        hiddenProofIds.insert(messageId)
        guard let userId = hiddenOwnerUserId else { return }
        UserDefaults.standard.set(
            hiddenProofIds.map(\.uuidString),
            forKey: Self.hiddenProofsKey(userId)
        )
    }

    /// Hide one Golden Hour capture from this account's walls. Quiet
    /// and instant — nothing is sent to the author.
    func hideGoldenHourPost(_ postId: UUID) {
        hiddenGoldenHourPostIds.insert(postId)
        guard let userId = hiddenOwnerUserId else { return }
        UserDefaults.standard.set(
            hiddenGoldenHourPostIds.map(\.uuidString),
            forKey: Self.hiddenGoldenHourKey(userId)
        )
    }

    /// Profiles for the people the user has blocked — for the
    /// blocked-accounts management screen.
    func loadBlockedProfiles() async -> [RemoteProfile] {
        guard !blockedIds.isEmpty else { return [] }
        do {
            let rows: [RemoteProfile] = try await supabase
                .from("profiles")
                .select("id, name, username, avatar_url, header_url")
                .in("id", values: Array(blockedIds))
                .execute()
                .value
            return rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            print("[Moderation] loadBlockedProfiles failed: \(error)")
            return []
        }
    }

    // MARK: Block

    /// Block someone: record the block, sever any friendship, and clear
    /// pending requests in both directions. RLS does the rest (no future
    /// messages or requests can cross the block).
    func block(_ profileId: String, myUserId: String) async {
        guard profileId != myUserId else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabase
                .from("blocks")
                .upsert(BlockInsert(blockerId: myUserId, blockedId: profileId), onConflict: "blocker_id,blocked_id")
                .execute()
            blockedIds.insert(profileId)

            // Sever the friendship (ids are stored sorted).
            let a = min(myUserId, profileId)
            let b = max(myUserId, profileId)
            try? await supabase
                .from("friendships")
                .delete()
                .eq("user_a", value: a)
                .eq("user_b", value: b)
                .execute()

            // Clear any pending requests either way.
            try? await supabase
                .from("friend_requests")
                .delete()
                .eq("requester_id", value: myUserId)
                .eq("addressee_id", value: profileId)
                .execute()
            try? await supabase
                .from("friend_requests")
                .delete()
                .eq("requester_id", value: profileId)
                .eq("addressee_id", value: myUserId)
                .execute()
        } catch {
            fail("Couldn't block this person.", error)
        }
    }

    func unblock(_ profileId: String, myUserId: String) async {
        do {
            try await supabase
                .from("blocks")
                .delete()
                .eq("blocker_id", value: myUserId)
                .eq("blocked_id", value: profileId)
                .execute()
            blockedIds.remove(profileId)
        } catch {
            fail("Couldn't unblock this person.", error)
        }
    }

    // MARK: Report

    /// File a report against a person and/or a specific piece of
    /// content — a proof message, a story post, or a story comment.
    @discardableResult
    func report(
        reportedUserId: String?,
        messageId: UUID?,
        storyPostId: UUID? = nil,
        storyCommentId: UUID? = nil,
        reason: String,
        details: String?,
        myUserId: String
    ) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        let trimmedDetails = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await supabase
                .from("reports")
                .insert(ReportInsert(
                    reporterId: myUserId,
                    reportedUserId: reportedUserId,
                    messageId: messageId?.uuidString,
                    storyPostId: storyPostId?.uuidString,
                    storyCommentId: storyCommentId?.uuidString,
                    reason: reason,
                    details: (trimmedDetails?.isEmpty == false) ? trimmedDetails : nil
                ))
                .execute()
            return true
        } catch {
            fail("Couldn't send your report.", error)
            return false
        }
    }

    // MARK: Helpers

    private func fail(_ message: String, _ error: Error) {
        print("[Moderation] \(message) \(error)")
        errorMessage = message
        showError = true
    }
}
