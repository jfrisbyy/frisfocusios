//
//  ShareCardModels.swift
//  FrisFocus
//
//  Data for the "Share My Day" system (S3). The share camera renders a
//  live overlay — the sun-state mark, season name, completed-task chips,
//  attribution — entirely from these values. Everything is computed
//  locally from the frozen day data; no API calls anywhere in the flow.
//

import Foundation

/// One completed-task capsule on the share overlay ("Lifted",
/// "Built · 3 hrs"). `id` is the originating LogEntry's id so taps on
/// the viewfinder can hide/show a specific completion.
struct ShareTaskChip: Identifiable, Equatable {
    let id: UUID
    let label: String
}

/// What the sun-state mark renders: a single day's ratio, or the
/// weekly variant — seven small suns above one shared hairline.
enum ShareSunData: Equatable {
    case day(ratio: Double)
    case week(ratios: [Double])
}

/// Everything the overlay needs for one shareable day (or week).
/// `ratio` may exceed 1.0 — rays and the golden wash key off ≥ 1.
struct ShareDayContext: Equatable {
    var sun: ShareSunData
    var ratio: Double
    var percent: Int
    var seasonName: String
    var chips: [ShareTaskChip]
}

/// The user's disclosure choices from the Layers sheet plus per-chip
/// curation. The sun itself has no toggle — it is the mark.
struct ShareOverlayOptions: Equatable {
    var showSeasonName: Bool = true
    var showTasks: Bool = true
    /// The percent (never raw points). Off by default — opt-in.
    var showNumbers: Bool = false
    /// Chips the user tapped off on the viewfinder; excluded from export.
    var hiddenChipIds: Set<UUID> = []
}

// MARK: - Context builders

extension Store {
    /// The share context for a given local day (today by default).
    /// Sharing a past day renders that day's sun state retroactively.
    func dayShareContext(for date: Date = Date()) -> ShareDayContext {
        let cal = Calendar.current
        let dayScore = logEntries
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .map { $0.pointsEarned }
            .reduce(0, +)
        let goal = max(1, currentSeason.dailyGoal)
        let ratio = Double(dayScore) / Double(goal)
        return ShareDayContext(
            sun: .day(ratio: ratio),
            ratio: ratio,
            percent: max(0, Int((ratio * 100).rounded())),
            seasonName: currentSeason.name,
            chips: shareChips(for: date)
        )
    }

    /// The weekly variant — seven day-ratios above one hairline. Task
    /// chips are omitted (a week is a shape, not a checklist).
    func weekShareContext() -> ShareDayContext {
        let goal = max(1, currentSeason.dailyGoal)
        let ratios = weekStripeData.map { Double($0) / Double(goal) }
        let weeklyGoal = max(1, currentSeason.weeklyGoal)
        let weekRatio = Double(weekScore) / Double(weeklyGoal)
        return ShareDayContext(
            sun: .week(ratios: ratios),
            ratio: weekRatio,
            percent: max(0, Int((weekRatio * 100).rounded())),
            seasonName: currentSeason.name,
            chips: []
        )
    }

    /// Completed tasks / to-dos on the given day as overlay chips —
    /// names and logged amounts only, never point values.
    private func shareChips(for date: Date) -> [ShareTaskChip] {
        let cal = Calendar.current
        let completed = logEntries
            .filter { cal.isDate($0.date, inSameDayAs: date) && $0.entryType == .completed }
            .sorted { $0.date < $1.date }

        var chips: [ShareTaskChip] = []
        for entry in completed {
            if let taskId = entry.taskId,
               let task = tasks.first(where: { $0.id == taskId }) {
                var label = task.title
                if let quantity = entry.quantity, quantity > 0 {
                    let unit = task.scoring.unit.trimmingCharacters(in: .whitespaces)
                    let amount = Self.shareQuantityText(quantity)
                    label += unit.isEmpty ? " · \(amount)" : " · \(amount) \(unit)"
                }
                chips.append(ShareTaskChip(id: entry.id, label: label))
            } else if let todoId = entry.todoId,
                      let todo = todos.first(where: { $0.id == todoId }) {
                chips.append(ShareTaskChip(id: entry.id, label: todo.title))
            }
        }
        return Array(chips.prefix(8))
    }

    /// "3" for whole amounts, "2.5" otherwise.
    private static func shareQuantityText(_ quantity: Double) -> String {
        quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(quantity))
            : String(format: "%.1f", quantity)
    }
}
