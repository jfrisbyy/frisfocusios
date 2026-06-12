//
//  FocusTaskAttachment.swift
//  FrisFocus
//
//  Tasks attached to a focus session. Each attachment links a personal
//  to-do and carries a `shared` flag: shared tasks are visible to the
//  friends in a grove session (with live check-off), private ones stay
//  just for you. Completion itself flows through the normal task log —
//  an attachment never auto-completes; you check it off yourself.
//

import Foundation

/// Whether an attachment points at a pinned Task or a dated To-do.
/// Both flow through the same attachment so the focus task strip can mix
/// them freely.
enum FocusItemKind: String, Codable, Hashable {
    case task
    case todo
}

/// One personal item (Task or To-do) attached to a focus session. Each
/// attachment links a personal item and carries a `shared` flag: shared
/// items are visible to the friends in a grove session (with live
/// check-off), private ones stay just for you.
struct FocusTaskAttachment: Codable, Hashable, Identifiable {
    /// The id of the linked Task or To-do (`kind` disambiguates).
    var taskId: UUID
    /// When true, this item is published to the grove so friends can see
    /// it and your live progress. Always false for solo sessions.
    var shared: Bool = false
    /// Whether `taskId` references a Task or a To-do. Defaults to `.task`
    /// so attachments persisted before To-do support still decode.
    var kind: FocusItemKind = .task

    var id: UUID { taskId }

    init(taskId: UUID, shared: Bool = false, kind: FocusItemKind = .task) {
        self.taskId = taskId
        self.shared = shared
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case taskId, shared, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.taskId = try c.decode(UUID.self, forKey: .taskId)
        self.shared = try c.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        self.kind = try c.decodeIfPresent(FocusItemKind.self, forKey: .kind) ?? .task
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(taskId, forKey: .taskId)
        try c.encode(shared, forKey: .shared)
        try c.encode(kind, forKey: .kind)
    }
}

/// A friend's shared task as it appears in the grove's task panel.
/// Built from the live sync rows; `done` updates as they check it off.
struct GroveSharedTask: Identifiable, Hashable {
    var userId: UUID
    var taskId: UUID
    var title: String
    var done: Bool

    var id: String { "\(userId.uuidString):\(taskId.uuidString)" }
}
