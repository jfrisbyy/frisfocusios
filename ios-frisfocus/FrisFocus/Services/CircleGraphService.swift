//
//  CircleGraphService.swift
//  FrisFocus
//
//  Real, multiplayer circles backed by Supabase. A circle is a shared
//  goal owned by one account, with real members keyed to `profiles.id`
//  (the Rork Auth id) — the same identity the friend graph uses.
//
//  This is Phase 2 of the multiplayer build: it graduates "circles" off
//  the seeded local `Store` onto the real friend graph. Like
//  `FriendGraphService`, it's pure backend state — it never touches the
//  local seeded Store. RLS does the real enforcement; `myUserId` is only
//  used to shape and label results.
//
//  Two circle shapes are supported:
//   • parallel   — a shared task list; each member checks tasks off for
//                  the day, and everyone sees everyone's progress.
//   • collective — one shared numeric target; members log contributions
//                  that sum toward it.
//

import Foundation
import Supabase

// MARK: - Circle shape

nonisolated enum CircleKind: String, Codable, Sendable {
    case witness
    case parallel
    case collective
    case hybrid
}

extension CircleKind {
    /// The objective layers this shape carries (0 for witness, 1 for the
    /// goal-bearing shapes, 2 for hybrid). Symmetric with the local model:
    /// a circle is a group + presence + 0–2 layers, and the kind is a
    /// readout of them.
    var objectives: [CircleObjectiveKind] {
        switch self {
        case .witness: return []
        case .parallel: return [.sharedList]
        case .collective: return [.sharedNumber]
        case .hybrid: return [.sharedList, .sharedNumber]
        }
    }

    /// Whether a shared checklist layer is active.
    var hasSharedList: Bool { self == .parallel || self == .hybrid }
    /// Whether a shared number layer is active.
    var hasSharedNumber: Bool { self == .collective || self == .hybrid }

    /// Derive the kind from a list/number layer pair — the readout used
    /// when switching modes by adding or setting aside a layer.
    static func from(hasList: Bool, hasNumber: Bool) -> CircleKind {
        if hasList && hasNumber { return .hybrid }
        if hasList { return .parallel }
        if hasNumber { return .collective }
        return .witness
    }
}

// MARK: - Wire rows (decoded straight from Supabase)
//
// Timestamps/dates are decoded as `String` and parsed lazily so we never
// depend on the SDK's date-decoding strategy. Ordering is done in SQL.

private nonisolated struct CircleRow: Codable, Sendable {
    let id: UUID
    let ownerId: String
    let name: String
    let type: String
    let timeframeKind: String
    let endDate: String?
    let collectiveUnit: String?
    let collectiveTarget: Double?
    let createdAt: String?
    let visibility: String?
    let joinRule: String?
    let description: String?
    let headerUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, visibility, description
        case ownerId = "owner_id"
        case timeframeKind = "timeframe_kind"
        case endDate = "end_date"
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
        case createdAt = "created_at"
        case joinRule = "join_rule"
        case headerUrl = "header_url"
    }
}

private nonisolated struct CircleMemberRow: Codable, Sendable {
    let circleId: UUID
    let userId: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case circleId = "circle_id"
        case userId = "user_id"
        case role
    }
}

nonisolated struct CircleTaskRow: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let circleId: UUID
    let title: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, title, position
        case circleId = "circle_id"
    }
}

nonisolated struct CircleCompletionRow: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let taskId: UUID
    let userId: String
    let completedOn: String

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case userId = "user_id"
        case completedOn = "completed_on"
    }
}

nonisolated struct CircleContributionRow: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let userId: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case id, amount
        case userId = "user_id"
    }
}

// MARK: - Insert payloads

private nonisolated struct CircleInsert: Encodable, Sendable {
    let ownerId: String
    let name: String
    let type: String
    let timeframeKind: String
    let endDate: String?
    let collectiveUnit: String?
    let collectiveTarget: Double?
    let visibility: String
    let joinRule: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case name, type, visibility, description
        case ownerId = "owner_id"
        case timeframeKind = "timeframe_kind"
        case endDate = "end_date"
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
        case joinRule = "join_rule"
    }
}

private nonisolated struct CircleMemberInsert: Encodable, Sendable {
    let circleId: String
    let userId: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case role
        case circleId = "circle_id"
        case userId = "user_id"
    }
}

private nonisolated struct CircleTaskInsert: Encodable, Sendable {
    let circleId: String
    let title: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case title, position
        case circleId = "circle_id"
    }
}

private nonisolated struct CompletionInsert: Encodable, Sendable {
    let circleId: String
    let taskId: String
    let userId: String
    let completedOn: String

    enum CodingKeys: String, CodingKey {
        case circleId = "circle_id"
        case taskId = "task_id"
        case userId = "user_id"
        case completedOn = "completed_on"
    }
}

private nonisolated struct ContributionInsert: Encodable, Sendable {
    let circleId: String
    let userId: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case amount
        case circleId = "circle_id"
        case userId = "user_id"
    }
}

private nonisolated struct CircleInvitationRow: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let inviterId: String
    let inviteeId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case circleId = "circle_id"
        case inviterId = "inviter_id"
        case inviteeId = "invitee_id"
    }
}

