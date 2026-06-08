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
    case parallel
    case collective
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

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case ownerId = "owner_id"
        case timeframeKind = "timeframe_kind"
        case endDate = "end_date"
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
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

    enum CodingKeys: String, CodingKey {
        case name, type
        case ownerId = "owner_id"
        case timeframeKind = "timeframe_kind"
        case endDate = "end_date"
        case collectiveUnit = "collective_unit"
        case collectiveTarget = "collective_target"
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
    let collectiveUnit: String?
    let collectiveTarget: Double?
    let members: [RemoteProfile]
    let roles: [String: String]
    var tasks: [CircleTaskRow]
    var completions: [CircleCompletionRow]
    var contributions: [CircleContributionRow]

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

// MARK: - Service

@Observable
@MainActor
final class CircleGraphService {
    var circles: [SharedCircle] = []
    var isLoading = false
    var isWorking = false
    var errorMessage: String?
    var showError = false

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
                .select("id, owner_id, name, type, timeframe_kind, end_date, collective_unit, collective_target")
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
                    collectiveUnit: row.collectiveUnit,
                    collectiveTarget: row.collectiveTarget,
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
        myUserId: String
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
                    collectiveTarget: kind == .collective ? collectiveTarget : nil
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

            let others = memberIds.filter { $0 != myUserId }
            if !others.isEmpty {
                let rows = others.map { CircleMemberInsert(circleId: cid, userId: $0, role: "member") }
                try await supabase.from("circle_members").insert(rows).execute()
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
        } catch {
            fail("Couldn't log your contribution.", error)
            await load(myUserId: myUserId)
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

    // MARK: Helpers

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
