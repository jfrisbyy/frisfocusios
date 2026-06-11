//
//  FriendDay.swift
//  FrisFocus
//
//  The witnessing texture of a friend's day, used by the friend
//  profile when their visibility tier lets it through. Built by the
//  Store from real shared data (circle check-offs, pact completions)
//  — nothing is fabricated.
//
//  This is witnessing, not monitoring: completed things read warm,
//  open things read gentle/grey, never red, never "failed."
//

import Foundation

/// The texture of a relationship since it began — proofs traded,
/// cheers exchanged, milestones witnessed, plus a warm honest line.
/// Floored so it reads full even on a day the friend logged nothing.
struct ConnectionTexture: Equatable {
    let proofsTraded: Int
    let cheersExchanged: Int
    let milestonesWitnessed: Int
    let line: String
}

/// One routine the friend ran today, with a human status line. A
/// routine is either fully done ("done · 7:10a") or partway through
/// ("3 of 5 · tonight"). Never framed as a failure.
struct FriendRoutine: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let isComplete: Bool
}

/// One item on the friend's task checklist. Completed items tick green;
/// open items render neutral/grey — the day's not over. Each task
/// carries its life category so the profile can group the checklist
/// and color-code effort the way the user's own day is color-coded.
struct FriendDayTask: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isDone: Bool
    let category: Category
}

/// A friend's full-visibility day. The snapshot fields (logged, rhythm,
/// week, bars) power the Open tier; the rich fields (routines, tasks,
/// focus, milestone) power Full.
struct FriendDay: Equatable {
    let moodLine: String
    let todayLogged: Int
    let rhythmDays: Int
    let weekHeldBack: Bool
    let rhythmBars: [Double]
    let rhythmSummary: String
    let routines: [FriendRoutine]
    let tasks: [FriendDayTask]
    let focusText: String
    let focusSessions: Int
    let milestoneTitle: String
    let milestoneProgress: String
    let milestoneAddedToday: Bool

    var doneCount: Int { tasks.filter { $0.isDone }.count }
    var totalCount: Int { tasks.count }

    /// Completed items, optionally followed by open items when the
    /// friend chose to share their whole list at Full tier.
    func visibleTasks(showOpen: Bool) -> [FriendDayTask] {
        showOpen ? tasks : tasks.filter { $0.isDone }
    }

    var openCount: Int { tasks.filter { !$0.isDone }.count }

    /// Categories present today, ordered by how much was done in each
    /// (then by total size), paired with their done/total counts.
    /// Drives the grouped checklist at Full and the anonymous effort
    /// breakdown at Open.
    var categoryBreakdown: [(category: Category, done: Int, total: Int)] {
        var order: [Category] = []
        var done: [Category: Int] = [:]
        var total: [Category: Int] = [:]
        for task in tasks {
            if total[task.category] == nil { order.append(task.category) }
            total[task.category, default: 0] += 1
            if task.isDone { done[task.category, default: 0] += 1 }
        }
        return order
            .map { (category: $0, done: done[$0] ?? 0, total: total[$0] ?? 0) }
            .sorted { lhs, rhs in
                if lhs.done != rhs.done { return lhs.done > rhs.done }
                return lhs.total > rhs.total
            }
    }

    /// Today's completion as a 0...1 fraction — done tasks over total.
    /// Drives the full-tier progress ring and the friend-card summary.
    var completionFraction: Double {
        totalCount > 0 ? Double(doneCount) / Double(totalCount) : 0
    }

    /// Recent momentum as a 0...1 value — the average of the rhythm
    /// bars. Used at the Open tier where the ring shows the *shape* of
    /// someone's days without ever revealing specific tasks.
    var momentum: Double {
        guard !rhythmBars.isEmpty else { return 0 }
        return rhythmBars.reduce(0, +) / Double(rhythmBars.count)
    }
}
