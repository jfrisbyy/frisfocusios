//
//  MilestoneService.swift
//  FrisFocus
//
//  Milestones are scored: a deliberately large, one-time reward that
//  lands on the day it's achieved. Completing one writes a `.milestone`
//  LogEntry so its value folds into that day's total (and therefore the
//  week and season totals) exactly like a task completion — even when the
//  value far exceeds the daily target. Un-completing pulls the entry back.
//

import Foundation

extension Store {
    // MARK: - Scoring

    /// Mark a milestone achieved today, crediting its `pointValue` once.
    /// No-op if already completed. The credit lands on today's local day.
    func completeMilestone(_ milestone: Milestone) {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        guard currentSeason.milestones[idx].completedDate == nil else { return }

        let now = Date()
        currentSeason.milestones[idx].completedDate = now
        currentSeason.milestones[idx].status = .cleared

        let value = currentSeason.milestones[idx].pointValue
        if value != 0 {
            logEntries.append(
                LogEntry(
                    date: now,
                    taskId: nil,
                    todoId: nil,
                    milestoneId: milestone.id,
                    pointsEarned: value,
                    entryType: .milestone
                )
            )
        }

        let clearedCount = currentSeason.milestones.filter { $0.isCompleted }.count
        recordMilestoneSignal(
            title: currentSeason.milestones[idx].title,
            done: clearedCount,
            total: currentSeason.milestones.count
        )

        persistAll()
    }

    /// Undo a milestone completion, removing its credit so the score
    /// reflects the new state honestly.
    func uncompleteMilestone(_ milestone: Milestone) {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        currentSeason.milestones[idx].completedDate = nil
        currentSeason.milestones[idx].status = .inMotion
        logEntries.removeAll { $0.milestoneId == milestone.id && $0.entryType == .milestone }
        persistAll()
    }

    // MARK: - CRUD

    /// Append a new milestone to the current season.
    @discardableResult
    func addMilestone(title: String, weekNumber: Int, pointValue: Int) -> Milestone {
        let milestone = Milestone(
            seasonId: currentSeason.id,
            weekNumber: max(1, weekNumber),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .upcoming,
            pointValue: max(0, pointValue)
        )
        currentSeason.milestones.append(milestone)
        persistAll()
        return milestone
    }

    /// Update a milestone's title / week / value in place. If the value
    /// changes while the milestone is already completed, its credited
    /// LogEntry is re-stamped so the score stays in sync.
    func updateMilestone(_ milestone: Milestone) {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        var updated = milestone
        updated.title = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.weekNumber = max(1, milestone.weekNumber)
        updated.pointValue = max(0, milestone.pointValue)
        currentSeason.milestones[idx] = updated

        if updated.isCompleted {
            if let entryIdx = logEntries.firstIndex(where: { $0.milestoneId == updated.id && $0.entryType == .milestone }) {
                logEntries[entryIdx].pointsEarned = updated.pointValue
            }
        }
        persistAll()
    }

    /// Delete a milestone and any credit it produced.
    func deleteMilestone(_ milestone: Milestone) {
        currentSeason.milestones.removeAll { $0.id == milestone.id }
        logEntries.removeAll { $0.milestoneId == milestone.id }
        persistAll()
    }

    // MARK: - Season total

    /// The running season total — every point logged since the season
    /// started: daily task points, booster bonuses, penalties, avoidance
    /// deductions, and milestone completions all fold in naturally
    /// because each writes a `LogEntry`.
    var seasonTotalScore: Int {
        let start = Calendar.current.startOfDay(for: currentSeason.startDate)
        return logEntries
            .filter { $0.date >= start }
            .map(\.pointsEarned)
            .reduce(0, +)
    }
}
