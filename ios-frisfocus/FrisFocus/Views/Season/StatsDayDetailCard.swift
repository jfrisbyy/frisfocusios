//
//  StatsDayDetailCard.swift
//  FrisFocus
//
//  One day's full breakdown — every LogEntry with an icon, a label,
//  and its points — shown when a bar is tapped in the Week or Month
//  stats charts. Shared by both scopes so the day always reads the
//  same wherever it's opened from.
//

import SwiftUI

struct StatsDayDetailCard: View {
    @Environment(Store.self) private var store

    let day: Date

    private let glassFill = Color.white.opacity(0.10)
    private let glassStroke = Color.white.opacity(0.18)

    private var cal: Calendar { Calendar.current }

    var body: some View {
        let entries = dayEntries
        let score = entries.map(\.pointsEarned).reduce(0, +)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.serif(16, weight: .medium))
                    .foregroundStyle(Theme.textCream)

                Spacer()

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("\(score)")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(score < 0 ? Theme.alertRed : Theme.textCream)
                    Text(" / \(store.currentSeason.dailyGoal)")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.5))
                }
            }

            if entries.isEmpty {
                Text("Nothing logged this day.")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textCream.opacity(0.5))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(entries, id: \.id) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(glassStroke, lineWidth: 0.5)
        )
    }

    private var title: String {
        if cal.isDateInToday(day) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE · MMM d"
        return formatter.string(from: day)
    }

    private var dayEntries: [LogEntry] {
        store.logEntries
            .filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Entry row

    @ViewBuilder
    private func entryRow(_ entry: LogEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entryIconName(entry))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entryIconColor(entry))
                .frame(width: 18)

            Text(entryLabel(entry))
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.92))
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(entry.pointsEarned >= 0 ? "+\(entry.pointsEarned)" : "\(entry.pointsEarned)")
                .font(.serif(15, weight: .medium))
                .foregroundStyle(
                    entry.pointsEarned < 0 ? Theme.alertRed : Theme.textCream
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func entryIconName(_ entry: LogEntry) -> String {
        switch entry.entryType {
        case .completed: return "checkmark.circle.fill"
        case .boosterBonus: return "sparkles"
        case .trainBonus: return "rectangle.stack.fill"
        case .milestone: return "flag.checkered"
        case .skipped: return "minus.circle"
        case .penalty: return "exclamationmark.circle.fill"
        }
    }

    private func entryIconColor(_ entry: LogEntry) -> Color {
        switch entry.entryType {
        case .completed: return Theme.sunWarm
        case .boosterBonus, .trainBonus, .milestone: return Theme.sunWarm.opacity(0.85)
        case .skipped: return Theme.textCream.opacity(0.4)
        case .penalty: return Theme.alertRed
        }
    }

    private func entryLabel(_ entry: LogEntry) -> String {
        if let taskId = entry.taskId,
           let task = store.tasks.first(where: { $0.id == taskId }) {
            switch entry.entryType {
            case .boosterBonus: return "\(task.title) · booster"
            case .penalty: return "\(task.title) · weekly limit"
            default: return task.title
            }
        }
        if let todoId = entry.todoId,
           let todo = store.todos.first(where: { $0.id == todoId }) {
            return todo.title
        }
        if let trainId = entry.trainId,
           let train = store.habitTrains.first(where: { $0.id == trainId }) {
            return "\(train.name) · routine"
        }
        if let milestoneId = entry.milestoneId,
           let milestone = store.currentSeason.milestones.first(where: { $0.id == milestoneId }) {
            return "\(milestone.title) · milestone"
        }
        switch entry.entryType {
        case .boosterBonus: return "Booster bonus"
        case .trainBonus: return "Routine complete"
        case .milestone: return "Milestone"
        case .penalty: return "Avoidance"
        case .skipped: return "Skipped"
        case .completed: return "Logged"
        }
    }
}
