//
//  SeasonSetupCommit.swift
//  FrisFocus
//
//  The freeze: turns an edited `RubricDraft` into the Store's live
//  season graph — Season (targets, categories, milestones), the daily
//  FFTask board, standalone negatives, first-class weekly boosters, and
//  task-attached weekly floors. One-shot and local; after this, daily
//  scoring is pure math against the frozen rubric.
//

import Foundation

extension Store {
    /// Freeze `draft` as a brand-new season starting today.
    ///
    /// Mapping notes:
    /// - Draft categories occupy the app's stable `Category` slots in
    ///   order, carrying their own name + color as per-season overrides
    ///   (the same mechanism the categories editor uses). First two read
    ///   as primary, next two support, the rest quiet.
    /// - Draft tasks become FFTasks with their scoring shape intact and
    ///   no pin schedule (`.none`), so a new season starts with an empty
    ///   Today's Plan; the user deliberately pins what to work on. The
    ///   previous board is replaced (log history and to-dos stay untouched).
    /// - Weekly floors attach as `PenaltyRule`s to the referenced task;
    ///   boosters reference the task when the name resolves, otherwise
    ///   the task's whole category.
    /// - Milestones start unscheduled — a clean list with no target date
    ///   and no forced "week" assignment; the user can give any one a
    ///   target date later from the milestone editor.
    /// - `endMode` decides how the season ends: open-ended (default),
    ///   when every milestone lands, or on a chosen `endDate`. The stored
    ///   `lengthDays` is derived from `endDate` for date-ending seasons
    ///   and kept as a quiet nominal value otherwise (the day counter and
    ///   stats read `endMode` to know whether to show a total).
    @discardableResult
    func startSeason(
        from draft: RubricDraft,
        name: String,
        endMode: SeasonEndMode,
        endDate: Date?
    ) -> Season {
        let seasonId = UUID()
        let slots: [Category] = [.spiritual, .fitness, .health, .work, .creative, .apartment]
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())

        // Derive the stored length. Date-ending seasons measure to the
        // chosen end date; open-ended / milestone seasons keep a nominal
        // 90 that display code never shows (it branches on `endMode`).
        let resolvedEndDate: Date? = endMode == .date ? endDate : nil
        let lengthDays: Int = {
            guard endMode == .date, let endDate else { return 90 }
            let days = cal.dateComponents([.day], from: startOfToday, to: cal.startOfDay(for: endDate)).day ?? 90
            return max(1, days)
        }()

        // Category slots + per-season name/color overrides.
        var slotByDraftId: [UUID: Category] = [:]
        var seasonCategories: [SeasonCategory] = []
        for (index, draftCategory) in draft.categories.prefix(slots.count).enumerated() {
            let slot = slots[index]
            slotByDraftId[draftCategory.id] = slot
            let tier: CategoryTier = index < 2 ? .primary : (index < 4 ? .support : .quiet)
            seasonCategories.append(
                SeasonCategory(
                    category: slot,
                    tier: tier,
                    customName: draftCategory.name,
                    customColorHex: draftCategory.colorHex
                )
            )
        }
        if seasonCategories.isEmpty {
            seasonCategories = [SeasonCategory(category: .health, tier: .primary)]
        }

        // Milestones start as a clean, unscheduled list — no scatter into
        // random weeks and no target date. The user opts into a target
        // date per milestone from the editor.
        let milestones: [Milestone] = draft.milestones.map { m in
            Milestone(
                seasonId: seasonId,
                weekNumber: 1,
                title: m.name,
                status: .upcoming,
                pointValue: m.value
            )
        }

        var season = Season(
            id: seasonId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Season" : name,
            lengthDays: max(1, lengthDays),
            startDate: startOfToday,
            startedAt: Date(),
            vibe: .coolDawn,
            dailyGoal: max(1, draft.dailyTarget),
            weeklyGoal: max(1, draft.weeklyTarget),
            categories: seasonCategories,
            milestones: milestones,
            endMode: endMode,
            endDate: resolvedEndDate
        )

