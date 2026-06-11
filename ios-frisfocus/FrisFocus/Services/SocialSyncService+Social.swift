//
//  SocialSyncService+Social.swift
//  FrisFocus
//
//  Cheers, pacts, and circles — mirrored from Supabase into the Store
//  and written through on every local mutation. Local-only enrichments
//  (chapter timelines, personal-task links) are preserved across
//  refreshes; the server owns membership, status, and completions.
//

import Foundation
import Supabase

// MARK: - Wire rows

private nonisolated struct CheerRow: Codable, Sendable {
    let id: UUID
    let senderId: String
    let recipientId: String
    let message: String
    let createdAt: String
    let readAt: String?
    let dismissedAt: String?
    let reaction: String?
    let reactionAt: String?
    enum CodingKeys: String, CodingKey {
        case id, message, reaction
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case createdAt = "created_at"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
        case reactionAt = "reaction_at"
    }
}

private nonisolated struct CheerInsert: Encodable, Sendable {
    let id: String
    let senderId: String
    let recipientId: String
    let message: String
    enum CodingKeys: String, CodingKey {
        case id, message
        case senderId = "sender_id"
        case recipientId = "recipient_id"
    }
}

private nonisolated struct CheerStampUpdate: Encodable, Sendable {
    let readAt: String?
    let dismissedAt: String?
    enum CodingKeys: String, CodingKey {
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

private nonisolated struct CheerReactionUpdate: Encodable, Sendable {
    let reaction: String?
    let reactionAt: String?
    let readAt: String?
    enum CodingKeys: String, CodingKey {
        case reaction
        case reactionAt = "reaction_at"
        case readAt = "read_at"
    }
}

private nonisolated struct PactRow: Codable, Sendable {
    let id: UUID
    let proposerId: String
    let partnerId: String
    let title: String?
    let durationDays: Int
    let status: String
    let startDate: String?
    let endDate: String?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, title, status
        case proposerId = "proposer_id"
        case partnerId = "partner_id"
        case durationDays = "duration_days"
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
    }
}

private nonisolated struct PactTaskRow: Codable, Sendable {
    let id: UUID
    let pactId: UUID
    let title: String
    let position: Int
    enum CodingKeys: String, CodingKey {
        case id, title, position
        case pactId = "pact_id"
    }
}

private nonisolated struct PactCompletionRow: Codable, Sendable {
    let id: UUID
    let pactId: UUID
    let taskId: UUID
    let userId: String
    let completedOn: String
    enum CodingKeys: String, CodingKey {
        case id
        case pactId = "pact_id"
        case taskId = "task_id"
        case userId = "user_id"
        case completedOn = "completed_on"
    }
}

private nonisolated struct PactInsert: Encodable, Sendable {
    let id: String
    let proposerId: String
    let partnerId: String
    let title: String
    let durationDays: Int
    let status: String
    enum CodingKeys: String, CodingKey {
        case id, title, status
        case proposerId = "proposer_id"
        case partnerId = "partner_id"
        case durationDays = "duration_days"
    }
}

private nonisolated struct PactTaskInsert: Encodable, Sendable {
    let id: String
    let pactId: String
    let title: String
    let position: Int
    enum CodingKeys: String, CodingKey {
        case id, title, position
        case pactId = "pact_id"
    }
}

private nonisolated struct PactStatusUpdate: Encodable, Sendable {
    let status: String
    let startDate: String?
    let endDate: String?
    let respondedAt: String
    enum CodingKeys: String, CodingKey {
        case status
        case startDate = "start_date"
        case endDate = "end_date"
        case respondedAt = "responded_at"
    }
}

private nonisolated struct PactCompletionInsert: Encodable, Sendable {
    let id: String
    let pactId: String
    let taskId: String
    let userId: String
    let completedOn: String
    enum CodingKeys: String, CodingKey {
        case id
        case pactId = "pact_id"
        case taskId = "task_id"
        case userId = "user_id"
        case completedOn = "completed_on"
    }
}

private nonisolated struct CircleRowS: Codable, Sendable {
    let id: UUID
    let ownerId: String
    let name: String
    let type: String
    let endDate: String?
    let collectiveUnit: String?
    let collectiveTarget: Double?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, name, type
        case ownerId = "owner_id"
        case endDate = "end_date"
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
        case createdAt = "created_at"
    }
}

