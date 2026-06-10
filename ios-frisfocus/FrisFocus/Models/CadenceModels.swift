//
//  CadenceModels.swift
//  FrisFocus
//
//  The Esengo link — FrisFocus's side of the Cadence ↔ FrisFocus bridge.
//  FrisFocus owns scoring; Cadence publishes honest *facts* (outcome
//  events). These are pure data types:
//
//   • CadenceRoutineSummary — a row from `cadence_routines`, used to
//     populate the link picker. FrisFocus never reads Cadence's routine
//     internals beyond this summary.
//   • CadenceLink — a FrisFocus-side link record binding a Cadence
//     routine (or an outcome rule) to FrisFocus scoring: points, season,
//     tier, recurrence. Persisted locally alongside the rest of the
//     FrisFocus graph.
//   • CadenceOutcomeFulfillment — a recorded passive-outcome fill (sleep
//     / focus / wind-down) so the Season view can show "✓ 6h 40m last
//     night" and the credited points.
//   • CadenceOutcomeEventRow / CadenceMetrics — wire shapes for the
//     `cadence_outcome_events` seam (the ONLY cross-app data interface).
//
//  Pure Foundation. The Theme + views layer the lavender accent on top.
//

import Foundation

// MARK: - Routine summary (link picker)

/// One of the user's Cadence routines, read from `cadence_routines`.
/// Display-only — the link picker lists these so the user can choose
/// which routine to launch-and-run from FrisFocus.
struct CadenceRoutineSummary: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    /// Opaque domain word (e.g. "sleep", "morning"). Surfaced as the
    /// lead token of the plan-row meta line when present.
    let kind: String?
    let stepCount: Int
    let estMinutes: Int
}

// MARK: - Link shape

/// Whether a link is a routine you launch-and-run (lives in Today's
/// Plan, opens Cadence) or a passive outcome that fulfils itself
/// (lives in the Season view, nothing to tap).
enum CadenceLinkType: String, Codable, Equatable {
    case launchRun
    case passiveOutcome
}

/// The kind of passive outcome a `.passiveOutcome` link scores against.
/// Maps 1:1 to a `cadence_outcome_events.event_type`.
enum CadenceOutcomeKind: String, Codable, Equatable, CaseIterable, Identifiable {
    case sleepDuration
    case focusBlock
    case windDownTiming

    var id: String { rawValue }

    /// The matching `cadence_outcome_events.event_type`.
    var eventType: String {
        switch self {
        case .sleepDuration: return "sleep_summary"
        case .focusBlock: return "focus_block"
        case .windDownTiming: return "wind_down_timing"
        }
    }

    var icon: String {
        switch self {
        case .sleepDuration: return "moon.stars.fill"
        case .focusBlock: return "timer"
        case .windDownTiming: return "moon.zzz.fill"
        }
    }

    /// Default threshold in the kind's native unit:
    /// sleep = hours, focus = minutes, wind-down = minutes from midnight.
    var defaultThreshold: Double {
        switch self {
        case .sleepDuration: return 6
        case .focusBlock: return 60
        case .windDownTiming: return 23 * 60
        }
    }

    /// Stepper bounds + step in the kind's native unit.
    var thresholdRange: ClosedRange<Double> {
        switch self {
        case .sleepDuration: return 4...10
        case .focusBlock: return 15...180
        case .windDownTiming: return (20 * 60)...(26 * 60) // 8pm … 2am
        }
    }

    var thresholdStep: Double {
        switch self {
        case .sleepDuration: return 1
        case .focusBlock: return 15
        case .windDownTiming: return 15
        }
    }

    /// "Slept 6+ hours" / "1-hour focus block" / "Wind-down by 11pm".
    func ruleTitle(threshold: Double) -> String {
        switch self {
        case .sleepDuration:
            return "Slept \(Int(threshold))+ hours"
        case .focusBlock:
            let m = Int(threshold)
            return m % 60 == 0 ? "\(m / 60)-hour focus block" : "\(m)-min focus block"
        case .windDownTiming:
            return "Wind-down by \(Self.clockLabel(minutes: threshold))"
        }
    }

    /// Short editable-threshold label for the link form ("6 hours",
    /// "60 min", "11:00pm").
    func thresholdLabel(_ threshold: Double) -> String {
        switch self {
        case .sleepDuration: return "\(Int(threshold)) hours"
        case .focusBlock: return "\(Int(threshold)) min"
        case .windDownTiming: return Self.clockLabel(minutes: threshold)
        }
    }

    /// 12-hour clock label from minutes-since-midnight ("11pm", "12:30am").
    static func clockLabel(minutes: Double) -> String {
        let total = Int(minutes.rounded()) % (24 * 60)
        let h = total / 60
        let m = total % 60
        let ampm = h >= 12 ? "pm" : "am"
        var hr = h % 12
        if hr == 0 { hr = 12 }
        return m == 0 ? "\(hr)\(ampm)" : String(format: "%d:%02d%@", hr, m, ampm)
    }
}

