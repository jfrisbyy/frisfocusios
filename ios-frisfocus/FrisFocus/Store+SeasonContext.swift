//
//  Store+SeasonContext.swift
//  FrisFocus
//
//  Builds the warm-start envelope (`ColdStartContext`) from the live
//  season + log history, so the season conversation opens already knowing
//  what the person chose, built, and has actually been doing.
//
//  Entry richness differs: the day-1 fork sends directions only (built at
//  the pick screen); the invitation card, settings resume, and season
//  detail send this full picture. Everything here is local — no network,
//  no model — and any subset may be empty.
//

import Foundation

extension Store {
    /// The full warm-start envelope from the current season: its
    /// directions (category names), the priced board, the north stars, and
    /// a per-task activity summary since the season began.
    func makeSeasonSetupContext() -> ColdStartContext {
        let cal = Calendar.current
        let seasonStart = cal.startOfDay(for: currentSeason.startedAt ?? currentSeason.startDate)

        // Directions — the season's category display names, in order.
        let directions: [String] = currentSeason.categories.map { seasonCategory in
            let custom = seasonCategory.customName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let custom, !custom.isEmpty { return custom }
            return seasonCategory.category.displayName
        }

        // Board — rank tasks by value and split into thirds to recover a
        // plausible effort band (the exact band placement isn't persisted;
        // this is context for the chat, not scoring).
        let board = boardItems()

        // North stars — the free-written milestones, in the person's words.
        let northStars: [String] = currentSeason.milestones
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Logs — completions and distinct active days per task since the
        // season started.
        let (logs, daysActive) = logSummaries(since: seasonStart, calendar: cal)

        return ColdStartContext(
            directions: directions,
            subDirections: [],
            board: board,
            northStars: northStars,
            logs: logs,
            daysActive: daysActive
        )
    }

    /// The board, priced and banded (bands recovered by value-thirds).
    private func boardItems() -> [ColdStartContext.BoardItem] {
        let ranked = tasks.sorted { $0.pointValue > $1.pointValue }
        guard !ranked.isEmpty else { return [] }
        let count = ranked.count

        func band(forIndex index: Int) -> (name: String, rank: Int) {
            // Top third = ideal (heaviest), middle = normal, bottom = floor.
            let third = max(1, Int((Double(count) / 3.0).rounded(.up)))
            if index < third { return ("ideal", index) }
            if index < third * 2 { return ("normal", index - third) }
            return ("floor", index - third * 2)
        }

        return ranked.enumerated().map { index, task in
            let b = band(forIndex: index)
            return ColdStartContext.BoardItem(
                label: task.title,
                band: b.name,
                bandRank: max(0, b.rank),
                value: task.scoring.headlineValue(flatValue: task.pointValue),
                isCustom: task.isCustom
            )
        }
    }

    /// Per-task completion counts + distinct active days since the season
    /// began, plus the overall count of distinct active days.
    private func logSummaries(
        since seasonStart: Date,
        calendar cal: Calendar
    ) -> ([ColdStartContext.LogSummary], Int) {
        let titleById: [UUID: String] = Dictionary(
            tasks.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )

        var completionsByTask: [UUID: Int] = [:]
        var daysByTask: [UUID: Set<Date>] = [:]
        var allActiveDays: Set<Date> = []

        for entry in logEntries {
            guard entry.entryType == .completed,
                  let taskId = entry.taskId,
                  titleById[taskId] != nil else { continue }
            let day = cal.startOfDay(for: entry.date)
            guard day >= seasonStart else { continue }
            completionsByTask[taskId, default: 0] += 1
            daysByTask[taskId, default: []].insert(day)
            allActiveDays.insert(day)
        }

        let summaries: [ColdStartContext.LogSummary] = completionsByTask
            .compactMap { taskId, completions in
                guard let title = titleById[taskId] else { return nil }
                return ColdStartContext.LogSummary(
                    task: title,
                    completions: completions,
                    daysActive: daysByTask[taskId]?.count ?? 0
                )
            }
            .sorted { $0.completions > $1.completions }

        return (summaries, allActiveDays.count)
    }
}
