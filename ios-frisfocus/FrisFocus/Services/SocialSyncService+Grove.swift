//
//  SocialSyncService+Grove.swift
//  FrisFocus
//
//  Live shared-focus presence. Starting a grove creates a real
//  `focus_blocks` row with invited participants; every device (and the
//  test-user engine, for simulated friends) updates its own
//  `focus_participants` row, and realtime fans the changes out so each
//  tree reflects the participant's actual live state.
//

import Foundation
import Supabase

// MARK: - Wire rows

private nonisolated struct FocusBlockInsert: Encodable, Sendable {
    let id: String
    let hostId: String
    let label: String?
    let plannedMinutes: Int
    let startedAt: String
    enum CodingKeys: String, CodingKey {
        case id, label
        case hostId = "host_id"
        case plannedMinutes = "planned_minutes"
        case startedAt = "started_at"
    }
}

private nonisolated struct FocusParticipantInsert: Encodable, Sendable {
    let blockId: String
    let userId: String
    let state: String
    let leafTier: String
    enum CodingKeys: String, CodingKey {
        case state
        case blockId = "block_id"
        case userId = "user_id"
        case leafTier = "leaf_tier"
    }
}

private nonisolated struct FocusParticipantUpdate: Encodable, Sendable {
    let state: String
    let leafTier: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case state
        case leafTier = "leaf_tier"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct FocusBlockEndUpdate: Encodable, Sendable {
    let endedAt: String
    enum CodingKeys: String, CodingKey {
        case endedAt = "ended_at"
    }
}

private nonisolated struct FocusParticipantRow: Codable, Sendable {
    let blockId: UUID
    let userId: String
    let state: String
    let leafTier: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case state
        case blockId = "block_id"
        case userId = "user_id"
        case leafTier = "leaf_tier"
        case updatedAt = "updated_at"
    }
}

// MARK: - Grove sync

extension SocialSyncService {
    /// Refresh live presence for the active shared block, if any.
    func refreshGrove() async {
        guard let store, let block = store.activeSharedFocusBlock else { return }
        do {
            let rows: [FocusParticipantRow] = try await supabase
                .from("focus_participants")
                .select("block_id, user_id, state, leaf_tier, updated_at")
                .eq("block_id", value: block.id.uuidString)
                .execute()
                .value
            await ensureProfiles(remoteIds: rows.map { $0.userId })
            store.focusPresences = rows.map { row in
                let state: PresenceState
                switch row.state {
                case "inBlock": state = .inBlock
                case "steppedAway": state = .steppedAway
                default: state = .invited
                }
                return FocusPresence(
                    blockId: row.blockId,
                    userId: localId(forRemote: row.userId),
                    state: state,
                    leafTier: LeafTier(rawValue: row.leafTier) ?? .full,
                    updatedAt: SyncDates.parse(row.updatedAt)
                )
            }
        } catch {
            print("[SocialSync] grove refresh failed: \(error)")
        }
    }

    nonisolated func groveStarted(block: SharedFocusBlock, invitedFriendIds: [UUID]) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                try await supabase.from("focus_blocks").insert(FocusBlockInsert(
                    id: block.id.uuidString,
                    hostId: myUserId,
                    label: block.label,
                    plannedMinutes: max(1, Int(block.plannedDuration / 60)),
                    startedAt: SyncDates.iso(block.startedAt)
                )).execute()

                var participants: [FocusParticipantInsert] = [
                    FocusParticipantInsert(
                        blockId: block.id.uuidString,
                        userId: myUserId,
                        state: "inBlock",
                        leafTier: "full"
                    )
                ]
                for friendLocal in invitedFriendIds {
                    if let remote = self.remoteId(forLocal: friendLocal) {
                        participants.append(FocusParticipantInsert(
                            blockId: block.id.uuidString,
                            userId: remote,
                            state: "invited",
                            leafTier: "full"
                        ))
                        PushService.send(to: remote, kind: .focusInvite, preview: block.label)
                    }
                }
                try await supabase.from("focus_participants").insert(participants).execute()
                self.pokeEngine(trigger: "grove")
                await self.refreshGrove()
            } catch {
                print("[SocialSync] grove start failed: \(error)")
            }
        }
    }

    nonisolated func grovePresenceChanged(blockId: UUID, state: PresenceState, leafTier: LeafTier) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                try await supabase.from("focus_participants")
                    .update(FocusParticipantUpdate(
                        state: state == .inBlock ? "inBlock" : "steppedAway",
                        leafTier: leafTier.rawValue,
                        updatedAt: SyncDates.iso(Date())
                    ))
                    .eq("block_id", value: blockId.uuidString)
                    .eq("user_id", value: myUserId)
                    .execute()
            } catch {
                print("[SocialSync] presence publish failed: \(error)")
            }
        }
    }

    nonisolated func groveEnded(blockId: UUID) {
        Task { @MainActor in
            do {
                try await supabase.from("focus_blocks")
                    .update(FocusBlockEndUpdate(endedAt: SyncDates.iso(Date())))
                    .eq("id", value: blockId.uuidString)
                    .execute()
            } catch {
                print("[SocialSync] grove end failed: \(error)")
            }
        }
    }
}