private nonisolated struct CircleInvitationInsert: Encodable, Sendable {
    let circleId: String
    let inviterId: String
    let inviteeId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case circleId = "circle_id"
        case inviterId = "inviter_id"
        case inviteeId = "invitee_id"
    }
}

/// A type-only mode switch — changes the circle's shape readout without
/// touching any goal data (suspend-not-delete).
private nonisolated struct CircleTypeUpdate: Encodable, Sendable {
    let type: String
}

/// A mode switch that also (re)sets the shared number's unit + target,
/// used when a shared-number layer is added.
private nonisolated struct CircleTypeNumberUpdate: Encodable, Sendable {
    let type: String
    let collectiveUnit: String?
    let collectiveTarget: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
    }
}

private nonisolated struct InvitationStatusUpdate: Encodable, Sendable {
    let status: String
    let respondedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case respondedAt = "responded_at"
    }
}

/// Owner-side edit of a circle's sharing posture: private/public, the
/// join rule for public circles, and the short directory description.
private nonisolated struct CircleSharingUpdate: Encodable, Sendable {
    let visibility: String
    let joinRule: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case visibility, description
        case joinRule = "join_rule"
    }
}

/// A role change on one `circle_members` row — the only column a
/// governance action ever writes there.
private nonisolated struct MemberRoleUpdate: Encodable, Sendable {
    let role: String
}

/// Moves `circles.owner_id`. Separate from the role rows because
/// ownership is read from the circle, not from the membership.
private nonisolated struct CircleOwnerUpdate: Encodable, Sendable {
    let ownerId: String

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
    }
}

private nonisolated struct JoinRequestInsert: Encodable, Sendable {
    let circleId: String
    let requesterId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case circleId = "circle_id"
        case requesterId = "requester_id"
    }
}

private nonisolated struct JoinRequestRow: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let requesterId: String
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case circleId = "circle_id"
        case requesterId = "requester_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct DiscoverParams: Encodable, Sendable {
    let search: String?
}

/// One row of the public-circles directory, returned by the
/// `discover_public_circles` RPC. Carries only the circle's headline
/// (name, shape, goal, member count) — never member identities or
/// anyone's personal activity.
nonisolated struct DiscoverableCircle: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: String
    let timeframeKind: String
    let endDate: String?
    let collectiveUnit: String?
    let collectiveTarget: Double?
    let description: String?
    let joinRule: String
    let memberCount: Int
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, description
        case timeframeKind = "timeframe_kind"
        case endDate = "end_date"
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
        case joinRule = "join_rule"
        case memberCount = "member_count"
        case createdAt = "created_at"
    }

    var kind: CircleKind { CircleKind(rawValue: type) ?? .parallel }
    var isOpenJoin: Bool { joinRule != "approval" }
}

// MARK: - Assembled view model

/// One circle plus everything needed to render it: resolved member
/// profiles, the task list, and the activity (completions / contributions).
/// Activity arrays are `var` so the UI can apply optimistic edits before
/// a refresh confirms them.
struct SharedCircle: Identifiable {
    let id: UUID
    let name: String
    let kind: CircleKind
    let ownerId: String
    let isOngoing: Bool
    let endDate: Date?
    let createdAt: Date?
    let collectiveUnit: String?
    let collectiveTarget: Double?
    /// 'private' (invite only, the default) or 'public' (discoverable).
    var visibility: String = "private"
    /// For public circles: 'open' (anyone joins instantly) or 'approval'.
    var joinRule: String = "open"
    /// The owner-written blurb shown in the public directory.
    var descriptionText: String?
    /// Shared header photo set by an owner/admin, shown behind the hero.
    var headerUrl: String? = nil
    let members: [RemoteProfile]
    let roles: [String: String]
    var tasks: [CircleTaskRow]
    var completions: [CircleCompletionRow]
    var contributions: [CircleContributionRow]

    var isPublic: Bool { visibility == "public" }
    var requiresApproval: Bool { isPublic && joinRule == "approval" }

    var headerURL: URL? {
        guard let headerUrl else { return nil }
        return URL(string: headerUrl)
    }

    func profile(_ userId: String) -> RemoteProfile? { members.first { $0.id == userId } }

    func role(of userId: String) -> String { roles[userId] ?? "member" }

    func canManageTasks(_ userId: String) -> Bool {
        let r = role(of: userId)
        return r == "owner" || r == "admin"
    }

    var sortedTasks: [CircleTaskRow] { tasks.sorted { $0.position < $1.position } }

    /// Member ids that completed `taskId` on the given local day.
    func completers(taskId: UUID, on dayKey: String) -> [String] {
        completions.filter { $0.taskId == taskId && $0.completedOn == dayKey }.map(\.userId)
    }

    func didComplete(taskId: UUID, userId: String, on dayKey: String) -> Bool {
        completions.contains { $0.taskId == taskId && $0.userId == userId && $0.completedOn == dayKey }
    }

