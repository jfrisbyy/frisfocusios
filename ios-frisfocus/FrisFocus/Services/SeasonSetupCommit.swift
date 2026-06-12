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
    /// - Draft tasks become `.daily`-pinned FFTasks with their scoring
    ///   shape intact; the previous board is replaced (log history and
    ///   to-dos stay untouched).
    /// - Weekly floors attach as `PenaltyRule`s to the referenced task;
    ///   boosters reference the task when the name resolves, otherwise
    ///   the task's whole category.
    @discardableResult
    func startSeason(from draft: RubricDraft, name: String, lengthDays: Int) -> Season {
        let seasonId = UUID()
        let slots: [Category] = [.spiritual, .fitness, .health, .work, .creative, .apartment]

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

        // Milestones, spread across the season's weeks.
        let weeks = max(1, lengthDays / 7)
        let milestones: [Milestone] = draft.milestones.enumerated().map { index, m in
            let count = max(1, draft.milestones.count)
            let week = max(1, min(weeks, Int((Double(index + 1) / Double(count)) * Double(weeks))))
            return Milestone(
                seasonId: seasonId,
                weekNumber: week,
                title: m.name,
                status: .upcoming,
                pointValue: m.value
            )
        }

        let season = Season(
            id: seasonId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Season" : name,
            lengthDays: max(7, lengthDays),
            startDate: Calendar.current.startOfDay(for: Date()),
            vibe: .coolDawn,
            dailyGoal: max(1, draft.dailyTarget),
            weeklyGoal: max(1, draft.weeklyTarget),
            categories: seasonCategories,
            milestones: milestones
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
                pinSchedule: .daily,
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

        // The freeze. Log history, to-dos, and notes stay untouched.
        // The season being replaced is archived as a past chapter first
        // so profile pages can tell the story season by season.
        archiveCurrentSeasonAsChapter()
        currentSeason = season
        tasks = newTasks
        avoidanceItems = newNegatives
        boosters = newBoosters
        persistAll()
        return season
    }
}
