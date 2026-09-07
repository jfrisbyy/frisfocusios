//
//  CategoryService.swift
//  FrisFocus
//
//  Per-season editable categories and the copy-forward season helper.
//
//  Categories stay keyed to the stable `Category` cases (so the rest of
//  the app keeps working), but each season can rename and recolor them
//  freely via `SeasonCategory.customName` / `customColorHex`. The
//  resolvers below are the single source of truth for the name and color
//  a category shows under the current season — views read them instead of
//  the built-in `Category.displayName` / `hexColor` so a recolor takes
//  effect everywhere at once.
//

import Foundation

// MARK: - Season import

/// What a new season carries forward from the one it replaces.
///
/// Starting a new season used to be all-or-nothing in a way nobody
/// chose. The task library, boosters and negatives simply stayed —
/// there was no way to leave any of them behind — while every
/// milestone was dropped on the floor, finished or not. Both halves
/// were wrong for the same reason: the person was never asked. A
/// quarter reuses most of the last one with edited values, and the
/// milestones that didn't land are usually exactly what the next
/// season is for.
struct SeasonImportPlan {
    /// Tasks to keep in the live library. Anything not listed stays in
    /// the previous season's archive and leaves the board.
    var taskIds: Set<UUID> = []
    /// To-dos to keep. Completed ones are normally left behind.
    var todoIds: Set<UUID> = []
    /// Weekly boosters to keep.
    var boosterIds: Set<UUID> = []
    /// Negatives / avoidance items to keep.
    var avoidanceIds: Set<UUID> = []
    /// Habit trains to keep. A train whose steps didn't all survive is
    /// pruned rather than left pointing at tasks that no longer exist.
    var habitTrainIds: Set<UUID> = []
    /// Milestones to carry into the new season. Each is re-stamped with
    /// the new season's id, keeping its steps, attachments and notes.
    var milestoneIds: Set<UUID> = []

    /// Carry the category set — names, colors, tiers.
    var categories: Bool = true
    /// Carry the daily / weekly targets.
    var goals: Bool = true
    /// Carry each task's pin schedule, time window and part-of-day.
    /// Off means the tasks arrive unscheduled in the Anytime tray,
    /// which is what someone rebuilding their week actually wants.
    var schedule: Bool = true

    /// Everything the current season holds — the default the picker
    /// opens on, since carrying forward is the common case.
    static func everything(from store: Store) -> SeasonImportPlan {
        SeasonImportPlan(
            taskIds: Set(store.tasks.map(\.id)),
            todoIds: Set(store.todos.filter { !$0.isCompleted }.map(\.id)),
            boosterIds: Set(store.boosters.map(\.id)),
            avoidanceIds: Set(store.avoidanceItems.map(\.id)),
            habitTrainIds: Set(store.habitTrains.map(\.id)),
            // Finished milestones belong to the season that finished
            // them; the unfinished ones are the reason for a new season.
            milestoneIds: Set(store.currentSeason.milestones.filter { !$0.isCompleted }.map(\.id))
        )
    }

    /// A clean slate — nothing carries but the person's own choices in
    /// the flow that follows.
    static let nothing = SeasonImportPlan(categories: false, goals: false, schedule: false)
}

extension Store {
    // MARK: - Resolution

    /// The season's record for a category, if it participates this season.
    func seasonCategoryRecord(_ category: Category) -> SeasonCategory? {
        currentSeason.categories.first { $0.category == category }
    }

    /// The display name for a category under the current season — the
    /// per-season rename when set, otherwise the built-in name.
    func categoryDisplayName(_ category: Category) -> String {
        if let custom = seasonCategoryRecord(category)?.customName?
            .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return category.displayName
    }

    /// The swatch color (as `#RRGGBB`) for a category under the current
    /// season — the per-season recolor when set, otherwise the built-in
    /// hex. Views wrap this in `Color(hex:)`.
    func categoryColorHex(_ category: Category) -> String {
        if let custom = seasonCategoryRecord(category)?.customColorHex?
            .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return category.hexColor
    }

    // MARK: - Editing

    /// Rename a category for the current season. Passing `nil` or a blank
    /// string clears the override and restores the built-in name. Adds a
    /// season record for the category if one doesn't exist yet.
    func renameSeasonCategory(_ category: Category, to name: String?) {
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (cleaned?.isEmpty ?? true) ? nil : cleaned
        upsertSeasonCategory(category) { $0.customName = value }
    }

    /// Recolor a category for the current season. Passing `nil` clears the
    /// override and restores the built-in swatch.
    func recolorSeasonCategory(_ category: Category, hex: String?) {
        let cleaned = hex?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (cleaned?.isEmpty ?? true) ? nil : cleaned
        upsertSeasonCategory(category) { $0.customColorHex = value }
    }

    private func upsertSeasonCategory(_ category: Category, _ mutate: (inout SeasonCategory) -> Void) {
        if let idx = currentSeason.categories.firstIndex(where: { $0.category == category }) {
            mutate(&currentSeason.categories[idx])
        } else {
            var record = SeasonCategory(category: category, tier: .support)
            mutate(&record)
            currentSeason.categories.append(record)
        }
        persistAll()
    }