        // The daily task board.
        var newTasks: [FFTask] = []
        var taskIdByName: [String: UUID] = [:]
        for draftTask in draft.tasks {
            guard let slot = slotByDraftId[draftTask.categoryId] else { continue }
            let scoring: ScoringConfig
            switch draftTask.shape {
            case .flat:
                scoring = ScoringConfig()
            case .tiered:
                scoring = ScoringConfig(
                    type: .tiered,
                    unit: draftTask.unit,
                    tiers: draftTask.tiers
                )
            case .quantity:
                scoring = ScoringConfig(
                    type: .quantity,
                    unit: draftTask.unit,
                    baseThreshold: draftTask.baseThreshold,
                    basePoints: draftTask.basePoints,
                    unitSize: max(1, draftTask.unitSize),
                    pointsPerUnit: draftTask.pointsPerUnit
                )
            }
            var task = FFTask(
                title: draftTask.name,
                category: slot,
                pointValue: max(1, draftTask.value),
                pinSchedule: .none,
                scoring: scoring
            )
            // Weekly floor referencing this task → attached penalty rule.
            if let floor = draft.weeklyPenalties.first(where: {
                $0.referenceName.caseInsensitiveCompare(draftTask.name) == .orderedSame
            }) {
                task.penalty = PenaltyRule(
                    enabled: true,
                    timesThreshold: floor.threshold,
                    condition: .lessThan,
                    penaltyPoints: floor.value
                )
            }
            taskIdByName[draftTask.name.lowercased()] = task.id
            newTasks.append(task)
        }

        // Negatives — standalone avoidance items bound to the new season.
        let newNegatives: [AvoidanceItem] = draft.negatives.map { negative in
            AvoidanceItem(
                name: negative.name,
                pointsPerOccurrence: max(1, negative.value),
                seasonId: seasonId,
                negativeType: negative.shape,
                window: negative.window,
                freeCount: negative.shape == .frequencyThreshold ? max(0, negative.freeCount) : 0
            )
        }

        // Boosters — reference the named task when it resolves, else the
        // first category as a whole-area consistency reward.
        let fallbackCategory = seasonCategories.first?.category ?? .health
        let newBoosters: [WeeklyBooster] = draft.boosters.map { booster in
            let reference: BoosterReference
            if let taskId = taskIdByName[booster.referenceName.lowercased()] {
                reference = .task(taskId)
            } else {
                reference = .category(fallbackCategory)
            }
            return WeeklyBooster(
                seasonId: seasonId,
                name: booster.name,
                reference: reference,
                threshold: max(1, booster.threshold),
                period: .week,
                bonusPoints: max(1, booster.value)
            )
        }

        // The freeze. A new season is a clean slate: the previous board's
        // tasks and to-dos are cleared so nothing from the old chapter
        // bleeds in, and `startedAt` scopes the live score so today opens
        // at zero. Log history and notes stay untouched (the rhythm chart
        // still tells the full story). The season being replaced is
        // archived as a past chapter first so profile pages can tell the
        // story season by season.
        // Same clamp as the edit-in-place path, applied here only now
        // that the board exists: the target and the task list are separate
        // parts of the model's reply and nothing makes them agree, so a
        // target the tasks cannot reach would leave the sun unfillable
        // from day one. Only ever lowered — a reachable target is left as
        // the conversation set it.
        let reachable = Store.strongDayValue(from: newTasks)
        season.dailyGoal = min(season.dailyGoal, reachable)
        season.weeklyGoal = max(season.dailyGoal, min(season.weeklyGoal, season.dailyGoal * 7))

