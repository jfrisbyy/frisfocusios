//
//  TaskStickerPickerView.swift
//  FrisFocus
//
//  A dark, searchable picker presented from the capture editor's
//  "Add task" tool. Lists every repeatable Task and every active
//  (not-yet-done) To-do, grouped and filterable by title. Choosing one
//  hands a ready-made `TaskStickerBlock` back to the editor, which drops
//  it onto the canvas. Attaching never mutates the underlying item.
//

import SwiftUI
import UIKit

struct TaskStickerPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onPick: (TaskStickerBlock) -> Void

    @State private var query: String = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredTasks: [FFTask] {
        guard !trimmedQuery.isEmpty else { return store.tasks }
        return store.tasks.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// Active = not completed. A done one-time to-do has nothing left to
    /// document, so it's left out of the picker.
    private var filteredTodos: [Todo] {
        let active = store.todos.filter { !$0.isCompleted }
        guard !trimmedQuery.isEmpty else { return active }
        return active.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var isEmpty: Bool {
        filteredTasks.isEmpty && filteredTodos.isEmpty
    }

    var body: some View {
        ZStack {
            Color(hex: 0x1A1817).ignoresSafeArea()

            VStack(spacing: 0) {
                grabberHeader
                searchField
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)

                if isEmpty {
                    emptyState
                } else {
                    listBody
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var grabberHeader: some View {
        HStack {
            Text("Add a task")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Color.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            TextField(
                "",
                text: $query,
                prompt: Text("Search tasks & to-dos")
                    .foregroundStyle(Color.white.opacity(0.4))
            )
            .font(.sans(15, weight: .regular))
            .foregroundStyle(Color.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - List

    private var listBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                if !filteredTasks.isEmpty {
                    sectionLabel("TASKS")
                    ForEach(filteredTasks) { task in
                        row(
                            title: task.title,
                            isTask: true,
                            isMust: task.tier == .must,
                            isChecked: store.hasLogEntryToday(forTaskId: task.id),
                            subtitle: task.category.displayName
                        ) {
                            pick(
                                TaskStickerBlock(
                                    task: task,
                                    isChecked: store.hasLogEntryToday(forTaskId: task.id)
                                )
                            )
                        }
                    }
                }

                if !filteredTodos.isEmpty {
                    sectionLabel("TO-DOS")
                    ForEach(filteredTodos) { todo in
                        row(
                            title: todo.title,
                            isTask: false,
                            isMust: false,
                            isChecked: todo.isCompleted,
                            subtitle: todo.dueText
                        ) {
                            pick(TaskStickerBlock(todo: todo))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 28)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.sans(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private func row(
        title: String,
        isTask: Bool,
        isMust: Bool,
        isChecked: Bool,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                checkboxGlyph(isTask: isTask, isMust: isMust, isChecked: isChecked)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.alertGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(title)")
    }

    @ViewBuilder
    private func checkboxGlyph(isTask: Bool, isMust: Bool, isChecked: Bool) -> some View {
        ZStack {
            if isTask {
                Circle()
                    .stroke(
                        isChecked ? Theme.alertGreen : (isMust ? Theme.alertRed : Color.white.opacity(0.4)),
                        lineWidth: 1.5
                    )
                    .frame(width: 22, height: 22)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isChecked ? Theme.alertGreen : Color.white.opacity(0.4),
                        lineWidth: 1.5
                    )
                    .frame(width: 22, height: 22)
            }
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.alertGreen)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: trimmedQuery.isEmpty ? "checklist" : "magnifyingglass")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
            Text(trimmedQuery.isEmpty ? "No tasks or to-dos yet" : "Nothing matches \u{201C}\(trimmedQuery)\u{201D}")
                .font(.serif(16, weight: .regular))
                .italic()
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pick

    private func pick(_ block: TaskStickerBlock) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPick(block)
        dismiss()
    }
}
