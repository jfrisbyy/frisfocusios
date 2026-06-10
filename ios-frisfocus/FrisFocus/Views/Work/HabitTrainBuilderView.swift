//
//  HabitTrainBuilderView.swift
//  FrisFocus
//
//  Create / edit a habit train. Name, optional description, bonus
//  points, and an ordered list of steps. Drag handles reorder steps;
//  remove control deletes one. "Add task step" opens a picker of
//  existing FFTasks; "Add note step" inlines a text field.
//

import SwiftUI
import UIKit

struct HabitTrainBuilderView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: HabitTrain?

    @State private var name: String
    @State private var trainDescription: String
    @State private var bonusPoints: Int
    @State private var steps: [HabitTrainStep]

    @State private var showTaskPicker: Bool = false
    @State private var addingNote: Bool = false
    @State private var newNoteText: String = ""

    init(editing: HabitTrain?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _trainDescription = State(initialValue: editing?.trainDescription ?? "")
        _bonusPoints = State(initialValue: editing?.bonusPoints ?? 10)
        _steps = State(initialValue: (editing?.steps ?? []).sorted { $0.orderIndex < $1.orderIndex })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Morning train", text: $name, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...2)
                } header: {
                    Text("Name")
                }

                Section {
                    TextField("Optional — what this routine is for", text: $trainDescription, axis: .vertical)
                        .font(.serifItalic(14))
                        .lineLimit(1...4)
                } header: {
                    Text("Description")
                }

                Section {
                    Stepper(value: $bonusPoints, in: 0...100) {
                        HStack {
                            Text("Bonus points")
                            Spacer()
                            Text(bonusPoints == 0 ? "none" : "+\(bonusPoints)")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(bonusPoints == 0
                                    ? Theme.textPrimary.opacity(0.45)
                                    : Theme.alertAmber)
                        }
                    }
                    if bonusPoints > 0 {
                        Text("Awarded once per day when every task-step is done.")
                            .font(.serifItalic(12))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                } header: {
                    Text("Completion bonus")
                }

                stepsSection

                addSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(editing == nil ? "New train" : "Edit train")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showTaskPicker) {
                TaskPickerView(
                    excludedTaskIds: Set(steps.compactMap { $0.type == .task ? $0.taskId : nil })
                ) { task in
                    addTaskStep(task)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var stepsSection: some View {
        Section {
            if steps.isEmpty {
                Text("Add at least one step below.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            } else {
                ForEach(steps) { step in
                    stepRow(step)
                }
                .onMove(perform: moveSteps)
                .onDelete(perform: removeSteps)
            }
        } header: {
            HStack {
                Text("Steps")
                Spacer()
                if !steps.isEmpty {
                    EditButton()
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        } footer: {
            if !steps.isEmpty {
                Text("Drag to reorder. Swipe a row to delete.")
                    .font(.serifItalic(12))
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ step: HabitTrainStep) -> some View {
        if step.type == .task, let task = store.task(forStep: step) {
            HStack(spacing: 10) {
                Circle().fill(task.category.color).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(task.category.displayName) · \(task.pointValue) pts")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer(minLength: 4)
            }
        } else if step.type == .task {
            HStack(spacing: 10) {
                Circle().fill(Theme.alertAmber.opacity(0.6)).frame(width: 6, height: 6)
                Text("Missing task")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.alertAmber)
                Spacer()
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    .padding(.top, 3)
                Text(step.noteText ?? "")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                Spacer(minLength: 4)
            }
        }
    }

    @ViewBuilder
    private var addSection: some View {
        Section {
            Button {
                showTaskPicker = true
            } label: {
                Label("Add task step", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.textPrimary)
            }

            if addingNote {
                HStack {
                    TextField("Type a cue…", text: $newNoteText, axis: .vertical)
                        .font(.serifItalic(14))
                        .lineLimit(1...3)
                    Button("Add") { commitNoteStep() }
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(canCommitNote ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                        .disabled(!canCommitNote)
                }
            } else {
                Button {
                    addingNote = true
                } label: {
                    Label("Add note step", systemImage: "text.alignleft")
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        } header: {
            Text("Add a step")
        }
    }

    // MARK: - Step ops

    private func addTaskStep(_ task: FFTask) {
        let step = HabitTrainStep(
            orderIndex: steps.count,
            type: .task,
            taskId: task.id,
            noteText: nil
        )
        steps.append(step)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func commitNoteStep() {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let step = HabitTrainStep(
            orderIndex: steps.count,
            type: .note,
            taskId: nil,
            noteText: trimmed
        )
        steps.append(step)
        newNoteText = ""
        addingNote = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        steps.move(fromOffsets: source, toOffset: destination)
    }

    private func removeSteps(at offsets: IndexSet) {
        steps.remove(atOffsets: offsets)
    }

    // MARK: - Save

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !steps.isEmpty
    }

    private var canCommitNote: Bool {
        !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = trainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc: String? = trimmedDesc.isEmpty ? nil : trimmedDesc

        if let editing {
            var updated = editing
            updated.name = trimmedName
            updated.trainDescription = desc
            updated.bonusPoints = bonusPoints
            updated.steps = steps
            store.updateHabitTrain(updated)
        } else {
            store.createHabitTrain(
                name: trimmedName,
                description: desc,
                bonusPoints: bonusPoints,
                steps: steps,
                seasonId: store.currentSeason.id
            )
        }

        dismiss()
    }
}

// MARK: - Task picker

private struct TaskPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let excludedTaskIds: Set<UUID>
    let onPick: (FFTask) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.category) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            Button {
                                onPick(task)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(hex: store.categoryColorHex(task.category))).frame(width: 6, height: 6)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(task.title)
                                            .font(.sans(14, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text("\(task.nominalValue) pts")
                                            .font(.sans(11, weight: .regular))
                                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                                    }
                                    Spacer()
                                    if excludedTaskIds.contains(task.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary.opacity(0.35))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(excludedTaskIds.contains(task.id))
                        }
                    } header: {
                        Text(group.category.displayName)
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(group.category.darkColor)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("Add a task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
    }

    private var grouped: [(category: Category, tasks: [FFTask])] {
        let byCat = Dictionary(grouping: store.tasks) { $0.category }
        return Category.allCases.compactMap { cat in
            guard let arr = byCat[cat], !arr.isEmpty else { return nil }
            let sorted = arr.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return (cat, sorted)
        }
    }
}

#Preview {
    HabitTrainBuilderView(editing: nil)
        .environment(Store())
}
