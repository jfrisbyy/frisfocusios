//
//  PinTaskToDaySheet.swift
//  FrisFocus
//
//  "Add a task to this day" — opened from the weekly schedule page's
//  empty-day hint and per-day plus button. Lists every task in the
//  library; tapping one adds that weekday to its recurring schedule
//  (or pins it for today when the chosen day is today and the task
//  was unscheduled). Tasks already on the day show a checkmark and
//  tap to remove the weekday again.
//

import SwiftUI
import UIKit

struct PinTaskToDaySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: Date

    @State private var showNewTaskForm: Bool = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private var weekday: Int {
        Calendar.current.component(.weekday, from: day)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tap a task to pin it to \(Self.dayFormatter.string(from: day))s. Tap again to remove it.")
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))

                    if store.tasks.isEmpty {
                        Text("No tasks in your library yet.")
                            .font(.sans(14))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(store.tasks) { task in
                                taskRow(task)
                            }
                        }
                    }

                    Button {
                        showNewTaskForm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text("New task")
                                .font(.sans(14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.alertGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.alertGreen.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.warmWheat)
            .navigationTitle("Pin to \(Self.dayFormatter.string(from: day))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                }
            }
        }
        .sheet(isPresented: $showNewTaskForm) {
            NewTaskFormView { }
                .environment(store)
        }
    }

    @ViewBuilder
    private func taskRow(_ task: FFTask) -> some View {
        let pinned = task.isPinnedFor(day)
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if pinned {
                store.removeWeekday(weekday, fromTaskId: task.id)
            } else {
                store.addWeekday(weekday, toTaskId: task.id)
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: store.categoryColorHex(task.category)))
                    .frame(width: 7, height: 7)
                Text(task.title)
                    .font(.sans(14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(task.nominalValue)")
                    .font(.serif(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                Image(systemName: pinned ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(pinned ? Theme.alertGreen : Theme.textPrimary.opacity(0.25))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(pinned ? Theme.alertGreen.opacity(0.08) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        pinned ? Theme.alertGreen.opacity(0.25) : Theme.textPrimary.opacity(0.07),
                        lineWidth: 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pinned
            ? "Remove \(task.title) from \(Self.dayFormatter.string(from: day))s"
            : "Pin \(task.title) to \(Self.dayFormatter.string(from: day))s")
    }
}
