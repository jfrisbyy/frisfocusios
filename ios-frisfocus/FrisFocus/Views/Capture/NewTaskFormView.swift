//
//  NewTaskFormView.swift
//  FrisFocus
//
//  Full-height sheet for creating or editing a repeatable Task, in the
//  app's warm paper style — cream background, white card sections with
//  quiet eyebrow headers, serif numerals. Title, season category, a
//  scoring style (flat / tiered / quantity) with its details, an
//  optional skip penalty, a proper Schedule section (not pinned /
//  today / specific days / every day plus an optional time window),
//  and the Weekly-limit rule.
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
    @State private var scheduleDraft: ScheduleDraft

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
        _scheduleDraft = State(initialValue: ScheduleDraft(task: editing))

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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionCard(eyebrow: "Title") {
                        TextField("e.g. Lift — push day", text: $title, axis: .vertical)
                            .font(.serif(18, weight: .regular))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1...3)
                    }

                    sectionCard(eyebrow: "Category") {
                        categoryChips
                    }

                    sectionCard(eyebrow: "Scoring", footer: scoringType.blurb) {
                        scoringContent
                    }

                    sectionCard(
                        eyebrow: "Schedule",
                        footer: scheduleFooter
                    ) {
                        ScheduleEditorView(draft: $scheduleDraft)
                    }

                    sectionCard(
                        eyebrow: "Skip penalty",
                        footer: "Optional. When on, skipping this task on a day it's pinned pulls points from that day."
                    ) {
                        skipPenaltyContent
                    }

                    sectionCard(
                        eyebrow: "Weekly limit",
                        footer: "A gentle, private reduction goal. Points stay off your friends' feeds and only show up in your own weekly total."
                    ) {
                        weeklyLimitContent
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.sans(14))
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

    // MARK: - Section card scaffolding

    @ViewBuilder
    private func sectionCard<Content: View>(
        eyebrow: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: eyebrow, opacity: 0.55)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
            )

            if let footer {
                Text(footer)
                    .font(.serifItalic(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 2)
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

    @ViewBuilder
    private var categoryChips: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(availableCategories, id: \.self) { cat in
                let selected = category == cat
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    category = cat
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(hex: store.categoryColorHex(cat)))
                            .frame(width: 7, height: 7)
                        Text(store.categoryDisplayName(cat))
                            .font(.sans(13, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.75))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule().fill(selected ? Theme.textPrimary : Theme.warmWheat)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            selected ? Color.clear : Theme.textPrimary.opacity(0.10),
                            lineWidth: 0.6
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Scoring

    @ViewBuilder
    private var scoringContent: some View {
        HStack(spacing: 6) {
            ForEach(ScoringType.allCases, id: \.self) { type in
                let selected = scoringType == type
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { scoringType = type }
                } label: {
                    Text(type.displayName)
                        .font(.sans(13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.warmWheat : Theme.textPrimary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Theme.textPrimary : Theme.warmWheat)
                        )
                }
                .buttonStyle(.plain)
            }
        }

        switch scoringType {
        case .flat:
            Stepper(value: $pointValue, in: 1...100) {
                HStack {
                    Text("Worth")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
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
    }

    @ViewBuilder
    private var tieredEditor: some View {
        unitField(placeholder: "e.g. hours")

        ForEach($tiers) { $tier in
            HStack(spacing: 10) {
                Text("At")
                    .font(.sans(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                TextField("amount", value: $tier.threshold, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 56)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .background(Theme.textPrimary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.sans(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                Spacer()
                Stepper("\(tier.points) pts", value: $tier.points, in: 0...100)
                    .labelsHidden()
                Text("\(tier.points) pts")
                    .font(.serif(15, weight: .medium))
                    .frame(width: 52, alignment: .trailing)
            }
        }

        Button {
            let nextThreshold = (tiers.map(\.threshold).max() ?? 0) + 1
            let nextPoints = (tiers.map(\.points).max() ?? 0) + 2
            tiers.append(ScoreTier(threshold: nextThreshold, points: nextPoints))
        } label: {
            Label("Add level", systemImage: "plus.circle")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.alertGreen)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var quantityEditor: some View {
        unitField(placeholder: "e.g. reps")

        HStack {
            Text("Base at")
                .font(.sans(14, weight: .medium))
            Spacer()
            TextField("amount", value: $baseThreshold, format: .number)
                .keyboardType(.decimalPad)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            if !unit.isEmpty {
                Text(unit)
                    .font(.sans(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        }
        Stepper(value: $basePoints, in: 0...100) {
            HStack {
                Text("Base points")
                    .font(.sans(14, weight: .medium))
                Spacer()
                Text("\(basePoints) pts").font(.serif(16, weight: .medium))
            }
        }
        HStack {
            Text("Then every")
                .font(.sans(14, weight: .medium))
            Spacer()
            TextField("size", value: $unitSize, format: .number)
                .keyboardType(.decimalPad)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            if !unit.isEmpty {
                Text(unit)
                    .font(.sans(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }
        }
        Stepper(value: $pointsPerUnit, in: 0...50) {
            HStack {
                Text("Adds")
                    .font(.sans(14, weight: .medium))
                Spacer()
                Text("+\(pointsPerUnit) pts")
                    .font(.serif(16, weight: .medium))
                    .foregroundStyle(Theme.alertGreen)
            }
        }

        Text(quantityPreview)
            .font(.serifItalic(13))
            .foregroundStyle(Theme.textPrimary.opacity(0.7))
    }

    private func unitField(placeholder: String) -> some View {
        HStack {
            Text("Unit")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
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

    // MARK: - Skip penalty

    @ViewBuilder
    private var skipPenaltyContent: some View {
        Toggle(isOn: $skipPenaltyEnabled.animation(.easeInOut(duration: 0.2))) {
            Text("Skip penalty")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.alertGreen)

        if skipPenaltyEnabled {
            Stepper(value: $skipPenalty, in: -20 ... -1) {
                HStack {
                    Text("If skipped")
                        .font(.sans(14, weight: .medium))
                    Spacer()
                    Text("\(skipPenalty) pts")
                        .font(.serif(16, weight: .medium))
                        .foregroundStyle(Theme.alertRed)
                }
            }
        }
    }

    // MARK: - Weekly limit

    @ViewBuilder
    private var weeklyLimitContent: some View {
        Toggle(isOn: $penaltyEnabled.animation(.easeInOut(duration: 0.2))) {
            Text("Weekly limit")
                .font(.sans(14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.alertGreen)

        if penaltyEnabled {
            Picker("Condition", selection: $penaltyCondition) {
                Text("More than").tag(PenaltyCondition.moreThan)
                Text("Less than").tag(PenaltyCondition.lessThan)
            }
            .pickerStyle(.segmented)

            Stepper(value: $penaltyThreshold, in: 0...7) {
                HStack {
                    Text("Times this week")
                        .font(.sans(14, weight: .medium))
                    Spacer()
                    Text("\(penaltyThreshold)\u{00D7}")
                        .font(.serif(17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            Stepper(value: $penaltyPoints, in: 1...100) {
                HStack {
                    Text("Penalty points")
                        .font(.sans(14, weight: .medium))
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
    }

    // MARK: - Derived

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var scheduleFooter: String {
        switch scheduleDraft.mode {
        case .notPinned:
            return "Not on Today's Plan — the task stays in your library."
        case .today:
            return "On Today's Plan until the day rolls over."
        case .specificDays:
            return "Lands on Today's Plan every week on the chosen days."
        case .everyDay:
            return "On Today's Plan every single day."
        }
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

        let schedule = scheduleDraft.resolvedSchedule
        let window = scheduleDraft.resolvedTimeWindow

        if let editing, let idx = store.tasks.firstIndex(where: { $0.id == editing.id }) {
            var updated = store.tasks[idx]
            updated.title = trimmedTitle
            updated.category = category
            updated.pointValue = resolvedValue
            updated.scoring = config
            updated.skipPenalty = resolvedSkip
            updated.pinSchedule = schedule
            updated.timeWindow = window
            // "Not pinned" explicitly clears any one-off pin too.
            if scheduleDraft.mode == .notPinned {
                updated.oneOffPinDate = nil
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
                pinSchedule: schedule,
                timeWindow: window,
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
