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
        // Every slot the model may be given. This list used to hold six
        // while the conversation was told it could build up to eight
        // areas and the server kept eight, so a seventh or eighth
        // category — and every task inside it — was dropped here with
        // no error and nothing on screen. `Category.allCases` keeps the
        // two in step by construction from now on.
        let slots: [Category] = Category.allCases
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
        var takenSlots: Set<Category> = []
        for (index, draftCategory) in draft.categories.prefix(slots.count).enumerated() {
            let slot = Category.bestSlot(for: draftCategory.name, avoiding: takenSlots)
            takenSlots.insert(slot)
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
            // The stages of a decomposed goal. The conversation emits
            // them, the draft carries them, and the review screen shows
            // and edits them by name and price — and this map used to
            // build a `Milestone` without them, so every rung the person
            // had just been looking at was gone the moment they tapped
            // through. A staged destination arrived as a single boulder.
            let steps = m.steps.enumerated().map { index, step in
                MilestoneStep(
                    title: step.name,
                    orderIndex: index,
                    pointValue: max(0, step.value)
                )
            }
            return Milestone(
                seasonId: seasonId,
                weekNumber: 1,
                title: m.name,
                status: .upcoming,
                pointValue: m.value,
                steps: steps,
                // Per-step credit only where a step was actually priced.
                // Turning it on for progress-only stages would silently
                // move points off the destination and onto zeroes.
                pointsPerStep: steps.contains { $0.pointValue > 0 }
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
            // A task whose category found no slot is re-homed rather than
            // deleted. There should be none now that the slots match what
            // the flow promises, but silently dropping someone's work is
            // never the right answer to a mismatch nobody predicted.
            guard let slot = slotByDraftId[draftTask.categoryId] ?? seasonCategories.last?.category else { continue }
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
                // The conversation estimates how long everything takes
                // and the estimate was thrown away at the door, so a
                // board built from a fifteen-minute interview arrived
                // with nothing for the agenda to lay a day out with.
                estimatedMinutes: draftTask.estimatedMinutes,
                // The week the season describes. Unpinned left the plan
                // empty the morning after a fifteen-minute interview;
                // pinning everything to every day replaced that with a
                // wall. Both were guesses standing in for the frequency
                // the rubric had been stating all along — a booster
                // reading "three gym days" is three days a week.
                pinSchedule: draftTask.isEveryDay ? .daily : .daysOfWeek(draftTask.days),
                scoring: scoring
            )
            // Weekly floor referencing this task → attached penalty rule.
            // Every floor referencing this task, not just the first.
            // Taking `.first` dropped the rest without a word, so
            // someone who wanted both "at least three runs" and "at
            // least 15km" lost one and never learned which.
            let floors = draft.weeklyPenalties
                .filter { $0.referenceName.caseInsensitiveCompare(draftTask.name) == .orderedSame }
                .map { floor in
                    PenaltyRule(
                        enabled: true,
                        timesThreshold: floor.threshold,
                        condition: .lessThan,
                        penaltyPoints: floor.value,
                        metric: floor.metric
                    )
                }
            task.penalty = floors.first
            task.extraPenalties = Array(floors.dropFirst())
            // Where in the day it sits. `.anytime` is the tray, which is
            // the honest answer for most of a board — the agenda bands
            // hold what someone actually placed.
            task.partOfDay = draftTask.partOfDay
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
                freeCount: negative.shape == .frequencyThreshold ? max(0, negative.freeCount) : 0,
                tiers: negative.shape == .tiered ? negative.tiers : []
            )
        }

        // Boosters reference the named task. An unresolved name used to
        // fall back to `.category(seasonCategories.first)` — "any task in
        // whatever area happened to be listed first" — so a booster for
        // six lifting days could quietly become a booster on prayer. A
        // booster nobody can explain is worse than one that isn't there,
        // and the server now drops unmatched references before this.
        let newBoosters: [WeeklyBooster] = draft.boosters.compactMap { booster in
            // A manual goal names no task on purpose, so the
            // resolve-or-drop rule below must not eat it.
            let reference: BoosterReference
            if booster.isManual {
                reference = .manual
            } else if let taskId = taskIdByName[booster.referenceName.lowercased()] {
                reference = .task(taskId)
            } else {
                return nil
            }
            return WeeklyBooster(
                seasonId: seasonId,
                name: booster.name,
                reference: reference,
                metric: booster.metric,
                threshold: booster.isManual ? 1 : max(1, booster.threshold),
                period: .week,
                bonusPoints: max(1, booster.value)
            )
        }

        // Blocks of committed time. These are the one part of the day
        // shape the conversation cannot derive — it is forbidden from
        // asking when anything happens — so they exist only because
        // someone named them on the shaping screen.
        let newBuckets: [Bucket] = draft.buckets.compactMap { draftBucket in
            guard let slot = slotByDraftId[draftBucket.categoryId] ?? seasonCategories.first?.category else {
                return nil
            }
            let window: TimeWindow? = draftBucket.startMinutes.map { start in
                TimeWindow(
                    startMinutes: start,
                    endMinutes: max(draftBucket.endMinutes ?? start + 60, start)
                )
            }
            return Bucket(
                title: draftBucket.title,
                category: slot,
                pointValue: max(1, draftBucket.value),
                timeWindow: window,
                // A block with a real clock is placed by it; one without
                // floats in the band it was given.
                partOfDay: window == nil ? draftBucket.partOfDay : .anytime,
                pinSchedule: draftBucket.isEveryDay ? .daily : .daysOfWeek(draftBucket.days),
                candidateTitles: draftBucket.candidates
            )
        }

        // The freeze. A new season is a clean slate: the previous board's
        // tasks and to-dos are cleared so nothing from the old chapter
        // bleeds in, and `startedAt` scopes the live score so today opens
        // at zero. Log history and notes stay untouched (the rhythm chart
        // still tells the full story). The season being replaced is
        // archived as a past chapter first so profile pages can tell the
        // story season by season.
        // A safety floor, not a second opinion.
        //
        // This used to be `min(dailyGoal, Store.strongDayValue(...))`.
        // Setup tasks are all created unpinned, so `strongDayValue` fell
        // through to "the sum of the four highest-valued tasks" — a
        // cold-start heuristic. With task values capped at 10 that put a
        // hard ceiling of 40 on any conversation-built season, no matter
        // how large: a fifty-task board calibrated to a daily 55 was
        // silently cut to the low thirties, and the number the person had
        // said out loud was replaced without a word. The server already
        // validates the target against a knapsack over a real day; the
        // app cannot reproduce that and should not overrule it.
        //
        // What remains is the case that check was actually for: a target
        // the whole board cannot reach, which would leave the sun
        // unfillable from day one.
        let everythingInADay = newTasks.reduce(0) { sum, task in
            sum + max(1, task.scoring.headlineValue(flatValue: task.pointValue))
        }
        if everythingInADay > 0 {
            season.dailyGoal = min(season.dailyGoal, everythingInADay)
        }
        // Weekly was capped at 7× daily, which contradicted the flow's own
        // teaching — and its own worked example, "daily 55 → weekly ~400",
        // is 7.3×. A strong week is solid days PLUS the end-of-week
        // bonuses, so the ceiling has to leave room for them.
        let boosterHeadroom = newBoosters.reduce(0) { $0 + max(0, $1.bonusPoints) }
        season.weeklyGoal = max(
            season.dailyGoal,
            min(season.weeklyGoal, season.dailyGoal * 7 + boosterHeadroom)
        )

        archiveCurrentSeasonAsChapter()
        currentSeason = season
        tasks = newTasks
        todos = []
        avoidanceItems = newNegatives
        boosters = newBoosters
        buckets = newBuckets
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
        // Every slot the model may be given. This list used to hold six
        // while the conversation was told it could build up to eight
        // areas and the server kept eight, so a seventh or eighth
        // category — and every task inside it — was dropped here with
        // no error and nothing on screen. `Category.allCases` keeps the
        // two in step by construction from now on.
        let slots: [Category] = Category.allCases
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
        var takenSlots: Set<Category> = []
        for (index, draftCategory) in draft.categories.prefix(slots.count).enumerated() {
            let slot = Category.bestSlot(for: draftCategory.name, avoiding: takenSlots)
            takenSlots.insert(slot)
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
            // The stages of a decomposed goal. The conversation emits
            // them, the draft carries them, and the review screen shows
            // and edits them by name and price — and this map used to
            // build a `Milestone` without them, so every rung the person
            // had just been looking at was gone the moment they tapped
            // through. A staged destination arrived as a single boulder.
            let steps = m.steps.enumerated().map { index, step in
                MilestoneStep(
                    title: step.name,
                    orderIndex: index,
                    pointValue: max(0, step.value)
                )
            }
            return Milestone(
                seasonId: seasonId,
                weekNumber: 1,
                title: m.name,
                status: .upcoming,
                pointValue: m.value,
                steps: steps,
                // Per-step credit only where a step was actually priced.
                // Turning it on for progress-only stages would silently
                // move points off the destination and onto zeroes.
                pointsPerStep: steps.contains { $0.pointValue > 0 }
            )
        }

        var newTasks: [FFTask] = []
        var taskIdByName: [String: UUID] = [:]
        for draftTask in draft.tasks {
            // A task whose category found no slot is re-homed rather than
            // deleted. There should be none now that the slots match what
            // the flow promises, but silently dropping someone's work is
            // never the right answer to a mismatch nobody predicted.
            guard let slot = slotByDraftId[draftTask.categoryId] ?? seasonCategories.last?.category else { continue }
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
                // The conversation estimates how long everything takes
                // and the estimate was thrown away at the door, so a
                // board built from a fifteen-minute interview arrived
                // with nothing for the agenda to lay a day out with.
                estimatedMinutes: draftTask.estimatedMinutes,
                // The week the season describes. Unpinned left the plan
                // empty the morning after a fifteen-minute interview;
                // pinning everything to every day replaced that with a
                // wall. Both were guesses standing in for the frequency
                // the rubric had been stating all along — a booster
                // reading "three gym days" is three days a week.
                pinSchedule: draftTask.isEveryDay ? .daily : .daysOfWeek(draftTask.days),
                scoring: scoring
            )
            // Every floor referencing this task, not just the first.
            // Taking `.first` dropped the rest without a word, so
            // someone who wanted both "at least three runs" and "at
            // least 15km" lost one and never learned which.
            let floors = draft.weeklyPenalties
                .filter { $0.referenceName.caseInsensitiveCompare(draftTask.name) == .orderedSame }
                .map { floor in
                    PenaltyRule(
                        enabled: true,
                        timesThreshold: floor.threshold,
                        condition: .lessThan,
                        penaltyPoints: floor.value,
                        metric: floor.metric
                    )
                }
            task.penalty = floors.first
            task.extraPenalties = Array(floors.dropFirst())
            // Where in the day it sits. `.anytime` is the tray, which is
            // the honest answer for most of a board — the agenda bands
            // hold what someone actually placed.
            task.partOfDay = draftTask.partOfDay
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
                freeCount: negative.shape == .frequencyThreshold ? max(0, negative.freeCount) : 0,
                tiers: negative.shape == .tiered ? negative.tiers : []
            )
        }

        // Boosters reference the named task. An unresolved name used to
        // fall back to `.category(seasonCategories.first)` — "any task in
        // whatever area happened to be listed first" — so a booster for
        // six lifting days could quietly become a booster on prayer. A
        // booster nobody can explain is worse than one that isn't there,
        // and the server now drops unmatched references before this.
        let newBoosters: [WeeklyBooster] = draft.boosters.compactMap { booster in
            // A manual goal names no task on purpose, so the
            // resolve-or-drop rule below must not eat it.
            let reference: BoosterReference
            if booster.isManual {
                reference = .manual
            } else if let taskId = taskIdByName[booster.referenceName.lowercased()] {
                reference = .task(taskId)
            } else {
                return nil
            }
            return WeeklyBooster(
                seasonId: seasonId,
                name: booster.name,
                reference: reference,
                metric: booster.metric,
                threshold: booster.isManual ? 1 : max(1, booster.threshold),
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
        // for more than the WHOLE BOARD is worth in a day, the sun cannot
        // be filled — the same unreachable-sun the cold start had,
        // arriving by a different route.
        //
        // The measure used to be `Store.strongDayValue`, which for the
        // unpinned tasks this path creates means "the four highest
        // values" — a cold-start heuristic that capped every
        // conversation-built season at 40 points regardless of size. The
        // server already validates the target against a knapsack over a
        // real day; this is only a floor against the impossible.
        let everythingInADay = newTasks.reduce(0) { sum, task in
            sum + max(1, task.scoring.headlineValue(flatValue: task.pointValue))
        }
        let requested = max(1, draft.dailyTarget)
        let dailyGoal = everythingInADay > 0 ? min(requested, everythingInADay) : requested

        // Blocks of committed time — the one part of the day shape the
        // conversation cannot derive, so they exist only because someone
        // named them on the shaping screen.
        let newBuckets: [Bucket] = draft.buckets.compactMap { draftBucket in
            guard let slot = slotByDraftId[draftBucket.categoryId] ?? seasonCategories.first?.category else {
                return nil
            }
            let window: TimeWindow? = draftBucket.startMinutes.map { start in
                TimeWindow(
                    startMinutes: start,
                    endMinutes: max(draftBucket.endMinutes ?? start + 60, start)
                )
            }
            return Bucket(
                title: draftBucket.title,
                category: slot,
                pointValue: max(1, draftBucket.value),
                timeWindow: window,
                partOfDay: window == nil ? draftBucket.partOfDay : .anytime,
                pinSchedule: draftBucket.isEveryDay ? .daily : .daysOfWeek(draftBucket.days),
                candidateTitles: draftBucket.candidates
            )
        }

        var season = currentSeason
        season.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? season.name : name
        season.lengthDays = max(1, lengthDays)
        season.dailyGoal = dailyGoal
        // Room for the end-of-week bonuses, which are exactly what makes
        // a strong week more than seven strong days.
        let boosterHeadroom = newBoosters.reduce(0) { $0 + max(0, $1.bonusPoints) }
        season.weeklyGoal = max(dailyGoal, min(max(1, draft.weeklyTarget), dailyGoal * 7 + boosterHeadroom))
        season.categories = seasonCategories
        season.milestones = milestones
        season.endMode = endMode
        season.endDate = resolvedEndDate
        season.isProvisional = false

        currentSeason = season
        tasks = newTasks
        avoidanceItems = newNegatives
        boosters = newBoosters
        buckets = newBuckets
        persistAll()
        MilestoneNudgeService.refresh(for: season)
        republishSeasonCardNow()
        return season
    }
}