private nonisolated struct CircleMemberRowS: Codable, Sendable {
    let circleId: UUID
    let userId: String
    let role: String
    enum CodingKeys: String, CodingKey {
        case role
        case circleId = "circle_id"
        case userId = "user_id"
    }
}

private nonisolated struct CircleTaskRowS: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let title: String
    let pointValue: Int?
    let position: Int
    enum CodingKeys: String, CodingKey {
        case id, title, position
        case circleId = "circle_id"
        case pointValue = "point_value"
    }
}

private nonisolated struct CircleCompletionRowS: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let taskId: UUID
    let userId: String
    let completedOn: String
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case taskId = "task_id"
        case userId = "user_id"
        case completedOn = "completed_on"
    }
}

private nonisolated struct CircleContributionRowS: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let userId: String
    let amount: Double
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, amount
        case circleId = "circle_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct CircleInsertS: Encodable, Sendable {
    let id: String
    let ownerId: String
    let name: String
    let type: String
    let timeframeKind: String
    let endDate: String?
    let collectiveUnit: String?
    let collectiveTarget: Double?
    let visibility: String
    let joinRule: String
    enum CodingKeys: String, CodingKey {
        case id, name, type, visibility
        case ownerId = "owner_id"
        case timeframeKind = "timeframe_kind"
        case endDate = "end_date"
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
        case joinRule = "join_rule"
    }
}

private nonisolated struct CircleMemberInsertS: Encodable, Sendable {
    let circleId: String
    let userId: String
    let role: String
    enum CodingKeys: String, CodingKey {
        case role
        case circleId = "circle_id"
        case userId = "user_id"
    }
}

private nonisolated struct CircleTaskUpsertS: Encodable, Sendable {
    let id: String
    let circleId: String
    let title: String
    let pointValue: Int?
    let position: Int
    enum CodingKeys: String, CodingKey {
        case id, title, position
        case circleId = "circle_id"
        case pointValue = "point_value"
    }
}

private nonisolated struct CircleCompletionInsertS: Encodable, Sendable {
    let id: String
    let circleId: String
    let taskId: String
    let userId: String
    let completedOn: String
    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case taskId = "task_id"
        case userId = "user_id"
        case completedOn = "completed_on"
    }
}

// MARK: - Cheers

extension SocialSyncService {
    func refreshCheers() async {
        guard let store, myUserId != nil else { return }
        do {
            let cutoff = SyncDates.iso(Date().addingTimeInterval(-30 * 24 * 3600))
            let rows: [CheerRow] = try await supabase
                .from("cheers")
                .select(Self.cheerSelect)
                .gte("created_at", value: cutoff)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            await ensureProfiles(remoteIds: rows.flatMap { [$0.senderId, $0.recipientId] })
            store.cheers = rows.map { mapCheer($0) }
            store.persistAll()
        } catch {
            print("[SocialSync] cheers refresh failed: \(error)")
        }
    }

    private static let cheerSelect =
        "id, sender_id, recipient_id, message, created_at, read_at, dismissed_at, reaction, reaction_at"

    private func mapCheer(_ row: CheerRow) -> Cheer {
        Cheer(
            id: row.id,
            fromFriendId: localId(forRemote: row.senderId),
            fromName: displayName(forRemote: row.senderId),
            fromInitials: initials(forRemote: row.senderId),
            fromColorHex: row.senderId == myUserId ? "2C2C2A" : RemoteIDMapper.accentHex(forRemoteId: row.senderId),
            toUserId: localId(forRemote: row.recipientId),
            message: row.message,
            sentAt: SyncDates.parse(row.createdAt),
            readAt: row.readAt.map { SyncDates.parse($0) },
            dismissedAt: row.dismissedAt.map { SyncDates.parse($0) },
            reaction: row.reaction,
            reactionAt: row.reactionAt.map { SyncDates.parse($0) }
        )
    }

