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

/// One personal task attached to a focus session.
struct FocusTaskAttachment: Codable, Hashable, Identifiable {
    var taskId: UUID
    /// When true, this task is published to the grove so friends can see
    /// it and your live progress. Always false for solo sessions.
    var shared: Bool = false

    var id: UUID { taskId }
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
