//
//  ScheduledGrove.swift
//  FrisFocus
//
//  A grove session planned for later — optionally recurring (e.g. a
//  weekday study hall at 7pm). Stored locally; a local notification
//  reminds you (and an invite push reminds friends) shortly before it
//  starts so everyone shows up together.
//

import Foundation

/// How a scheduled grove repeats.
enum GroveRecurrence: String, Codable, Hashable, CaseIterable {
    case once
    case daily
    case weekdays
    case weekly

    var label: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        }
    }
}

struct ScheduledGrove: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String?
    /// Invited friends (local ids).
    var friendIds: [UUID]
    /// Planned length in seconds.
    var plannedDuration: TimeInterval
    /// The next fire moment (for `.once`) or the anchor time-of-day used
    /// to compute the next occurrence (for recurring schedules).
    var startAt: Date
    var recurrence: GroveRecurrence

    /// The next concrete start time at or after `from`, honoring the
    /// recurrence rule. Returns nil for a one-off that's already past.
    func nextOccurrence(after from: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch recurrence {
        case .once:
            return startAt > from ? startAt : nil
        case .daily, .weekdays, .weekly:
            let comps = cal.dateComponents([.hour, .minute], from: startAt)
            var candidate = cal.nextDate(
                after: from,
                matching: comps,
                matchingPolicy: .nextTime
            ) ?? startAt
            if recurrence == .weekly {
                let targetWeekday = cal.component(.weekday, from: startAt)
                while cal.component(.weekday, from: candidate) != targetWeekday {
                    candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                }
            } else if recurrence == .weekdays {
                while cal.isDateInWeekend(candidate) {
                    candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                }
            }
            return candidate
        }
    }
}
