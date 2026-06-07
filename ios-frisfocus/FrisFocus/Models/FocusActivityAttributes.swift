//
//  FocusActivityAttributes.swift
//  FrisFocus
//
//  F3 — Shared ActivityKit attributes for the focus-block Live Activity.
//  Lives in both the app target and the widget extension target so the
//  same type identifies the activity on both sides. Keep this file
//  pure data (no Theme, no app-only imports) so the widget can compile it.
//

import ActivityKit
import Foundation

/// Static attributes for a focus-block Live Activity. The dynamic
/// state lives in ``FocusActivityAttributes/ContentState``.
struct FocusActivityAttributes: ActivityAttributes {
    /// Per-tick state pushed from the app. Compact on purpose — the
    /// system limits Live Activity payload size.
    public struct ContentState: Codable, Hashable {
        /// Wall-clock anchor; remaining time = `startedAt + plannedDuration - now`.
        var startedAt: Date
        /// Total planned length in seconds.
        var plannedDuration: TimeInterval
        /// Real leaves fallen so far this session.
        var leavesFallen: Int
        /// Total canopy size so the widget can render the right
        /// fullness without hard-coding it.
        var canopyTotal: Int
    }

    /// Optional eyebrow label (e.g. "Deep work"). Static for the
    /// life of the activity — relabeling means a new session.
    var label: String?
}
