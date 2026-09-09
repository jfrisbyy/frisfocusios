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
    /// Steps drafted right in the composer — a milestone's shape is its
    /// steps, and having to save first and add them from the detail page
    /// meant most milestones were born shapeless.
    @State private var draftSteps: [DraftStep]
    @State private var newStepTitle: String = ""

    @FocusState private var titleFocused: Bool
    @FocusState private var newStepFocused: Bool

    /// One step being drafted. Carries the original id while editing so
    /// saving can update in place without disturbing checked-off steps.
    struct DraftStep: Identifiable, Equatable {
        let id: UUID
        var title: String
        var points: Int
        let existing: Bool

        init(id: UUID = UUID(), title: String, points: Int = 0, existing: Bool = false) {
            self.id = id
            self.title = title
            self.points = points
            self.existing = existing
        }
    }

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
        _draftSteps = State(initialValue: (editing?.sortedSteps ?? []).map {
            DraftStep(id: $0.id, title: $0.title, points: $0.pointValue, existing: true)
        })
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
                        stepsCard
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

    private var stepsCard: some View {
        card {
            EyebrowText(text: "Steps along the way", opacity: 0.5)

            if draftSteps.isEmpty {
                Text("Break the win into checkable pieces — each one you tick moves the progress bar.")
                    .font(.serifItalic(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach($draftSteps) { $step in
                HStack(spacing: 10) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))

                    TextField("Step", text: $step.title)
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)

                    if pointsPerStep {
                        Stepper(value: $step.points, in: 0...200, step: 5) {
                            Text("\(step.points)")
                                .font(.sans(12.5, weight: .semibold))
                                .foregroundStyle(step.points > 0 ? Theme.alertGreen : Theme.textPrimary.opacity(0.4))
                                .frame(minWidth: 26, alignment: .trailing)
                        }
                        .fixedSize()
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            draftSteps.removeAll { $0.id == step.id }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.35))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                TextField("Add a step…", text: $newStepTitle)
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($newStepFocused)
                    .submitLabel(.next)
                    .onSubmit(commitNewStep)
                if !newStepTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: commitNewStep)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Append the in-progress step draft and keep the keyboard up for
    /// the next one — building a list should feel like typing a list.
    private func commitNewStep() {
        let trimmed = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            draftSteps.append(DraftStep(title: trimmed))
        }
        newStepTitle = ""
        newStepFocused = true
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
        // A title typed into the add row but never submitted still counts —
        // losing it to a missing return-key press would feel like theft.
        commitNewStep()
        let keptSteps = draftSteps.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if let editing {
            var updated = editing
            updated.title = title
            updated.targetDate = chosenDate
            updated.pointValue = pointValue
            updated.pointsPerStep = pointsPerStep
            store.updateMilestone(updated)
            reconcileSteps(keptSteps, against: editing)
        } else {
            let created = store.addMilestone(
                title: title,
                targetDate: chosenDate,
                pointValue: pointValue,
                pointsPerStep: pointsPerStep
            )
            for draft in keptSteps {
                store.addMilestoneStep(to: created.id, title: draft.title, pointValue: draft.points)
            }
        }
        dismiss()
    }

    /// Bring the stored steps in line with the drafts: update the kept,
    /// remove the dropped, append the new — checked-off steps keep their
    /// identity (and any credited points) because ids never change.
    private func reconcileSteps(_ drafts: [DraftStep], against milestone: Milestone) {
        let draftIds = Set(drafts.filter(\.existing).map(\.id))
        for step in milestone.steps where !draftIds.contains(step.id) {
            store.deleteMilestoneStep(step, from: milestone.id)
        }
        for draft in drafts {
            if draft.existing, var step = milestone.steps.first(where: { $0.id == draft.id }) {
                if step.title != draft.title || step.pointValue != draft.points {
                    step.title = draft.title
                    step.pointValue = draft.points
                    store.updateMilestoneStep(step, in: milestone.id)
                }
            } else if !draft.existing {
                store.addMilestoneStep(to: milestone.id, title: draft.title, pointValue: draft.points)
            }
        }
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
