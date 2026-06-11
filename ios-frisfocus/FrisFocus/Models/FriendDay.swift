//
//  FriendDay.swift
//  FrisFocus
//
//  The witnessing texture of a friend's day, used by the friend
//  profile when their visibility tier lets it through. There is no
//  backend yet, so the day is built deterministically from the friend
//  (Aaron matches the reference exactly; everyone else gets a calm,
//  stable, plausible day that doesn't reshuffle on every render).
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

extension FriendDay {
    /// Deterministic day for a friend. The named full-visibility friends
    /// are hand-authored so their profiles read rich and *stable* across
    /// launches; anyone else falls back to a seeded generator.
    static func make(for friend: Friend) -> FriendDay {
        switch friend.displayName {
        case "Aaron":   return aaron
        case "Theo":    return theo
        case "Priya":   return priya
        case "Jonah":   return jonah
        case "Kennedy": return kennedy
        default:        return generated(for: friend)
        }
    }

    /// The reference "Aaron's day."
    static let aaron = FriendDay(
        moodLine: "A good, steady day.",
        todayLogged: 38,
        rhythmDays: 9,
        weekHeldBack: true,
        rhythmBars: [0.5, 0.72, 0.42, 0.22, 0.6, 0.88, 0.62, 0.66, 0.5, 0.56],
        rhythmSummary: "mostly steady",
        routines: [
            FriendRoutine(title: "Morning routine", detail: "done · 7:10a", isComplete: true),
            FriendRoutine(title: "Deep work block", detail: "done · 9:30a", isComplete: true),
            FriendRoutine(title: "Wind-down", detail: "3 of 5 · tonight", isComplete: false)
        ],
        tasks: [
            FriendDayTask(title: "20-min run", isDone: true, category: .fitness),
            FriendDayTask(title: "Took meds", isDone: true, category: .health),
            FriendDayTask(title: "Journaled", isDone: true, category: .spiritual),
            FriendDayTask(title: "Read 10 pages", isDone: true, category: .creative),
            FriendDayTask(title: "Made the bed", isDone: true, category: .apartment),
            FriendDayTask(title: "Walked the dog", isDone: true, category: .health),
            FriendDayTask(title: "Call mom", isDone: false, category: .health),
            FriendDayTask(title: "Meal prep", isDone: false, category: .apartment)
        ],
        focusText: "1h 40m",
        focusSessions: 2,
        milestoneTitle: "Run a 5K",
        milestoneProgress: "2.1mi",
        milestoneAddedToday: true
    )

    /// Theo — a steady builder, deep in Build Season.
    static let theo = FriendDay(
        moodLine: "Locked in this afternoon.",
        todayLogged: 44,
        rhythmDays: 14,
        weekHeldBack: false,
        rhythmBars: [0.62, 0.7, 0.55, 0.8, 0.74, 0.48, 0.66, 0.82, 0.7, 0.76],
        rhythmSummary: "building",
        routines: [
            FriendRoutine(title: "Cold plunge", detail: "done · 6:40a", isComplete: true),
            FriendRoutine(title: "Deep work block", detail: "done · 10:00a", isComplete: true),
            FriendRoutine(title: "Wind-down", detail: "2 of 4 · tonight", isComplete: false)
        ],
        tasks: [
            FriendDayTask(title: "Cold plunge", isDone: true, category: .fitness),
            FriendDayTask(title: "500 words", isDone: true, category: .creative),
            FriendDayTask(title: "Gym session", isDone: true, category: .fitness),
            FriendDayTask(title: "Read 20 pages", isDone: true, category: .creative),
            FriendDayTask(title: "Inbox zero", isDone: true, category: .work),
            FriendDayTask(title: "Call landlord", isDone: false, category: .apartment),
            FriendDayTask(title: "Plan the week", isDone: false, category: .work)
        ],
        focusText: "2h 10m",
        focusSessions: 3,
        milestoneTitle: "Ship the side project",
        milestoneProgress: "62%",
        milestoneAddedToday: true
    )

    /// Priya — a full, productive day of making.
    static let priya = FriendDay(
        moodLine: "A good, full day of making.",
        todayLogged: 51,
        rhythmDays: 11,
        weekHeldBack: false,
        rhythmBars: [0.7, 0.5, 0.84, 0.66, 0.9, 0.6, 0.78, 0.72, 0.88, 0.8],
        rhythmSummary: "on a roll",
        routines: [
            FriendRoutine(title: "Morning pages", detail: "done · 7:30a", isComplete: true),
            FriendRoutine(title: "Studio block", detail: "done · 9:00a", isComplete: true),
            FriendRoutine(title: "Wind-down", detail: "done · 9:30p", isComplete: true)
        ],
        tasks: [
            FriendDayTask(title: "Morning pages", isDone: true, category: .spiritual),
            FriendDayTask(title: "Zine layout", isDone: true, category: .creative),
            FriendDayTask(title: "Ink 3 panels", isDone: true, category: .creative),
            FriendDayTask(title: "Post to the shop", isDone: true, category: .work),
            FriendDayTask(title: "Answer emails", isDone: true, category: .work),
            FriendDayTask(title: "Sketch the cover", isDone: false, category: .creative)
        ],
        focusText: "3h 05m",
        focusSessions: 4,
        milestoneTitle: "Finish the zine",
        milestoneProgress: "7/10",
        milestoneAddedToday: true
    )

