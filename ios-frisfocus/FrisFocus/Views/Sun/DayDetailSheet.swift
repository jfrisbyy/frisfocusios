//
//  DayDetailSheet.swift
//  FrisFocus
//
//  Opens when the user taps the date line on the Sun zone. A graphical
//  calendar at the top lets the user jump to any day; the lower half
//  changes shape based on whether that day is:
//
//   • in the past — read-only summary of the day's score + every
//     LogEntry recorded against it (completions, booster / train
//     bonuses, penalties)
//   • today      — a quiet pointer back to Today's Plan
//   • in the future — a list of to-dos already scheduled for that day,
//     plus an inline quick-add so the user can plan ahead.
//

import SwiftUI
import UIKit

struct DayDetailSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var selectedDate: Date

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var startOfSelected: Date { cal.startOfDay(for: selectedDate) }

    private enum Relation { case past, today, future }
    private var relation: Relation {
        if cal.isDate(selectedDate, inSameDayAs: today) { return .today }
        return startOfSelected < today ? .past : .future
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DatePicker(
                        "Day",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .tint(Theme.alertGreen)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    Group {
                        switch relation {
                        case .past:
                            PastDayView(date: startOfSelected)
                        case .today:
                            TodayDayPointerView()
                        case .future:
                            FutureDayView(date: startOfSelected)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                }
            }
        }
    }

    private var navTitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: selectedDate)
    }
}

// MARK: - Past day

private struct PastDayView: View {
    @Environment(Store.self) private var store
    let date: Date

    @State private var showShareCamera: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            scoreCard

            sectionHeader("What happened")

            if entries.isEmpty {
                Text("No activity logged this day.")
                    .font(.serifItalic(14))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(entries, id: \.id) { entry in
                        PastEntryRow(entry: entry)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showShareCamera) {
            // Sharing retroactively renders THIS day's sun state.
            ShareCameraView(context: store.dayShareContext(for: date))
        }
    }

    private var entries: [LogEntry] {
        let cal = Calendar.current
        return store.logEntries
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    private var score: Int {
        entries.map(\.pointsEarned).reduce(0, +)
    }

    private var scoreCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowText(text: "Score", opacity: 0.55).tracking(2)
                Text("\(score)")
                    .font(.serif(44, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showShareCamera = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().strokeBorder(Theme.textPrimary.opacity(0.18), lineWidth: 1)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share this day")
            .accessibilityHint("Opens the share camera with this day's sun")
            .padding(.trailing, 12)

            VStack(alignment: .trailing, spacing: 4) {
                EyebrowText(text: "Goal", opacity: 0.55).tracking(2)
                Text("\(store.currentSeason.dailyGoal)")
                    .font(.serif(20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct PastEntryRow: View {
    @Environment(Store.self) private var store
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            Text(label)
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(pointsText)
                .font(.serif(17, weight: .medium))
                .foregroundStyle(entry.pointsEarned < 0 ? Theme.alertRed : Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var pointsText: String {
        entry.pointsEarned >= 0 ? "+\(entry.pointsEarned)" : "\(entry.pointsEarned)"
    }

    private var iconName: String {
        switch entry.entryType {
        case .completed: return "checkmark.circle.fill"
        case .boosterBonus: return "sparkles"
        case .trainBonus: return "rectangle.stack.fill"
        case .milestone: return "flag.checkered"
        case .skipped: return "minus.circle"
        case .penalty: return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch entry.entryType {
        case .completed: return Theme.alertGreen
        case .boosterBonus, .trainBonus, .milestone: return Theme.alertGreen.opacity(0.85)
        case .skipped: return Theme.textPrimary.opacity(0.45)
        case .penalty: return Theme.alertRed
        }
    }

    private var label: String {
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

// MARK: - Today pointer

private struct TodayDayPointerView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.alertGreen.opacity(0.7))

            Text("This is today.")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text("Close this and use Today's Plan to log what's happening now.")
                .font(.serifItalic(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Future day

private struct FutureDayView: View {
    @Environment(Store.self) private var store
    let date: Date

    @State private var quickTitle: String = ""
    @State private var withPoints: Bool = false
    @State private var pointValue: Int = 2
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Planned for \(dayLabel)")

            if todosDue.isEmpty {
                Text("Nothing planned yet.")
                    .font(.serifItalic(14))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(todosDue, id: \.id) { todo in
                        scheduledRow(todo)
                    }
                }
            }

            sectionHeader("Add a to-do")

            VStack(spacing: 12) {
                TextField("e.g. Call grandma", text: $quickTitle)
                    .focused($titleFocused)
                    .font(.sans(15, weight: .regular))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.1), lineWidth: 0.5)
                    )
                    .submitLabel(.done)
                    .onSubmit(add)

                Toggle("Worth points", isOn: $withPoints.animation(.easeInOut(duration: 0.2)))
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.alertGreen)

                if withPoints {
                    Stepper(value: $pointValue, in: 1...10) {
                        HStack {
                            Text("Bonus")
                                .font(.sans(14, weight: .medium))
                            Spacer()
                            Text("+\(pointValue) pts")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }

                Button(action: add) {
                    Text("Add to \(dayLabel)")
                        .font(.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canAdd ? Theme.alertGreen : Theme.textPrimary.opacity(0.12))
                        .foregroundStyle(canAdd ? Theme.warmWheat : Theme.textPrimary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            .padding(14)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
    }

    private var todosDue: [Todo] {
        let cal = Calendar.current
        return store.todos
            .filter { todo in
                guard let due = todo.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: date)
            }
            .sorted { ($0.pointValue ?? -1) > ($1.pointValue ?? -1) }
    }

    @ViewBuilder
    private func scheduledRow(_ todo: Todo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(width: 18)

            Text(todo.title)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .strikethrough(todo.isCompleted, color: Theme.textPrimary.opacity(0.5))
                .lineLimit(2)

            Spacer(minLength: 8)

            if let pts = todo.pointValue {
                Text("+\(pts)")
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }

    private var canAdd: Bool {
        !quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Anchor the dueDate at noon on the picked day so any later
        // formatting that displays a time-of-day reads as midday rather
        // than tripping over DST midnight edge cases.
        let cal = Calendar.current
        let due = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date

        let todo = Todo(
            title: quickTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: due,
            pointValue: withPoints ? pointValue : nil
        )
        store.todos.append(todo)
        store.persistAll()

        quickTitle = ""
        titleFocused = false
    }
}

// MARK: - Shared section header

@ViewBuilder
private func sectionHeader(_ text: String) -> some View {
    EyebrowText(text: text, opacity: 0.6)
        .tracking(2)
        .padding(.top, 4)
}

#Preview {
    DayDetailSheet(selectedDate: Date())
        .environment(Store())
}
