//
//  Store+SeasonInvitation.swift
//  FrisFocus
//
//  The local, no-model logic that decides whether the home invitation card
//  has something SPECIFIC to say — and what. Pulls only from the live
//  season + log history. Returns nil (stay silent) unless a concrete
//  observation exists and the card hasn't retired.
//

import Foundation

extension Store {
    /// The one invitation to show right now, or nil to stay silent.
    /// `dismissed` are observation kinds the person has already quieted for
    /// this season (they never return; a different one still can).
    func seasonInvitation(excluding dismissed: Set<SeasonInvitationKind>) -> SeasonInvitation? {
        // Only ever for a live, provisional cold-start season.
        guard appMode == .clean, currentSeason.isProvisional else { return nil }
        // Retire after a sustained stretch — a few quiets or ~30 days.
        guard dismissed.count < SeasonInvitationStore.retireAfterDismissals else { return nil }
        guard currentSeasonDay < SeasonInvitationStore.retireAfterDays else { return nil }

        let cta = "Talk it through · about 15 min"
        // North star wins ties; the data-driven observations outrank the
        // always-available custom-heavy fallback so copy sharpens over time.
        for kind in [SeasonInvitationKind.northStar, .consistency, .gap, .customHeavy] {
            guard !dismissed.contains(kind), let headline = invitationHeadline(for: kind) else { continue }
            return SeasonInvitation(kind: kind, headline: headline, cta: cta)
        }
        return nil
    }

    // MARK: - Templated copy (filled from local stats)

    private func invitationHeadline(for kind: SeasonInvitationKind) -> String? {
        switch kind {
        case .northStar:
            guard let star = firstNorthStar else { return nil }
            return "You said \(star) is the goal — want to build the season that gets you there?"
        case .consistency:
            guard let run = longestCompletionRun, run.days >= 3 else { return nil }
            return "You've hit \(run.task) \(run.days) days running — want to build a real season around that?"
        case .gap:
            guard currentSeasonDay >= 3, let area = firstUntouchedArea else { return nil }
            return "\(currentSeasonDay) days in, and \(area) hasn't been touched — want to talk through what actually fits?"
        case .customHeavy:
            let n = tasks.filter(\.isCustom).count
            guard n >= 2 else { return nil }
            return "You've added \(n) of your own tasks — sounds like you know what matters. Want to price it properly?"
        }
    }

    // MARK: - Local stats

    private var firstNorthStar: String? {
        currentSeason.milestones
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The task with the longest current run of consecutive completed days
    /// (a run may end today or yesterday, so it survives an in-progress day).
    private var longestCompletionRun: (task: String, days: Int)? {
        let cal = Calendar.current
        let seasonStart = cal.startOfDay(for: currentSeason.startedAt ?? currentSeason.startDate)
        var daysByTask: [UUID: Set<Date>] = [:]
        for entry in logEntries where entry.entryType == .completed {
            guard let taskId = entry.taskId else { continue }
            let day = cal.startOfDay(for: entry.date)
            guard day >= seasonStart else { continue }
            daysByTask[taskId, default: []].insert(day)
        }

        let today = cal.startOfDay(for: Date())
        var best: (task: String, days: Int)?
        for task in tasks {
            guard let days = daysByTask[task.id], !days.isEmpty else { continue }
            var anchor = today
            if !days.contains(anchor) {
                guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                      days.contains(yesterday) else { continue }
                anchor = yesterday
            }
            var run = 0
            var cursor = anchor
            while days.contains(cursor) {
                run += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
            if run > (best?.days ?? 0) { best = (task.title, run) }
        }
        return best
    }

    /// A season area that has tasks but no completed entry yet — its
    /// display name, primary areas first.
    private var firstUntouchedArea: String? {
        let cal = Calendar.current
        let seasonStart = cal.startOfDay(for: currentSeason.startedAt ?? currentSeason.startDate)
        let categoryByTask: [UUID: Category] = Dictionary(
            tasks.map { ($0.id, $0.category) },
            uniquingKeysWith: { first, _ in first }
        )
        var touched: Set<Category> = []
        for entry in logEntries where entry.entryType == .completed {
            guard let taskId = entry.taskId, let category = categoryByTask[taskId] else { continue }
            guard cal.startOfDay(for: entry.date) >= seasonStart else { continue }
            touched.insert(category)
        }
        for seasonCategory in currentSeason.categories {
            let category = seasonCategory.category
            let hasTasks = tasks.contains { $0.category == category }
            guard hasTasks, !touched.contains(category) else { continue }
            let custom = seasonCategory.customName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (custom?.isEmpty == false) ? custom! : category.displayName
        }
        return nil
    }
}
