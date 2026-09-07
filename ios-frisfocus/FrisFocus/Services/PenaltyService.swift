//
//  PenaltyService.swift
//  FrisFocus
//
//  Weekly-limit penalty evaluation and standalone avoidance occurrences —
//  the negative-habit mirror of BoosterService. Both flavors fold into
//  the existing weekly score via `.penalty` LogEntries (negative
//  `pointsEarned`), so no new scoring plumbing is required.
//
//  Task-attached penalties resolve at the weekly window: once per week
//  when the condition holds, revoked if the user crosses back.
//  Standalone avoidance occurrences deduct in real time on log and
//  restore on undo. Framed as private reduction goals, never broadcast.
//

import Foundation

extension Store {
    // MARK: - Task-attached weekly limit

    /// Apply or revoke the weekly-limit penalty for `task` based on the
    /// current week's completion count. Called from both
    /// `completeTask` and `uncompleteTask` so a single toggle can move
    /// the rule into or out of penalty range.
    ///
    /// Idempotent: at most one `.penalty` log entry tagged with this
    /// task lives in the current week interval at any time.
    func evaluatePenaltyForTask(_ task: FFTask) {
        guard let rule = task.penalty, rule.enabled else {
            // Rule was removed — sweep any lingering penalty entry
            // from the current week so disabling immediately restores
            // the deducted points.
            removeTaskPenaltyEntries(taskId: task.id)
            return
        }

        let interval = currentWeekInterval()
        // A `.sum` floor measures volume, not attendance — "less than
        // 400 pushups this week" is a total, and counting days would
        // answer a different question and let a week of single reps pass.
        let count = rule.resolvedMetric == .sum
            ? quantitySum(taskIds: [task.id], within: interval)
            : completionCount(taskId: task.id, within: interval)
        let breached: Bool = {
            switch rule.condition {
            case .moreThan: return count > rule.timesThreshold
            case .lessThan: return count < rule.timesThreshold
            }
        }()

        let hasEntry = logEntries.contains { entry in
            entry.taskId == task.id
                && entry.entryType == .penalty
                && interval.contains(entry.date)
                // Distinguish from a Must-Do skip penalty (which is
                // tied to a single past day, not the current week).
                && isWeeklyLimitPenaltyEntry(entry, taskId: task.id, interval: interval)
        }

        if breached && !hasEntry {
            let entry = LogEntry(
                date: Date(),
                taskId: task.id,
                todoId: nil,
                pointsEarned: -abs(rule.penaltyPoints),
                entryType: .penalty
            )
            logEntries.append(entry)
        } else if !breached && hasEntry {
            removeTaskPenaltyEntries(taskId: task.id, restrictTo: interval)
        }
    }

    /// True when a `.penalty` LogEntry was written by the weekly-limit
    /// evaluator (rather than by the Must-Do skip path). The skip path
    /// writes its entries dated to the missed day (yesterday at
    /// rollover time), so any `.penalty` entry whose date falls inside
    /// the current week interval AND wasn't dated to a past day is
    /// considered ours.
    ///
    /// In practice the skip-penalty entries are always dated to a
    /// prior day, so any `.penalty` whose date is today (and inside
    /// the current week) is one of ours. We use that as the test.
    private func isWeeklyLimitPenaltyEntry(_ entry: LogEntry, taskId: UUID, interval: DateInterval) -> Bool {
        let cal = Calendar.current
        return cal.isDateInToday(entry.date) || entry.date >= cal.startOfDay(for: Date())
    }

    /// Remove every weekly-limit penalty entry for `taskId`, optionally
    /// restricted to a specific interval. Used when the rule is
    /// disabled or the condition is no longer breached.
    private func removeTaskPenaltyEntries(taskId: UUID, restrictTo interval: DateInterval? = nil) {
        logEntries.removeAll { entry in
            guard entry.taskId == taskId, entry.entryType == .penalty else { return false }
            if let interval, !interval.contains(entry.date) { return false }
            return isWeeklyLimitPenaltyEntry(entry, taskId: taskId, interval: interval ?? currentWeekInterval())
        }
    }

    /// Status readout for a task's weekly limit rule, mirroring the
    /// booster status shape so the UI can render a chip / preview off
    /// the same data. Returns nil when no enabled rule is configured.
    func penaltyStatus(for task: FFTask, reference: Date = Date())
        -> (count: Int, threshold: Int, condition: PenaltyCondition,
            penaltyPoints: Int, breached: Bool)?
    {
        guard let rule = task.penalty, rule.enabled else { return nil }
        let interval = currentWeekInterval(reference: reference)
        let count = completionCount(taskId: task.id, within: interval)
        let breached: Bool = {
            switch rule.condition {
            case .moreThan: return count > rule.timesThreshold
            case .lessThan: return count < rule.timesThreshold
            }
        }()
        return (count, rule.timesThreshold, rule.condition, rule.penaltyPoints, breached)
    }