    /// One older page for the history view, fetched past the rolling
    /// 30-day window the Store mirrors. Returns mapped cheers without
    /// touching `store.cheers` — the history view owns the paged tail.
    func fetchCheerHistory(before: Date, limit: Int = 60) async -> [Cheer] {
        guard myUserId != nil else { return [] }
        do {
            let rows: [CheerRow] = try await supabase
                .from("cheers")
                .select(Self.cheerSelect)
                .lt("created_at", value: SyncDates.iso(before))
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            await ensureProfiles(remoteIds: rows.flatMap { [$0.senderId, $0.recipientId] })
            return rows.map { mapCheer($0) }
        } catch {
            print("[SocialSync] cheer history fetch failed: \(error)")
            return []
        }
    }

    nonisolated func cheerSent(_ cheer: Cheer) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId,
                  let recipient = self.remoteId(forLocal: cheer.toUserId) else { return }
            do {
                try await supabase.from("cheers").insert(CheerInsert(
                    id: cheer.id.uuidString,
                    senderId: myUserId,
                    recipientId: recipient,
                    message: cheer.message
                )).execute()
                PushService.send(to: recipient, kind: .cheer, preview: cheer.message)
                self.pokeEngine(trigger: "cheer")
            } catch {
                print("[SocialSync] cheer send failed: \(error)")
            }
        }
    }

    nonisolated func cheerStamped(_ cheer: Cheer) {
        Task { @MainActor in
            do {
                try await supabase.from("cheers")
                    .update(CheerStampUpdate(
                        readAt: cheer.readAt.map { SyncDates.iso($0) },
                        dismissedAt: cheer.dismissedAt.map { SyncDates.iso($0) }
                    ))
                    .eq("id", value: cheer.id.uuidString)
                    .execute()
            } catch {
                print("[SocialSync] cheer stamp failed: \(error)")
            }
        }
    }

    /// Up-sync the recipient's emoji reaction and notify the sender.
    /// Fired by `Store.reactToCheer`; the row update also stamps
    /// `read_at` since reacting implies the cheer was seen.
    nonisolated func cheerReacted(_ cheer: Cheer) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await supabase.from("cheers")
                    .update(CheerReactionUpdate(
                        reaction: cheer.reaction,
                        reactionAt: cheer.reactionAt.map { SyncDates.iso($0) },
                        readAt: cheer.readAt.map { SyncDates.iso($0) }
                    ))
                    .eq("id", value: cheer.id.uuidString)
                    .execute()
                if let reaction = cheer.reaction,
                   let sender = self.remoteId(forLocal: cheer.fromFriendId) {
                    PushService.send(to: sender, kind: .cheerReaction, preview: reaction)
                }
            } catch {
                print("[SocialSync] cheer reaction failed: \(error)")
            }
        }
    }
}

// MARK: - Pacts

extension SocialSyncService {
    func refreshPacts() async {
        guard let store, myUserId != nil else { return }
        do {
            let pactRows: [PactRow] = try await supabase
                .from("pacts")
                .select("id, proposer_id, partner_id, title, duration_days, status, start_date, end_date, created_at")
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            let pactIds = pactRows.map { $0.id.uuidString }
            var taskRows: [PactTaskRow] = []
            var completionRows: [PactCompletionRow] = []
            if !pactIds.isEmpty {
                async let t: [PactTaskRow] = supabase
                    .from("pact_tasks")
                    .select("id, pact_id, title, position")
                    .in("pact_id", values: pactIds)
                    .execute().value
                async let c: [PactCompletionRow] = supabase
                    .from("pact_completions")
                    .select("id, pact_id, task_id, user_id, completed_on")
                    .in("pact_id", values: pactIds)
                    .execute().value
                (taskRows, completionRows) = try await (t, c)
            }
            await ensureProfiles(remoteIds: pactRows.flatMap { [$0.proposerId, $0.partnerId] })

            // Preserve local personal-task links across refreshes.
            var localLinks: [UUID: UUID] = [:]
            for pact in store.pacts {
                for task in pact.tasks where task.linkedPersonalTaskId != nil {
                    localLinks[task.id] = task.linkedPersonalTaskId
                }
            }

            let tasksByPact = Dictionary(grouping: taskRows, by: { $0.pactId })
            store.pacts = pactRows.map { row in
                let tasks = (tasksByPact[row.id] ?? [])
                    .sorted { $0.position < $1.position }
                    .map { t in
                        PactTask(
                            id: t.id,
                            name: t.title,
                            category: nil,
                            linkedPersonalTaskId: localLinks[t.id]
                        )
                    }
                return Pact(
                    id: row.id,
                    title: row.title ?? "Pact",
                    proposerId: localId(forRemote: row.proposerId),
                    partnerId: localId(forRemote: row.partnerId),
                    tasks: tasks,
                    durationDays: row.durationDays,
                    startDate: row.startDate.map { SyncDates.parseDay($0) },
                    endDate: row.endDate.map { SyncDates.parseDay($0) },
                    status: PactStatus(rawValue: row.status) ?? .pending,
                    createdAt: SyncDates.parse(row.createdAt)
                )
            }
            store.pactCompletions = completionRows.map { row in
                PactCompletion(
                    id: row.id,
                    pactId: row.pactId,
                    taskId: row.taskId,
                    userId: localId(forRemote: row.userId),
                    date: SyncDates.parseDay(row.completedOn)
                )
            }
            store.persistAll()
        } catch {
            print("[SocialSync] pacts refresh failed: \(error)")
        }
    }

