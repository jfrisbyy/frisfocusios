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

private nonisolated struct FocusSharedTaskRow: Codable, Sendable {
    let blockId: String
    let userId: String
    let taskId: String
    let title: String
    let done: Bool
    enum CodingKeys: String, CodingKey {
        case title, done
        case blockId = "block_id"
        case userId = "user_id"
        case taskId = "task_id"
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
            await refreshGroveSharedTasks(blockId: block.id)
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
            Log.socialSync.error("grove refresh failed: \(error)")
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
                await self.refreshGrove()
            } catch {
                Log.socialSync.error("grove start failed: \(error)")
            }
        }
    }

    /// Pull every participant's shared tasks for the block (mine excluded
    /// in the panel by `userId`). Best-effort: a missing table just
    /// leaves the list empty so the rest of the grove keeps working.
    func refreshGroveSharedTasks(blockId: UUID) async {
        guard let store else { return }
        do {
            let rows: [FocusSharedTaskRow] = try await supabase
                .from("focus_shared_tasks")
                .select("block_id, user_id, task_id, title, done")
                .eq("block_id", value: blockId.uuidString)
                .execute()
                .value
            store.groveSharedTasks = rows.compactMap { row in
                guard let taskId = UUID(uuidString: row.taskId) else { return nil }
                return GroveSharedTask(
                    userId: localId(forRemote: row.userId),
                    taskId: taskId,
                    title: row.title,
                    done: row.done
                )
            }
        } catch {
            Log.socialSync.error("grove shared tasks refresh failed: \(error)")
        }
    }

    /// Add a friend to an already-running grove: insert their invited
    /// participant row and push them a join prompt.
    nonisolated func groveFriendInvited(blockId: UUID, friendId: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let remote = self.remoteId(forLocal: friendId) else { return }
            do {
                try await supabase.from("focus_participants").insert(FocusParticipantInsert(
                    blockId: blockId.uuidString,
                    userId: remote,
                    state: "invited",
                    leafTier: "full"
                )).execute()
                PushService.send(to: remote, kind: .focusInvite, preview: nil)
                await self.refreshGrove()
            } catch {
                Log.socialSync.error("grove mid-session invite failed: \(error)")
            }
        }
    }

    /// Replace my published shared-task rows for the block. Deletes the
    /// old set then inserts the current one so check-off + removal both
    /// propagate. Best-effort against a `focus_shared_tasks` table.
    nonisolated func groveSharedTasksChanged(
        blockId: UUID,
        tasks: [(taskId: UUID, title: String, done: Bool)]
    ) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                try await supabase.from("focus_shared_tasks")
                    .delete()
                    .eq("block_id", value: blockId.uuidString)
                    .eq("user_id", value: myUserId)
                    .execute()
                if !tasks.isEmpty {
                    let rows = tasks.map { t in
                        FocusSharedTaskRow(
                            blockId: blockId.uuidString,
                            userId: myUserId,
                            taskId: t.taskId.uuidString,
                            title: t.title,
                            done: t.done
                        )
                    }
                    try await supabase.from("focus_shared_tasks").insert(rows).execute()
                }
                await self.refreshGroveSharedTasks(blockId: blockId)
            } catch {
                Log.socialSync.error("grove shared tasks publish failed: \(error)")
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
                Log.socialSync.error("presence publish failed: \(error)")
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
                Log.socialSync.error("grove end failed: \(error)")
            }
        }
    }
}