    // MARK: - Standalone avoidance items

    /// Add a new avoidance item. Trims whitespace off the name so
    /// accidental padding doesn't break sort order. `negativeType`
    /// selects the shape: `.perInstance` charges every occurrence;
    /// `.frequencyThreshold` is free up to `freeCount` per `window`.
    @discardableResult
    func addAvoidanceItem(
        name: String,
        pointsPerOccurrence: Int,
        note: String? = nil,
        category: Category? = nil,
        negativeType: NegativeType = .perInstance,
        window: NegativeWindow = .weekly,
        freeCount: Int = 0,
        tiers: [NegativeTier] = []
    ) -> AvoidanceItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = AvoidanceItem(
            name: trimmed,
            pointsPerOccurrence: max(1, pointsPerOccurrence),
            seasonId: currentSeason.id,
            note: (cleanNote?.isEmpty ?? true) ? nil : cleanNote,
            category: category,
            negativeType: negativeType,
            window: window,
            freeCount: max(0, freeCount),
            tiers: tiers
        )
        avoidanceItems.append(item)
        persistAll()
        return item
    }

    /// Update an existing avoidance item's name / point cost / note /
    /// shape. Clamps the value and free count to sane minimums.
    func updateAvoidanceItem(_ item: AvoidanceItem) {
        guard let idx = avoidanceItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.pointsPerOccurrence = max(1, item.pointsPerOccurrence)
        updated.freeCount = max(0, item.freeCount)
        avoidanceItems[idx] = updated
        persistAll()
    }

    /// Delete an avoidance item and every occurrence it spawned, plus
    /// the matching `.penalty` LogEntries so the historical score
    /// reflects the removal honestly. (If you'd rather keep history,
    /// keep the LogEntries — but the UX of "delete this thing" is
    /// cleaner when it's truly gone.)
    func deleteAvoidanceItem(_ item: AvoidanceItem) {
        let logIds = Set(avoidanceOccurrences.filter { $0.itemId == item.id }.map(\.logEntryId))
        logEntries.removeAll { logIds.contains($0.id) }
        avoidanceOccurrences.removeAll { $0.itemId == item.id }
        avoidanceItems.removeAll { $0.id == item.id }
        persistAll()
    }

    /// Log a single occurrence of an avoidance item. The deduction
    /// depends on the shape: `.perInstance` always charges the value;
    /// `.frequencyThreshold` charges 0 while the occurrence still sits
    /// inside the free allowance, then the full value once over the line.
    /// A matching `.penalty` LogEntry (possibly worth 0) folds the
    /// deduction into the existing daily / weekly score, and the
    /// occurrence drives the manager's running counter.
    func logAvoidanceOccurrence(_ item: AvoidanceItem) {
        let now = Date()
        let deduction = avoidanceDeduction(for: item, at: now)
        let entry = LogEntry(
            date: now,
            taskId: nil,
            todoId: nil,
            pointsEarned: -deduction,
            entryType: .penalty
        )
        logEntries.append(entry)

        let occurrence = AvoidanceOccurrence(
            itemId: item.id,
            date: now,
            pointsDeducted: deduction,
            logEntryId: entry.id
        )
        avoidanceOccurrences.append(occurrence)
        persistAll()
    }

    /// Remove the most recent occurrence of an item, restoring its
    /// deducted points. No-op when there's nothing to undo.
    func undoLatestAvoidanceOccurrence(_ item: AvoidanceItem) {
        guard let latest = avoidanceOccurrences
            .filter({ $0.itemId == item.id })
            .max(by: { $0.date < $1.date })
        else { return }
        logEntries.removeAll { $0.id == latest.logEntryId }
        avoidanceOccurrences.removeAll { $0.id == latest.id }
        persistAll()
    }

    /// Occurrences of `item` inside the current week, newest first.
    func occurrencesThisWeek(for item: AvoidanceItem) -> [AvoidanceOccurrence] {
        let interval = currentWeekInterval()
        return avoidanceOccurrences
            .filter { $0.itemId == item.id && interval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    /// Total points deducted by `item` inside the current week.
    func avoidancePointsThisWeek(for item: AvoidanceItem) -> Int {
        occurrencesThisWeek(for: item)
            .map(\.pointsDeducted)
            .reduce(0, +)
    }

    // MARK: - Negative-shape windows & deduction

    /// The interval the item's running counter spans: the configured
    /// weekly/monthly window for a frequency-threshold negative, and the
    /// week for a per-instance negative (which has no free allowance but
    /// still reads its week-to-date count in the manager).
    func avoidanceWindowInterval(for item: AvoidanceItem, reference: Date = Date()) -> DateInterval {
        switch item.negativeType {
        case .frequencyThreshold:
            return item.window == .monthly
                ? currentMonthInterval(reference: reference)
                : currentWeekInterval(reference: reference)
        case .perInstance:
            return currentWeekInterval(reference: reference)
        case .tiered:
            // A tiered negative escalates within a DAY — "two or more"
            // means two or more tonight, not two or more this week — so
            // its counter resets every morning.
            let cal = Calendar.current
            let start = cal.startOfDay(for: reference)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? reference
            return DateInterval(start: start, end: end)
        }
    }

    /// Occurrences of `item` inside its current window, newest first.
    func occurrencesInWindow(for item: AvoidanceItem, reference: Date = Date()) -> [AvoidanceOccurrence] {
        let interval = avoidanceWindowInterval(for: item, reference: reference)
        return avoidanceOccurrences
            .filter { $0.itemId == item.id && interval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    /// How many occurrences sit inside the item's current window.
    func avoidanceCountInWindow(for item: AvoidanceItem, reference: Date = Date()) -> Int {
        occurrencesInWindow(for: item, reference: reference).count
    }

    /// Free occurrences still available before deductions begin this
    /// window. Always 0 for per-instance items (no free allowance).
    func avoidanceFreeRemaining(for item: AvoidanceItem, reference: Date = Date()) -> Int {
        // A tiered negative has no free allowance — the first one
        // already costs, it just costs less than the second.
        guard item.negativeType == .frequencyThreshold else { return 0 }
        let used = avoidanceCountInWindow(for: item, reference: reference)
        return max(0, item.freeCount - used)
    }

    /// Occurrences past the free line this window — the ones that cost
    /// points. Equals the full count for per-instance negatives.
    func avoidanceChargedCount(for item: AvoidanceItem, reference: Date = Date()) -> Int {
        switch item.negativeType {
        case .perInstance, .tiered:
            return avoidanceCountInWindow(for: item, reference: reference)
        case .frequencyThreshold:
            return max(0, avoidanceCountInWindow(for: item, reference: reference) - item.freeCount)
        }
    }

    /// Total points deducted by `item` inside its current window.
    func avoidancePointsInWindow(for item: AvoidanceItem, reference: Date = Date()) -> Int {
        occurrencesInWindow(for: item, reference: reference)
            .map(\.pointsDeducted)
            .reduce(0, +)
    }

    /// Points the next occurrence logged at `date` would cost given the
    /// shape and the count already inside the window. per-instance always
    /// charges the value; frequency-threshold charges 0 until the free
    /// allowance is spent, then the full value for each one beyond it;
    /// tiered charges only the DIFFERENCE between the tier this
    /// occurrence reaches and the one already paid for.
    func avoidanceDeduction(for item: AvoidanceItem, at date: Date = Date()) -> Int {
        let value = abs(item.pointsPerOccurrence)
        switch item.negativeType {
        case .perInstance:
            return value
        case .frequencyThreshold:
            let interval = avoidanceWindowInterval(for: item, reference: date)
            let priorCount = avoidanceOccurrences.filter {
                $0.itemId == item.id && interval.contains($0.date)
            }.count
            // This occurrence is at position priorCount + 1 (1-indexed):
            // free while that position is within the allowance.
            return (priorCount + 1) <= max(0, item.freeCount) ? 0 : value
        case .tiered:
            // "One drink is minus three, two or more is minus fifteen"
            // means fifteen ALTOGETHER, not eighteen. So each occurrence
            // charges the step up: the day's new total minus what has
            // already been paid today. Reaching a tier costs the jump;
            // a third drink inside the same tier costs nothing more.
            //
            // Expressing it as a per-occurrence delta rather than by
            // rewriting the day's earlier entries means undo stays exact
            // and the log keeps reading as a list of real events.
            let interval = avoidanceWindowInterval(for: item, reference: date)
            let priorCount = avoidanceOccurrences.filter {
                $0.itemId == item.id && interval.contains($0.date)
            }.count
            let before = item.tieredTotal(for: priorCount)
            let after = item.tieredTotal(for: priorCount + 1)
            // A tier list that somehow descends can't refund points.
            return max(0, after - before)
        }
    }
}
