//
//  FocusActivityAttributes.swift
//  FrisFocusWidget
//
//  F3 — Shared ActivityKit attributes for the focus-block Live Activity.
//  Duplicated verbatim in the app target. Keep the two copies in sync;
//  ActivityKit identifies activities by attribute type name + module,
//  but the payload layout must match on both sides.
//

import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date
        var plannedDuration: TimeInterval
        var leavesFallen: Int
        var canopyTotal: Int
    }

    var label: String?
}
