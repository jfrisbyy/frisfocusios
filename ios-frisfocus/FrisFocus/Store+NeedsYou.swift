//
//  Store+NeedsYou.swift
//  FrisFocus
//
//  The local ranking engine behind the smart "Needs You" section. Builds
//  one cross-type candidate list (open tasks, penalty routines, category
//  drift), scores each by a priority heuristic, sorts, and filters out the
//  cards the user has dismissed or snoozed for today.
//
//  This is 100% local logic — it NEVER calls a model. The only model call
//  in this feature is the once-daily Today's Read (see Store+TodaysRead).
//

import Foundation

extension Store {

    // MARK: - Active window

    /// Quiet-hours bounds: nothing surfaces before 10 AM or after 10 PM.
    var needsYouActiveHours: Range<Int> { 10..<22 }

    /// Coarse part of the day used to pick time-aware copy.
    enum TimeBucket { case morning, afternoon, evening }

    func needsYouTimeBucket(now: Date = Date()) -> TimeBucket {
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        return .evening
    }

    /// Whole-ish hours left before the active window closes (10 PM).
    func needsYouHoursLeft(now: Date = Date()) -> Int {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        return max(0, needsYouActiveHours.upperBound - hour)
    }

    /// Whether the section renders at all today (not history, within hours).
    /// When true but the ranked list is empty, the calm "all caught up"
    /// line takes the section's place instead of vanishing.
    var needsYouSectionVisible: Bool {
        guard !isViewingPast else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return needsYouActiveHours.contains(hour)
    }

    /// The day's target is already met — suppress the urgency cards.
    var needsYouTargetHit: Bool {
        todayScore >= max(1, currentSeason.dailyGoal)
    }

    // MARK: - Ranked list

    /// The single cross-type ranked Needs You list, already filtered for
    /// dismissed/snoozed cards and suppressed when the target is hit.
    /// Capping to the top few is the view's job (it keeps the overflow for
    /// the "+N more" expander).
    var rankedNeedsYou: [NeedsYouItem] {
        guard needsYouSectionVisible else { return [] }
        // Going quiet when you're winning: nothing to push once the day's
        // target is met.
        guard !needsYouTargetHit else { return [] }

        let now = Date()
        let bucket = needsYouTimeBucket(now: now)
        let hoursLeft = needsYouHoursLeft(now: now)
        var items: [NeedsYouItem] = []

        // 1. High-value open tasks pinned to today, not yet logged.
        let openTasks = tasks.filter {
            $0.isPinnedToday
                && $0.nominalValue >= reminderValueThreshold
                && !hasLogEntryToday(forTaskId: $0.id)
        }
        for task in openTasks {
            let penalty = abs(min(0, task.skipPenalty ?? 0))
            let heavy = (task.estimatedMinutes ?? 0) >= 60
            items.append(NeedsYouItem(
                key: "task:\(task.id.uuidString)",
                kind: .task,
                title: task.title,
                subtitle: taskSubtitle(value: task.nominalValue, penalty: penalty, bucket: bucket),
                priority: priorityScore(
                    value: task.nominalValue,
                    penalty: penalty,
                    timeSensitive: true,
                    driftDays: 0,
                    timeCompeting: heavy,
                    hoursLeft: hoursLeft
                ),
                taskId: task.id,
                routineId: nil,
                category: task.category,
                value: task.nominalValue,
                penalty: penalty,
                isTimeSensitive: true,
                driftDays: 0,
                timeCompeting: heavy
            ))
        }

        // 2. Linked Cadence routines with a skip penalty, not yet run.
        for link in todaysCadenceLinks where (link.skipPenalty ?? 0) < 0 {
            guard !isCadenceLinkEarnedToday(link) else { continue }
            let penalty = abs(link.skipPenalty ?? 0)
            let heavy = link.estMinutes >= 60
            items.append(NeedsYouItem(
                key: "routine:\(link.id.uuidString)",
                kind: .routine,
                title: link.routineName,
                subtitle: routineSubtitle(penalty: penalty, runWord: link.runWord, bucket: bucket),
                priority: priorityScore(
                    value: link.points,
                    penalty: penalty,
                    timeSensitive: true,
                    driftDays: 0,
                    timeCompeting: heavy,
                    hoursLeft: hoursLeft
                ),
                taskId: nil,
                routineId: link.id,
                category: link.category,
                value: link.points,
                penalty: penalty,
                isTimeSensitive: true,
                driftDays: 0,
                timeCompeting: heavy
            ))
        }

        // 3. Category drift — one card per non-Quiet category idle 7+ days.
        let quietCategories: Set<Category> = Set(
            currentSeason.categories.filter { $0.tier == .quiet }.map(\.category)
        )
        var coveredCategories: Set<Category> = []
        let cal = Calendar.current
        for task in tasks where !quietCategories.contains(task.category)
            && task.nominalValue >= reminderValueThreshold {
            guard !coveredCategories.contains(task.category) else { continue }

            let mostRecent = logEntries
                .filter { $0.taskId == task.id && $0.entryType == .completed }
                .map(\.date)
                .max()
            let daysSince: Int = {
                guard let mostRecent else { return Int.max }
                return cal.dateComponents([.day], from: mostRecent, to: now).day ?? Int.max
            }()
            guard daysSince >= 7 else { continue }
            coveredCategories.insert(task.category)

            let shownDays = min(daysSince, 99)
            items.append(NeedsYouItem(
                key: "drift:\(task.category.rawValue)",
                kind: .drift,
                title: "No \(categoryDisplayName(task.category)) time in \(shownDays) days",
                subtitle: driftSubtitle(category: task.category, days: shownDays, bucket: bucket),
                priority: priorityScore(
                    value: 0,
                    penalty: 0,
                    timeSensitive: false,
                    driftDays: shownDays,
                    timeCompeting: false,
                    hoursLeft: hoursLeft
                ),
                taskId: nil,
                routineId: nil,
                category: task.category,
                value: 0,
                penalty: 0,
                isTimeSensitive: false,
                driftDays: shownDays,
                timeCompeting: false
            ))
        }

        // Filter out anything dismissed or snoozed for today, then sort by
        // priority (descending) with a stable title tiebreak.
        return items
            .filter { !needsYou.isHidden(key: $0.key, now: now) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title < rhs.title
            }
    }

