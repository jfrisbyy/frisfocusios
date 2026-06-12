//
//  FocusTaskTrayView.swift
//  FrisFocus
//
//  A discreet, expandable task tray for the running focus screen (solo
//  and grove). Collapsed it's a quiet strip showing how many of your
//  attached tasks remain. Tapping expands a calm panel listing each
//  attached task with a checkbox you tick off yourself as you finish —
//  a check marks the task done for the day everywhere in the app.
//
//  In a grove, the expanded panel also lists friends' shared tasks
//  grouped under their name with their live check-off progress. Private
//  tasks never surface to anyone else.
//

import SwiftUI
import UIKit

struct FocusTaskTrayView: View {
    @Environment(Store.self) private var store

    /// My attached tasks for this session (shared + private).
    let attachments: [FocusTaskAttachment]
    /// Friends' shared tasks to show grouped by name. Empty for solo.
    let friendTasks: [GroveSharedTask]
    /// Called after I toggle one of my tasks so the host can re-publish
    /// shared-task state to the grove.
    var onToggle: (() -> Void)? = nil

    @State private var expanded = false

    private var myTasks: [(att: FocusTaskAttachment, task: FFTask)] {
        attachments.compactMap { att in
            guard let task = store.personalTask(by: att.taskId) else { return nil }
            return (att, task)
        }
    }

    private var remainingCount: Int {
        myTasks.filter { !store.hasLogEntryToday(forTaskId: $0.task.id) }.count
    }

    var body: some View {
        if myTasks.isEmpty && friendTasks.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                collapsedBar
                if expanded {
                    expandedPanel
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.textPrimary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Collapsed

    @ViewBuilder
    private var collapsedBar: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text(collapsedLabel)
                    .font(.sans(12, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var collapsedLabel: String {
        if myTasks.isEmpty {
            return "Shared tasks"
        }
        if remainingCount == 0 {
            return "All tasks done"
        }
        return "\(remainingCount) task\(remainingCount == 1 ? "" : "s") left"
    }

    // MARK: - Expanded

    @ViewBuilder
    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.25)
                .padding(.horizontal, 14)

            if !myTasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    panelHeader("YOURS")
                    ForEach(myTasks, id: \.task.id) { pair in
                        myTaskRow(pair.att, pair.task)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, friendGroups.isEmpty ? 14 : 6)
            }

            ForEach(friendGroups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 6) {
                    panelHeader(group.name.uppercased())
                    if group.allDone {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.alertGreen)
                            Text("All done")
                                .font(.serifItalic(14))
                                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(group.tasks) { t in
                        friendTaskRow(t)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func panelHeader(_ text: String) -> some View {
        Text(text)
            .font(.sans(9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Theme.textPrimary.opacity(0.4))
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func myTaskRow(_ att: FocusTaskAttachment, _ task: FFTask) -> some View {
        let done = store.hasLogEntryToday(forTaskId: task.id)
        Button {
            toggle(task, currentlyDone: done)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(done ? Theme.alertGreen : Theme.textPrimary.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))
                Text(task.title)
                    .font(.serif(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(done ? 0.45 : 0.95))
                    .strikethrough(done, color: Theme.textPrimary.opacity(0.35))
                    .lineLimit(1)
                Spacer()
                if att.shared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func friendTaskRow(_ t: GroveSharedTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(t.done ? Theme.alertGreen : Theme.textPrimary.opacity(0.3))
            Text(t.title)
                .font(.serif(14, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(t.done ? 0.4 : 0.8))
                .strikethrough(t.done, color: Theme.textPrimary.opacity(0.3))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 5)
    }

    // MARK: - Friend grouping

    private struct FriendGroup {
        let name: String
        let tasks: [GroveSharedTask]
        var allDone: Bool { !tasks.isEmpty && tasks.allSatisfy(\.done) }
    }

    private var friendGroups: [FriendGroup] {
        let byUser = Dictionary(grouping: friendTasks, by: \.userId)
        return byUser.compactMap { userId, tasks -> FriendGroup? in
            guard userId != store.currentUserId else { return nil }
            let name = store.friends.first(where: { $0.id == userId })?.displayName ?? "Friend"
            return FriendGroup(name: name, tasks: tasks)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Actions

    private func toggle(_ task: FFTask, currentlyDone: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            store.setPersonalTaskCompleted(task.id, completed: !currentlyDone, mirror: true)
        }
        onToggle?()
    }
}