    /// How many of today's tasks a member has checked off (parallel circles).
    func todayCount(userId: String, on dayKey: String) -> Int {
        let taskIds = Set(tasks.map(\.id))
        return completions.filter { $0.userId == userId && $0.completedOn == dayKey && taskIds.contains($0.taskId) }.count
    }

    var contributionTotal: Double { contributions.reduce(0) { $0 + $1.amount } }

    func contributionTotal(userId: String) -> Double {
        contributions.filter { $0.userId == userId }.reduce(0) { $0 + $1.amount }
    }

    /// 0...1 progress toward the collective target (0 when no target set).
    var collectiveFraction: Double {
        guard let target = collectiveTarget, target > 0 else { return 0 }
        return min(1, contributionTotal / target)
    }
}

/// A pending ask to join a public approval-required circle, with the
/// requester's profile resolved so the owner can act on it.
struct CircleJoinRequest: Identifiable {
    let id: UUID
    let circleId: UUID
    let requester: RemoteProfile
    let createdAt: Date?
}

/// A pending invitation to join a circle, with the circle's headline
/// details and the inviter's profile resolved for display.
struct CircleInvitation: Identifiable {
    let id: UUID
    let circleId: UUID
    let circleName: String
    let kind: CircleKind
    let collectiveUnit: String?
    let collectiveTarget: Double?
    let inviter: RemoteProfile
}

/// Why a governance action was refused before it ever reached the
/// network. RLS enforces the same rules server-side, but a denial there
/// arrives as an anonymous permission error; refusing here lets the
/// person read the actual reason.
nonisolated enum CircleGovernanceError: LocalizedError {
    case notPermitted
    case ownerNotRemovable
    case useTransfer
    case notAMember

    var errorDescription: String? {
        switch self {
        case .notPermitted: return "You don't have permission to do that in this circle."
        case .ownerNotRemovable: return "A circle's owner can't be removed."
        case .useTransfer: return "Ownership moves by transfer, not by a role change."
        case .notAMember: return "That person isn't a member of this circle."
        }
    }
}

// MARK: - Service

@Observable
@MainActor
final class CircleGraphService {
    var circles: [SharedCircle] = []
    var invitations: [CircleInvitation] = []
    /// Public circles the user isn't in — the Discover directory.
    var discovered: [DiscoverableCircle] = []
    var isDiscovering = false
    /// Circle ids the user has a pending join request for, so Discover
    /// can render "Requested" instead of the request button.
    var myPendingRequestCircleIds: Set<UUID> = []
    /// Pending join requests for the circle currently being managed.
    var joinRequests: [CircleJoinRequest] = []
    var isLoading = false
    var isWorking = false
    var errorMessage: String?
    var showError = false

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?