    nonisolated func pactProposed(_ pact: Pact) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId,
                  let partner = self.remoteId(forLocal: pact.partnerId) else { return }
            do {
                try await supabase.from("pacts").insert(PactInsert(
                    id: pact.id.uuidString,
                    proposerId: myUserId,
                    partnerId: partner,
                    title: pact.title,
                    durationDays: pact.durationDays,
                    status: "pending"
                )).execute()
                let tasks = pact.tasks.enumerated().map { idx, task in
                    PactTaskInsert(
                        id: task.id.uuidString,
                        pactId: pact.id.uuidString,
                        title: task.name,
                        position: idx
                    )
                }
                if !tasks.isEmpty {
                    try await supabase.from("pact_tasks").insert(tasks).execute()
                }
                PushService.send(to: partner, kind: .pactInvite, preview: pact.title)
                self.pokeEngine(trigger: "pact")
            } catch {
                print("[SocialSync] pact propose failed: \(error)")
            }
        }
    }

    nonisolated func pactStatusChanged(_ pact: Pact) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await supabase.from("pacts")
                    .update(PactStatusUpdate(
                        status: pact.status.rawValue,
                        startDate: pact.startDate.map { SyncDates.dayKey($0) },
                        endDate: pact.endDate.map { SyncDates.dayKey($0) },
                        respondedAt: SyncDates.iso(Date())
                    ))
                    .eq("id", value: pact.id.uuidString)
                    .execute()
                if pact.status == .active, let store = self.store {
                    let otherLocal = pact.proposerId == store.currentUserId ? pact.partnerId : pact.proposerId
                    if let remote = self.remoteId(forLocal: otherLocal) {
                        PushService.send(to: remote, kind: .pactAccept, preview: pact.title)
                    }
                }
            } catch {
                print("[SocialSync] pact status sync failed: \(error)")
            }
        }
    }

    nonisolated func pactLeft(_ pactId: UUID) {
        Task { @MainActor in
            do {
                try await supabase.from("pacts")
                    .delete()
                    .eq("id", value: pactId.uuidString)
                    .execute()
            } catch {
                print("[SocialSync] pact delete failed: \(error)")
            }
        }
    }

    nonisolated func pactCompletionToggled(pactId: UUID, taskId: UUID, completionId: UUID, date: Date, completed: Bool) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            let day = SyncDates.dayKey(date)
            do {
                if completed {
                    try await supabase.from("pact_completions").insert(PactCompletionInsert(
                        id: completionId.uuidString,
                        pactId: pactId.uuidString,
                        taskId: taskId.uuidString,
                        userId: myUserId,
                        completedOn: day
                    )).execute()
                } else {
                    try await supabase.from("pact_completions")
                        .delete()
                        .eq("pact_id", value: pactId.uuidString)
                        .eq("task_id", value: taskId.uuidString)
                        .eq("user_id", value: myUserId)
                        .eq("completed_on", value: day)
                        .execute()
                }
            } catch {
                print("[SocialSync] pact completion sync failed: \(error)")
            }
        }
    }
}

// MARK: - Circles

