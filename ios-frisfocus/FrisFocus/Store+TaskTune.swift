//
//  Store+TaskTune.swift
//  FrisFocus
//
//  The scoped "talk it through" — context builders and change
//  application. The coach on the server only ever PROPOSES typed
//  changes; everything that actually moves state funnels through here,
//  on the Store's ordinary editing paths, when the person taps Apply.
//

import Foundation

extension Store {

    // MARK: - Context

    /// The numbers the coach may reason from, for one task.
    func tuneItem(forTaskId id: UUID) -> TaskTuneItem? {
        guard let task = tasks.first(where: { $0.id == id }) else { return nil }
        let cal = Calendar.current
        let completions = logEntries.filter { $0.taskId == id && $0.entryType == .completed }

        let lastTouched = completions.map(\.date).max()
        let daysSince = lastTouched.map {
            cal.dateComponents([.day], from: $0, to: Date()).day ?? 0
        }

        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekCount = completions.filter { $0.date >= weekStart }.count

        return TaskTuneItem(
            kind: "task",
            name: task.title,
            value: task.nominalValue,
            estMinutes: task.estimatedMinutes,
            schedule: Self.scheduleText(task.pinSchedule),
            daysSinceTouched: daysSince,
            weekCount: weekCount,
            seasonDay: currentSeasonDay,
            dailyGoal: currentSeason.dailyGoal,
            targetDate: nil,
            stepsTotal: nil,
            stepsDone: nil
        )
    }

    /// The numbers the coach may reason from, for one milestone.
    func tuneItem(forMilestoneId id: UUID) -> TaskTuneItem? {
        guard let milestone = currentSeason.milestones.first(where: { $0.id == id }) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return TaskTuneItem(
            kind: "milestone",
            name: milestone.title,
            value: milestone.pointValue,
            estMinutes: nil,
            schedule: milestone.targetDate.map { "lands by \(formatter.string(from: $0))" } ?? "no target date",
            daysSinceTouched: nil,
            weekCount: 0,
            seasonDay: currentSeasonDay,
            dailyGoal: currentSeason.dailyGoal,
            targetDate: milestone.targetDate.map { formatter.string(from: $0) },
            stepsTotal: milestone.steps.count,
            stepsDone: milestone.steps.filter(\.isCompleted).count
        )
    }

    private static func scheduleText(_ schedule: PinSchedule) -> String {
        switch schedule {
        case .none: return "unscheduled"
        case .today: return "pinned for today"
        case .singleDate(let date): return "one day: \(date.formatted(.dateTime.month().day()))"
        case .daily: return "every day"
        case .daysOfWeek(let days):
            guard !days.isEmpty else { return "unscheduled" }
            let symbols = Calendar.current.shortWeekdaySymbols
            let names = days.sorted().compactMap { index -> String? in
                guard (1...7).contains(index) else { return nil }
                return symbols[index - 1]
            }
            return names.joined(separator: ", ")
        }
    }

    // MARK: - Applying

    /// Apply one accepted proposal to a task. Returns the past-tense
    /// confirmation line for the transcript, or nil when nothing could
    /// be applied (the task vanished mid-conversation, say).
    @discardableResult
    func applyTune(_ change: TaskTuneChange, toTaskId id: UUID) -> String? {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        switch change {
        case .reschedule(let days):
            if days.isEmpty {
                tasks[idx].pinSchedule = .none
            } else if days.count == 7 {
                tasks[idx].pinSchedule = .daily
            } else {
                tasks[idx].pinSchedule = .daysOfWeek(days)
            }
            tasks[idx].pausedUntil = nil
            recalibrateDailyGoalIfProvisional()
            persistAll()
            return "Rescheduled to \(Self.scheduleText(tasks[idx].pinSchedule))."

        case .shrink(let estMinutes, let name):
            tasks[idx].estimatedMinutes = estMinutes
            if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                tasks[idx].title = name
            }
            persistAll()
            return "Shrunk to about \(estMinutes) minutes."

        case .reprice(let value):
            tasks[idx].pointValue = max(1, min(10, value))
            recalibrateDailyGoalIfProvisional()
            persistAll()
            return "Now worth \(tasks[idx].pointValue) points."

        case .pause(let days):
            let until = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
            tasks[idx].pausedUntil = until
            needsYou.snooze(key: "task:\(id.uuidString)", until: until)
            persistAll()
            return "Paused for \(days) days — it comes back on its own."

        case .drop:
            let title = tasks[idx].title
            deleteTask(tasks[idx])
            return "\(title) is off the board."

        case .pushDate, .addStep, .unsupported:
            return nil
        }
    }

    /// Apply one accepted proposal to a milestone.
    @discardableResult
    func applyTune(_ change: TaskTuneChange, toMilestoneId id: UUID) -> String? {
        guard var milestone = currentSeason.milestones.first(where: { $0.id == id }) else { return nil }
        switch change {
        case .pushDate(let date):
            milestone.targetDate = date
            updateMilestone(milestone)
            return "Now aimed at \(date.formatted(.dateTime.month().day()))."

        case .addStep(let title):
            addMilestoneStep(to: id, title: title)
            return "Added the step: \(title)."

        case .reprice(let value):
            milestone.pointValue = max(5, min(500, value))
            updateMilestone(milestone)
            return "Now worth \(milestone.pointValue) points."

        case .drop:
            let title = milestone.title
            deleteMilestone(milestone)
            return "\(title) is retired."

        case .reschedule, .shrink, .pause, .unsupported:
            return nil
        }
    }
}
