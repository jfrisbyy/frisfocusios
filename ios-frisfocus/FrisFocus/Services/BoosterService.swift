//
//  BoosterService.swift
//  FrisFocus
//
//  Booster rule evaluation. A booster rewards completing a task at least
//  `timesRequired` times within the current period (week or month).
//  When the count crosses the threshold for the first time in the period,
//  we append a `LogEntry` of type `.boosterBonus` so the bonus folds into
//  the existing daily / weekly score the same way per-task points do.
//
//  Award-once-per-period is enforced by checking for an existing
//  `.boosterBonus` entry for the same task within the period interval.
//  Removing today's completion can revoke a bonus that was earned today
//  if the count drops below the threshold again.
//

import Foundation

/// A transient signal the UI can render as a toast.
/// Cleared after it's been shown.
struct BoosterAward: Equatable {
    var id: UUID = UUID()
    var taskTitle: String
    var bonusPoints: Int
    var period: BoosterPeriod
}

extension Store {
    // MARK: - Period intervals

    /// The week interval the rest of the app already uses for `weekScore`.
    func currentWeekInterval(reference: Date = Date()) -> DateInterval {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: reference)
            ?? DateInterval(start: reference, duration: 0)
    }

    /// The current calendar month.
    func currentMonthInterval(reference: Date = Date()) -> DateInterval {
        let cal = Calendar.current
        return cal.dateInterval(of: .month, for: reference)
            ?? DateInterval(start: reference, duration: 0)
    }

    /// Interval for a booster's configured period.
    func boosterPeriodInterval(_ period: BoosterPeriod, reference: Date = Date()) -> DateInterval {
        switch period {
        case .week:  return currentWeekInterval(reference: reference)
        case .month: return currentMonthInterval(reference: reference)
        }
    }

    // MARK: - Completion count

    /// Number of `.completed` log entries for a specific task within a
    /// date interval. Drives the booster progress readout.
    func completionCount(taskId: UUID, within interval: DateInterval) -> Int {
        logEntries.reduce(0) { acc, entry in
            guard entry.taskId == taskId,
                  entry.entryType == .completed,
                  interval.contains(entry.date)
            else { return acc }
            return acc + 1
        }
    }

    // MARK: - Status

    /// Booster progress for a task in its configured period.
    /// Returns nil if the task has no enabled booster.
    func boosterStatus(for task: FFTask, reference: Date = Date())
        -> (progress: Int, required: Int, earned: Bool, period: BoosterPeriod, bonusPoints: Int)?
    {
        guard let rule = task.booster, rule.enabled else { return nil }
        let interval = boosterPeriodInterval(rule.period, reference: reference)
        let count = completionCount(taskId: task.id, within: interval)
        return (
            progress: min(count, rule.timesRequired),
            required: rule.timesRequired,
            earned: count >= rule.timesRequired,
            period: rule.period,
            bonusPoints: rule.bonusPoints
        )
    }

    /// Has a `.boosterBonus` already been awarded for this task within
    /// the given interval? Used to guard against re-awarding.
    func hasBoosterAward(taskId: UUID, within interval: DateInterval) -> Bool {
        logEntries.contains { entry in
            entry.taskId == taskId
                && entry.entryType == .boosterBonus
                && interval.contains(entry.date)
        }
    }

    /// Date the booster was earned in the current period, or nil.
    func boosterEarnedDate(for task: FFTask, reference: Date = Date()) -> Date? {
        guard let rule = task.booster, rule.enabled else { return nil }
        let interval = boosterPeriodInterval(rule.period, reference: reference)
        return logEntries
            .filter {
                $0.taskId == task.id
                && $0.entryType == .boosterBonus
                && interval.contains($0.date)
            }
            .map(\.date)
            .min()
    }

    // MARK: - Award / revoke

    /// Evaluate after a fresh completion. If the booster just crossed
    /// its threshold and hasn't been awarded in this period, append a
    /// `.boosterBonus` log entry and publish a transient award signal.
    @discardableResult
    func evaluateBoosterAfterCompletion(_ task: FFTask) -> BoosterAward? {
        guard let rule = task.booster, rule.enabled else { return nil }
        let interval = boosterPeriodInterval(rule.period)
        let count = completionCount(taskId: task.id, within: interval)
        guard count >= rule.timesRequired else { return nil }
        guard !hasBoosterAward(taskId: task.id, within: interval) else { return nil }

        let entry = LogEntry(
            date: Date(),
            taskId: task.id,
            todoId: nil,
            pointsEarned: rule.bonusPoints,
            entryType: .boosterBonus
        )
        logEntries.append(entry)

        let award = BoosterAward(
            taskTitle: task.title,
            bonusPoints: rule.bonusPoints,
            period: rule.period
        )
        pendingBoosterAward = award
        return award
    }

    /// Inverse of the awarder. If a user undoes a completion that was
    /// the one carrying the booster over the line, remove the bonus
    /// entry so the score reflects the new state honestly.
    func revokeBoosterIfNoLongerEarned(_ task: FFTask) {
        guard let rule = task.booster, rule.enabled else { return }
        let interval = boosterPeriodInterval(rule.period)
        let count = completionCount(taskId: task.id, within: interval)
        guard count < rule.timesRequired else { return }
        logEntries.removeAll { entry in
            entry.taskId == task.id
                && entry.entryType == .boosterBonus
                && interval.contains(entry.date)
        }
    }
}
