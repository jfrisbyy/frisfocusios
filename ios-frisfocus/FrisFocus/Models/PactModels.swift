//
//  PactModels.swift
//  FrisFocus
//
//  A pact is the witness-model reframe of a 1v1: two people commit to
//  the same thing for a set window, both see each other's progress,
//  both finish. There is deliberately no winner field and no ranking —
//  symmetric mutual visibility is the point.
//
//  Pure data, Codable, no UI dependencies. Reuses the circle-style
//  bridging (`linkedPersonalTaskId`) so a pact task can complete a
//  personal `FFTask` and vice-versa.
//

import Foundation

/// Lifecycle of a pact. A pact stays `.pending` until the partner
/// accepts, at which point both `startDate` and `endDate` get stamped
/// and it flips to `.active`. `.completed` is set at window close;
/// `.declined` is terminal.
enum PactStatus: String, Codable {
    case pending, active, completed, declined
}

/// A shared task inside a pact. Mirrors `CircleTask`'s linking model
/// so completing a pact task can mirror into a personal `FFTask`.
struct PactTask: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: Category?
    var linkedPersonalTaskId: UUID?
}

/// A two-person commitment to the same task(s) over a set window.
/// There is no winner — progress is each person's count of pact-task
/// completions across the window. Both bars are surfaced together for
/// mutual visibility, not for ranking.
struct Pact: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var proposerId: UUID
    var partnerId: UUID
    var tasks: [PactTask]
    /// Duration chosen at propose time, in days. Window dates are
    /// finalized to `startDate` ... `startDate + durationDays` on
    /// acceptance.
    var durationDays: Int
    var startDate: Date?
    var endDate: Date?
    var status: PactStatus = .pending
    var createdAt: Date = Date()
}

/// One completion of one pact task on one local day by one person.
/// Progress = count of these per user within the window.
struct PactCompletion: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var pactId: UUID
    var taskId: UUID
    var userId: UUID
    var date: Date
}