    /// Jonah — a slow day, but he showed up. Gentle, never a failure.
    static let jonah = FriendDay(
        moodLine: "Slow start, but I showed up.",
        todayLogged: 19,
        rhythmDays: 5,
        weekHeldBack: true,
        rhythmBars: [0.3, 0.18, 0.42, 0.24, 0.5, 0.34, 0.2, 0.46, 0.28, 0.38],
        rhythmSummary: "finding rhythm",
        routines: [
            FriendRoutine(title: "Morning routine", detail: "done · 8:20a", isComplete: true),
            FriendRoutine(title: "Deep work block", detail: "1 of 3 · tonight", isComplete: false)
        ],
        tasks: [
            FriendDayTask(title: "Open the doc", isDone: true, category: .work),
            FriendDayTask(title: "Cold shower", isDone: true, category: .health),
            FriendDayTask(title: "20-min walk", isDone: true, category: .fitness),
            FriendDayTask(title: "Deep work", isDone: false, category: .work),
            FriendDayTask(title: "Read a chapter", isDone: false, category: .creative),
            FriendDayTask(title: "Meal prep", isDone: false, category: .apartment)
        ],
        focusText: "35m",
        focusSessions: 1,
        milestoneTitle: "30 days of deep work",
        milestoneProgress: "9/30",
        milestoneAddedToday: true
    )

    /// Kennedy — a quiet day, on purpose. Calm and low-key.
    static let kennedy = FriendDay(
        moodLine: "A quiet day, on purpose.",
        todayLogged: 8,
        rhythmDays: 6,
        weekHeldBack: true,
        rhythmBars: [0.2, 0.32, 0.16, 0.28, 0.22, 0.4, 0.18, 0.3, 0.24, 0.26],
        rhythmSummary: "resting on purpose",
        routines: [
            FriendRoutine(title: "Morning routine", detail: "done · 9:00a", isComplete: true),
            FriendRoutine(title: "Evening walk", detail: "tonight", isComplete: false)
        ],
        tasks: [
            FriendDayTask(title: "Stretch", isDone: true, category: .fitness),
            FriendDayTask(title: "Tea + journal", isDone: true, category: .spiritual),
            FriendDayTask(title: "Water the plants", isDone: false, category: .apartment),
            FriendDayTask(title: "Read", isDone: false, category: .creative)
        ],
        focusText: "20m",
        focusSessions: 1,
        milestoneTitle: "Rest & reset",
        milestoneProgress: "day 8",
        milestoneAddedToday: false
    )

    /// Stable pseudo-random day generated from the friend's id.
    private static func generated(for friend: Friend) -> FriendDay {
        var seed = UInt64(abs(friend.id.uuidString.hashValue) % 100_000 + 1)
        func next(_ upper: Int) -> Int {
            // xorshift — deterministic, no Foundation RNG state.
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Int(seed % UInt64(max(1, upper)))
        }

        let moods = [
            "A quiet day so far.",
            "Slow start, finding the rhythm.",
            "Showing up — that's the win.",
            "Locked in this afternoon.",
            "A good, steady day."
        ]
        let routinePool: [(String, String)] = [
            ("Morning routine", "7:10a"),
            ("Movement", "8:30a"),
            ("Deep work block", "9:30a"),
            ("Reading", "1:00p"),
            ("Wind-down", "tonight")
        ]
        let taskPool: [(String, Category)] = [
            ("20-min walk", .fitness), ("Drank water", .health),
            ("Journaled", .spiritual), ("Read 10 pages", .creative),
            ("Made the bed", .apartment), ("Stretched", .fitness),
            ("Inbox zero", .work), ("Cooked dinner", .health),
            ("Called a friend", .health), ("Tidied desk", .apartment)
        ]

        let totalTasks = 6 + next(3)            // 6–8
        let doneTasks = 2 + next(totalTasks - 2) // at least 2 done, never all
        let tasks: [FriendDayTask] = (0..<totalTasks).map { i in
            let (title, category) = taskPool[(i + next(taskPool.count)) % taskPool.count]
            return FriendDayTask(title: title, isDone: i < doneTasks, category: category)
        }

        let routineCount = 2 + next(2)          // 2–3
        let routines: [FriendRoutine] = (0..<routineCount).map { i in
            let (title, when) = routinePool[(i + next(routinePool.count)) % routinePool.count]
            let complete = i < routineCount - 1
            return FriendRoutine(
                title: title,
                detail: complete ? "done · \(when)" : "\(2 + next(3)) of 5 · tonight",
                isComplete: complete
            )
        }

        let bars: [Double] = (0..<10).map { _ in 0.2 + Double(next(70)) / 100.0 }
        let logged = 12 + next(34)
        let focusMin = 20 + next(100)
        let h = focusMin / 60
        let m = focusMin % 60
        let focusText = h > 0 ? "\(h)h \(m)m" : "\(m)m"

        return FriendDay(
            moodLine: moods[next(moods.count)],
            todayLogged: logged,
            rhythmDays: 3 + next(12),
            weekHeldBack: next(2) == 0,
            rhythmBars: bars,
            rhythmSummary: ["mostly steady", "building", "finding rhythm"][next(3)],
            routines: routines,
            tasks: tasks,
            focusText: focusText,
            focusSessions: 1 + next(3),
            milestoneTitle: friend.currentSeasonName?.replacingOccurrences(of: " Season", with: "") ?? "This season",
            milestoneProgress: "\(1 + next(4)).\(next(9))mi",
            milestoneAddedToday: next(2) == 0
        )
    }
}