extension SocialSyncService {
    func refreshCircles() async {
        guard let store, let myUserId else { return }
        do {
            let myMemberships: [CircleMemberRowS] = try await supabase
                .from("circle_members")
                .select("circle_id, user_id, role")
                .eq("user_id", value: myUserId)
                .execute()
                .value
            let circleIds = myMemberships.map { $0.circleId.uuidString }
            guard !circleIds.isEmpty else {
                if !store.circles.isEmpty {
                    store.circles = []
                    store.circleTaskCompletions = []
                    store.circleContributions = []
                    store.persistAll()
                }
                return
            }

            async let circlesQ: [CircleRowS] = supabase
                .from("circles")
                .select("id, owner_id, name, type, end_date, collective_unit, collective_target, created_at")
                .in("id", values: circleIds)
                .execute().value
            async let membersQ: [CircleMemberRowS] = supabase
                .from("circle_members")
                .select("circle_id, user_id, role")
                .in("circle_id", values: circleIds)
                .execute().value
            async let tasksQ: [CircleTaskRowS] = supabase
                .from("circle_tasks")
                .select("id, circle_id, title, point_value, position")
                .in("circle_id", values: circleIds)
                .execute().value
            async let completionsQ: [CircleCompletionRowS] = supabase
                .from("circle_task_completions")
                .select("id, circle_id, task_id, user_id, completed_on")
                .in("circle_id", values: circleIds)
                .execute().value
            async let contributionsQ: [CircleContributionRowS] = supabase
                .from("circle_contributions")
                .select("id, circle_id, user_id, amount, created_at")
                .in("circle_id", values: circleIds)
                .execute().value

            let (circleRows, memberRows, taskRows, completionRows, contributionRows) =
                try await (circlesQ, membersQ, tasksQ, completionsQ, contributionsQ)

            await ensureProfiles(remoteIds: memberRows.map { $0.userId } + circleRows.map { $0.ownerId })

            let membersByCircle = Dictionary(grouping: memberRows, by: { $0.circleId })
            let tasksByCircle = Dictionary(grouping: taskRows, by: { $0.circleId })
            let contributionsByCircle = Dictionary(grouping: contributionRows, by: { $0.circleId })
            let existingById = Dictionary(store.circles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            var mapped: [FFCircle] = circleRows.map { row in
                let existing = existingById[row.id]
                let localLinks: [UUID: UUID] = Dictionary(
                    (existing?.tasks ?? []).compactMap { t in
                        t.linkedPersonalTaskId.map { (t.id, $0) }
                    },
                    uniquingKeysWith: { a, _ in a }
                )
                let tasks = (tasksByCircle[row.id] ?? [])
                    .sorted { $0.position < $1.position }
                    .map { t in
                        CircleTask(
                            id: t.id,
                            title: t.title,
                            pointValue: t.pointValue,
                            linkedPersonalTaskId: localLinks[t.id]
                        )
                    }
                let members = membersByCircle[row.id] ?? []
                let memberLocalIds = members.map { localId(forRemote: $0.userId) }
                let adminLocalIds = members.filter { $0.role == "admin" }.map { localId(forRemote: $0.userId) }
                let type = CircleType(rawValue: row.type) ?? .witness
                let progress = (contributionsByCircle[row.id] ?? []).reduce(0.0) { $0 + $1.amount }
                var circle = FFCircle(
                    id: row.id,
                    name: row.name,
                    type: type,
                    timeframe: row.endDate.map { .timeBoxed(endDate: SyncDates.parse($0)) } ?? .ongoing,
                    memberIds: memberLocalIds,
                    tasks: tasks,
                    collectiveUnit: row.collectiveUnit,
                    collectiveTarget: row.collectiveTarget,
                    collectiveProgress: type.hasSharedNumber ? progress : nil,
                    createdAt: SyncDates.parse(row.createdAt),
                    ownerId: localId(forRemote: row.ownerId),
                    adminIds: adminLocalIds,
                    membersCanProposeTasks: existing?.membersCanProposeTasks ?? false,
                    chapters: existing?.chapters ?? []
                )
                circle.objectives = type.objectives
                return circle
            }
            mapped = Store.withChapterTimelines(mapped)
            store.circles = mapped

            store.circleTaskCompletions = completionRows.map { row in
                CircleTaskCompletion(
                    id: row.id,
                    circleId: row.circleId,
                    circleTaskId: row.taskId,
                    memberId: localId(forRemote: row.userId),
                    date: SyncDates.parseDay(row.completedOn)
                )
            }
            store.circleContributions = contributionRows.map { row in
                CircleContribution(
                    id: row.id,
                    circleId: row.circleId,
                    memberId: localId(forRemote: row.userId),
                    amount: row.amount,
                    date: SyncDates.parse(row.createdAt)
                )
            }
            store.persistAll()
        } catch {
            print("[SocialSync] circles refresh failed: \(error)")
        }
    }

    nonisolated func circleCreated(_ circle: FFCircle) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            do {
                var endDate: String?
                if case .timeBoxed(let date) = circle.timeframe {
                    endDate = SyncDates.iso(date)
                }
                try await supabase.from("circles").insert(CircleInsertS(
                    id: circle.id.uuidString,
                    ownerId: myUserId,
                    name: circle.name,
                    type: circle.type.rawValue,
                    timeframeKind: endDate == nil ? "ongoing" : "ends",
                    endDate: endDate,
                    collectiveUnit: circle.collectiveUnit,
                    collectiveTarget: circle.collectiveTarget,
                    visibility: "private",
                    joinRule: "open"
                )).execute()

                var members: [CircleMemberInsertS] = [
                    CircleMemberInsertS(circleId: circle.id.uuidString, userId: myUserId, role: "owner")
                ]
                for localMember in circle.memberIds where localMember != self.store?.currentUserId {
                    if let remote = self.remoteId(forLocal: localMember) {
                        members.append(CircleMemberInsertS(circleId: circle.id.uuidString, userId: remote, role: "member"))
                        PushService.send(to: remote, kind: .circleInvite, circleId: circle.id.uuidString)
                    }
                }
                try await supabase.from("circle_members").insert(members).execute()

                let tasks = circle.tasks.enumerated().map { idx, t in
                    CircleTaskUpsertS(
                        id: t.id.uuidString,
                        circleId: circle.id.uuidString,
                        title: t.title,
                        pointValue: t.pointValue,
                        position: idx
                    )
                }
                if !tasks.isEmpty {
                    try await supabase.from("circle_tasks").insert(tasks).execute()
                }
                self.pokeEngine(trigger: "circle")
            } catch {
                print("[SocialSync] circle create failed: \(error)")
            }
        }
    }

    nonisolated func circleTaskToggled(circleId: UUID, taskId: UUID, completionId: UUID, completed: Bool, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            let day = SyncDates.dayKey(date)
            do {
                if completed {
                    try await supabase.from("circle_task_completions").insert(CircleCompletionInsertS(
                        id: completionId.uuidString,
                        circleId: circleId.uuidString,
                        taskId: taskId.uuidString,
                        userId: myUserId,
                        completedOn: day
                    )).execute()
                } else {
                    try await supabase.from("circle_task_completions")
                        .delete()
                        .eq("circle_id", value: circleId.uuidString)
                        .eq("task_id", value: taskId.uuidString)
                        .eq("user_id", value: myUserId)
                        .eq("completed_on", value: day)
                        .execute()
                }
            } catch {
                print("[SocialSync] circle completion sync failed: \(error)")
            }
        }
    }

    nonisolated func circleTaskUpserted(circleId: UUID, task: CircleTask, position: Int) {
        Task { @MainActor in
            do {
                try await supabase.from("circle_tasks").upsert(CircleTaskUpsertS(
                    id: task.id.uuidString,
                    circleId: circleId.uuidString,
                    title: task.title,
                    pointValue: task.pointValue,
                    position: position
                ), onConflict: "id").execute()
            } catch {
                print("[SocialSync] circle task upsert failed: \(error)")
            }
        }
    }

    nonisolated func circleTaskRemoved(circleId: UUID, taskId: UUID) {
        Task { @MainActor in
            do {
                try await supabase.from("circle_tasks")
                    .delete()
                    .eq("id", value: taskId.uuidString)
                    .execute()
            } catch {
                print("[SocialSync] circle task delete failed: \(error)")
            }
        }
    }
}