        archiveCurrentSeasonAsChapter()
        currentSeason = season
        tasks = newTasks
        todos = []
        avoidanceItems = newNegatives
        boosters = newBoosters
        persistAll()
        // Cancel any milestone reminders left pending from the finished
        // season and schedule only the new season's milestone nudges, so
        // no ghost notification fires for a goal that no longer exists.
        MilestoneNudgeService.refresh(for: season)
        // Push the fresh season card right away so friends stop seeing
        // the finished season's name, cover, and milestone tally the
        // instant the new season begins, not after the next sync flush.
        republishSeasonCardNow()
        return season
    }

    /// Graduate a PROVISIONAL cold-start season by editing it IN PLACE.
    ///
    /// The season conversation, when reached by a cold-start user (via the
    /// invitation card, settings resume, or season detail), refines the
    /// season they already have — it must NEVER archive-and-replace it, or
    /// a parallel "first" season would appear. So this keeps the same
    /// season id, start date, `startedAt`, and cover, preserves the whole
    /// log history and the sun's continuity, replaces the board with the
    /// conversation's priced tasks, and clears `isProvisional` (the
    /// invitation card retires the instant this lands).
    @discardableResult
    func editProvisionalSeason(
        from draft: RubricDraft,
        name: String,
        endMode: SeasonEndMode,
        endDate: Date?
    ) -> Season {
        let seasonId = currentSeason.id
        let slots: [Category] = [.spiritual, .fitness, .health, .work, .creative, .apartment]
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: currentSeason.startDate)

        let resolvedEndDate: Date? = endMode == .date ? endDate : nil
        let lengthDays: Int = {
            guard endMode == .date, let endDate else { return currentSeason.lengthDays }
            let days = cal.dateComponents([.day], from: startOfToday, to: cal.startOfDay(for: endDate)).day ?? 90
            return max(1, days)
        }()

        var slotByDraftId: [UUID: Category] = [:]
        var seasonCategories: [SeasonCategory] = []
        for (index, draftCategory) in draft.categories.prefix(slots.count).enumerated() {
            let slot = slots[index]
            slotByDraftId[draftCategory.id] = slot
            let tier: CategoryTier = index < 2 ? .primary : (index < 4 ? .support : .quiet)
            seasonCategories.append(
                SeasonCategory(
                    category: slot,
                    tier: tier,
                    customName: draftCategory.name,
                    customColorHex: draftCategory.colorHex
                )
            )
        }
        if seasonCategories.isEmpty {
            seasonCategories = currentSeason.categories.isEmpty
                ? [SeasonCategory(category: .health, tier: .primary)]
                : currentSeason.categories
        }

        let milestones: [Milestone] = draft.milestones.map { m in
            Milestone(
                seasonId: seasonId,
                weekNumber: 1,
                title: m.name,
                status: .upcoming,
                pointValue: m.value
            )
        }

        var newTasks: [FFTask] = []
        var taskIdByName: [String: UUID] = [:]
        for draftTask in draft.tasks {
            guard let slot = slotByDraftId[draftTask.categoryId] else { continue }
            let scoring: ScoringConfig
            switch draftTask.shape {
            case .flat:
                scoring = ScoringConfig()
            case .tiered:
                scoring = ScoringConfig(type: .tiered, unit: draftTask.unit, tiers: draftTask.tiers)
            case .quantity:
                scoring = ScoringConfig(
                    type: .quantity,
                    unit: draftTask.unit,
                    baseThreshold: draftTask.baseThreshold,
                    basePoints: draftTask.basePoints,
                    unitSize: max(1, draftTask.unitSize),
                    pointsPerUnit: draftTask.pointsPerUnit
                )
            }
            var task = FFTask(
                title: draftTask.name,
                category: slot,
                pointValue: max(1, draftTask.value),
                pinSchedule: .none,
                scoring: scoring
            )
            if let floor = draft.weeklyPenalties.first(where: {
                $0.referenceName.caseInsensitiveCompare(draftTask.name) == .orderedSame
            }) {
                task.penalty = PenaltyRule(
                    enabled: true,
                    timesThreshold: floor.threshold,
                    condition: .lessThan,
                    penaltyPoints: floor.value
                )
            }
            taskIdByName[draftTask.name.lowercased()] = task.id
            newTasks.append(task)
        }

        let newNegatives: [AvoidanceItem] = draft.negatives.map { negative in
            AvoidanceItem(
                name: negative.name,
                pointsPerOccurrence: max(1, negative.value),
                seasonId: seasonId,
                negativeType: negative.shape,
                window: negative.window,
                freeCount: negative.shape == .frequencyThreshold ? max(0, negative.freeCount) : 0
            )
        }

        let fallbackCategory = seasonCategories.first?.category ?? .health
        let newBoosters: [WeeklyBooster] = draft.boosters.map { booster in
            let reference: BoosterReference
            if let taskId = taskIdByName[booster.referenceName.lowercased()] {
                reference = .task(taskId)
            } else {
                reference = .category(fallbackCategory)
            }
            return WeeklyBooster(
                seasonId: seasonId,
                name: booster.name,
                reference: reference,
                threshold: max(1, booster.threshold),
                period: .week,
                bonusPoints: max(1, booster.value)
            )
        }

        // Edit in place — same season id, dates, and cover; the log history
        // and the sun's progress carry through untouched.
        // The daily target here comes from the conversation, not from a
        // formula, so it is deliberately NOT recalibrated the way the
        // cold start's provisional one is — the person discussed what a
        // day looks like and that answer should stand.
        //
        // But the target and the task list are two separate parts of the
        // model's reply, and nothing guarantees they agree. If it asks
        // for more than a whole strong day of the tasks it just wrote,
        // the sun cannot be filled — the same unreachable-sun the cold
        // start had, arriving by a different route. Clamp only in that
        // direction: a target the tasks can already reach is left exactly
        // as the conversation set it.
        let reachable = Store.strongDayValue(from: newTasks)
        let requested = max(1, draft.dailyTarget)
        let dailyGoal = min(requested, reachable)

        var season = currentSeason
        season.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? season.name : name
        season.lengthDays = max(1, lengthDays)
        season.dailyGoal = dailyGoal
        season.weeklyGoal = max(dailyGoal, min(max(1, draft.weeklyTarget), dailyGoal * 7))
        season.categories = seasonCategories
        season.milestones = milestones
        season.endMode = endMode
        season.endDate = resolvedEndDate
        season.isProvisional = false

        currentSeason = season
        tasks = newTasks
        avoidanceItems = newNegatives
        boosters = newBoosters
        persistAll()
        MilestoneNudgeService.refresh(for: season)
        republishSeasonCardNow()
        return season
    }
}
