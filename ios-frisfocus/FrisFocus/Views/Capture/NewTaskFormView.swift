//
//  NewTaskFormView.swift
//  FrisFocus
//
//  Full-height form sheet for creating or editing a repeatable Task.
//  Title, category, point value, tier, optional skip penalty for
//  Must-Dos, pin-to-today, and an optional Booster rule.
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
    @State private var tier: Tier
    @State private var skipPenalty: Int
    @State private var pinToToday: Bool

    // Booster
    @State private var boosterEnabled: Bool
    @State private var boosterTimesRequired: Int
    @State private var boosterPeriod: BoosterPeriod
    @State private var boosterBonusPoints: Int

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
        _tier = State(initialValue: editing?.tier ?? .should)
        _skipPenalty = State(initialValue: editing?.skipPenalty ?? -5)
        _pinToToday = State(initialValue: {
            guard let t = editing else { return false }
            return t.isPinnedToday
        }())

        let booster = editing?.booster
        _boosterEnabled = State(initialValue: booster?.enabled ?? false)
        _boosterTimesRequired = State(initialValue: booster?.timesRequired ?? 3)
        _boosterPeriod = State(initialValue: booster?.period ?? .week)
        _boosterBonusPoints = State(initialValue: booster?.bonusPoints ?? 10)

        let penalty = editing?.penalty
        _penaltyEnabled = State(initialValue: penalty?.enabled ?? false)
        _penaltyCondition = State(initialValue: penalty?.condition ?? .moreThan)
        _penaltyThreshold = State(initialValue: penalty?.timesThreshold ?? 2)
        _penaltyPoints = State(initialValue: penalty?.penaltyPoints ?? 10)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let editing {
                    BoosterReadoutSection(task: editing)
                }

                Section {
                    TextField("e.g. Lift — push day", text: $title, axis: .vertical)
                        .font(.sans(16, weight: .regular))
                        .lineLimit(1...3)
                } header: {
                    Text("Title")
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases, id: \.self) { cat in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(cat.color)
                                    .frame(width: 8, height: 8)
                                Text(cat.displayName)
                            }
                            .tag(cat)
                        }
                    }
                } header: {
                    Text("Category")
                }

                Section {
                    Stepper(value: $pointValue, in: 1...30) {
                        HStack {
                            Text("Worth")
                            Spacer()
                            Text("\(pointValue) pts")
                                .font(.serif(17, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                } header: {
                    Text("Points")
                } footer: {
                    Text("How many points this Task is worth toward your daily goal.")
                }

                Section {
                    Picker("Tier", selection: $tier) {
                        Text("Must").tag(Tier.must)
                        Text("Should").tag(Tier.should)
                        Text("Could").tag(Tier.could)
                    }
                    .pickerStyle(.segmented)

                    if tier == .must {
                        Stepper(value: $skipPenalty, in: -20...0) {
                            HStack {
                                Text("Skip penalty")
                                Spacer()
                                Text("\(skipPenalty) pts")
                                    .foregroundStyle(Theme.alertRed)
                            }
                        }
                    }
                } header: {
                    Text("Tier")
                } footer: {
                    Text(tierFooter)
                }

                Section {
                    Toggle("Pin to today", isOn: $pinToToday)
                } footer: {
                    Text("Pinned Tasks appear on Today's Plan on the home screen.")
                }

                // MARK: Booster

                Section {
                    Toggle("Booster", isOn: $boosterEnabled.animation(.easeInOut(duration: 0.2)))

                    if boosterEnabled {
                        Stepper(value: $boosterTimesRequired, in: 1...30) {
                            HStack {
                                Text("Times required")
                                Spacer()
                                Text("\(boosterTimesRequired)\u{00D7}")
                                    .font(.serif(17, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }

                        Picker("Period", selection: $boosterPeriod) {
                            Text("Week").tag(BoosterPeriod.week)
                            Text("Month").tag(BoosterPeriod.month)
                        }
                        .pickerStyle(.segmented)

                        Stepper(value: $boosterBonusPoints, in: 1...100) {
                            HStack {
                                Text("Bonus points")
                                Spacer()
                                Text("+\(boosterBonusPoints)")
                                    .font(.serif(17, weight: .medium))
                                    .foregroundStyle(Theme.alertGreen)
                            }
                        }

                        Text(boosterPreviewSentence)
                            .font(.serifItalic(13))
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                            .padding(.top, 2)
                    }
                } header: {
                    Text("Booster")
                } footer: {
                    Text("A count-toward-a-target reward. Miss a day, no problem — only the count by the end of the \(boosterPeriod.displayName) matters.")
                }

                // MARK: Weekly limit

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

    // MARK: - Derived

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tierFooter: String {
        switch tier {
        case .must: return "Must-Dos cost points if you skip them."
        case .should: return "Should-Dos are pinned to the season but unpenalized."
        case .could: return "Could-Dos are nice-to-haves with no pressure."
        }
    }

    private var boosterPreviewSentence: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "this task" : trimmed
        return "Complete \(name) \(boosterTimesRequired) times per \(boosterPeriod.displayName) to earn +\(boosterBonusPoints) bonus points."
    }

    private var penaltyPreviewSentence: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "this task" : trimmed
        return "If \(name) is completed \(penaltyCondition.phrase) \(penaltyThreshold) times this week, lose \(penaltyPoints) points."
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let boosterRule: BoosterRule? = boosterEnabled
            ? BoosterRule(
                enabled: true,
                timesRequired: boosterTimesRequired,
                period: boosterPeriod,
                bonusPoints: boosterBonusPoints
            )
            : nil
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
            updated.pointValue = pointValue
            updated.tier = tier
            updated.skipPenalty = tier == .must ? skipPenalty : nil
            // Preserve any non-`.today` schedule; only flip the today
            // pin when the user changed it.
            switch updated.pinSchedule {
            case .none, .today:
                updated.pinSchedule = pinToToday ? .today : .none
            default:
                if !pinToToday {
                    // Honor explicit unpin from the form even on
                    // recurring schedules.
                    updated.pinSchedule = .none
                }
            }
            updated.booster = boosterRule
            updated.penalty = penaltyRule
            store.tasks[idx] = updated
            // Re-evaluate the weekly limit so a freshly-saved (or
            // disabled) rule takes effect immediately on the score.
            store.evaluatePenaltyForTask(updated)
        } else {
            let task = FFTask(
                title: trimmedTitle,
                category: category,
                pointValue: pointValue,
                tier: tier,
                skipPenalty: tier == .must ? skipPenalty : nil,
                pinSchedule: pinToToday ? .today : .none,
                booster: boosterRule,
                penalty: penaltyRule
            )
            store.tasks.append(task)
            store.evaluatePenaltyForTask(task)
        }
        store.persistAll()

        dismiss()
        onSave()
    }
}

// MARK: - Booster readout (edit mode)
//
// Quiet status block at the top of an edit-task form: progress chip plus,
// when earned, the date the booster crossed the line in the current period.

private struct BoosterReadoutSection: View {
    @Environment(Store.self) private var store
    let task: FFTask

    var body: some View {
        if let status = store.boosterStatus(for: task) {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    BoosterProgressChip(
                        progress: status.progress,
                        required: status.required,
                        earned: status.earned,
                        period: status.period,
                        category: task.category
                    )

                    Text("Complete \(task.title) \(status.required) times per \(status.period.displayName) to earn +\(status.bonusPoints) bonus points.")
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))

                    if status.earned, let earnedOn = store.boosterEarnedDate(for: task) {
                        Text("Earned \(earnedOn.formatted(date: .abbreviated, time: .omitted)) \u{00B7} +\(status.bonusPoints) pts")
                            .font(.sans(11, weight: .medium))
                            .foregroundStyle(Theme.alertGreen)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Booster status")
            }
        }
    }
}

#Preview {
    NewTaskFormView { }
        .environment(Store())
}
