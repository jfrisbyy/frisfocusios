//
//  ModerationService.swift
//  FrisFocus
//
//  Safety tools required for a social app: blocking and reporting. Block
//  is symmetric — once you block someone the friendship is severed, any
//  pending requests are cleared, and RLS stops either of you from
//  messaging or re-requesting the other. Reporting files a row for
//  out-of-band review.
//
//  Injected once at the app root so every surface can read `blockedIds`
//  to hide a blocked person, and call `block` / `report` from their
//  "..." menus.
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
    let reason: String
    let details: String?

    enum CodingKeys: String, CodingKey {
        case reporterId = "reporter_id"
        case reportedUserId = "reported_user_id"
        case messageId = "message_id"
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
    var isWorking = false
    var errorMessage: String?
    var showError = false

    func isBlocked(_ id: String) -> Bool { blockedIds.contains(id) }

    // MARK: Load

    func loadBlocks(myUserId: String) async {
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
    }

    /// Profiles for the people the user has blocked — for the
    /// blocked-accounts management screen.
    func loadBlockedProfiles() async -> [RemoteProfile] {
        guard !blockedIds.isEmpty else { return [] }
        do {
            let rows: [RemoteProfile] = try await supabase
                .from("profiles")
                .select("id, email, name, username, avatar_url")
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

    /// File a report against a person and/or a specific message.
    @discardableResult
    func report(
        reportedUserId: String?,
        messageId: UUID?,
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
