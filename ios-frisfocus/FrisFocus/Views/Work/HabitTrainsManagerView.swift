//
//  HabitTrainsManagerView.swift
//  FrisFocus
//
//  "Habit trains" — the manager surface listing every train the user
//  has built. Each card shows name, step count, today's progress chip,
//  and the total potential payoff (task points + bonus). Tap to run,
//  long-press / menu to edit or delete. The "+ New train" action opens
//  the builder sheet.
//

import SwiftUI
import UIKit

struct HabitTrainsManagerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showBuilder: Bool = false
    @State private var editing: HabitTrain? = nil
    @State private var running: HabitTrain? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if store.habitTrains.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.habitTrains) { train in
                                HabitTrainCard(
                                    train: train,
                                    onRun: { running = train },
                                    onEdit: { editing = train },
                                    onDelete: { store.deleteHabitTrain(train) }
                                )
                            }
                        }
                    }

                    addButton

                    framingFooter

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .background(Theme.warmWheat)
            .navigationTitle("Habit trains")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .sheet(isPresented: $showBuilder) {
                HabitTrainBuilderView(editing: nil)
            }
            .sheet(item: $editing) { train in
                HabitTrainBuilderView(editing: train)
            }
            .sheet(item: $running) { train in
                HabitTrainRunView(train: train)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Routines that stack")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Chain tasks and cues into a routine. Finish every task-step in a day and the train pays a small bonus on top — once per day, never a streak.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No trains yet")
                .font(.serif(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
            Text("Build your first routine below — e.g. pray, lift, journal.")
                .font(.sans(12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showBuilder = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                Text("New train")
                    .font(.sans(13, weight: .regular))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var framingFooter: some View {
        Text("Miss a step or a day and nothing resets. The train rewards finishing the routine, not perfect attendance.")
            .font(.serifItalic(12))
            .foregroundStyle(Theme.textPrimary.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Card

private struct HabitTrainCard: View {
    @Environment(Store.self) private var store
    let train: HabitTrain
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(train.name)
                        .font(.serif(17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let desc = train.trainDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.serifItalic(12))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        ForEach(stepDots, id: \.self) { color in
                            Circle().fill(color).frame(width: 5, height: 5)
                        }
                        Text(stepSummary)
                            .font(.sans(11, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 8)

                Menu {
                    Button("Run", systemImage: "play.fill") { onRun() }
                    Button("Edit", systemImage: "pencil") { onEdit() }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }

            HStack(spacing: 8) {
                HabitTrainProgressChip(
                    done: status.done,
                    total: status.totalTaskSteps,
                    earned: status.complete
                )

                if train.bonusPoints > 0 {
                    Text("+\(train.bonusPoints) bonus")
                        .font(.serifItalic(12))
                        .foregroundStyle(Theme.alertAmber)
                }

                Spacer()

                Text("\(store.trainTotalPoints(train)) pts total")
                    .font(.sans(11, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            if expanded {
                Divider().overlay(Theme.textPrimary.opacity(0.08))
                stepPreview
            }

            HStack(spacing: 8) {
                Button(action: onRun) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 11, weight: .semibold))
                        Text("Run").font(.sans(12, weight: .medium))
                    }
                    .foregroundStyle(Theme.warmWheat)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.textPrimary))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .regular))
                        Text(expanded ? "Hide steps" : "Show steps")
                            .font(.sans(12, weight: .regular))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().strokeBorder(Theme.textPrimary.opacity(0.22), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var status: (done: Int, totalTaskSteps: Int, complete: Bool, awarded: Bool) {
        store.trainStatus(train)
    }

    private var stepDots: [Color] {
        store.orderedSteps(of: train).prefix(6).map { step in
            if step.type == .note { return Theme.textPrimary.opacity(0.3) }
            if let task = store.task(forStep: step) {
                return task.category.color
            }
            return Theme.textPrimary.opacity(0.2)
        }
    }

    private var stepSummary: String {
        let total = train.steps.count
        let tasks = train.steps.filter { $0.type == .task }.count
        let notes = total - tasks
        var parts: [String] = []
        if tasks > 0 { parts.append("\(tasks) task\(tasks == 1 ? "" : "s")") }
        if notes > 0 { parts.append("\(notes) note\(notes == 1 ? "" : "s")") }
        if parts.isEmpty { return "no steps yet" }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var stepPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(store.orderedSteps(of: train).enumerated()), id: \.element.id) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1).")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .frame(width: 18, alignment: .leading)

                    if step.type == .task, let task = store.task(forStep: step) {
                        Circle().fill(task.category.color).frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(task.title)
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        Spacer(minLength: 4)
                        Text("\(task.pointValue)")
                            .font(.serif(13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    } else if step.type == .note {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                            .padding(.top, 3)
                        Text(step.noteText ?? "")
                            .font(.serifItalic(12))
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        Spacer(minLength: 4)
                    } else {
                        Text("(missing task)")
                            .font(.sans(12))
                            .foregroundStyle(Theme.alertAmber)
                    }
                }
            }
        }
    }
}

#Preview {
    HabitTrainsManagerView()
        .environment(Store())
}
