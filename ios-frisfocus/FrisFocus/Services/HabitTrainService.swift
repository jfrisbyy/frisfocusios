//
//  HabitTrainService.swift
//  FrisFocus
//
//  Habit-train evaluation + CRUD. A train rewards completing every
//  task-step on the same calendar day with a single `.trainBonus`
//  LogEntry that folds into the daily / weekly score the same way
//  per-task points and booster bonuses already do.
//
//  Award-once-per-day is enforced by checking for an existing
//  `.trainBonus` entry for the same trainId today. Uncompleting any
//  task-step revokes the bonus if the train is no longer fully done.
//

import Foundation

/// A transient signal the UI can render as a toast when a train just
/// crossed its completion threshold for today.
struct TrainAward: Equatable {
    var id: UUID = UUID()
    var trainId: UUID
    var trainName: String
    var bonusPoints: Int
}

extension Store {
    // MARK: - Lookup

    /// All steps in canonical order (`orderIndex` ascending).
    func orderedSteps(of train: HabitTrain) -> [HabitTrainStep] {
        train.steps.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// The personal task referenced by a step, if any. Returns nil for
    /// note steps and for task steps whose underlying task was deleted.
    func task(forStep step: HabitTrainStep) -> FFTask? {
        guard step.type == .task, let id = step.taskId else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Resolved task steps — task steps whose underlying task still
    /// exists. Note steps are skipped; deleted-task steps are skipped.
    func resolvedTaskSteps(of train: HabitTrain) -> [(step: HabitTrainStep, task: FFTask)] {
        orderedSteps(of: train).compactMap { step in
            guard let task = task(forStep: step) else { return nil }
            return (step, task)
        }
    }

    // MARK: - Completion status

    /// Today's progress for a train: how many task-steps are done
    /// (resolves through the personal task ledger) over how many task
    /// steps the train has, plus whether the bonus has been awarded
    /// today.
    func trainStatus(_ train: HabitTrain)
        -> (done: Int, totalTaskSteps: Int, complete: Bool, awarded: Bool)
    {
        let pairs = resolvedTaskSteps(of: train)
        let total = pairs.count
        let done = pairs.reduce(0) { acc, pair in
            hasLogEntryToday(forTaskId: pair.task.id) ? acc + 1 : acc
        }
        let complete = total > 0 && done == total
        return (done, total, complete, hasTrainAwardToday(trainId: train.id))
    }

    /// Sum of task-step `pointValue` for a train (skips note steps and
    /// deleted-task steps) — used by the manager card.
    func trainTaskPoints(_ train: HabitTrain) -> Int {
        resolvedTaskSteps(of: train).map(\.task.pointValue).reduce(0, +)
    }

    /// Total potential payoff: task points + bonus.
    func trainTotalPoints(_ train: HabitTrain) -> Int {
        trainTaskPoints(train) + train.bonusPoints
    }

    /// True when a `.trainBonus` LogEntry exists for this train on
    /// today's calendar day.
    func hasTrainAwardToday(trainId: UUID) -> Bool {
        let cal = Calendar.current
        let today = Date()
        return logEntries.contains { entry in
            entry.entryType == .trainBonus
                && entry.trainId == trainId
                && cal.isDate(entry.date, inSameDayAs: today)
        }
    }

    // MARK: - Award / revoke

    /// Called whenever a personal task's today-state may have changed.
    /// For every train that includes the task, award the bonus if all
    /// task-steps are now done (and not yet awarded today), or revoke
    /// it if the train is no longer fully done today.
    func evaluateTrainsAfterTaskChange(taskId: UUID) {
        let cal = Calendar.current
        let today = Date()

        for train in habitTrains {
            let touchesTask = train.steps.contains { $0.type == .task && $0.taskId == taskId }
            guard touchesTask else { continue }

            let status = trainStatus(train)

            if status.complete && !status.awarded {
                // Cross the line — award once for today.
                let entry = LogEntry(
                    date: today,
                    taskId: nil,
                    todoId: nil,
                    trainId: train.id,
                    pointsEarned: train.bonusPoints,
                    entryType: .trainBonus
                )
                logEntries.append(entry)
                pendingTrainAward = TrainAward(
                    trainId: train.id,
                    trainName: train.name,
                    bonusPoints: train.bonusPoints
                )
            } else if !status.complete && status.awarded {
                // Step undone — pull today's award back.
                logEntries.removeAll { entry in
                    entry.entryType == .trainBonus
                        && entry.trainId == train.id
                        && cal.isDate(entry.date, inSameDayAs: today)
                }
            }
        }
    }

    // MARK: - CRUD

    /// Create a fresh train with renormalised step indices and an
    /// optional seasonId binding it to the current season. Returns the
    /// newly minted train so callers can navigate into it.
    @discardableResult
    func createHabitTrain(
        name: String,
        description: String?,
        bonusPoints: Int,
        steps: [HabitTrainStep],
        seasonId: UUID? = nil
    ) -> HabitTrain {
        let normalised = normaliseStepOrder(steps)
        let train = HabitTrain(
            name: name,
            trainDescription: description,
            bonusPoints: bonusPoints,
            seasonId: seasonId,
            steps: normalised
        )
        habitTrains.append(train)
        persistAll()
        return train
    }

    /// In-place update of an existing train. Step indices are
    /// renormalised so drag-reorder writes a clean 0..n sequence.
    func updateHabitTrain(_ train: HabitTrain) {
        guard let idx = habitTrains.firstIndex(where: { $0.id == train.id }) else { return }
        var updated = train
        updated.steps = normaliseStepOrder(train.steps)
        habitTrains[idx] = updated

        // The bonus might have dropped, or steps might have been removed.
        // Re-evaluate the award state for today against the new shape.
        let cal = Calendar.current
        let today = Date()
        let status = trainStatus(updated)
        if !status.complete && status.awarded {
            logEntries.removeAll { entry in
                entry.entryType == .trainBonus
                    && entry.trainId == updated.id
                    && cal.isDate(entry.date, inSameDayAs: today)
            }
        }

        persistAll()
    }

    /// Drop a train and any `.trainBonus` log entries it owns. We pull
    /// past entries too so the bonus doesn't haunt the weekly total
    /// after the routine is gone.
    func deleteHabitTrain(_ train: HabitTrain) {
        habitTrains.removeAll { $0.id == train.id }
        logEntries.removeAll { $0.entryType == .trainBonus && $0.trainId == train.id }
        persistAll()
    }

    /// Rewrite step `orderIndex`s to a clean `0..<count` sequence in
    /// the array's current order. Lets the builder reorder by swapping
    /// array positions without having to track indices manually.
    private func normaliseStepOrder(_ steps: [HabitTrainStep]) -> [HabitTrainStep] {
        steps.enumerated().map { i, step in
            var s = step
            s.orderIndex = i
            return s
        }
    }
}
