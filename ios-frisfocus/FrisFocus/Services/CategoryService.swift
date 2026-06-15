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

    /// Start a fresh season from a copy of the current season's setup —
    /// its categories (names, colors, tiers) and daily/weekly targets —
    /// instead of rebuilding from scratch. The new season freezes its own
    /// rubric on start; the task library (which isn't season-scoped)
    /// carries forward untouched. Milestones reset (they're per-season
    /// achievements). Returns the new season for the caller's convenience.
    @discardableResult
    func startNewSeasonFromCurrent(
        name: String? = nil,
        lengthDays: Int? = nil,
        dailyGoal: Int? = nil,
        weeklyGoal: Int? = nil
    ) -> Season {
        let previous = currentSeason
        let newId = UUID()

        let copiedCategories = previous.categories.map { sc in
            SeasonCategory(
                category: sc.category,
                tier: sc.tier,
                customName: sc.customName,
                customColorHex: sc.customColorHex
            )
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let season = Season(
            id: newId,
            name: (trimmedName?.isEmpty ?? true) ? "New Season" : (trimmedName ?? "New Season"),
            lengthDays: lengthDays ?? previous.lengthDays,
            startDate: Calendar.current.startOfDay(for: Date()),
            vibe: previous.vibe,
            dailyGoal: dailyGoal ?? previous.dailyGoal,
            weeklyGoal: weeklyGoal ?? previous.weeklyGoal,
            categories: copiedCategories,
            milestones: []
        )

        currentSeason = season
        persistAll()
        // Clear stale milestone reminders from the previous season. The
        // new season has no milestones yet, so this only cancels.
        MilestoneNudgeService.refresh(for: season)
        // Republish the season card immediately so friends see the new
        // season's name/cover and reset milestone tally without waiting
        // for the debounced sync flush.
        republishSeasonCardNow()
        return season
    }
}
