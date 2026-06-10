//
//  CategorySectionView.swift
//  FrisFocus
//
//  One per-category block on the expanded Season page. Renders a header
//  (category swatch + name + tier pill + status line + day points) then
//  the category's pinned Tasks for today — completed entries on top,
//  open ones below.
//
//  Cards use the same `TaskCardView` the home uses, so completing /
//  uncompleting a task here flows through the same Store action and
//  the hero score updates live.
//

import SwiftUI

struct CategorySectionView: View {
    @Environment(Store.self) private var store
    let category: Category
    let tasks: [FFTask]
    let seasonCategory: SeasonCategory?

    // MARK: - Derived

    private var doneTasks: [FFTask] {
        tasks.filter { store.hasLogEntryToday(forTaskId: $0.id) }
    }

    private var openTasks: [FFTask] {
        tasks.filter { !store.hasLogEntryToday(forTaskId: $0.id) }
    }

    /// Sum of today's completed `LogEntry.pointsEarned` for tasks in
    /// this category. Drives the `+N` lockup on the right of the header.
    private var pointsToday: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let taskIds = Set(tasks.map(\.id))
        return store.logEntries
            .filter { entry in
                guard let taskId = entry.taskId,
                      taskIds.contains(taskId),
                      entry.entryType == .completed,
                      cal.isDate(entry.date, inSameDayAs: today)
                else { return false }
                return true
            }
            .map(\.pointsEarned)
            .reduce(0, +)
    }

    private var statusLine: String {
        var parts: [String] = []
        if !doneTasks.isEmpty {
            parts.append("\(doneTasks.count) done")
        }
        if !openTasks.isEmpty {
            parts.append("\(openTasks.count) open")
        }
        let highValueOpen = openTasks.filter { $0.nominalValue >= store.reminderValueThreshold }.count
        if highValueOpen > 0 {
            parts.append("\(highValueOpen) high-value")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.bottom, 12)

            VStack(spacing: 6) {
                ForEach(doneTasks + openTasks) { task in
                    TaskCardView(task: task)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 22)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            categorySwatch

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.categoryDisplayName(category))
                        .font(.serif(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    if let tierPill {
                        tierPill
                    }
                }

                Text(statusLine)
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 8)

            if pointsToday > 0 {
                Text("+\(pointsToday)")
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .contentTransition(.numericText(value: Double(pointsToday)))
                    .animation(.easeOut(duration: 0.4), value: pointsToday)
            }
        }
    }

    private var categorySwatch: some View {
        let swatch = Color(hex: store.categoryColorHex(category))
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(swatch.opacity(0.15))
                .frame(width: 30, height: 30)

            Circle()
                .fill(swatch)
                .frame(width: 11, height: 11)
        }
    }

    // MARK: - Tier pill

    @ViewBuilder
    private var tierPill: AnyView? {
        guard let sc = seasonCategory else { return nil }
        let label: String
        switch sc.tier {
        case .primary: label = "PRIMARY"
        case .support: label = "SUPPORT"
        case .quiet:   label = "QUIET"
        }

        let view = Text(label)
            .font(.sans(9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(tierTextColor(for: sc.tier))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tierBackground(for: sc.tier))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

        return AnyView(view)
    }

    private func tierTextColor(for tier: CategoryTier) -> Color {
        switch tier {
        case .quiet:
            return Theme.textPrimary.opacity(0.55)
        case .primary, .support:
            return category.darkColor
        }
    }

    private func tierBackground(for tier: CategoryTier) -> Color {
        switch tier {
        case .quiet:
            return Theme.textPrimary.opacity(0.06)
        case .primary, .support:
            return Color(hex: store.categoryColorHex(category)).opacity(0.15)
        }
    }
}

#Preview {
    let store = Store()
    return ScrollView {
        VStack(spacing: 0) {
            CategorySectionView(
                category: .spiritual,
                tasks: store.tasks.filter { $0.category == .spiritual && $0.isPinnedToday },
                seasonCategory: store.currentSeason.categories.first { $0.category == .spiritual }
            )

            CategorySectionView(
                category: .work,
                tasks: store.tasks.filter { $0.category == .work && $0.isPinnedToday },
                seasonCategory: store.currentSeason.categories.first { $0.category == .work }
            )
        }
    }
    .background(Theme.warmWheat)
    .environment(store)
}
