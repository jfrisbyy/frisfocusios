//
//  TaskScheduleSheet.swift
//  FrisFocus
//
//  Compact scheduling sheet — opened from a task card's hold menu
//  ("Pin to days…") and from tapping a task on the weekly schedule
//  page. Edits only the schedule (mode, weekday chips, time window)
//  with an "Open full editor" escape hatch for everything else.
//

import SwiftUI
import UIKit

struct TaskScheduleSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let taskId: UUID

    @State private var draft: ScheduleDraft
    @State private var showFullEditor: Bool = false

    /// Live task from the Store — survives edits made in the full editor.
    private var task: FFTask? {
        store.tasks.first { $0.id == taskId }
    }

    init(task: FFTask) {
        self.taskId = task.id
        _draft = State(initialValue: ScheduleDraft(task: task))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let task {
                        // Task identity row
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: store.categoryColorHex(task.category)))
                                .frame(width: 8, height: 8)
                            Text(task.title)
                                .font(.serif(18, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Text("\(task.nominalValue)")
                                .font(.serif(18, weight: .medium))
                                .foregroundStyle(Theme.textPrimary.opacity(0.65))
                        }
                    }

                    EyebrowText(text: "Schedule", opacity: 0.55)

                    ScheduleEditorView(draft: $draft)
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
                        )

                    Button(action: save) {
                        Text("Save schedule")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.warmWheat)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.textPrimary)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFullEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .medium))
                            Text("Open full editor")
                                .font(.sans(13, weight: .medium))
                        }
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("Pin to days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.sans(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                }
            }
        }
        .sheet(isPresented: $showFullEditor) {
            if let task {
                NewTaskFormView(editing: task) {
                    // Re-seed the draft from the freshly saved task so the
                    // compact sheet doesn't overwrite editor changes.
                    if let updated = store.tasks.first(where: { $0.id == taskId }) {
                        draft = ScheduleDraft(task: updated)
                    }
                }
                .environment(store)
            }
        }
    }

    private func save() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.setSchedule(
            draft.resolvedSchedule,
            timeWindow: draft.resolvedTimeWindow,
            forTaskId: taskId
        )
        dismiss()
    }
}
