//
//  DayDetailSheet.swift
//  FrisFocus
//
//  Opens when the user taps the date line on the Sun zone. A graphical
//  calendar at the top lets the user jump to any day; the lower half
//  changes shape based on whether that day is:
//
//   • in the past — the day's full record: score, every LogEntry,
//     the tasks pinned that day, to-dos due that day, notes written
//     that day, and milestone movement. Past items CAN be edited
//     (toggle a task / to-do, remove an entry) — every change first
//     confirms "you're editing a previous day".
//   • today      — a quiet pointer back to Today's Plan
//   • in the future — a list of to-dos already scheduled for that day,
//     plus an inline quick-add so the user can plan ahead.
//
//  A "Today" shortcut in the toolbar jumps the picker back to now
//  from any old day.
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
                ToolbarItem(placement: .topBarLeading) {
                    if relation != .today {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                selectedDate = Date()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Today")
                                    .font(.sans(14, weight: .semibold))
                            }
                            .foregroundStyle(Theme.alertGreen)
                        }
                        .accessibilityLabel("Back to today")
                    }
                }
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

    /// A mutation waiting on the "editing a previous day" confirmation.
    @State private var pendingEditAction: (() -> Void)?
    @State private var showEditConfirm: Bool = false

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
                        PastEntryRow(entry: entry, day: date)
                            .contextMenu {
                                Button(role: .destructive) {
                                    requestEdit { store.removeLogEntry(entry) }
                                } label: {
                                    Label("Remove this entry", systemImage: "trash")
                                }
                            }
                    }
                }
                Text("hold an entry to remove it")
                    .font(.sans(10, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }

            if !dayTasks.isEmpty {
                sectionHeader("Tasks that day")
                VStack(spacing: 8) {
                    ForEach(dayTasks, id: \.id) { task in
                        pastTaskRow(task)
                    }
                }
            }

            if !dayTodos.isEmpty {
                sectionHeader("To-dos that day")
                VStack(spacing: 8) {
                    ForEach(dayTodos, id: \.id) { todo in
                        pastTodoRow(todo)
                    }
                }
            }

            if !dayNotes.isEmpty {
                sectionHeader("Notes from this day")
                VStack(spacing: 8) {
                    ForEach(dayNotes, id: \.id) { note in
                        pastNoteRow(note)
                    }
                }
            }

            if !milestoneLines.isEmpty {
                sectionHeader("Milestones")
                VStack(spacing: 8) {
                    ForEach(milestoneLines, id: \.self) { line in
                        milestoneRow(line)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showShareCamera) {
            // Sharing retroactively renders THIS day's sun state.
            ShareCameraView(context: store.dayShareContext(for: date))
        }
        .alert("Editing a previous day", isPresented: $showEditConfirm) {
            Button("Cancel", role: .cancel) {
                pendingEditAction = nil
            }
            Button("Edit this day") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                pendingEditAction?()
                pendingEditAction = nil
            }
        } message: {
            Text("You're changing \(dayName), not today. The day's score and history will update.")
        }
    }

    /// Gate every past-day mutation behind one confirmation.
    private func requestEdit(_ action: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pendingEditAction = action
        showEditConfirm = true
    }

    private var dayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    private var entries: [LogEntry] {
        let cal = Calendar.current
        return store.logEntries
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - The day's items

    /// Tasks whose schedule pinned them on that day, plus any task
    /// actually logged that day (even if it wasn't pinned).
    private var dayTasks: [FFTask] {
        let loggedIds = Set(entries.compactMap { $0.entryType == .completed ? $0.taskId : nil })
        return store.tasks.filter { $0.isPinnedFor(date) || loggedIds.contains($0.id) }
    }

    private var dayTodos: [Todo] {
        let cal = Calendar.current
        return store.todos.filter { todo in
            if let due = todo.dueDate, cal.isDate(due, inSameDayAs: date) { return true }
            if let done = todo.completedAt, cal.isDate(done, inSameDayAs: date) { return true }
            return false
        }
    }

    private var dayNotes: [Note] {
        let cal = Calendar.current
        return store.notes
            .filter { cal.isDate($0.createdAt, inSameDayAs: date) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Milestone movement on this day — landings and checked steps,
    /// read from the day's own log entries.
    private var milestoneLines: [String] {
        var lines: [String] = []
        for entry in entries {
            guard let milestoneId = entry.milestoneId,
                  let milestone = store.currentSeason.milestones.first(where: { $0.id == milestoneId })
            else { continue }
            if entry.entryType == .milestone {
                lines.append("\(milestone.title) · landed this day")
            } else if entry.entryType == .milestoneStep {
                let stepTitle = entry.milestoneStepId.flatMap { stepId in
                    milestone.steps.first { $0.id == stepId }?.title
                }
                lines.append("\(milestone.title) · step checked\(stepTitle.map { ": \($0)" } ?? "")")
            }
        }
        return lines
    }

    private func taskCompletedThatDay(_ task: FFTask) -> Bool {
        let cal = Calendar.current
        return store.logEntries.contains {
            $0.taskId == task.id
                && cal.isDate($0.date, inSameDayAs: date)
                && $0.entryType == .completed
        }
    }

    // MARK: - Editable rows

    @ViewBuilder
    private func pastTaskRow(_ task: FFTask) -> some View {
        let done = taskCompletedThatDay(task)
        Button {
            requestEdit { store.setTaskCompleted(task, completed: !done, on: date) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    SwiftUI.Circle()
                        .stroke(done ? Theme.alertGreen : Theme.textPrimary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.alertGreen)
                    }
                }

                Text(task.title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(done, color: Theme.textPrimary.opacity(0.4))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title)
        .accessibilityHint(done ? "Marks it not done for this day" : "Marks it done for this day")
    }

    @ViewBuilder
    private func pastTodoRow(_ todo: Todo) -> some View {
        Button {
            requestEdit { store.setTodoCompleted(todo, completed: !todo.isCompleted, on: date) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(
                            todo.isCompleted ? Theme.alertGreen : Theme.textPrimary.opacity(0.3),
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)
                    if todo.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.alertGreen)
                    }
                }

                Text(todo.title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(todo.isCompleted, color: Theme.textPrimary.opacity(0.4))
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
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todo.title)
        .accessibilityHint(todo.isCompleted ? "Marks it not done" : "Marks it done for this day")
    }

    @ViewBuilder
    private func pastNoteRow(_ note: Note) -> some View {
        HStack(spacing: 12) {
            Image(systemName: note.voiceMemos.isEmpty ? "text.alignleft" : "waveform")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(noteTitle(note))
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(noteTime(note))
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            Spacer(minLength: 8)

            if !note.photos.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
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

    private func noteTitle(_ note: Note) -> String {
        if let label = note.label, !label.isEmpty { return label }
        if let body = note.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }
        if !note.voiceMemos.isEmpty { return "Voice memo" }
        if !note.photos.isEmpty { return "Media note" }
        return "Untitled note"
    }

    private func noteTime(_ note: Note) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: note.createdAt)
    }

    @ViewBuilder
    private func milestoneRow(_ line: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flag")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.alertGreen.opacity(0.85))
                .frame(width: 18)

            Text(line)
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 8)
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
    let day: Date

    /// Whether the pinned-proof viewer is unfolded beneath the row.
    @State private var showProof: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                guard !pins.isEmpty else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showProof.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 18)

                    Text(label)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    if !pins.isEmpty {
                        Image(systemName: "photo.fill.on.rectangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.sunShadow)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                            .rotationEffect(.degrees(showProof ? 180 : 0))
                    }

                    Spacer(minLength: 8)

                    Text(pointsText)
                        .font(.serif(17, weight: .medium))
                        .foregroundStyle(entry.pointsEarned < 0 ? Theme.alertRed : Theme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pins.isEmpty)

            if showProof, !pins.isEmpty {
                VStack(spacing: 10) {
                    ForEach(pins) { pin in
                        ProofPinMediaView(pin: pin)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    /// Proofs pinned to this entry's task / to-do on this day.
    private var pins: [ProofPin] {
        if let taskId = entry.taskId {
            return store.proofPins(forTaskId: taskId, on: day)
        }
        if let todoId = entry.todoId {
            return store.proofPins(forTodoId: todoId, on: day)
        }
        return []
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
        case .milestoneStep: return "flag"
        case .skipped: return "minus.circle"
        case .penalty: return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch entry.entryType {
        case .completed: return Theme.alertGreen
        case .boosterBonus, .trainBonus, .milestone, .milestoneStep: return Theme.alertGreen.opacity(0.85)
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
            if entry.entryType == .milestoneStep {
                let stepTitle = entry.milestoneStepId.flatMap { stepId in
                    milestone.steps.first { $0.id == stepId }?.title
                }
                return "\(stepTitle ?? milestone.title) · milestone step"
            }
            return "\(milestone.title) · milestone"
        }
        if let cadenceLinkId = entry.cadenceLinkId,
           let link = store.cadenceLinks.first(where: { $0.id == cadenceLinkId }) {
            return link.displayTitle
        }
        // Title snapshot taken at logging time — survives deletion of
        // the source item.
        if let title = entry.title, !title.isEmpty {
            switch entry.entryType {
            case .boosterBonus: return "\(title) · booster"
            case .penalty: return "\(title) · penalty"
            default: return title
            }
        }
        switch entry.entryType {
        case .boosterBonus: return "Booster bonus"
        case .trainBonus: return "Routine complete"
        case .milestone: return "Milestone"
        case .milestoneStep: return "Milestone step"
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
