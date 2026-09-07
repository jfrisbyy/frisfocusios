//
//  BoosterService.swift
//  FrisFocus
//
//  First-class booster evaluation. A `WeeklyBooster` rewards completing
//  its referenced target — a single task or a whole category — at least
//  `threshold` times within the current period (week or month). When the
//  count crosses the threshold for the first time in the period, we append
//  a `.boosterBonus` LogEntry tagged with the booster's id so the bonus
//  folds into the existing daily / weekly score the same way per-task
//  points do.
//
//  Award-once-per-period is enforced by checking for an existing
//  `.boosterBonus` entry for the same booster within the period interval.
//  Removing a completion can revoke a bonus earned this period if the
//  count drops back below the threshold.
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

    // MARK: - Reference matching

    /// Does a completed `task` count toward this booster's threshold?
    /// A `.task` booster matches only its exact task; a `.category`
    /// booster matches every task in that area.
    func task(_ task: FFTask, matches booster: WeeklyBooster) -> Bool {
        switch booster.reference {
        case .task(let id):       return task.id == id
        case .category(let cat):  return task.category == cat
        // Nothing a person completes can feed a manual weekly goal —
        // they decide themselves whether the week met it.
        case .manual:             return false
        }
    }

    /// Every booster whose reference includes this task — directly, or
    /// because the booster watches the task's category.
    func boosters(referencing task: FFTask) -> [WeeklyBooster] {
        boosters.filter { self.task(task, matches: $0) }
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

    /// The total of a task's own logged units across an interval — the
    /// steps walked, the pushups done, the lessons finished.
    ///
    /// A completion with no recorded quantity counts as one, so a flat
    /// task under a `.sum` booster behaves exactly like a day count
    /// instead of contributing nothing.
    func quantitySum(taskIds: Set<UUID>, within interval: DateInterval) -> Int {
        logEntries.reduce(0) { acc, entry in
            guard let tid = entry.taskId, taskIds.contains(tid),
                  entry.entryType == .completed,
                  interval.contains(entry.date)
            else { return acc }
            return acc + Int((entry.quantity ?? 1).rounded())
        }
    }

    /// Completions counting toward a booster within an interval. For a
    /// task booster it's that task's completions; for a category booster
    /// it's the combined completions of every task in the area.
    func completionCount(for booster: WeeklyBooster, within interval: DateInterval) -> Int {
        // A `.sum` booster measures volume, not attendance: its threshold
        // is a weekly total of the task's own units, so counting days
        // would answer a completely different question.
        // A manual goal is not counted, it is claimed. Reading the award
        // back as its own progress keeps every caller — the status
        // readout, the day breakdown, the award guard — working off one
        // notion of "earned" instead of needing a second one.
        if case .manual = booster.reference {
            return hasBoosterAward(boosterId: booster.id, within: interval) ? max(1, booster.threshold) : 0
        }
        if (booster.metric ?? .days) == .sum {
            let ids: Set<UUID>
            switch booster.reference {
            case .task(let id): ids = [id]
            case .category(let cat): ids = Set(tasks.filter { $0.category == cat }.map(\.id))
            case .manual: ids = []
            }
            return quantitySum(taskIds: ids, within: interval)
        }
        switch booster.reference {
        case .manual:
            return 0
        case .task(let id):
            return completionCount(taskId: id, within: interval)
        case .category(let cat):
            let ids = Set(tasks.filter { $0.category == cat }.map(\.id))
            return logEntries.reduce(0) { acc, entry in
                guard let tid = entry.taskId, ids.contains(tid),
                      entry.entryType == .completed,
                      interval.contains(entry.date)
                else { return acc }
                return acc + 1
            }
        }
    }

    // MARK: - Status

    /// Booster progress for a booster in its configured period.
    func boosterStatus(for booster: WeeklyBooster, reference: Date = Date())
        -> (progress: Int, required: Int, earned: Bool, period: BoosterPeriod, bonusPoints: Int)
    {
        let interval = boosterPeriodInterval(booster.period, reference: reference)
        let count = completionCount(for: booster, within: interval)
        return (
            progress: min(count, booster.threshold),
            required: booster.threshold,
            earned: count >= booster.threshold,
            period: booster.period,
            bonusPoints: booster.bonusPoints
        )
    }

    /// Has a `.boosterBonus` already been awarded for this booster within
    /// the given interval? Used to guard against re-awarding.
    func hasBoosterAward(boosterId: UUID, within interval: DateInterval) -> Bool {
        logEntries.contains { entry in
            entry.boosterId == boosterId
                && entry.entryType == .boosterBonus
                && interval.contains(entry.date)
        }
    }

    /// Date the booster was earned in the current period, or nil.
    func boosterEarnedDate(for booster: WeeklyBooster, reference: Date = Date()) -> Date? {
        let interval = boosterPeriodInterval(booster.period, reference: reference)
        return logEntries
            .filter {
                $0.boosterId == booster.id
                && $0.entryType == .boosterBonus
                && interval.contains($0.date)
            }
            .map(\.date)
            .min()
    }

    // MARK: - Award / revoke

    /// Evaluate every booster the just-completed task feeds. Returns the
    /// first fresh award (if any) so the caller can surface a toast.
    @discardableResult
    func evaluateBoostersAfterCompletion(_ task: FFTask) -> BoosterAward? {
        var firstAward: BoosterAward? = nil
        for booster in boosters(referencing: task) {
            if let award = evaluateBooster(booster), firstAward == nil {
                firstAward = award
            }
        }
        return firstAward
    }

    /// Award a single booster if it just crossed its threshold this
    /// period and hasn't already been paid out. Appends a `.boosterBonus`
    /// log entry tagged with the booster's id and publishes a transient
    /// award signal.
    @discardableResult
    func evaluateBooster(_ booster: WeeklyBooster) -> BoosterAward? {
        let interval = boosterPeriodInterval(booster.period)
        let count = completionCount(for: booster, within: interval)
        guard count >= booster.threshold else { return nil }
        guard !hasBoosterAward(boosterId: booster.id, within: interval) else { return nil }

        let entry = LogEntry(
            date: Date(),
            taskId: nil,
            todoId: nil,
            boosterId: booster.id,
            pointsEarned: booster.bonusPoints,
            entryType: .boosterBonus
        )
        logEntries.append(entry)

        let award = BoosterAward(
            taskTitle: booster.name,
            bonusPoints: booster.bonusPoints,
            period: booster.period
        )
        pendingBoosterAward = award
        return award
    }

    /// Tick (or untick) a manual weekly goal for the current period.
    ///
    /// The counted boosters award themselves the moment a completion
    /// crosses the threshold. A manual goal has nothing to cross, so
    /// this IS its award — the person judging their own week, which is
    /// the only thing that can judge "the apartment is clean".
    @discardableResult
    func toggleManualBooster(_ booster: WeeklyBooster) -> Bool {
        guard case .manual = booster.reference else { return false }
        let interval = boosterPeriodInterval(booster.period)
        if hasBoosterAward(boosterId: booster.id, within: interval) {
            logEntries.removeAll {
                $0.boosterId == booster.id
                    && $0.entryType == .boosterBonus
                    && interval.contains($0.date)
            }
            persistAll()
            return false
        }
        logEntries.append(
            LogEntry(
                date: Date(),
                taskId: nil,
                todoId: nil,
                boosterId: booster.id,
                pointsEarned: booster.bonusPoints,
                entryType: .boosterBonus,
                title: booster.name
            )
        )
        pendingBoosterAward = BoosterAward(
            taskTitle: booster.name,
            bonusPoints: booster.bonusPoints,
            period: booster.period
        )
        persistAll()
        return true
    }

    /// Every manual weekly goal, with whether it has been ticked for the
    /// current period. Drives the end-of-week checklist.
    func manualBoosters(reference: Date = Date()) -> [(booster: WeeklyBooster, claimed: Bool)] {
        boosters.compactMap { booster in
            guard case .manual = booster.reference else { return nil }
            let interval = boosterPeriodInterval(booster.period, reference: reference)
            return (booster, hasBoosterAward(boosterId: booster.id, within: interval))
        }
    }

    /// Inverse of the awarder. If undoing a completion drops a booster's
    /// count back below its threshold for the current period, pull the
    /// bonus entry so the score reflects the new state honestly.
    func revokeBoostersIfNoLongerEarned(_ task: FFTask) {
        for booster in boosters(referencing: task) {
            let interval = boosterPeriodInterval(booster.period)
            let count = completionCount(for: booster, within: interval)
            guard count < booster.threshold else { continue }
            logEntries.removeAll { entry in
                entry.boosterId == booster.id
                    && entry.entryType == .boosterBonus
                    && interval.contains(entry.date)
            }
        }
    }

    // MARK: - CRUD

    /// Add a new first-class booster bound to the current season.
    func addBooster(name: String, reference: BoosterReference, threshold: Int, period: BoosterPeriod, bonusPoints: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let booster = WeeklyBooster(
            seasonId: currentSeason.id,
            name: trimmed,
            reference: reference,
            threshold: max(1, threshold),
            period: period,
            bonusPoints: max(1, bonusPoints)
        )
        boosters.append(booster)
        persistAll()
    }

    /// Replace an existing booster in place.
    func updateBooster(_ booster: WeeklyBooster) {
        guard let idx = boosters.firstIndex(where: { $0.id == booster.id }) else { return }
        boosters[idx] = booster
        persistAll()
    }

    /// Remove a booster and any bonus entries it has paid out, so the
    /// score no longer reflects a reward that no longer exists.
    func deleteBooster(_ booster: WeeklyBooster) {
        boosters.removeAll { $0.id == booster.id }
        logEntries.removeAll { $0.boosterId == booster.id && $0.entryType == .boosterBonus }
        persistAll()
    }
}
