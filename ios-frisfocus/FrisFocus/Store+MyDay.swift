//
//  Store+MyDay.swift
//  FrisFocus
//
//  My own day, shaped exactly like the `FriendDay` a friend's profile
//  renders — but built from the *real* local data: today's plan
//  (pinned tasks + due to-dos), linked Cadence routines, completed
//  focus sessions, the season's milestones, and the last ten days of
//  logged points. Powers the "My profile" page's faithful preview of
//  what each sharing tier reveals.
//

import Foundation

extension Store {
    /// The current user's day in the friend-profile shape. Honest by
    /// design — every field reads from real local state, so the
    /// preview shows exactly the texture a Full-tier friend would see.
    var myDay: FriendDay {
        let cal = Calendar.current
        let today = Date()

        // Checklist — today's plan. Cadence links read as routines
        // below; to-dos have no category, so they file under Work.
        var dayTasks: [FriendDayTask] = []
        for item in todaysPlan {
            switch item {
            case .task(let task):
                dayTasks.append(FriendDayTask(
                    title: task.title,
                    isDone: hasLogEntryToday(forTaskId: task.id),
                    category: task.category
                ))
            case .todo(let todo):
                dayTasks.append(FriendDayTask(
                    title: todo.title,
                    isDone: todo.isCompleted,
                    category: .work
                ))
            case .cadenceLink:
                break
            }
        }

        // Routines — linked Cadence routines scheduled for today.
        let dayRoutines: [FriendRoutine] = todaysCadenceLinks.map { link in
            let earned = cadenceEarnedEntryToday(linkId: link.id) != nil
            return FriendRoutine(
                title: link.displayTitle,
                detail: earned ? "done today" : "~\(link.estMinutes) min · \(link.runWord)",
                isComplete: earned
            )
        }

        // Focus — completed sessions today.
        let sessionsToday: [FocusSession] = focusSessions.filter {
            cal.isDate($0.startedAt, inSameDayAs: today) && $0.endedAt != nil
        }
        let focusMinutes: Int = sessionsToday.reduce(0) { total, session in
            guard let end = session.endedAt else { return total }
            return total + max(0, Int(end.timeIntervalSince(session.startedAt) / 60))
        }
        let focusText: String
        if sessionsToday.isEmpty {
            focusText = "—"
        } else if focusMinutes >= 60 {
            focusText = "\(focusMinutes / 60)h \(focusMinutes % 60)m"
        } else {
            focusText = "\(focusMinutes)m"
        }

        // Milestone — the next one in flight, or the latest landed.
        let orderedMilestones = currentSeason.milestones.sorted { $0.weekNumber < $1.weekNumber }
        let milestone = orderedMilestones.first { !$0.isCompleted } ?? orderedMilestones.last
        let milestoneProgress: String = {
            guard let milestone else { return "—" }
            if milestone.isCompleted { return "landed" }
            if milestone.steps.isEmpty { return "week \(milestone.weekNumber)" }
            let done = milestone.steps.filter(\.isCompleted).count
            return "\(done) of \(milestone.steps.count) steps"
        }()
        let milestoneAddedToday: Bool = {
            guard let milestone else { return false }
            if let completed = milestone.completedDate, cal.isDate(completed, inSameDayAs: today) {
                return true
            }
            return milestone.steps.contains { step in
                guard let date = step.completedDate else { return false }
                return cal.isDate(date, inSameDayAs: today)
            }
        }()

        // Rhythm — each of the last 10 days' score against the goal.
        let goal = Double(max(1, currentSeason.dailyGoal))
        let bars: [Double] = (0..<10).reversed().map { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            let score = logEntries
                .filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.pointsEarned }
            return max(0, min(1, Double(score) / goal))
        }
        let momentumAvg = bars.reduce(0, +) / 10.0

        return FriendDay(
            moodLine: forwardSentence,
            todayLogged: todayScore,
            rhythmDays: bars.filter { $0 > 0 }.count,
            weekHeldBack: false,
            rhythmBars: bars,
            rhythmSummary: momentumAvg > 0.5 ? "building" : (momentumAvg > 0.12 ? "finding rhythm" : "quiet lately"),
            routines: dayRoutines,
            tasks: dayTasks,
            focusText: focusText,
            focusSessions: sessionsToday.count,
            milestoneTitle: milestone?.title ?? "",
            milestoneProgress: milestoneProgress,
            milestoneAddedToday: milestoneAddedToday
        )
    }

    /// The tasks and to-dos I actually completed on a given calendar day,
    /// read from my own real records. Powers the profile day card's
    /// tap-to-revisit on my own page. Each item reads as done (history).
    func myCompletedTasks(on date: Date) -> [FriendDayTask] {
        let cal = Calendar.current
        var result: [FriendDayTask] = []
        var seen = Set<UUID>()
        for entry in logEntries
            where cal.isDate(entry.date, inSameDayAs: date) && entry.entryType == .completed {
            if let taskId = entry.taskId, let task = tasks.first(where: { $0.id == taskId }) {
                if seen.insert(task.id).inserted {
                    result.append(FriendDayTask(title: task.title, isDone: true, category: task.category))
                }
            } else if let todoId = entry.todoId, let todo = todos.first(where: { $0.id == todoId }) {
                if seen.insert(todo.id).inserted {
                    result.append(FriendDayTask(title: todo.title, isDone: true, category: .work))
                }
            } else if let title = entry.title, !title.isEmpty {
                result.append(FriendDayTask(title: title, isDone: true, category: .work))
            }
        }
        return result
    }

    /// The shared circle / pact tasks a friend completed on a given day,
    /// built from the same locally-synced completion records that power
    /// their today card and rhythm. Only completed items are returned —
    /// this is honest history of what actually happened, and reveals
    /// nothing beyond what they already share.
    func friendCompletedTasks(for friend: Friend, on date: Date) -> [FriendDayTask] {
        let cal = Calendar.current
        let categories: [Category] = [.fitness, .health, .creative, .work, .spiritual, .apartment]
        var result: [FriendDayTask] = []
        var ci = 0
        for circle in sharedCircles(withFriendId: friend.id) where circle.hasSharedList {
            for task in circle.tasks {
                let done = circleTaskCompletions.contains { c in
                    c.circleId == circle.id
                        && c.circleTaskId == task.id
                        && c.memberId == friend.id
                        && cal.isDate(c.date, inSameDayAs: date)
                }
                if done {
                    result.append(FriendDayTask(title: task.title, isDone: true, category: categories[ci % categories.count]))
                }
                ci += 1
            }
        }
        for pact in sharedPacts(withFriendId: friend.id).filter({ $0.status == .active }) {
            for task in pact.tasks {
                let done = pactCompletions.contains { c in
                    c.pactId == pact.id
                        && c.taskId == task.id
                        && c.userId == friend.id
                        && cal.isDate(c.date, inSameDayAs: date)
                }
                if done {
                    result.append(FriendDayTask(title: task.name, isDone: true, category: categories[ci % categories.count]))
                }
                ci += 1
            }
        }
        return result
    }
}