    /// Local-day key (yyyy-MM-dd in the device's calendar) used as the
    /// completion bucket so "today" lines up with the user's clock.
    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

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
        return plain.date(from: raw)
    }

    // MARK: Load

    /// Pull every circle the signed-in user belongs to, with members,
    /// tasks, and activity resolved in a handful of parallel round-trips.
    func load(myUserId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            await loadInvitations(myUserId: myUserId)
            let memberships: [CircleMemberRow] = try await supabase
                .from("circle_members")
                .select("circle_id, user_id, role")
                .eq("user_id", value: myUserId)
                .execute()
                .value

            let circleIds = Array(Set(memberships.map { $0.circleId.uuidString }))
            guard !circleIds.isEmpty else { circles = []; return }

            async let circleRowsReq: [CircleRow] = supabase
                .from("circles")
                .select("id, owner_id, name, type, timeframe_kind, end_date, collective_unit, collective_target, created_at, visibility, join_rule, description, header_url")
                .in("id", values: circleIds)
                .execute().value
            async let memberRowsReq: [CircleMemberRow] = supabase
                .from("circle_members")
                .select("circle_id, user_id, role")
                .in("circle_id", values: circleIds)
                .execute().value
            async let taskRowsReq: [CircleTaskRow] = supabase
                .from("circle_tasks")
                .select("id, circle_id, title, position")
                .in("circle_id", values: circleIds)
                .order("position", ascending: true)
                .execute().value
            async let completionRowsReq: [CircleCompletionWire] = supabase
                .from("circle_task_completions")
                .select("id, circle_id, task_id, user_id, completed_on")
                .in("circle_id", values: circleIds)
                .execute().value
            async let contributionRowsReq: [CircleContributionWire] = supabase
                .from("circle_contributions")
                .select("id, circle_id, user_id, amount")
                .in("circle_id", values: circleIds)
                .execute().value

            let circleRows = try await circleRowsReq
            let memberRows = try await memberRowsReq
            let taskRows = try await taskRowsReq
            let completionRows = try await completionRowsReq
            let contributionRows = try await contributionRowsReq

            let profilesById = try await fetchProfiles(ids: Array(Set(memberRows.map { $0.userId })))

            circles = circleRows.map { row in
                let cid = row.id
                let memberRowsForCircle = memberRows.filter { $0.circleId == cid }
                var roles: [String: String] = [:]
                for m in memberRowsForCircle { roles[m.userId] = m.role }
                let memberProfiles = memberRowsForCircle.compactMap { profilesById[$0.userId] }

                return SharedCircle(
                    id: cid,
                    name: row.name,
                    kind: CircleKind(rawValue: row.type) ?? .parallel,
                    ownerId: row.ownerId,
                    isOngoing: row.timeframeKind != "time_boxed",
                    endDate: Self.parseDate(row.endDate),
                    createdAt: Self.parseDate(row.createdAt),
                    collectiveUnit: row.collectiveUnit,
                    collectiveTarget: row.collectiveTarget,
                    visibility: row.visibility ?? "private",
                    joinRule: row.joinRule ?? "open",
                    descriptionText: row.description,
                    headerUrl: row.headerUrl,
                    members: memberProfiles.sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    },
                    roles: roles,
                    tasks: taskRows.filter { $0.circleId == cid }.map { CircleTaskRow(id: $0.id, circleId: $0.circleId, title: $0.title, position: $0.position) },
                    completions: completionRows.filter { $0.circleId == cid }.map { $0.model },
                    contributions: contributionRows.filter { $0.circleId == cid }.map { $0.model }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            fail("Couldn't load your circles.", error)
        }
    }

    // MARK: Create

    /// Create a circle owned by the current user, seed its members from
    /// real friends, and (for parallel circles) its shared task list.
    @discardableResult
    func createCircle(
        name: String,
        kind: CircleKind,
        isOngoing: Bool,
        endDate: Date?,
        taskTitles: [String],
        collectiveUnit: String?,
        collectiveTarget: Double?,
        memberIds: [String],
        myUserId: String,
        visibility: String = "private",
        joinRule: String = "open",
        description: String? = nil
    ) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created: CircleRow = try await supabase
                .from("circles")
                .insert(CircleInsert(
                    ownerId: myUserId,
                    name: trimmedName.isEmpty ? "New circle" : trimmedName,
                    type: kind.rawValue,
                    timeframeKind: isOngoing ? "ongoing" : "time_boxed",
                    endDate: isOngoing ? nil : endDate.map(Self.isoString),
                    collectiveUnit: kind == .collective ? collectiveUnit?.trimmedNonEmpty : nil,
                    collectiveTarget: kind == .collective ? collectiveTarget : nil,
                    visibility: visibility,
                    joinRule: joinRule,
                    description: description?.trimmedNonEmpty
                ))
                .select("id, owner_id, name, type, timeframe_kind, end_date, collective_unit, collective_target")
                .single()
                .execute()
                .value

            let cid = created.id.uuidString

            try await supabase
                .from("circle_members")
                .insert(CircleMemberInsert(circleId: cid, userId: myUserId, role: "owner"))
                .execute()

            // Friends are invited, not silently enrolled — they opt in.
            let others = memberIds.filter { $0 != myUserId }
            if !others.isEmpty {
                let rows = others.map {
                    CircleInvitationInsert(circleId: cid, inviterId: myUserId, inviteeId: $0, status: "pending")
                }
                try await supabase.from("circle_invitations").insert(rows).execute()
                for inviteeId in others {
                    PushService.send(to: inviteeId, kind: .circleInvite, circleId: cid)
                }
            }

            if kind == .parallel {
                let titles = taskTitles
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !titles.isEmpty {
                    let rows = titles.enumerated().map { CircleTaskInsert(circleId: cid, title: $1, position: $0) }
                    try await supabase.from("circle_tasks").insert(rows).execute()
                }
            }

            await load(myUserId: myUserId)
            return true
        } catch {
            fail("Couldn't create the circle.", error)
            return false
        }
    }

    // MARK: Tasks

    /// Add a task to a parallel circle (owner / admin only — enforced by RLS).
    func addTask(circleId: UUID, title: String, myUserId: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextPosition = circles.first { $0.id == circleId }?.tasks.count ?? 0
        do {
            try await supabase
                .from("circle_tasks")
                .insert(CircleTaskInsert(circleId: circleId.uuidString, title: trimmed, position: nextPosition))
                .execute()
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't add the task.", error)
        }
    }

    // MARK: Completions

    /// Toggle the current user's completion of a task for today. Applies an
    /// optimistic local edit, then writes through; a failure reloads to undo.
    func setCompletion(circleId: UUID, taskId: UUID, completed: Bool, myUserId: String) async {
        let dayKey = Self.dayKey()
        applyOptimisticCompletion(circleId: circleId, taskId: taskId, userId: myUserId, dayKey: dayKey, completed: completed)
        do {
            if completed {
                try await supabase
                    .from("circle_task_completions")
                    .insert(CompletionInsert(circleId: circleId.uuidString, taskId: taskId.uuidString, userId: myUserId, completedOn: dayKey))
                    .execute()
                let taskTitle = circles.first(where: { $0.id == circleId })?.tasks.first(where: { $0.id == taskId })?.title
                notifyCircleMembers(circleId: circleId, kind: .circleTask, preview: taskTitle, myUserId: myUserId)
            } else {
                try await supabase
                    .from("circle_task_completions")
                    .delete()
                    .eq("task_id", value: taskId.uuidString)
                    .eq("user_id", value: myUserId)
                    .eq("completed_on", value: dayKey)
                    .execute()
            }
        } catch {
            fail("Couldn't update your progress.", error)
            await load(myUserId: myUserId)
        }
    }

    private func applyOptimisticCompletion(circleId: UUID, taskId: UUID, userId: String, dayKey: String, completed: Bool) {
        guard let idx = circles.firstIndex(where: { $0.id == circleId }) else { return }
        if completed {
            guard !circles[idx].didComplete(taskId: taskId, userId: userId, on: dayKey) else { return }
            circles[idx].completions.append(
                CircleCompletionRow(id: UUID(), taskId: taskId, userId: userId, completedOn: dayKey)
            )
        } else {
            circles[idx].completions.removeAll {
                $0.taskId == taskId && $0.userId == userId && $0.completedOn == dayKey
            }
        }
    }

    // MARK: Contributions

    /// Log a contribution toward a collective circle's target.
    func addContribution(circleId: UUID, amount: Double, myUserId: String) async {
        guard amount > 0 else { return }
        if let idx = circles.firstIndex(where: { $0.id == circleId }) {
            circles[idx].contributions.append(CircleContributionRow(id: UUID(), userId: myUserId, amount: amount))
        }
        do {
            try await supabase
                .from("circle_contributions")
                .insert(ContributionInsert(circleId: circleId.uuidString, userId: myUserId, amount: amount))
                .execute()
            notifyCircleMembers(circleId: circleId, kind: .circleProgress, preview: nil, myUserId: myUserId)
        } catch {
            fail("Couldn't log your contribution.", error)
            await load(myUserId: myUserId)
        }
    }

    // MARK: Mode switching (CR2)

    /// Switch a circle's mode by changing which objective layers are
    /// active — owner/admin only (RLS enforces it server-side). Crucially
    /// this is suspend-not-delete: only the circle's `type` readout (and,
    /// when a number is being added, its unit + target) is written. Tasks,
    /// completions, and contributions are never touched, so a layer set
    /// aside goes dormant and resumes intact when re-added. Every member
    /// is notified of the switch.
    func setCircleKind(
        circleId: UUID,
        kind: CircleKind,
        unit: String? = nil,
        target: Double? = nil,
        myUserId: String
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if kind.hasSharedNumber, let target, target > 0 {
                try await supabase
                    .from("circles")
                    .update(CircleTypeNumberUpdate(
                        type: kind.rawValue,
                        collectiveUnit: unit?.trimmedNonEmpty,
                        collectiveTarget: target
                    ))
                    .eq("id", value: circleId.uuidString)
                    .execute()
            } else {
                try await supabase
                    .from("circles")
                    .update(CircleTypeUpdate(type: kind.rawValue))
                    .eq("id", value: circleId.uuidString)
                    .execute()
            }
            notifyCircleMembers(circleId: circleId, kind: .circleMode, preview: nil, myUserId: myUserId)
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't switch the circle's mode.", error)
        }
    }

    // MARK: Membership

    /// Leave a circle. The owner can't simply leave — they delete instead.
    func leaveCircle(_ circleId: UUID, myUserId: String) async {
        do {
            try await supabase
                .from("circle_members")
                .delete()
                .eq("circle_id", value: circleId.uuidString)
                .eq("user_id", value: myUserId)
                .execute()
            circles.removeAll { $0.id == circleId }
        } catch {
            fail("Couldn't leave the circle.", error)
        }
    }

    /// Delete a circle entirely (owner only — enforced by RLS). Cascades to
    /// members, tasks, completions, and contributions.
    func deleteCircle(_ circleId: UUID) async {
        do {
            try await supabase
                .from("circles")
                .delete()
                .eq("id", value: circleId.uuidString)
                .execute()
            circles.removeAll { $0.id == circleId }
        } catch {
            fail("Couldn't delete the circle.", error)
        }
    }

    // MARK: Governance
    //
    // Roles and membership are the one part of a circle where a local-only
    // edit is worse than no edit at all: `circle_members` is the table RLS
    // reads, so a member who is only removed on the device keeps every bit
    // of their access and simply reappears on the next refresh. These
    // three write to the server and reload from it.
    //
    // Each one re-reads the circle's roles first and refuses what it isn't
    // allowed to do. RLS refuses the same things, but it answers with an
    // anonymous permission error; checking here means the person is told
    // which rule stopped them.

    /// Remove a member. Owner or admin only, an admin can remove plain
    /// members but not another admin, and the owner can't be removed by
    /// anyone — ownership is handed on first. Their completions and
    /// contributions stay behind as history; only the membership goes.
    func removeMember(circleId: UUID, userId: String, myUserId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let roles = try await memberRoles(circleId: circleId)
            let mine = roles[myUserId] ?? "member"
            let theirs = roles[userId] ?? "member"
            guard mine == "owner" || mine == "admin" else {
                fail("Only the circle's owner or an admin can remove someone.", CircleGovernanceError.notPermitted)
                return
            }
            guard theirs != "owner" else {
                fail("The owner can't be removed — transfer ownership first.", CircleGovernanceError.ownerNotRemovable)
                return
            }
            guard mine == "owner" || theirs == "member" else {
                fail("Only the owner can remove an admin.", CircleGovernanceError.notPermitted)
                return
            }
            try await supabase
                .from("circle_members")
                .delete()
                .eq("circle_id", value: circleId.uuidString)
                .eq("user_id", value: userId)
                .execute()
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't remove them from the circle.", error)
        }
    }

    /// Promote a member to admin, or demote an admin back to member.
    /// Owner-only. Ownership deliberately can't be handed over this way —
    /// it also has to move `circles.owner_id`, which `transferOwnership`
    /// does in one piece.
    func setRole(circleId: UUID, userId: String, role: CircleRole, myUserId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let roles = try await memberRoles(circleId: circleId)
            guard (roles[myUserId] ?? "member") == "owner" else {
                fail("Only the circle's owner can change roles.", CircleGovernanceError.notPermitted)
                return
            }
            guard role != .owner else {
                fail("Ownership moves by transfer, not by a role change.", CircleGovernanceError.useTransfer)
                return
            }
            guard let theirs = roles[userId] else {
                fail("They're not a member of this circle.", CircleGovernanceError.notAMember)
                return
            }
            guard theirs != "owner" else {
                fail("The owner's role can't be changed — transfer ownership first.", CircleGovernanceError.ownerNotRemovable)
                return
            }
            try await supabase
                .from("circle_members")
                .update(MemberRoleUpdate(role: role.rawValue))
                .eq("circle_id", value: circleId.uuidString)
                .eq("user_id", value: userId)
                .execute()
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't update their role.", error)
        }
    }

    /// Hand the circle to another member. Owner-only. Three rows move: the
    /// new owner's role, the outgoing owner's demotion to plain member, and
    /// `circles.owner_id`.
    ///
    /// `owner_id` is written last on purpose. It's both the column every
    /// surface reads ownership from and the one RLS grants owner authority
    /// by, so flipping it first would revoke the permission needed for the
    /// two role writes still to come. Written last, a failure part-way
    /// leaves the circle still owned by whoever started the transfer rather
    /// than owned by nobody.
    func transferOwnership(circleId: UUID, toUserId: String, myUserId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let roles = try await memberRoles(circleId: circleId)
            guard (roles[myUserId] ?? "member") == "owner" else {
                fail("Only the circle's owner can hand it on.", CircleGovernanceError.notPermitted)
                return
            }
            guard toUserId != myUserId, roles[toUserId] != nil else {
                fail("Ownership can only pass to another member.", CircleGovernanceError.notAMember)
                return
            }
            try await supabase
                .from("circle_members")
                .update(MemberRoleUpdate(role: "owner"))
                .eq("circle_id", value: circleId.uuidString)
                .eq("user_id", value: toUserId)
                .execute()
            try await supabase
                .from("circle_members")
                .update(MemberRoleUpdate(role: "member"))
                .eq("circle_id", value: circleId.uuidString)
                .eq("user_id", value: myUserId)
                .execute()
            try await supabase
                .from("circles")
                .update(CircleOwnerUpdate(ownerId: toUserId))
                .eq("id", value: circleId.uuidString)
                .execute()
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't transfer ownership.", error)
        }
    }

    /// The `profiles.id` → role map for one circle. Prefers the loaded
    /// copy and falls back to a small read, because governance is driven
    /// from the settings sheet, whose service instance has never run a
    /// full `load`.
    private func memberRoles(circleId: UUID) async throws -> [String: String] {
        if let circle = circles.first(where: { $0.id == circleId }) { return circle.roles }
        let rows: [CircleMemberRow] = try await supabase
            .from("circle_members")
            .select("circle_id, user_id, role")
            .eq("circle_id", value: circleId.uuidString)
            .execute()
            .value
        return Dictionary(rows.map { ($0.userId, $0.role) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Invitations

    /// Pending invitations addressed to the signed-in user, with each
    /// circle's headline details and the inviter's profile resolved.
    func loadInvitations(myUserId: String) async {
        do {
            let rows: [CircleInvitationRow] = try await supabase
                .from("circle_invitations")
                .select("id, circle_id, inviter_id, invitee_id, status")
                .eq("invitee_id", value: myUserId)
                .eq("status", value: "pending")
                .execute()
                .value
            guard !rows.isEmpty else { invitations = []; return }

            let circleIds = Array(Set(rows.map { $0.circleId.uuidString }))
            async let circleRowsReq: [CircleRow] = supabase
                .from("circles")
                .select("id, owner_id, name, type, timeframe_kind, end_date, collective_unit, collective_target")
                .in("id", values: circleIds)
                .execute().value
            let inviterProfiles = try await fetchProfiles(ids: Array(Set(rows.map { $0.inviterId })))
            let circleRows = try await circleRowsReq
            let circleById = Dictionary(circleRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            invitations = rows.compactMap { row in
                guard let circle = circleById[row.circleId],
                      let inviter = inviterProfiles[row.inviterId] else { return nil }
                return CircleInvitation(
                    id: row.id,
                    circleId: row.circleId,
                    circleName: circle.name,
                    kind: CircleKind(rawValue: circle.type) ?? .parallel,
                    collectiveUnit: circle.collectiveUnit,
                    collectiveTarget: circle.collectiveTarget,
                    inviter: inviter
                )
            }
            .sorted { $0.circleName.localizedCaseInsensitiveCompare($1.circleName) == .orderedAscending }
        } catch {
            print("[CircleGraph] loadInvitations failed: \(error)")
        }
    }

    /// Invite more friends to an existing circle (idempotent — re-inviting
    /// someone who declined simply resets their invite to pending).
    func inviteMembers(circleId: UUID, inviteeIds: [String], myUserId: String) async {
        let others = inviteeIds.filter { $0 != myUserId }
        guard !others.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let rows = others.map {
                CircleInvitationInsert(circleId: circleId.uuidString, inviterId: myUserId, inviteeId: $0, status: "pending")
            }
            try await supabase
                .from("circle_invitations")
                .upsert(rows, onConflict: "circle_id,invitee_id")
                .execute()
            for inviteeId in others {
                PushService.send(to: inviteeId, kind: .circleInvite, circleId: circleId.uuidString)
            }
        } catch {
            fail("Couldn't send the invites.", error)
        }
    }

    /// Accept an invitation: join the circle (RLS allows a self-insert
    /// while the invitation is pending), then stamp it accepted.
    func acceptInvitation(_ invitation: CircleInvitation, myUserId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabase
                .from("circle_members")
                .insert(CircleMemberInsert(circleId: invitation.circleId.uuidString, userId: myUserId, role: "member"))
                .execute()
            try await supabase
                .from("circle_invitations")
                .update(InvitationStatusUpdate(status: "accepted", respondedAt: Self.isoString(Date())))
                .eq("id", value: invitation.id.uuidString)
                .execute()
            invitations.removeAll { $0.id == invitation.id }
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't join the circle.", error)
        }
    }

    /// Decline an invitation — it leaves your inbox and you never join.
    func declineInvitation(_ invitation: CircleInvitation, myUserId: String) async {
        do {
            try await supabase
                .from("circle_invitations")
                .update(InvitationStatusUpdate(status: "declined", respondedAt: Self.isoString(Date())))
                .eq("id", value: invitation.id.uuidString)
                .execute()
            invitations.removeAll { $0.id == invitation.id }
        } catch {
            fail("Couldn't decline the invite.", error)
        }
    }

    // MARK: Public circles (Discover)

    /// Load the public directory — circles the user is NOT in, with
    /// member counts resolved server-side. `search` filters by name or
    /// description.
    func loadDiscover(search: String? = nil, myUserId: String) async {
        isDiscovering = true
        defer { isDiscovering = false }
        do {
            let rows: [DiscoverableCircle] = try await supabase
                .rpc("discover_public_circles", params: DiscoverParams(search: search?.trimmedNonEmpty))
                .execute()
                .value
            discovered = rows
            await loadMyPendingRequests(myUserId: myUserId)
        } catch {
            fail("Couldn't load public circles.", error)
        }
    }

    /// Circle ids with a pending join request from the signed-in user.
    func loadMyPendingRequests(myUserId: String) async {
        do {
            let rows: [JoinRequestRow] = try await supabase
                .from("circle_join_requests")
                .select("id, circle_id, requester_id, status, created_at")
                .eq("requester_id", value: myUserId)
                .eq("status", value: "pending")
                .execute()
                .value
            myPendingRequestCircleIds = Set(rows.map { $0.circleId })
        } catch {
            print("[CircleGraph] loadMyPendingRequests failed: \(error)")
        }
    }

    /// Join an open public circle instantly (RLS verifies the circle is
    /// public + open). On success the circle lands in `circles`.
    @discardableResult
    func joinPublicCircle(circleId: UUID, myUserId: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabase
                .from("circle_members")
                .insert(CircleMemberInsert(circleId: circleId.uuidString, userId: myUserId, role: "member"))
                .execute()
            discovered.removeAll { $0.id == circleId }
            await load(myUserId: myUserId)
            return true
        } catch {
            fail("Couldn't join the circle.", error)
            return false
        }
    }

    /// Ask to join an approval-required public circle. Idempotent — a
    /// re-request resets any earlier declined ask back to pending.
    @discardableResult
    func requestToJoin(circleId: UUID, myUserId: String) async -> Bool {
        do {
            try await supabase
                .from("circle_join_requests")
                .upsert(
                    JoinRequestInsert(circleId: circleId.uuidString, requesterId: myUserId, status: "pending"),
                    onConflict: "circle_id,requester_id"
                )
                .execute()
            myPendingRequestCircleIds.insert(circleId)
            return true
        } catch {
            fail("Couldn't send your request.", error)
            return false
        }
    }

    /// Pending join requests for a circle, with requester profiles
    /// resolved (owner/admin only — RLS scopes the read).
    func loadJoinRequests(circleId: UUID) async {
        do {
            let rows: [JoinRequestRow] = try await supabase
                .from("circle_join_requests")
                .select("id, circle_id, requester_id, status, created_at")
                .eq("circle_id", value: circleId.uuidString)
                .eq("status", value: "pending")
                .order("created_at", ascending: true)
                .execute()
                .value
            guard !rows.isEmpty else {
                joinRequests.removeAll { $0.circleId == circleId }
                return
            }
            let profiles = try await fetchProfiles(ids: Array(Set(rows.map { $0.requesterId })))
            let resolved: [CircleJoinRequest] = rows.compactMap { row in
                guard let profile = profiles[row.requesterId] else { return nil }
                return CircleJoinRequest(
                    id: row.id,
                    circleId: row.circleId,
                    requester: profile,
                    createdAt: Self.parseDate(row.createdAt)
                )
            }
            joinRequests.removeAll { $0.circleId == circleId }
            joinRequests.append(contentsOf: resolved)
        } catch {
            print("[CircleGraph] loadJoinRequests failed: \(error)")
        }
    }

    /// Approve a join request: add them as a member, stamp the request.
    func approveJoinRequest(_ request: CircleJoinRequest, myUserId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabase
                .from("circle_members")
                .insert(CircleMemberInsert(circleId: request.circleId.uuidString, userId: request.requester.id, role: "member"))
                .execute()
            try await supabase
                .from("circle_join_requests")
                .update(InvitationStatusUpdate(status: "approved", respondedAt: Self.isoString(Date())))
                .eq("id", value: request.id.uuidString)
                .execute()
            joinRequests.removeAll { $0.id == request.id }
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't approve the request.", error)
        }
    }

    /// Decline a join request — the asker can re-request later.
    func declineJoinRequest(_ request: CircleJoinRequest) async {
        do {
            try await supabase
                .from("circle_join_requests")
                .update(InvitationStatusUpdate(status: "declined", respondedAt: Self.isoString(Date())))
                .eq("id", value: request.id.uuidString)
                .execute()
            joinRequests.removeAll { $0.id == request.id }
        } catch {
            fail("Couldn't decline the request.", error)
        }
    }

    /// Owner-side sharing edit: flip private/public, set the join rule,
    /// and write the directory description.
    func updateCircleSharing(
        circleId: UUID,
        visibility: String,
        joinRule: String,
        description: String?,
        myUserId: String
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await supabase
                .from("circles")
                .update(CircleSharingUpdate(
                    visibility: visibility,
                    joinRule: joinRule,
                    description: description?.trimmedNonEmpty
                ))
                .eq("id", value: circleId.uuidString)
                .execute()
            await load(myUserId: myUserId)
        } catch {
            fail("Couldn't update sharing.", error)
        }
    }

    // MARK: Realtime

    /// Subscribe to live changes across every table that shapes a circle
    /// (members, tasks, completions, contributions, and the circle row
    /// itself). Any RLS-visible change triggers a reload, so a partner's
    /// check-off or logged contribution animates in without a manual
    /// refresh. Idempotent — a second call is a no-op.
    func startRealtime(myUserId: String) {
        guard channel == nil else { return }
        let ch = supabase.channel("circles-\(myUserId)")
        let tables = ["circles", "circle_members", "circle_tasks", "circle_task_completions", "circle_contributions", "circle_invitations"]
        let streams = tables.map { ch.postgresChange(AnyAction.self, schema: "public", table: $0) }
        channel = ch
        realtimeTask = Task { [weak self] in
            // Authorize the socket with the Rork Auth JWT so RLS-scoped
            // changes are delivered to this user.
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

    /// Tear down the realtime subscription. Call when the circles surface
    /// goes away.
    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = channel {
            Task { await supabase.removeChannel(ch) }
        }
        channel = nil
    }

    // MARK: Helpers

    /// Fan out a push to every member of a circle except the actor — the
    /// live co-op nudges (a check-off, a logged contribution). Copy is
    /// built server-side; we supply the kind, the circle, and an optional
    /// preview (e.g. the task title).
    private func notifyCircleMembers(circleId: UUID, kind: PushKind, preview: String?, myUserId: String) {
        guard let circle = circles.first(where: { $0.id == circleId }) else { return }
        for recipientId in circle.members.map(\.id) where recipientId != myUserId {
            PushService.send(to: recipientId, kind: kind, circleId: circleId.uuidString, preview: preview)
        }
    }

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
        print("[CircleGraph] \(message) \(error)")
        errorMessage = message
        showError = true
    }
}

// MARK: - Activity wire rows
//
// Completions and contributions carry `circle_id` only so `load` can bucket
// them by circle; the assembled `SharedCircle` drops it via `.model`.

private nonisolated struct CircleCompletionWire: Codable, Sendable {
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

    var model: CircleCompletionRow {
        CircleCompletionRow(id: id, taskId: taskId, userId: userId, completedOn: completedOn)
    }
}

private nonisolated struct CircleContributionWire: Codable, Sendable {
    let id: UUID
    let circleId: UUID
    let userId: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case id, amount
        case circleId = "circle_id"
        case userId = "user_id"
    }

    var model: CircleContributionRow {
        CircleContributionRow(id: id, userId: userId, amount: amount)
    }
}

// MARK: - Small utilities

private extension String {
    /// The trimmed string, or nil when it's empty after trimming.
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
