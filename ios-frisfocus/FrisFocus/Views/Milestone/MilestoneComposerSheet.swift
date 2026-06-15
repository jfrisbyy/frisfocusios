//
//  MilestoneComposerSheet.swift
//  FrisFocus
//
//  Create or edit a milestone — title, target week, reward, and the
//  per-milestone "points per step" choice. Styled on the warm paper
//  rather than a stock grouped form, matching the rest of the app's
//  quiet editorial language.
//

import SwiftUI
import UIKit

struct MilestoneComposerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: Milestone?

    @State private var title: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var pointValue: Int
    @State private var pointsPerStep: Bool

    @FocusState private var titleFocused: Bool

    init(editing: Milestone?) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _hasTargetDate = State(initialValue: editing?.targetDate != nil)
        _targetDate = State(
            initialValue: editing?.targetDate
                ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())
                ?? Date()
        )
        _pointValue = State(initialValue: editing?.pointValue ?? 50)
        _pointsPerStep = State(initialValue: editing?.pointsPerStep ?? false)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleCard
                        whenCard
                        rewardCard
                        stepPointsCard
                    }
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(editing == nil ? "New milestone" : "Edit milestone")
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
            .onAppear {
                if editing == nil { titleFocused = true }
            }
        }
    }

    // MARK: - Cards

    private var titleCard: some View {
        card {
            EyebrowText(text: "The big win", opacity: 0.5)
            TextField("e.g. Release the single", text: $title, axis: .vertical)
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .focused($titleFocused)
                .lineLimit(1...3)
        }
    }

    private var whenCard: some View {
        card {
            Toggle(isOn: $hasTargetDate.animation(.easeInOut(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Target date")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Optional — aim this milestone at a day. Leave it off and it simply lives on your list.")
                        .font(.serifItalic(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.alertGreen)

            if hasTargetDate {
                DatePicker(
                    "Lands by",
                    selection: $targetDate,
                    displayedComponents: .date
                )
                .font(.sans(14, weight: .regular))
                .tint(Theme.sunShadow)
                Text("A single gentle nudge arrives that morning, if the milestone isn't done yet.")
                    .font(.serifItalic(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
        }
    }

    private var rewardCard: some View {
        card {
            EyebrowText(text: "Reward", opacity: 0.5)
            Stepper(value: $pointValue, in: 5...500, step: 5) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(pointValue)")
                        .font(.serif(20, weight: .medium))
                        .foregroundStyle(Theme.alertGreen)
                    Text("pts")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            Text("A deliberately large, one-time reward — it can push that day well past your daily target.")
                .font(.serifItalic(11, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }

    private var stepPointsCard: some View {
        card {
            Toggle(isOn: $pointsPerStep) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Points per step")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(
                        pointsPerStep
                            ? "Each step carries its own value, credited the day you check it — the remainder lands at completion."
                            : "Steps track progress only — the full reward lands when the milestone completes."
                    )
                    .font(.serifItalic(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.alertGreen)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let chosenDate: Date? = hasTargetDate ? targetDate : nil
        if let editing {
            var updated = editing
            updated.title = title
            updated.targetDate = chosenDate
            updated.pointValue = pointValue
            updated.pointsPerStep = pointsPerStep
            store.updateMilestone(updated)
        } else {
            store.addMilestone(
                title: title,
                targetDate: chosenDate,
                pointValue: pointValue,
                pointsPerStep: pointsPerStep
            )
        }
        dismiss()
    }
}

// MARK: - Step editor

/// Small sheet for editing one step's title and (when the milestone
/// pays per step) its point value. Presented from the detail page.
struct MilestoneStepEditorSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let milestoneId: UUID
    let step: MilestoneStep

    @State private var title: String
    @State private var pointValue: Int

    init(milestoneId: UUID, step: MilestoneStep) {
        self.milestoneId = milestoneId
        self.step = step
        _title = State(initialValue: step.title)
        _pointValue = State(initialValue: step.pointValue)
    }

    private var paysPerStep: Bool {
        store.milestone(by: milestoneId)?.pointsPerStep ?? false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        EyebrowText(text: "Step", opacity: 0.5)
                        TextField("Step title", text: $title, axis: .vertical)
                            .font(.serif(17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1...2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))

                    if paysPerStep {
                        VStack(alignment: .leading, spacing: 8) {
                            EyebrowText(text: "Worth on check-off", opacity: 0.5)
                            Stepper(value: $pointValue, in: 0...200) {
                                HStack(alignment: .lastTextBaseline, spacing: 4) {
                                    Text("\(pointValue)")
                                        .font(.serif(18, weight: .medium))
                                        .foregroundStyle(pointValue > 0 ? Theme.alertGreen : Theme.textPrimary.opacity(0.5))
                                    Text("pts")
                                        .font(.sans(11, weight: .regular))
                                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                    }

                    Spacer()
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 14)
            }
            .navigationTitle("Edit step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = step
                        updated.title = title
                        updated.pointValue = pointValue
                        store.updateMilestoneStep(updated, in: milestoneId)
                        dismiss()
                    }
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(canSave ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
                    .disabled(!canSave)
                }
            }
        }
    }
}
