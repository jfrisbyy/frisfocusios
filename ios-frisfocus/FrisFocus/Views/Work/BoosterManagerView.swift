//
//  BoosterManagerView.swift
//  FrisFocus
//
//  "Boosters" — the standalone manager for first-class weekly boosters.
//  Each booster watches a task or a whole category and pays out
//  all-or-nothing once its count threshold is reached in the period.
//  Being first-class lets a booster span several tasks (a category) and
//  outlive any single task it once pointed at.
//

import SwiftUI
import UIKit

struct BoosterManagerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd: Bool = false
    @State private var editing: WeeklyBooster? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if store.boosters.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.boosters) { booster in
                                BoosterCard(
                                    booster: booster,
                                    onEdit: { editing = booster },
                                    onDelete: { store.deleteBooster(booster) }
                                )
                            }
                        }
                    }

                    addButton

                    footer

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .background(Theme.warmWheat)
            .navigationTitle("Boosters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .sheet(isPresented: $showAdd) {
                BoosterFormView(editing: nil)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editing) { booster in
                BoosterFormView(editing: booster)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Consistency rewards")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("A booster watches a task — or a whole area — and pays a bonus once you hit the count by the end of the week or month. Miss a day, no problem; only the count matters.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No boosters yet")
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
            Text("Add one below to reward a count toward a target.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAdd = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                Text("Add a booster")
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("Boosters settle into your own weekly and season totals. Point a booster at a category to reward a habit tracked across several tasks.")
            .font(.serifItalic(12))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Card

private struct BoosterCard: View {
    @Environment(Store.self) private var store
    let booster: WeeklyBooster
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let status = store.boosterStatus(for: booster)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(booster.name.isEmpty ? referenceName : booster.name)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }

                Spacer(minLength: 8)

                Menu {
                    Button("Edit", systemImage: "pencil") { onEdit() }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }

            HStack(spacing: 8) {
                BoosterProgressChip(
                    progress: status.progress,
                    required: status.required,
                    earned: status.earned,
                    period: status.period,
                    category: chipCategory
                )
                Spacer()
                Text("+\(booster.bonusPoints) pts")
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.alertGreen)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var referenceName: String {
        switch booster.reference {
        case .task(let id):
            return store.tasks.first(where: { $0.id == id })?.title ?? "a task"
        case .category(let cat):
            return store.categoryDisplayName(cat)
        }
    }

    private var subtitle: String {
        let target: String
        switch booster.reference {
        case .task:
            target = referenceName
        case .category:
            target = "\(referenceName) area"
        }
        return "\(target) \u{00B7} \(booster.threshold)\u{00D7} per \(booster.period.displayName)"
    }

    private var chipCategory: Category {
        switch booster.reference {
        case .category(let cat):
            return cat
        case .task(let id):
            return store.tasks.first(where: { $0.id == id })?.category
                ?? store.currentSeason.categories.first?.category
                ?? .work
        }
    }
}

// MARK: - Add / edit form

private struct BoosterFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: WeeklyBooster?

    private enum ReferenceKind: String, CaseIterable { case task, category }

    @State private var name: String
    @State private var referenceKind: ReferenceKind
    @State private var taskId: UUID?
    @State private var category: Category
    @State private var threshold: Int
    @State private var period: BoosterPeriod
    @State private var bonusPoints: Int

    init(editing: WeeklyBooster?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _threshold = State(initialValue: editing?.threshold ?? 3)
        _period = State(initialValue: editing?.period ?? .week)
        _bonusPoints = State(initialValue: editing?.bonusPoints ?? 10)

        switch editing?.reference {
        case .task(let id):
            _referenceKind = State(initialValue: .task)
            _taskId = State(initialValue: id)
            _category = State(initialValue: .work)
        case .category(let cat):
            _referenceKind = State(initialValue: .category)
            _taskId = State(initialValue: nil)
            _category = State(initialValue: cat)
        case nil:
            _referenceKind = State(initialValue: .task)
            _taskId = State(initialValue: nil)
            _category = State(initialValue: .work)
        }
    }

    private var seasonCategories: [Category] {
        store.currentSeason.categories.map(\.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Gym habit", text: $name, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...3)
                } header: {
                    Text("Name")
                } footer: {
                    Text("What the booster rewards. Leave blank to use the task or area name.")
                }

                Section {
                    Picker("Watches", selection: $referenceKind.animation(.easeInOut(duration: 0.2))) {
                        Text("A task").tag(ReferenceKind.task)
                        Text("An area").tag(ReferenceKind.category)
                    }
                    .pickerStyle(.segmented)

                    if referenceKind == .task {
                        Picker("Task", selection: $taskId) {
                            Text("Choose a task").tag(UUID?.none)
                            ForEach(store.tasks) { task in
                                Text(task.title).tag(UUID?.some(task.id))
                            }
                        }
                    } else {
                        Picker("Area", selection: $category) {
                            ForEach(seasonCategories, id: \.self) { cat in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: store.categoryColorHex(cat)))
                                        .frame(width: 8, height: 8)
                                    Text(store.categoryDisplayName(cat))
                                }
                                .tag(cat)
                            }
                        }
                    }
                } header: {
                    Text("Target")
                } footer: {
                    Text(referenceKind == .task
                        ? "Counts completions of one task."
                        : "Counts completions across every task in this area.")
                }

                Section {
                    Stepper(value: $threshold, in: 1...60) {
                        HStack {
                            Text("Times required")
                            Spacer()
                            Text("\(threshold)\u{00D7}")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }

                    Picker("Period", selection: $period) {
                        Text("Week").tag(BoosterPeriod.week)
                        Text("Month").tag(BoosterPeriod.month)
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $bonusPoints, in: 1...100) {
                        HStack {
                            Text("Bonus points")
                            Spacer()
                            Text("+\(bonusPoints)")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.alertGreen)
                        }
                    }

                    Text(previewSentence)
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                } header: {
                    Text("Reward")
                } footer: {
                    Text("All-or-nothing. The bonus lands once when the count is reached this \(period.displayName).")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(editing == nil ? "Add booster" : "Edit booster")
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
        }
    }

    private var canSave: Bool {
        switch referenceKind {
        case .task:     return taskId != nil
        case .category: return true
        }
    }

    private var targetName: String {
        switch referenceKind {
        case .task:
            return store.tasks.first(where: { $0.id == taskId })?.title ?? "this task"
        case .category:
            return "\(store.categoryDisplayName(category)) area"
        }
    }

    private var previewSentence: String {
        "Reach \(threshold)\u{00D7} on \(targetName) this \(period.displayName) to earn +\(bonusPoints) points."
    }

    private func resolvedReference() -> BoosterReference? {
        switch referenceKind {
        case .task:
            guard let id = taskId else { return nil }
            return .task(id)
        case .category:
            return .category(category)
        }
    }

    private func resolvedName() -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? targetName : trimmed
    }

    private func save() {
        guard let reference = resolvedReference() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if let editing {
            var updated = editing
            updated.name = resolvedName()
            updated.reference = reference
            updated.threshold = threshold
            updated.period = period
            updated.bonusPoints = bonusPoints
            store.updateBooster(updated)
        } else {
            store.addBooster(
                name: resolvedName(),
                reference: reference,
                threshold: threshold,
                period: period,
                bonusPoints: bonusPoints
            )
        }
        dismiss()
    }
}

#Preview {
    BoosterManagerView()
        .environment(Store())
}
