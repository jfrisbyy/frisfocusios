//
//  SeasonArchive.swift
//  FrisFocus
//
//  A complete, restorable copy of one season's graph — everything the
//  app clears when a new season replaces it (the season itself with its
//  categories/milestones/cover, the task library, to-dos, boosters,
//  habit trains, and avoidance items). Kept alongside the lightweight
//  `PastSeasonSummary` chapter so a past season can be fully reopened and
//  made live again, not just glanced at.
//
//  Pure data, Codable, tolerant decoding so archives written by older or
//  newer builds still hydrate.
//

import Foundation

/// The full, reactivatable snapshot of a season that was replaced.
/// `id` matches the archived `Season.id` (and the `PastSeasonSummary.id`
/// of the same chapter), so a summary card can find its full copy.
struct SeasonArchive: Codable, Identifiable, Equatable {
    var id: UUID
    var season: Season
    var tasks: [FFTask]
    var todos: [Todo]
    var boosters: [WeeklyBooster]
    var habitTrains: [HabitTrain]
    var avoidanceItems: [AvoidanceItem]
    /// When this archive was captured — used to pick the newest copy.
    var archivedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, season, tasks, todos, boosters, habitTrains, avoidanceItems, archivedAt
    }

    init(
        id: UUID,
        season: Season,
        tasks: [FFTask] = [],
        todos: [Todo] = [],
        boosters: [WeeklyBooster] = [],
        habitTrains: [HabitTrain] = [],
        avoidanceItems: [AvoidanceItem] = [],
        archivedAt: Date = Date()
    ) {
        self.id = id
        self.season = season
        self.tasks = tasks
        self.todos = todos
        self.boosters = boosters
        self.habitTrains = habitTrains
        self.avoidanceItems = avoidanceItems
        self.archivedAt = archivedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.season = try c.decode(Season.self, forKey: .season)
        self.id = (try c.decodeIfPresent(UUID.self, forKey: .id)) ?? season.id
        self.tasks = (try c.decodeIfPresent([FFTask].self, forKey: .tasks)) ?? []
        self.todos = (try c.decodeIfPresent([Todo].self, forKey: .todos)) ?? []
        self.boosters = (try c.decodeIfPresent([WeeklyBooster].self, forKey: .boosters)) ?? []
        self.habitTrains = (try c.decodeIfPresent([HabitTrain].self, forKey: .habitTrains)) ?? []
        self.avoidanceItems = (try c.decodeIfPresent([AvoidanceItem].self, forKey: .avoidanceItems)) ?? []
        self.archivedAt = (try c.decodeIfPresent(Date.self, forKey: .archivedAt)) ?? Date()
    }

    static func == (lhs: SeasonArchive, rhs: SeasonArchive) -> Bool {
        lhs.id == rhs.id && lhs.archivedAt == rhs.archivedAt
    }

    /// A lightweight chapter summary derived from this archive — used
    /// to (re)build the friend-visible "Seasons Before" card entry.
    func summary(endedAt: Date) -> PastSeasonSummary {
        PastSeasonSummary(
            id: season.id,
            name: season.name,
            startDate: season.startDate,
            endDate: max(season.startDate, endedAt),
            milestonesReached: season.milestones.filter { $0.status == .cleared }.count,
            milestonesTotal: season.milestones.count,
            coverId: season.coverId,
            accentHex: season.accentHex
        )
    }
}
