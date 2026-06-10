//
//  NewTaskFormView.swift
//  FrisFocus
//
//  Full-height form sheet for creating or editing a repeatable Task.
//  Title, season category, a scoring style (flat / tiered / quantity)
//  with its details, an optional skip penalty available on any task,
//  pin-to-today, and the optional Booster + Weekly-limit rules.
//
//  Use the default initializer to create; pass `editing:` to edit an
//  existing task in place. Saving appends/updates `store.tasks`,
//  persists, dismisses the sheet, then fires the `onSave` callback.
//

import SwiftUI
import UIKit

struct NewTaskFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: FFTask?
    let onSave: () -> Void

    @State private var title: String
    @State private var category: Category
    @State private var pointValue: Int
    @State private var pinToToday: Bool

    // Scoring style
    @State private var scoringType: ScoringType
    @State private var unit: String
    @State private var tiers: [ScoreTier]
    @State private var baseThreshold: Double
    @State private var basePoints: Int
    @State private var unitSize: Double
    @State private var pointsPerUnit: Int

    // Skip penalty (any task)
    @State private var skipPenaltyEnabled: Bool
    @State private var skipPenalty: Int

    // Weekly-limit penalty
    @State private var penaltyEnabled: Bool
    @State private var penaltyCondition: PenaltyCondition
    @State private var penaltyThreshold: Int
    @State private var penaltyPoints: Int

    init(editing: FFTask? = nil, onSave: @escaping () -> Void) {
        self.editing = editing
        self.onSave = onSave
        _title = State(initialValue: editing?.title ?? "")
        _category = State(initialValue: editing?.category ?? .work)
        _pointValue = State(initialValue: editing?.pointValue ?? 5)
        _pinToToday = State(initialValue: {
            guard let t = editing else { return false }
            return t.isPinnedToday
        }())

        let scoring = editing?.scoring ?? ScoringConfig()
        _scoringType = State(initialValue: scoring.type)
        _unit = State(initialValue: scoring.unit)
        _tiers = State(initialValue: scoring.tiers.isEmpty
            ? [ScoreTier(threshold: 6, points: 2), ScoreTier(threshold: 8, points: 4)]
            : scoring.sortedTiers)
        _baseThreshold = State(initialValue: scoring.baseThreshold == 0 ? 100 : scoring.baseThreshold)
        _basePoints = State(initialValue: scoring.basePoints == 0 ? 3 : scoring.basePoints)
        _unitSize = State(initialValue: scoring.unitSize <= 0 ? 50 : scoring.unitSize)
        _pointsPerUnit = State(initialValue: scoring.pointsPerUnit == 0 ? 1 : scoring.pointsPerUnit)

        let skip = editing?.skipPenalty
        _skipPenaltyEnabled = State(initialValue: (skip ?? 0) < 0)
        _skipPenalty = State(initialValue: skip ?? -5)

        let penalty = editing?.penalty
        _penaltyEnabled = State(initialValue: penalty?.enabled ?? false)
        _penaltyCondition = State(initialValue: penalty?.condition ?? .moreThan)
        _penaltyThreshold = State(initialValue: penalty?.timesThreshold ?? 2)
        _penaltyPoints = State(initialValue: penalty?.penaltyPoints ?? 10)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Lift — push day", text: $title, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...3)
                } header: {
                    Text("Title")
                }

                categorySection
                scoringSection
                skipPenaltySection

                Section {
                    Toggle("Pin to today", isOn: $pinToToday)
                } footer: {
                    Text("Pinned Tasks appear on Today's Plan on the home screen.")
                }

                weeklyLimitSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle(editing == nil ? "New Task" : "Edit Task")
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

    // MARK: - Category

    private var availableCategories: [Category] {
        var cats = store.currentSeason.categories.map(\.category)
        if let editing, !cats.contains(editing.category) { cats.append(editing.category) }
        if !cats.contains(category) { cats.append(category) }
        return cats
    }

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $category) {
                ForEach(availableCategories, id: \.self) { cat in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: store.categoryColorHex(cat)))
                            .frame(width: 8, height: 8)
                        Text(store.categoryDisplayName(cat))
                    }
                    .tag(cat)
                }
            }
        } header: {
            Text("Category")
        }
    }

    // MARK: - Scoring style

    private var scoringSection: some View {
        Section {
            Picker("Scoring style", selection: $scoringType.animation(.easeInOut(duration: 0.2))) {
                ForEach(ScoringType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            switch scoringType {
            case .flat:
                Stepper(value: $pointValue, in: 1...100) {
                    HStack {
                        Text("Worth")
                        Spacer()
                        Text("\(pointValue) pts")
                            .font(.serif(17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            case .tiered:
                tieredEditor
            case .quantity:
                quantityEditor
            }
        } header: {
            Text("Scoring")
        } footer: {
            Text(scoringType.blurb)
        }
    }

    @ViewBuilder
    private var tieredEditor: some View {
        unitField(placeholder: "e.g. hours")

        ForEach($tiers) { $tier in
            HStack(spacing: 10) {
                Text("At")
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                TextField("amount", value: $tier.threshold, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 56)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .background(Theme.textPrimary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer()
                Stepper("\(tier.points) pts", value: $tier.points, in: 0...100)
                    .labelsHidden()
                Text("\(tier.points) pts")
                    .font(.serif(15, weight: .medium))
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .onDelete { tiers.remove(atOffsets: $0) }

        Button {
            let nextThreshold = (tiers.map(\.threshold).max() ?? 0) + 1
            let nextPoints = (tiers.map(\.points).max() ?? 0) + 2
            tiers.append(ScoreTier(threshold: nextThreshold, points: nextPoints))
        } label: {
            Label("Add level", systemImage: "plus.circle")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.alertGreen)
        }
    }

    @ViewBuilder
    private var quantityEditor: some View {
        unitField(placeholder: "e.g. reps")

        HStack {
            Text("Base at")
            Spacer()
            TextField("amount", value: $baseThreshold, format: .number)
                .keyboardType(.decimalPad)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            if !unit.isEmpty { Text(unit).foregroundStyle(Theme.textPrimary.opacity(0.6)) }
        }
        Stepper(value: $basePoints, in: 0...100) {
            HStack {
                Text("Base points")
                Spacer()
                Text("\(basePoints) pts").font(.serif(16, weight: .medium))
            }
        }
        HStack {
            Text("Then every")
            Spacer()
            TextField("size", value: $unitSize, format: .number)
                .keyboardType(.decimalPad)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            if !unit.isEmpty { Text(unit).foregroundStyle(Theme.textPrimary.opacity(0.6)) }
        }
        Stepper(value: $pointsPerUnit, in: 0...50) {
            HStack {
                Text("Adds")
                Spacer()
                Text("+\(pointsPerUnit) pts").font(.serif(16, weight: .medium)).foregroundStyle(Theme.alertGreen)
            }
        }

        Text(quantityPreview)
            .font(.serifItalic(13))
            .foregroundStyle(Theme.textPrimary.opacity(0.7))
    }

    private func unitField(placeholder: String) -> some View {
        HStack {
            Text("Unit")
            Spacer()
            TextField(placeholder, text: $unit)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var quantityPreview: String {
        let cfg = buildConfig()
        let atBase = cfg.points(forQuantity: baseThreshold, flatValue: pointValue)
        let beyond = baseThreshold + unitSize * 2
        let atBeyond = cfg.points(forQuantity: beyond, flatValue: pointValue)
        let unitLabel = unit.isEmpty ? "" : " \(unit)"
        return "\(Int(baseThreshold))\(unitLabel) → \(atBase) pts · \(Int(beyond))\(unitLabel) → \(atBeyond) pts"
    }

    // MARK: - Skip penalty (any task)

    private var skipPenaltySection: some View {
        Section {
            Toggle("Skip penalty", isOn: $skipPenaltyEnabled.animation(.easeInOut(duration: 0.2)))
            if skipPenaltyEnabled {
                Stepper(value: $skipPenalty, in: -20 ... -1) {
                    HStack {
                        Text("If skipped")
                        Spacer()
                        Text("\(skipPenalty) pts")
                            .foregroundStyle(Theme.alertRed)
                    }
                }
            }
        } header: {
            Text("Skip penalty")
        } footer: {
            Text("Optional. When on, skipping this task on a day it's pinned pulls points from that day. Available on any task — no priority tiers.")
        }
    }

    // MARK: - Weekly limit

    private var weeklyLimitSection: some View {
        Section {
            Toggle("Weekly limit", isOn: $penaltyEnabled.animation(.easeInOut(duration: 0.2)))

            if penaltyEnabled {
                Picker("Condition", selection: $penaltyCondition) {
                    Text("More than").tag(PenaltyCondition.moreThan)
                    Text("Less than").tag(PenaltyCondition.lessThan)
                }
                .pickerStyle(.segmented)

                Stepper(value: $penaltyThreshold, in: 0...7) {
                    HStack {
                        Text("Times this week")
                        Spacer()
                        Text("\(penaltyThreshold)\u{00D7}")
                            .font(.serif(17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                Stepper(value: $penaltyPoints, in: 1...100) {
                    HStack {
                        Text("Penalty points")
                        Spacer()
                        Text("\u{2212}\(penaltyPoints)")
                            .font(.serif(17, weight: .medium))
                            .foregroundStyle(Theme.alertAmber)
                    }
                }

                Text(penaltyPreviewSentence)
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .padding(.top, 2)
            }
        } header: {
            Text("Weekly limit")
        } footer: {
            Text("A gentle, private reduction goal. Points stay off your friends' feeds and only show up in your own weekly total.")
        }
    }

    // MARK: - Derived

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var penaltyPreviewSentence: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "this task" : trimmed
        return "If \(name) is completed \(penaltyCondition.phrase) \(penaltyThreshold) times this week, lose \(penaltyPoints) points."
    }

    private func buildConfig() -> ScoringConfig {
        ScoringConfig(
            type: scoringType,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            tiers: tiers,
            baseThreshold: baseThreshold,
            basePoints: basePoints,
            unitSize: unitSize,
            pointsPerUnit: pointsPerUnit
        )
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = buildConfig()
        // Keep pointValue meaningful across shapes so value-based
        // reminders and legacy reads have a sane number.
        let resolvedValue = scoringType == .flat ? pointValue : config.headlineValue(flatValue: pointValue)
        let resolvedSkip: Int? = skipPenaltyEnabled ? min(-1, skipPenalty) : nil

        let penaltyRule: PenaltyRule? = penaltyEnabled
            ? PenaltyRule(
                enabled: true,
                timesThreshold: penaltyThreshold,
                condition: penaltyCondition,
                penaltyPoints: penaltyPoints
            )
            : nil

        if let editing, let idx = store.tasks.firstIndex(where: { $0.id == editing.id }) {
            var updated = store.tasks[idx]
            updated.title = trimmedTitle
            updated.category = category
            updated.pointValue = resolvedValue
            updated.scoring = config
            updated.skipPenalty = resolvedSkip
            switch updated.pinSchedule {
            case .none, .today:
                updated.pinSchedule = pinToToday ? .today : .none
            default:
                if !pinToToday {
                    updated.pinSchedule = .none
                }
            }
            updated.penalty = penaltyRule
            store.tasks[idx] = updated
            store.evaluatePenaltyForTask(updated)
        } else {
            let task = FFTask(
                title: trimmedTitle,
                category: category,
                pointValue: resolvedValue,
                skipPenalty: resolvedSkip,
                pinSchedule: pinToToday ? .today : .none,
                penalty: penaltyRule,
                scoring: config
            )
            store.tasks.append(task)
            store.evaluatePenaltyForTask(task)
        }
        store.persistAll()

        dismiss()
        onSave()
    }
}

#Preview {
    NewTaskFormView { }
        .environment(Store())
}