    // MARK: - Priority heuristic

    /// Blend the ranking signals into a single score. Tuned so a
    /// penalty-at-risk item outranks pure value, an expiring item beats an
    /// evergreen one with slack, long drift climbs, and — late in the day —
    /// heavy time-competing blocks sink while quick wins rise.
    private func priorityScore(
        value: Int,
        penalty: Int,
        timeSensitive: Bool,
        driftDays: Int,
        timeCompeting: Bool,
        hoursLeft: Int
    ) -> Double {
        var score = 0.0
        score += Double(penalty) * 3.0          // the day actively loses value
        score += Double(value) * 1.0            // points at stake
        if timeSensitive { score += 12.0 }      // expires today
        score += Double(min(driftDays, 30)) * 0.8

        // Hours-left shaping near the close of the active window.
        if hoursLeft <= 3 {
            if timeCompeting {
                score -= 14.0                    // no point surfacing a 2-hr block at 9 PM
            } else if value > 0 {
                score += 4.0                     // small quick wins rise
            }
        }
        return score
    }

    // MARK: - Time-aware templated copy (no model calls)

    private func taskSubtitle(value: Int, penalty: Int, bucket: TimeBucket) -> String {
        let dash = "\u{2212}"
        if penalty > 0 {
            switch bucket {
            case .morning: return "Skipping pulls \(dash)\(penalty) from the day"
            case .afternoon: return "\(dash)\(penalty) if it slips · still time"
            case .evening: return "\(dash)\(penalty) if skipped · the window's closing"
            }
        }
        switch bucket {
        case .morning: return "Worth \(value) · still open today"
        case .afternoon: return "Worth \(value) · the day's moving"
        case .evening: return "Worth \(value) · a few minutes still counts"
        }
    }

    private func routineSubtitle(penalty: Int, runWord: String, bucket: TimeBucket) -> String {
        let dash = "\u{2212}"
        switch bucket {
        case .morning, .afternoon:
            return "Not run \(runWord) · skipping pulls \(dash)\(penalty)"
        case .evening:
            return "Still un-run \(runWord) · \(dash)\(penalty) if skipped"
        }
    }

    private func driftSubtitle(category: Category, days: Int, bucket: TimeBucket) -> String {
        let flavor = driftFlavor(for: category)
        switch bucket {
        case .morning: return "\(flavor) · plenty of day to change that"
        case .afternoon: return "\(flavor) · a few minutes still counts"
        case .evening: return "\(flavor) · still time for fifteen minutes"
        }
    }

    /// Short editorial flavor paired to each category for drift nudges.
    private func driftFlavor(for category: Category) -> String {
        switch category {
        case .creative: return "The EP doesn\u{2019}t write itself"
        case .spiritual: return "Quiet time has been waiting"
        case .fitness: return "The body forgets quickly"
        case .health: return "Small habits compound"
        case .work: return "One small thing moves it"
        case .apartment: return "Little fixes pile up"
        case .learning: return "The thread drops fast"
        case .people: return "Someone's been waiting to hear from you"
        }
    }

    // MARK: - Witness-model actions

    /// Free, guilt-free decline — hide the card for the rest of today. No
    /// penalty, no confirm, no warning. The penalty (if any) was already
    /// shown in the subtitle; dismissing just stops surfacing it.
    func needsYouNotToday(_ item: NeedsYouItem) {
        needsYou.dismiss(key: item.key)
    }

    /// Re-surface the card after 5 PM (or, if it's already evening, two
    /// hours from now so it can still return tonight).
    func needsYouSnoozeTilEvening(_ item: NeedsYouItem, now: Date = Date()) {
        let cal = Calendar.current
        let fivePM = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
        let target = fivePM > now ? fivePM : now.addingTimeInterval(2 * 3600)
        needsYou.snooze(key: item.key, until: target)
    }

    /// Log the underlying task done from the card. Routines/drift have no
    /// direct log here (they open instead).
    func needsYouLog(_ item: NeedsYouItem) {
        guard let taskId = item.taskId,
              let task = tasks.first(where: { $0.id == taskId }) else { return }
        guard !hasLogEntryToday(forTaskId: task.id) else { return }
        captureUndo("Completed \u{201C}\(task.title)\u{201D}")
        completeTask(task)
    }

    /// The deep link to open a routine in Cadence, if this card is a
    /// routine with a known target.
    func needsYouOpenURL(_ item: NeedsYouItem) -> URL? {
        guard item.kind == .routine, let routineId = item.routineId,
              let link = cadenceLinks.first(where: { $0.id == routineId }) else { return nil }
        return link.runURL
    }
}
