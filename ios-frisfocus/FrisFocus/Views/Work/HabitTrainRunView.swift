//
//  HabitTrainRunView.swift
//  FrisFocus
//
//  Focused run view for a habit train. Steps list vertically with the
//  current step softly highlighted. Task steps complete the underlying
//  FFTask via the store (single source of truth); note steps are
//  read-only. Auto-advances past done steps. The bonus card at the
//  bottom warms to gold when every task-step is complete for today.
//

import SwiftUI
import UIKit

struct HabitTrainRunView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let train: HabitTrain

    @State private var currentIndex: Int = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        progressBar

                        VStack(spacing: 10) {
                            ForEach(Array(orderedSteps.enumerated()), id: \.element.id) { i, step in
                                stepCard(index: i, step: step)
                                    .id(step.id)
                            }
                        }

                        bonusCard

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                }
                .background(Theme.warmWheat)
                .onAppear { advanceToFirstOpen(proxy: proxy) }
                .onChange(of: currentIndex) { _, _ in
                    if let id = orderedSteps[safe: currentIndex]?.id {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(train.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let desc = train.trainDescription, !desc.isEmpty {
                Text(desc)
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
            }
            HStack(spacing: 8) {
                Text(stepCounterText)
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))

                HabitTrainProgressChip(
                    done: status.done,
                    total: status.totalTaskSteps,
                    earned: status.complete
                )
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textPrimary.opacity(0.08))
                Capsule()
                    .fill(status.complete ? Theme.alertAmber : Theme.textPrimary.opacity(0.55))
                    .frame(width: max(0, geo.size.width * progressFraction))
                    .animation(.easeInOut(duration: 0.3), value: progressFraction)
            }
        }
        .frame(height: 4)
    }

    private var progressFraction: CGFloat {
        guard status.totalTaskSteps > 0 else { return 0 }
        return CGFloat(status.done) / CGFloat(status.totalTaskSteps)
    }

    private var stepCounterText: String {
        guard !orderedSteps.isEmpty else { return "no steps" }
        let n = min(currentIndex + 1, orderedSteps.count)
        return "step \(n) of \(orderedSteps.count)"
    }

    // MARK: - Step card

    @ViewBuilder
    private func stepCard(index: Int, step: HabitTrainStep) -> some View {
        let isCurrent = index == currentIndex
        let isTaskDone: Bool = {
            guard step.type == .task,
                  let task = store.task(forStep: step) else { return false }
            return store.hasLogEntryToday(forTaskId: task.id)
        }()

        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(isCurrent ? 0.95 : 0.4))
                .frame(width: 24, alignment: .leading)

            if step.type == .task, let task = store.task(forStep: step) {
                taskStepBody(task: task, isDone: isTaskDone, isCurrent: isCurrent)
            } else if step.type == .note {
                noteStepBody(text: step.noteText ?? "", isCurrent: isCurrent)
            } else {
                Text("Missing task")
                    .font(.sans(13))
                    .foregroundStyle(Theme.alertAmber)
            }
        }
        .padding(14)
        .background(Color.white.opacity(isTaskDone ? 0.7 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isCurrent
                        ? Theme.textPrimary.opacity(0.45)
                        : Theme.textPrimary.opacity(0.08),
                    lineWidth: isCurrent ? 1.2 : 0.5
                )
        )
        .shadow(
            color: isCurrent ? Theme.textPrimary.opacity(0.08) : .clear,
            radius: isCurrent ? 8 : 0,
            y: 3
        )
        .opacity(isTaskDone ? 0.78 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isCurrent)
        .animation(.easeInOut(duration: 0.2), value: isTaskDone)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isCurrent {
                currentIndex = index
            }
        }
    }

    @ViewBuilder
    private func taskStepBody(task: FFTask, isDone: Bool, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: { toggleTask(task) }) {
                ZStack {
                    if isDone {
                        Circle().fill(Theme.alertGreen).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.warmWheat)
                    } else {
                        Circle()
                            .stroke(Theme.textPrimary.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(isDone ? 0.5 : 1.0))
                    .strikethrough(isDone, color: Theme.textPrimary.opacity(0.6))
                HStack(spacing: 6) {
                    Circle().fill(task.category.color).frame(width: 5, height: 5)
                    Text("\(store.categoryDisplayName(task.category)) · \(task.pointValue) pts")
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func noteStepBody(text: String, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
                .frame(width: 24, height: 24)

            Text(text)
                .font(.serifItalic(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bonus card

    @ViewBuilder
    private var bonusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: status.complete ? "sun.max.fill" : "sun.max")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(status.complete ? Theme.alertAmber : Theme.textPrimary.opacity(0.4))

            VStack(alignment: .leading, spacing: 2) {
                Text(status.complete ? "Routine complete" : "Routine bonus")
                    .font(.serif(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(bonusSubtitle)
                    .font(.serifItalic(12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if train.bonusPoints > 0 {
                Text("+\(train.bonusPoints)")
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(status.complete ? Theme.alertAmber : Theme.textPrimary.opacity(0.55))
            }
        }
        .padding(16)
        .background(
            status.complete
                ? Theme.sunWarm.opacity(0.4)
                : Color.white
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    status.complete
                        ? Theme.alertAmber.opacity(0.55)
                        : Theme.textPrimary.opacity(0.08),
                    lineWidth: status.complete ? 0.8 : 0.5
                )
        )
        .animation(.easeInOut(duration: 0.3), value: status.complete)
    }

    private var bonusSubtitle: String {
        if status.totalTaskSteps == 0 {
            return "Add a task step to earn the bonus."
        }
        if status.complete {
            return "Bonus folded into today's score."
        }
        let left = status.totalTaskSteps - status.done
        return "\(left) task-step\(left == 1 ? "" : "s") left to land the bonus."
    }

    // MARK: - Actions

    private func toggleTask(_ task: FFTask) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if store.hasLogEntryToday(forTaskId: task.id) {
            store.uncompleteTask(task)
        } else {
            store.completeTask(task)
            // Auto-advance past this step.
            advanceCurrent()
        }
    }

    private func advanceCurrent() {
        guard currentIndex + 1 < orderedSteps.count else { return }
        currentIndex += 1
        // Skip already-done task steps so the highlight lands on the
        // next undone slot.
        while currentIndex < orderedSteps.count - 1 {
            let step = orderedSteps[currentIndex]
            if step.type == .task,
               let t = store.task(forStep: step),
               store.hasLogEntryToday(forTaskId: t.id) {
                currentIndex += 1
            } else {
                break
            }
        }
    }

    private func advanceToFirstOpen(proxy: ScrollViewProxy) {
        for (i, step) in orderedSteps.enumerated() {
            if step.type == .task,
               let t = store.task(forStep: step),
               !store.hasLogEntryToday(forTaskId: t.id) {
                currentIndex = i
                proxy.scrollTo(step.id, anchor: .center)
                return
            }
        }
        currentIndex = max(0, orderedSteps.count - 1)
    }

    // MARK: - Helpers

    private var orderedSteps: [HabitTrainStep] {
        store.orderedSteps(of: liveTrain)
    }

    /// Re-fetch the train from the store so updates while the run view
    /// is open (rare, but possible if user edits in another sheet)
    /// don't render stale state.
    private var liveTrain: HabitTrain {
        store.habitTrains.first(where: { $0.id == train.id }) ?? train
    }

    private var status: (done: Int, totalTaskSteps: Int, complete: Bool, awarded: Bool) {
        store.trainStatus(liveTrain)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