/// How often a launch-run routine appears on Today's Plan.
enum CadenceRecurrence: String, Codable, Equatable, CaseIterable, Identifiable {
    case nightly
    case weekdays
    case daily

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nightly: return "Every night"
        case .weekdays: return "Weekdays"
        case .daily: return "Every day"
        }
    }

    /// True when a link with this recurrence belongs on the given day's
    /// plan. (`.nightly` and `.daily` are every-day; `.weekdays` is
    /// Mon–Fri using Calendar's 1=Sun…7=Sat convention.)
    func matches(_ date: Date = Date()) -> Bool {
        switch self {
        case .nightly, .daily:
            return true
        case .weekdays:
            let weekday = Calendar.current.component(.weekday, from: date)
            return (2...6).contains(weekday)
        }
    }
}

// MARK: - Link record

/// A FrisFocus-side link record. The scoring decision lives here:
/// points, season, recurrence — all owned by FrisFocus. Bound to
/// an Esengo `accountId` so links only surface for the account that
/// created them. Persisted locally with the rest of the FrisFocus graph.
struct CadenceLink: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var accountId: String
    var type: CadenceLinkType

    // launch-run
    var routineId: UUID?
    var routineName: String = ""
    var routineKind: String?
    var stepCount: Int = 0
    var estMinutes: Int = 0
    var category: Category = .health

    // passive-outcome
    var outcomeKind: CadenceOutcomeKind?
    /// Threshold in the outcome kind's native unit (sleep = hours,
    /// focus = minutes, wind-down = minutes from midnight).
    var threshold: Double?

    // scoring
    var points: Int = 5
    var seasonId: UUID?
    var recurrence: CadenceRecurrence = .nightly
    /// Opt-in negative penalty for a Must-level launch-run routine. Nil
    /// (the default) means the link enriches without pressure — exempt
    /// from the skip penalty. Set negative to pull points when skipped.
    var skipPenalty: Int?

    var createdAt: Date = Date()

    /// Sane ceiling so dual-app users can't trivially out-earn single-app
    /// users and cheapen the economy.
    static let pointCeiling = 15

    /// "tonight" for nightly cadence, otherwise "today" — used in the
    /// Needs You reminder phrasing.
    var runWord: String { recurrence == .nightly ? "tonight" : "today" }

    /// The title shown on the plan row / season row.
    var displayTitle: String {
        switch type {
        case .launchRun:
            return routineName
        case .passiveOutcome:
            guard let kind = outcomeKind else { return routineName }
            return kind.ruleTitle(threshold: threshold ?? kind.defaultThreshold)
        }
    }

    /// "{kind} · N steps · ~N min" meta for launch-run rows.
    var planMeta: String {
        var head = (routineKind?.isEmpty == false ? routineKind!.capitalized : category.displayName)
        if head.isEmpty { head = category.displayName }
        let stepWord = stepCount == 1 ? "step" : "steps"
        return "\(head) · \(stepCount) \(stepWord) · ~\(estMinutes) min"
    }

    /// The deep link that opens Cadence to run this routine.
    var runURL: URL? {
        guard let routineId else { return nil }
        return URL(string: "cadence://run?routineId=\(routineId.uuidString)")
    }
}

// MARK: - Passive-outcome fulfillment

/// A recorded passive-outcome fill so the Season view can show the
/// fulfilled state ("✓ 6h 40m last night") and the credited points.
/// Written alongside the scoring `LogEntry` when a verified outcome
/// event matches a passive link.
struct CadenceOutcomeFulfillment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var linkId: UUID
    var date: Date
    /// Human summary of what Cadence actually recorded ("6h 40m last
    /// night", "1h 05m focused today").
    var summary: String
    var points: Int
}

// MARK: - Outcome event seam (wire)

/// A row from `cadence_outcome_events` — the single cross-app interface.
/// `nonisolated` + `Sendable` so the read side can decode it off the
/// main actor before handing it to the Store for scoring.
nonisolated struct CadenceOutcomeEventRow: Decodable, Sendable, Identifiable {
    let id: UUID
    let accountId: String
    let eventType: String
    let routineId: UUID?
    let occurredAt: String
    let verified: Bool
    let metrics: CadenceMetrics

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case eventType = "event_type"
        case routineId = "routine_id"
        case occurredAt = "occurred_at"
        case verified
        case metrics
    }
}

/// Summary-level metrics carried on an outcome event. Every field is
/// optional — each `event_type` populates only the ones it owns.
nonisolated struct CadenceMetrics: Decodable, Sendable {
    let clean: Bool?
    let durationMinutes: Double?
    let verdict: String?
    let minutes: Double?
    let completedAtLocal: String?

    enum CodingKeys: String, CodingKey {
        case clean
        case durationMinutes = "duration_minutes"
        case verdict
        case minutes
        case completedAtLocal = "completed_at_local"
    }
}
