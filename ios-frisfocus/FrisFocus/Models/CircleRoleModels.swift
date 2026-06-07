//
//  CircleRoleModels.swift
//  FrisFocus
//
//  Light role model + opt-in governance for circles (C11).
//
//  Roles are additive to the existing FFCircle membership: the
//  creator is `owner`, anyone they promote is `admin`, and everyone
//  else stays a flat `member`. A friend circle that never touches
//  these controls behaves exactly as it did before — no role chips,
//  no approval queue, no extra friction.
//
//  Governance (`membersCanProposeTasks`) is the curated-circle mode:
//  when on, member-initiated shared-task changes become pending
//  `CircleTaskRequest`s for owner/admin review. When off (the
//  default), task edits from anyone with permission apply directly.
//

import Foundation

/// A member's role inside a circle. Roles are additive metadata on
/// the existing `FFCircle.memberIds` roster — never a replacement.
enum CircleRole: String, Codable, CaseIterable, Equatable {
    case owner
    case admin
    case member
}

/// What a `CircleTaskRequest` proposes — adding a new shared task,
/// editing an existing one, or removing one from the circle.
enum CircleRequestType: String, Codable, Equatable {
    case add
    case edit
    case delete
}

/// Lifecycle of a `CircleTaskRequest`. Approved/rejected requests
/// linger in the store so the requester can see the outcome and the
/// reviewer has an audit trail.
enum CircleRequestStatus: String, Codable, Equatable {
    case pending
    case approved
    case rejected
}

/// Proposed fields for a shared circle task. Mirrors the editable
/// subset of `CircleTask` so an `add` or `edit` request can carry a
/// full draft without needing the live `CircleTask` to exist yet.
struct CircleTaskDraft: Codable, Equatable {
    var title: String
    var pointValue: Int?
    var linkedPersonalTaskId: UUID?

    init(
        title: String,
        pointValue: Int? = nil,
        linkedPersonalTaskId: UUID? = nil
    ) {
        self.title = title
        self.pointValue = pointValue
        self.linkedPersonalTaskId = linkedPersonalTaskId
    }

    /// Construct a draft from an existing task — used when seeding the
    /// edit form so the request body starts pre-populated.
    init(from task: CircleTask) {
        self.title = task.title
        self.pointValue = task.pointValue
        self.linkedPersonalTaskId = task.linkedPersonalTaskId
    }
}

/// A member-initiated proposal to mutate a circle's shared task
/// list. Only created when the circle's `membersCanProposeTasks`
/// toggle is on AND the requester isn't already a curator
/// (owner/admin). Approve applies the change to the live circle and
/// records `reviewedById`/`reviewedAt`; reject just records the
/// rejection.
struct CircleTaskRequest: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var circleId: UUID
    var requesterId: UUID
    var type: CircleRequestType
    var taskData: CircleTaskDraft
    /// Target task id for `.edit` / `.delete` requests. `nil` for `.add`.
    var existingTaskId: UUID?
    var status: CircleRequestStatus = .pending
    var reviewedById: UUID?
    var reviewedAt: Date?
    var createdAt: Date = Date()
}
