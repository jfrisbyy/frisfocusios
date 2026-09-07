//
//  SetupTaskEditSheet.swift
//  FrisFocus
//
//  Bottom-sheet editors for the rubric review screen. The main sheet
//  edits a daily task: rename, switch its scoring shape (Yes/no ·
//  Tiered · Per amount) with per-shape inputs revealing, set points with
//  a gentle rationale, move category, or remove. Sibling sheets cover
//  negatives (shape, window, free count), end-of-week rules (boosters /
//  floors), and milestones.
//

import SwiftUI
import UIKit

// MARK: - Task editor

struct SetupTaskEditSheet: View {
    let task: DraftTask
    let categories: [DraftCategory]
    let onSave: (DraftTask) -> Void
    let onRemove: (DraftTask) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var shape: ScoringType = .flat
    @State private var value: Int = 3
    @State private var unit: String = ""
    @State private var tiers: [ScoreTier] = []
    @State private var baseThreshold: Double = 1
    @State private var basePoints: Int = 3
    @State private var unitSize: Double = 1
    @State private var pointsPerUnit: Int = 1
    @State private var categoryId: UUID = UUID()

    private var isNew: Bool { task.name.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task name", text: $name)
                        .font(.sans(16, weight: .regular))
                }

                Section {
                    Picker("Scoring", selection: $shape) {
                        Text("Yes / no").tag(ScoringType.flat)
                        Text("Tiered").tag(ScoringType.tiered)
                        Text("Per amount").tag(ScoringType.quantity)
                    }
                    .pickerStyle(.segmented)

                    switch shape {
                    case .flat:
                        Stepper(value: $value, in: 1...50) {
                            HStack {
                                Text("Points")
                                Spacer()
                                Text("\(value)")
                                    .font(.serif(17, weight: .medium))
                            }
                        }
                    case .tiered:
                        TextField("Unit (hours, pages…)", text: $unit)
                        ForEach($tiers) { $tier in
                            HStack(spacing: 10) {
                                TextField("Amount", value: $tier.threshold, format: .number)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 70)
                                Text("→")
                                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                                Stepper(value: $tier.points, in: 1...50) {
                                    Text("\(tier.points) pts")
                                        .font(.sans(14, weight: .regular))
                                }
                            }
                        }
                        .onDelete { tiers.remove(atOffsets: $0) }
                        Button {
                            let next = (tiers.map(\.threshold).max() ?? 0) + 1
                            let pts = (tiers.map(\.points).max() ?? 1) + 1
                            tiers.append(ScoreTier(threshold: next, points: pts))
                        } label: {
                            Label("Add level", systemImage: "plus")
                                .font(.sans(14, weight: .regular))
                        }
                    case .quantity:
                        TextField("Unit (pushups, pages…)", text: $unit)
                        HStack {
                            Text("Base at")
                            Spacer()
                            TextField("Amount", value: $baseThreshold, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        Stepper(value: $basePoints, in: 1...50) {
                            HStack {
                                Text("Base points")
                                Spacer()
                                Text("\(basePoints)")
                                    .font(.serif(16, weight: .medium))
                            }
                        }
                        HStack {
                            Text("Then per extra")
                            Spacer()
                            TextField("Size", value: $unitSize, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        Stepper(value: $pointsPerUnit, in: 1...20) {
                            HStack {
                                Text("Extra points")
                                Spacer()
                                Text("+\(pointsPerUnit)")
                                    .font(.serif(16, weight: .medium))
                            }
                        }
                    }
                } header: {
                    Text("Shape")
                } footer: {
                    Text(shapeFooter)
                }

                Section {
                    Picker("Category", selection: $categoryId) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                } footer: {
                    Text("Heavier values belong on the things that are hard for you — that's the point.")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onRemove(task)
                            dismiss()
                        } label: {
                            Label("Remove task", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(isNew ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .font(.sans(15, weight: .medium))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            name = task.name
            shape = task.shape
            value = task.value
            unit = task.unit
            tiers = task.tiers
            baseThreshold = task.baseThreshold
            basePoints = task.basePoints
            unitSize = task.unitSize
            pointsPerUnit = task.pointsPerUnit
            categoryId = task.categoryId
        }
    }

    private var shapeFooter: String {
        switch shape {
        case .flat: return "Done is done — a fixed number of points."
        case .tiered: return "The higher you log, the more you earn — the top level you reach pays out."
        case .quantity: return "A base payout at a floor, plus more for every extra block."
        }
    }

    private func save() {
        var updated = task
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.shape = shape
        updated.value = max(1, value)
        updated.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tiers = tiers.sorted { $0.threshold < $1.threshold }
        updated.baseThreshold = max(0, baseThreshold)
        updated.basePoints = max(1, basePoints)
        updated.unitSize = max(1, unitSize)
        updated.pointsPerUnit = max(1, pointsPerUnit)
        updated.categoryId = categoryId
        if shape == .tiered {
            if updated.tiers.isEmpty {
                updated.tiers = [ScoreTier(threshold: 1, points: max(1, value))]
            }
            updated.value = updated.tiers.map(\.points).max() ?? value
        }
        if shape == .quantity {
            updated.value = updated.basePoints
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSave(updated)
        dismiss()
    }
}

// MARK: - Negative editor

struct SetupNegativeEditSheet: View {
    let negative: DraftNegative
    let onSave: (DraftNegative) -> Void
    let onRemove: (DraftNegative) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var shape: NegativeType = .perInstance
    @State private var value: Int = 3
    @State private var window: NegativeWindow = .weekly
    @State private var freeCount: Int = 2

    private var isNew: Bool { negative.name.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What to avoid", text: $name)
                        .font(.sans(16, weight: .regular))
                }

                Section {
                    Picker("Shape", selection: $shape) {
                        Text("Every time").tag(NegativeType.perInstance)
                        Text("In excess").tag(NegativeType.frequencyThreshold)
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $value, in: 1...30) {
                        HStack {
                            Text("Costs")
                            Spacer()
                            Text("−\(value)")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.alertRed)
                        }
                    }

                    if shape == .frequencyThreshold {
                        Picker("Window", selection: $window) {
                            Text("Each week").tag(NegativeWindow.weekly)
                            Text("Each month").tag(NegativeWindow.monthly)
                        }
                        Stepper(value: $freeCount, in: 0...14) {
                            HStack {
                                Text("Free up to")
                                Spacer()
                                Text("\(freeCount)×")
                                    .font(.serif(16, weight: .medium))
                            }
                        }
                    }
                } footer: {
                    Text(shape == .perInstance
                         ? "Bad every time — each one costs points."
                         : "Fine in moderation — free up to the line, then each one counts. You see it coming.")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onRemove(negative)
                            dismiss()
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(isNew ? "New negative" : "Edit negative")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = negative
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.shape = shape
                        updated.value = max(1, value)
                        updated.window = window
                        updated.freeCount = max(0, freeCount)
                        onSave(updated)
                        dismiss()
                    }
                    .font(.sans(15, weight: .medium))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            name = negative.name
            shape = negative.shape
            value = negative.value
            window = negative.window
            freeCount = negative.freeCount
        }
    }
}

// MARK: - Weekly rule editor (boosters + floors)

struct SetupRuleEditSheet: View {
    let title: String
    let helper: String
    let name: String
    let reference: String
    let threshold: Int
    /// Whether `threshold` counts days in the week or a weekly total of
    /// the task's own units. The editor is unusable for a `.sum` rule
    /// without knowing this.
    let metric: BoosterMetric
    let value: Int
    let valueLabel: String
    let taskNames: [String]
    let onSave: (String, String, Int, Int) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editedName: String = ""
    @State private var editedReference: String = ""
    @State private var editedThreshold: Int = 3
    @State private var editedValue: Int = 10

    private var isNew: Bool { name.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $editedName)
                        .font(.sans(16, weight: .regular))
                    Picker("Watches", selection: $editedReference) {
                        ForEach(taskNames, id: \.self) { taskName in
                            Text(taskName).tag(taskName)
                        }
                    }
                    // A day count lives in 1...7; a weekly TOTAL does
                    // not. This stepper was pinned to 1...7 and labelled
                    // "Times per week", so a rule the conversation built
                    // as "150,000 steps" could not be seen, let alone
                    // edited — the first tap would have silently rewritten
                    // it to 7.
                    if metric == .sum {
                        HStack {
                            Text("Weekly total")
                            Spacer()
                            TextField("0", value: $editedThreshold, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.serif(16, weight: .medium))
                                .frame(maxWidth: 120)
                        }
                    } else {
                        Stepper(value: $editedThreshold, in: 1...7) {
                            HStack {
                                Text("Days per week")
                                Spacer()
                                Text("\(editedThreshold)×")
                                    .font(.serif(16, weight: .medium))
                            }
                        }
                    }
                    Stepper(value: $editedValue, in: 1...50) {
                        HStack {
                            Text(valueLabel)
                            Spacer()
                            Text("\(editedValue)")
                                .font(.serif(16, weight: .medium))
                        }
                    }
                } footer: {
                    Text(helper)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(
                            editedName.trimmingCharacters(in: .whitespacesAndNewlines),
                            editedReference,
                            editedThreshold,
                            editedValue
                        )
                        dismiss()
                    }
                    .font(.sans(15, weight: .medium))
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            editedName = name
            editedReference = reference.isEmpty ? (taskNames.first ?? "") : reference
            editedThreshold = threshold
            editedValue = value
        }
    }
}

