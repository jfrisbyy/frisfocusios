//
//  SeasonSetupDayShape.swift
//  FrisFocus
//
//  Deriving a week from a season that already describes one.
//
//  The setup conversation is forbidden from asking when things happen —
//  deliberately, because someone who doesn't yet know what their season
//  IS cannot say when it sits, and fifty-eight timing questions would
//  blow a budget already at twenty turns. The prompt says the app's
//  scheduling layer owns all of that after creation, and then nothing
//  picked the baton up: every task was committed with no day shape at
//  all, so the board was either pinned nowhere (an empty plan the
//  morning after a fifteen-minute interview) or pinned everywhere (a
//  fifty-eight row wall). Both are the same failure — a guess standing
//  in for an answer nobody was asked.
//
//  But the season is not silent about frequency. A booster reading
//  "three gym days" IS a statement that the gym happens three days a
//  week. A floor reading "a week with no lifting" says it from the other
//  side. A one-point worst-day item is by definition an every-day item.
//  All of it is already in the rubric, confirmed out loud, and the
//  commit path was throwing it away.
//
//  So: derive frequency confidently, because the season states it.
//  Derive bands minimally, because it doesn't — a band the app guessed
//  wrong is worse than one it left open, and the shaping screen exists
//  for the person to place what they actually know.
//

import Foundation

extension RubricDraft {

    /// Fill in every task's day shape from the rest of the rubric.
    ///
    /// Idempotent and non-destructive in spirit: it only writes tasks
    /// that are still at their defaults, so re-running it after someone
    /// has edited the shaping screen never undoes their work.
    mutating func deriveDayShape() {
        let boostersByTask = Dictionary(
            grouping: boosters.filter { !$0.isManual && !$0.referenceName.isEmpty },
            by: { $0.referenceName.lowercased() }
        )
        let floorsByTask = Dictionary(
            grouping: weeklyPenalties.filter { !$0.referenceName.isEmpty },
            by: { $0.referenceName.lowercased() }
        )

        for index in tasks.indices {
            let task = tasks[index]
            let key = task.name.lowercased()
            tasks[index].days = Self.derivedDays(
                for: task,
                boosters: boostersByTask[key] ?? [],
                floors: floorsByTask[key] ?? []
            )
            tasks[index].partOfDay = Self.derivedBand(for: task)
        }
    }

    /// How many days a week this task should sit on the board.
    ///
    /// Ordered by how much the season actually knows, most certain
    /// first. Anything the rubric is silent about falls through to the
    /// duration heuristic at the end, which is a guess and says so.
    static func derivedDays(
        for task: DraftTask,
        boosters: [DraftBooster],
        floors: [DraftWeeklyPenalty]
    ) -> Set<Int> {
        // A weekly TOTAL accrues across the week, so the task has to be
        // reachable on any day of it.
        if boosters.contains(where: { $0.metric == .sum }) { return [] }
        if floors.contains(where: { $0.metric == .sum }) { return [] }

        // A day-count booster is the season saying this out loud.
        let boosterDays = boosters.filter { $0.metric == .days }.map(\.threshold).max()
        // A floor is a lower bound, not a target: "fewer than two runs
        // and the season notices" means at least two, not exactly two.
        let floorDays = floors.filter { $0.metric == .days }.map(\.threshold).max()

        if let stated = [boosterDays, floorDays].compactMap({ $0 }).max() {
            return weekdays(count: stated)
        }

        // The worst-day layer. A one- or two-point item is the thing
        // that still counts when everything goes wrong, which only means
        // anything if it is reachable on the day everything goes wrong.
        if task.headlineValue <= 2 { return [] }

        // Nothing stated. Long efforts are not daily for most people;
        // short ones usually are. This is the only guess in here.
        switch task.estimatedMinutes ?? 0 {
        case 90...:  return weekdays(count: 3)
        case 45..<90: return weekdays(count: 4)
        case 25..<45: return weekdays(count: 5)
        default:     return []
        }
    }

    /// Where in the day a task most likely sits.
    ///
    /// Deliberately shy. Only two shapes are confident enough to place —
    /// the tiny anchors people stack at the start of a day, and the one
    /// heavy effort that lands after it. Everything else goes to the
    /// Anytime tray, where it is available without pretending the app
    /// knows when it happens.
    static func derivedBand(for task: DraftTask) -> PartOfDay {
        let minutes = task.estimatedMinutes ?? 0
        if task.headlineValue <= 2 && minutes > 0 && minutes <= 10 { return .morning }
        if task.headlineValue >= 7 && minutes >= 45 { return .evening }
        return .anytime
    }

    /// `count` weekdays spread across the week, as Calendar indices
    /// (1 = Sunday … 7 = Saturday). Empty means every day.
    ///
    /// Spread rather than clustered: three gym days is Monday, Wednesday
    /// and Friday, not Monday, Tuesday and Wednesday — nobody means the
    /// second thing, and a clustered guess is one someone has to undo.
    static func weekdays(count: Int) -> Set<Int> {
        switch max(0, count) {
        case 0, 7...: return []
        case 1: return [2]                    // Monday
        case 2: return [3, 6]                 // Tuesday, Friday
        case 3: return [2, 4, 6]              // Monday, Wednesday, Friday
        case 4: return [2, 3, 5, 7]           // Monday, Tuesday, Thursday, Saturday
        case 5: return [2, 3, 4, 5, 6]        // the working week
        default: return [2, 3, 4, 5, 6, 7]    // six: every day but Sunday
        }
    }

    /// Tasks long enough to be a standing commitment rather than
    /// something squeezed into an evening — the candidates the shaping
    /// screen offers to turn into a block with a real time on it.
    ///
    /// An offer, never an assumption: only the person knows whether
    /// their three-hour thing is a shift they must attend or a Saturday
    /// they chose.
    var blockCandidates: [DraftTask] {
        tasks
            .filter { ($0.estimatedMinutes ?? 0) >= 120 }
            .sorted { ($0.estimatedMinutes ?? 0) > ($1.estimatedMinutes ?? 0) }
    }

    /// How many things land on a given weekday, for the shaping
    /// screen's week strip.
    func load(onWeekday weekday: Int) -> Int {
        let taskCount = tasks.filter { $0.isEveryDay || $0.days.contains(weekday) }.count
        let bucketCount = buckets.filter { $0.isEveryDay || $0.days.contains(weekday) }.count
        return taskCount + bucketCount
    }
}
