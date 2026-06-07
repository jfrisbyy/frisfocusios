//
//  FocusModels.swift
//  FrisFocus
//
//  F1 — Focus Block (solo) data model. A focus session blocks nothing;
//  it holds the user accountable by recording whether they stayed in
//  the app for the planned duration. Each real "leave" (app switch /
//  home screen) appends a `FocusLeave` and drops a canopy leaf in the
//  visual scene. Locking / sleeping the phone is *not* a leave.
//

import Foundation

/// One recorded "left the app" event during a focus session. `awaySeconds`
/// is filled in when the user returns; an open leave (`nil`) means the
/// user is currently away.
struct FocusLeave: Codable, Hashable {
    var leftAt: Date
    var awaySeconds: TimeInterval?
}

/// A single focus block. Runs on wall-clock time
/// (`startedAt + plannedDuration`), so locking the device doesn't
/// desync the timer. Persists to focus history on completion.
struct FocusSession: Identifiable, Codable {
    var id: UUID = UUID()
    var label: String?
    var startedAt: Date
    var plannedDuration: TimeInterval
    var endedAt: Date?
    var leaves: [FocusLeave] = []
    var linkedTaskId: UUID?

    /// A clean block has no real leaves — the only way to keep every
    /// canopy leaf. Clean blocks also credit a linked task.
    var clean: Bool { leaves.isEmpty }

    /// Total seconds away from the app across every recorded leave.
    /// Open leaves (without an `awaySeconds`) don't count yet.
    var totalAwaySeconds: TimeInterval {
        leaves.reduce(0) { $0 + ($1.awaySeconds ?? 0) }
    }
}
