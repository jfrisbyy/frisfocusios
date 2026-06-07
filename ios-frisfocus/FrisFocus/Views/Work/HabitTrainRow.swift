//
//  HabitTrainRow.swift
//  FrisFocus
//
//  Compact, collapsible row that represents a habit train on Today's
//  Plan. Feels like a task card by default — tap to expand into an
//  inline step list, tap "Run" to open the focused run view. Done
//  state tracks the train's daily completion (every task-step
//  complete = warm gold checkmark + earned chip).
//

import SwiftUI
import UIKit

struct HabitTrainRow: View {
    @Environment(Store.self) private var store
    let train: HabitTrain

    @State private var expanded: Bool = false
    @State private var showRun: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if expanded {
                Divider().overlay(Theme.textPrimary.opacity(0.08))
                inlineSteps
                runButton
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    status.complete
                        ? Theme.alertAmber.opacity(0.35)
                        : Theme.textPrimary.opacity(0.08),
                    lineWidth: status.complete ? 0.8 : 0.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
        }
        .sheet(isPresented: $showRun) {
            HabitTrainRunView(train: train)
        }
        .animation(.easeInOut(duration: 0.2), value: status.complete)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            statusGlyph

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    Text(train.name)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(status.complete ? 0.55 : 1.0))
                        .strikethrough(status.complete, color: Theme.textPrimary.opacity(0.5))
                }

                HStack(spacing: 6) {
                    Text(metadataString)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }

                HStack(spacing: 6) {
                    HabitTrainProgressChip(
                        done: status.done,
                        total: status.totalTaskSteps,
                        earned: status.complete
                    )
                    if train.bonusPoints > 0 {
                        Text("+\(train.bonusPoints) bonus")
                            .font(.serifItalic(11))
                            .foregroundStyle(Theme.alertAmber)
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 6)

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        ZStack {
            Circle()
                .stroke(
                    status.complete
                        ? Theme.alertAmber
                        : Theme.textPrimary.opacity(0.35),
                    lineWidth: 1.5
                )
                .frame(width: 22, height: 22)
            if status.complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.alertAmber)
            } else if status.done > 0, status.totalTaskSteps > 0 {
                Circle()
                    .fill(Theme.textPrimary.opacity(0.22))
                    .frame(width: 10, height: 10)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 1)
    }

    // MARK: - Body

    @ViewBuilder
    private var inlineSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(store.orderedSteps(of: train).enumerated()), id: \.element.id) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1).")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .frame(width: 18, alignment: .leading)

                    if step.type == .task, let task = store.task(forStep: step) {
                        Image(systemName: store.hasLogEntryToday(forTaskId: task.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                store.hasLogEntryToday(forTaskId: task.id)
                                    ? Theme.alertGreen
                                    : Theme.textPrimary.opacity(0.35)
                            )
                            .padding(.top, 1)
                        Text(task.title)
                            .font(.sans(12, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(
                                store.hasLogEntryToday(forTaskId: task.id) ? 0.5 : 0.9
                            ))
                            .strikethrough(store.hasLogEntryToday(forTaskId: task.id),
                                           color: Theme.textPrimary.opacity(0.5))
                        Spacer(minLength: 4)
                        Text("\(task.pointValue)")
                            .font(.serif(13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    } else if step.type == .note {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                            .padding(.top, 3)
                        Text(step.noteText ?? "")
                            .font(.serifItalic(12))
                            .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        Spacer(minLength: 4)
                    }
                }
            }
        }
    }

    private var runButton: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showRun = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .semibold))
                    Text("Run")
                        .font(.sans(12, weight: .medium))
                }
                .foregroundStyle(Theme.warmWheat)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.textPrimary))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var status: (done: Int, totalTaskSteps: Int, complete: Bool, awarded: Bool) {
        store.trainStatus(train)
    }

    private var metadataString: String {
        let total = train.steps.count
        let tasks = train.steps.filter { $0.type == .task }.count
        let notes = total - tasks
        var parts: [String] = ["Routine"]
        if tasks > 0 { parts.append("\(tasks) task\(tasks == 1 ? "" : "s")") }
        if notes > 0 { parts.append("\(notes) note\(notes == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
