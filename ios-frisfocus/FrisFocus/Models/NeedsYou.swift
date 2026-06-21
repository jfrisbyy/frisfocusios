//
//  NeedsYou.swift
//  FrisFocus
//
//  Data types for the smart "Needs You" triage surface. A single ranked
//  list of cross-type candidates (open tasks, penalty routines, category
//  drift) replaces the old fixed-bucket concatenation. Ranking is 100%
//  local — these types carry the scored, sorted result the view renders.
//

import SwiftUI

/// What kind of thing a Needs You card represents. Drives the glyph,
/// tint, and which actions are offered.
enum NeedsYouKind: Equatable {
    /// A high-value task pinned to today and not yet logged.
    case task
    /// A linked Cadence routine with a skip penalty, not yet run.
    case routine
    /// A non-Quiet category that has drifted (idle for many days).
    case drift
}

/// One scored, ready-to-render candidate in the Needs You list.
///
/// `key` is a stable identity string used for dismiss/snooze persistence
/// across recomputes ("task:<uuid>", "routine:<uuid>", "drift:<category>").
struct NeedsYouItem: Identifiable, Equatable {
    let key: String
    let kind: NeedsYouKind
    let title: String
    let subtitle: String
    /// The pre-computed priority score. Higher surfaces first.
    let priority: Double

    // Targets for actions (only the relevant one is set).
    let taskId: UUID?
    let routineId: UUID?
    let category: Category?

    // Raw signals (also fed to the Today's Read input JSON).
    let value: Int
    let penalty: Int          // absolute magnitude, 0 when none
    let isTimeSensitive: Bool
    let driftDays: Int        // 0 for non-drift
    let timeCompeting: Bool   // a heavy block that competes for hours

    var id: String { key }

    /// The left glyph + tint. Red = penalty at risk, amber = open/time,
    /// lilac = drift — matching the mock.
    var tint: Color {
        switch kind {
        case .task: return penalty > 0 ? Theme.alertRed : Theme.alertAmber
        case .routine: return Theme.alertRed
        case .drift: return Theme.cadenceLavender
        }
    }

    var glyph: String {
        switch kind {
        case .task: return penalty > 0 ? "exclamationmark.triangle.fill" : "clock"
        case .routine: return "exclamationmark.triangle.fill"
        case .drift: return "arrow.up"
        }
    }

    /// Whether a "Start focus" action makes sense (tasks only).
    var canStartFocus: Bool { kind == .task && taskId != nil }
    /// Whether a "Log it" action makes sense.
    var canLog: Bool { taskId != nil || routineId != nil }

    /// A terse trailing signal for the collapsed read-state summary row
    /// ("−6 if skipped", "worth 8", "9 days").
    var compactSignal: String {
        if penalty > 0 { return "\u{2212}\(penalty) if skipped" }
        if value > 0 { return "worth \(value)" }
        if driftDays > 0 { return "\(driftDays) days" }
        return ""
    }
}

/// The available witness-model actions on a card. Decline is free — no
/// confirm, no penalty, no guilt copy.
enum NeedsYouAction: Equatable {
    case startFocus
    case log
    case open
    case notToday        // hide for the rest of today, no penalty
    case snoozeTilEvening
}
