//
//  TaskCardView.swift
//  FrisFocus
//
//  A Today's Few task card. Repeatable task with a circle checkbox,
//  a category dot, an optional MUST/SHOULD tier pill, an optional pin
//  icon next to the title, and a raw point value on the right (no `+`).
//
//  Tapping the checkbox writes a `LogEntry` to the Store (or removes
//  it, on a second tap). Light haptic on every toggle. The completed
//  state is derived live from `store.hasLogEntryToday(forTaskId:)` so
//  the checkbox always reflects the persisted truth.
//

import SwiftUI
import UIKit

struct TaskCardView: View {
    @Environment(Store.self) private var store
    let task: FFTask

    @State private var showEdit: Bool = false
    @State private var showShareCapture: Bool = false

    private var isCompleted: Bool {
        store.hasLogEntryToday(forTaskId: task.id)
    }

    private var boosterStatus: (progress: Int, required: Int, earned: Bool, period: BoosterPeriod, bonusPoints: Int)? {
        store.boosterStatus(for: task)
    }

    private var penaltyStatus: (count: Int, threshold: Int, condition: PenaltyCondition, penaltyPoints: Int, breached: Bool)? {
        store.penaltyStatus(for: task)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Circle checkbox (entire row is tappable below)
            checkbox

            // Title + metadata
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if task.isPinnedToday {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .regular))
                            .rotationEffect(.degrees(45))
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    }
                    Text(task.title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(isCompleted ? 0.5 : 1.0))
                        .strikethrough(isCompleted, color: Theme.textPrimary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(task.category.color)
                        .frame(width: 5, height: 5)

                    Text(metadataString)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))

                    TierPill(tier: task.tier)
                }

                if boosterStatus != nil || penaltyStatus != nil {
                    HStack(spacing: 6) {
                        if let status = boosterStatus {
                            BoosterProgressChip(
                                progress: status.progress,
                                required: status.required,
                                earned: status.earned,
                                period: status.period,
                                category: task.category
                            )
                        }
                        if let p = penaltyStatus {
                            PenaltyLimitTag(
                                count: p.count,
                                threshold: p.threshold,
                                condition: p.condition,
                                penaltyPoints: p.penaltyPoints,
                                breached: p.breached
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            // Point value
            Text("\(task.pointValue)")
                .font(.serif(22, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(isCompleted ? 0.4 : 1.0))
                .padding(.top, 2)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: isCompleted)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isCompleted ? "Mark \(task.title) incomplete" : "Complete \(task.title)")
        .onTapGesture {
            toggle()
        }
        .contextMenu {
            Button {
                showShareCapture = true
            } label: {
                Label("Share a photo/video", systemImage: "camera")
            }
            Button {
                showEdit = true
            } label: {
                Label("Edit task", systemImage: "pencil")
            }
        }
        .sheet(isPresented: $showEdit) {
            NewTaskFormView(editing: task) { }
        }
        .fullScreenCover(isPresented: $showShareCapture) {
            CaptureView(
                mode: .generalPost,
                initialTaskSticker: TaskStickerBlock(task: task, isChecked: isCompleted)
            )
            .environment(store)
        }
    }

    // MARK: - Checkbox

    @ViewBuilder
    private var checkbox: some View {
        ZStack {
            if isCompleted {
                Circle()
                    .fill(Theme.alertGreen)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.warmWheat)
            } else {
                Circle()
                    .stroke(
                        task.tier == .must
                            ? Theme.alertRed
                            : Theme.textPrimary.opacity(0.35),
                        lineWidth: 1.5
                    )
                    .frame(width: 22, height: 22)

                if task.tier == .must {
                    Circle()
                        .fill(Theme.alertRed.opacity(0.18))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 1)
        .contentShape(Rectangle())
    }

    // MARK: - Metadata

    private var metadataString: String {
        var parts = [task.category.displayName, "Task"]
        if let minutes = task.estimatedMinutes {
            parts.append("\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Action

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if isCompleted {
            store.uncompleteTask(task)
        } else {
            store.completeTask(task)
        }
    }
}

// MARK: - Tier pill

private struct TierPill: View {
    let tier: Tier

    var body: some View {
        Text(tier.label)
            .font(.sans(9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(tier.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tier.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

#Preview {
    let store = Store()
    VStack(spacing: 8) {
        ForEach(store.tasks.filter { $0.isPinnedToday }) { task in
            TaskCardView(task: task)
        }
    }
    .padding()
    .background(Theme.warmWheat)
    .environment(store)
}