    // MARK: - Copy forward

    /// Start a fresh season carrying forward exactly what the person
    /// chose. Everything not in the plan stays with the previous
    /// season's archive, which is captured in full first — so nothing
    /// is destroyed by leaving it behind, and a season can be restored.
    @discardableResult
    func startNewSeason(
        importing plan: SeasonImportPlan,
        name: String? = nil,
        lengthDays: Int? = nil,
        dailyGoal: Int? = nil,
        weeklyGoal: Int? = nil
    ) -> Season {
        let previous = currentSeason
        let newId = UUID()

        let copiedCategories: [SeasonCategory] = plan.categories
            ? previous.categories.map {
                SeasonCategory(
                    category: $0.category,
                    tier: $0.tier,
                    customName: $0.customName,
                    customColorHex: $0.customColorHex
                )
            }
            : []

        // Milestones are re-stamped with the new season's id, keeping
        // their steps, attachments, target dates and linked notes. They
        // used to be dropped wholesale — an unfinished milestone is
        // usually the whole reason someone starts the next season.
        let carriedMilestones: [Milestone] = previous.milestones
            .filter { plan.milestoneIds.contains($0.id) }
            .map { milestone in
                var copy = milestone
                copy.seasonId = newId
                return copy
            }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        var season = Season(
            id: newId,
            name: (trimmedName?.isEmpty ?? true) ? "New Season" : (trimmedName ?? "New Season"),
            lengthDays: lengthDays ?? previous.lengthDays,
            startDate: Calendar.current.startOfDay(for: Date()),
            vibe: previous.vibe,
            dailyGoal: dailyGoal ?? (plan.goals ? previous.dailyGoal : Season.defaultDailyGoal),
            weeklyGoal: weeklyGoal ?? (plan.goals ? previous.weeklyGoal : Season.defaultWeeklyGoal),
            categories: copiedCategories,
            milestones: carriedMilestones
        )
        season.startedAt = Date()

        // Capture the full restorable copy BEFORE trimming anything, so
        // what the person left behind is preserved rather than deleted.
        archiveCurrentSeasonAsChapter()

        // Now trim the live graph to the plan. Order matters: tasks go
        // first so trains and boosters can be checked against what
        // actually survived.
        tasks = tasks.filter { plan.taskIds.contains($0.id) }
        if !plan.schedule {
            for idx in tasks.indices {
                tasks[idx].pinSchedule = .none
                tasks[idx].oneOffPinDate = nil
                tasks[idx].skipDate = nil
                tasks[idx].timeWindow = nil
                tasks[idx].partOfDay = .anytime
                tasks[idx].agendaOrder = nil
                tasks[idx].templateStamp = nil
            }
        }
        todos = todos.filter { plan.todoIds.contains($0.id) }
        avoidanceItems = avoidanceItems.filter { plan.avoidanceIds.contains($0.id) }
        for idx in avoidanceItems.indices { avoidanceItems[idx].seasonId = newId }

        // A booster pointing at a task that didn't survive would never
        // fire and could never be explained. Category boosters always
        // survive — they don't name a task.
        let liveTaskIds = Set(tasks.map(\.id))
        boosters = boosters.filter { booster in
            guard plan.boosterIds.contains(booster.id) else { return false }
            switch booster.reference {
            case .task(let id): return liveTaskIds.contains(id)
            case .category: return true
            }
        }
        for idx in boosters.indices { boosters[idx].seasonId = newId }

        // Same for trains: a train missing a step is a routine that can
        // never complete, so drop the dead steps and then the train if
        // nothing scoreable is left.
        habitTrains = habitTrains.compactMap { train in
            guard plan.habitTrainIds.contains(train.id) else { return nil }
            var copy = train
            copy.steps = train.steps.filter { step in
                step.type == .note || (step.taskId.map(liveTaskIds.contains) ?? false)
            }
            copy.seasonId = newId
            return copy.steps.contains { $0.type == .task } ? copy : nil
        }

        currentSeason = season
        persistAll()
        MilestoneNudgeService.refresh(for: season)
        republishSeasonCardNow()
        return season
    }

    /// Start a fresh season carrying everything forward — the shorthand
    /// for "same setup, new chapter."
    ///
    /// This used to be its own copy of the logic, and it silently
    /// dropped every milestone on the way through: an unfinished
    /// milestone vanished with no warning and no way back except
    /// restoring the whole archived season. It now goes through the same
    /// path as the picker, with everything selected, so there is exactly
    /// one description of what carrying a season forward means.
    @discardableResult
    func startNewSeasonFromCurrent(
        name: String? = nil,
        lengthDays: Int? = nil,
        dailyGoal: Int? = nil,
        weeklyGoal: Int? = nil
    ) -> Season {
        startNewSeason(
            importing: .everything(from: self),
            name: name,
            lengthDays: lengthDays,
            dailyGoal: dailyGoal,
            weeklyGoal: weeklyGoal
        )
    }
}
