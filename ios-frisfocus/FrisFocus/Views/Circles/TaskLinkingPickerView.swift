//
//  TaskLinkingPickerView.swift
//  FrisFocus
//
//  The bottom-sheet picker that bridges a circle task to one of the
//  user's personal `FFTask`s. Reached from the "circle only · tap to
//  link" affordance on a parallel circle's "The work" row. Once a
//  link is written, completing either side of the bridge completes
//  the other (each awarding its own points), via the cross-task
//  bridge wired in the Store.
//
//  The sheet reads the circle + circle-task by id so it stays
//  reactive to Store mutations while it's open — selecting a link,
//  unlinking, or having another sheet change something underneath
//  all reflect immediately. A personal task already linked to a
//  DIFFERENT circle task is shown as disabled with a soft caption
//  naming where it's currently bridged.
//

import SwiftUI
import UIKit

struct TaskLinkingPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let circleId: UUID
    let circleTaskId: UUID

    @State private var selectedTaskId: UUID?

    // MARK: - Resolved live state

    private var circle: FFCircle? {
        store.circles.first { $0.id == circleId }
    }

    private var circleTask: CircleTask? {
        circle?.tasks.first { $0.id == circleTaskId }
    }

    private var currentlyLinkedId: UUID? {
        circleTask?.linkedPersonalTaskId
    }

    private var personalTasks: [FFTask] { store.tasks }

    private var selectedPersonalTask: FFTask? {
        guard let id = selectedTaskId else { return nil }
        return store.personalTask(by: id)
    }

    /// `(circleName, circleTaskTitle)` if the personal task is linked
    /// to a DIFFERENT circle task than the one we're editing. nil
    /// means it's either unlinked or linked to this same task.
    private func linkedElsewhere(_ task: FFTask)
        -> (circleName: String, taskTitle: String)?
    {
        guard let info = store.circleTaskLinked(toPersonalTaskId: task.id) else {
            return nil
        }
        guard info.circleTaskId != circleTaskId else { return nil }
        return (info.circleName, info.taskTitle)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if personalTasks.isEmpty {
                        emptyState
                    } else {
                        taskList
                        independenceNote
                    }
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }

            actionsBar
        }
        .background(Theme.warmWheat)
        .onAppear {
            // Pre-select the currently-linked task so the affordance
            // reads as "the link is here" rather than "pick one again."
            selectedTaskId = currentlyLinkedId
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LINK A CIRCLE TASK")
                .font(.sans(10, weight: .medium))
                .tracking(2.4)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))

            Text(circleTask?.title ?? "Circle task")
                .font(.serif(24, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            Text("Connect this to a task on your own board. Completing one will check off the other — no double-logging.")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Task list

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR TASKS")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .padding(.bottom, 2)

            ForEach(personalTasks) { task in
                row(for: task)
            }
        }
    }

    @ViewBuilder
    private func row(for task: FFTask) -> some View {
        let elsewhere = linkedElsewhere(task)
        let isDisabled = elsewhere != nil
        let isSelected = selectedTaskId == task.id
        let accent = Color(hex: task.category.hexColor)

        Button {
            guard !isDisabled else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                selectedTaskId = nil
            } else {
                selectedTaskId = task.id
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.sans(15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)

                    Text(metadataText(for: task))
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))

                    if let elsewhere {
                        HStack(spacing: 5) {
                            Image(systemName: "link")
                                .font(.sans(10, weight: .semibold))
                            Text("already linked to \(elsewhere.taskTitle) · \(elsewhere.circleName)")
                                .font(.sans(11, weight: .regular))
                                .lineLimit(2)
                        }
                        .foregroundStyle(Theme.alertAmber.opacity(0.85))
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                radio(isSelected: isSelected, accent: accent, disabled: isDisabled)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isDisabled ? 0.3 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent : Theme.textPrimary.opacity(0.08),
                        lineWidth: isSelected ? 1.4 : 0.5
                    )
            )
            .opacity(isDisabled ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(task.title)
        .accessibilityHint(isDisabled ? "Already linked to another circle task" : "Select to link")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func metadataText(for task: FFTask) -> String {
        "\(task.category.displayName) · \(task.pointValue) pts"
    }

    private func radio(isSelected: Bool, accent: Color, disabled: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? accent : Theme.textPrimary.opacity(0.3),
                    lineWidth: 1.4
                )
                .background(
                    Circle().fill(isSelected ? accent : Color.clear)
                )
                .frame(width: 22, height: 22)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.sans(10, weight: .bold))
                    .foregroundStyle(Theme.textCream)
            }
        }
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Independence note

    @ViewBuilder
    private var independenceNote: some View {
        if let task = selectedPersonalTask {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "scale.3d")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Points stay independent")
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("This earns \(task.pointValue) pts on your board; the circle just tracks completion.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.alertGreen.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.alertGreen.opacity(0.2), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You don\u{2019}t have any tasks to link yet")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text("Add a task to your personal board first, then come back here to bridge it to this circle task.")
                .font(.serifItalic(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Actions bar

    private var actionsBar: some View {
        let isLinked = currentlyLinkedId != nil
        let leftLabel = isLinked ? "Unlink" : "Keep separate"
        let canLink = selectedTaskId != nil && selectedTaskId != currentlyLinkedId
        let primaryLabel = isLinked && selectedTaskId == nil
            ? "Unlink"
            : "Link tasks"

        return HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if isLinked {
                    store.unlinkCircleTask(circleId: circleId, circleTaskId: circleTaskId)
                }
                dismiss()
            } label: {
                Text(leftLabel)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.textPrimary.opacity(0.06))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(leftLabel)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let id = selectedTaskId {
                    store.linkCircleTask(
                        circleId: circleId,
                        circleTaskId: circleTaskId,
                        personalTaskId: id
                    )
                } else if isLinked {
                    // Selected nothing while editing an existing link
                    // → treat the primary button as an explicit unlink.
                    store.unlinkCircleTask(circleId: circleId, circleTaskId: circleTaskId)
                }
                dismiss()
            } label: {
                Text(primaryLabel)
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(primaryEnabled(canLink: canLink, isLinked: isLinked)
                                  ? Theme.textPrimary
                                  : Theme.textPrimary.opacity(0.25))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled(canLink: canLink, isLinked: isLinked))
            .accessibilityLabel(primaryLabel)
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            Theme.warmWheat
                .overlay(
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.08))
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }

    private func primaryEnabled(canLink: Bool, isLinked: Bool) -> Bool {
        if personalTasks.isEmpty { return false }
        if canLink { return true }
        // Allow the primary to unlink when editing a link and the
        // user has deselected the current pick.
        if isLinked && selectedTaskId == nil { return true }
        return false
    }
}

#Preview {
    let store = Store()
    let circle = store.circles.first { $0.type == .parallel }!
    let task = circle.tasks.first!
    return Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TaskLinkingPickerView(circleId: circle.id, circleTaskId: task.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .environment(store)
        }
}
