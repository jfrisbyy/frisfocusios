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

        let season = Season(
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
}