// MARK: - Milestone editor

struct SetupMilestoneEditSheet: View {
    let milestone: DraftMilestone
    let onSave: (DraftMilestone) -> Void
    let onRemove: (DraftMilestone) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var value: Int = 60
    @State private var steps: [DraftMilestoneStep] = []
    @State private var newStepName: String = ""

    private var isNew: Bool { milestone.name.isEmpty }

    /// What the whole destination is worth once its rungs are counted.
    /// Shown because a staged milestone's headline number is only part
    /// of the story, and someone reading "+50" next to three priced
    /// steps should not have to add them up themselves.
    private var totalWithSteps: Int {
        value + steps.reduce(0) { $0 + max(0, $1.value) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Milestone", text: $name)
                        .font(.sans(16, weight: .regular))
                    Stepper(value: $value, in: 10...250, step: 10) {
                        HStack {
                            Text("Worth")
                            Spacer()
                            Text("+\(value)")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.sunShadow)
                        }
                    }
                } footer: {
                    Text("One-time and worth a lot — the season's bigger wins, not a repeating task.")
                }

                // Staging a big destination is instructed in setup and
                // the season stores it, but until now there was nowhere
                // to change one: a rung the conversation got wrong was
                // permanent, and a goal you wanted to break down after
                // the fact could not be.
                Section {
                    ForEach($steps) { $step in
                        HStack(spacing: 10) {
                            TextField("Step", text: $step.name)
                                .font(.sans(15, weight: .regular))
                            Spacer(minLength: 8)
                            Stepper(value: $step.value, in: 0...100, step: 5) {
                                Text(step.value == 0 ? "—" : "+\(step.value)")
                                    .font(.serif(15, weight: .medium))
                                    .foregroundStyle(step.value == 0
                                        ? Theme.textPrimary.opacity(0.4)
                                        : Theme.sunShadow)
                            }
                            .labelsHidden()
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }

                    HStack(spacing: 10) {
                        TextField("Add a step", text: $newStepName)
                            .font(.sans(15, weight: .regular))
                            .onSubmit(addStep)
                        Button(action: addStep) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Theme.sunShadow)
                        }
                        .buttonStyle(.plain)
                        .disabled(newStepName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    if steps.isEmpty {
                        Text("Optional. A long way off is easier to walk in stages — first 10-miler, first 20-miler, race day.")
                    } else {
                        Text("A step worth nothing still marks progress; one worth points pays the day it's checked off. This destination is worth \(totalWithSteps) in total.")
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onRemove(milestone)
                            dismiss()
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(isNew ? "New milestone" : "Edit milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = milestone
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.value = max(1, value)
                        updated.steps = steps
                            .map { step in
                                var copy = step
                                copy.name = step.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                return copy
                            }
                            .filter { !$0.name.isEmpty }
                        onSave(updated)
                        dismiss()
                    }
                    .font(.sans(15, weight: .medium))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            name = milestone.name
            value = milestone.value
            steps = milestone.steps
        }
    }

    private func addStep() {
        let trimmed = newStepName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        steps.append(DraftMilestoneStep(name: trimmed))
        newStepName = ""
    }
}
