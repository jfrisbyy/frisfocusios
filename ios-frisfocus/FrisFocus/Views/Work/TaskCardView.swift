//
//  TaskCardView.swift
//  FrisFocus
//
//  A Today's Few task card. Repeatable task with a circle checkbox,
//  a category dot, an optional pin icon next to the title, and the
//  point value on the right. Higher-value tasks get a quiet emphasis
//  (replacing the retired MUST/SHOULD/COULD tier pill).
//
//  Flat tasks toggle a completion directly. Tiered / quantity tasks open
//  an amount sheet so the engine can score the logged amount. The
//  completed state is derived live from the Store so the checkbox always
//  reflects the persisted truth.
//

import SwiftUI
import UIKit

struct TaskCardView: View {
    @Environment(Store.self) private var store
    let task: FFTask

    @State private var showEdit: Bool = false
    @State private var showShareCapture: Bool = false
    @State private var showLogAmount: Bool = false

    /// Today's completed entry for this task, if any. Carries the actual
    /// points earned (which, for tiered / quantity tasks, depends on the
    /// logged amount).
    private var todayEntry: LogEntry? {
        let cal = Calendar.current
        return store.logEntries.first {
            $0.taskId == task.id
                && $0.entryType == .completed
                && cal.isDate($0.date, inSameDayAs: Date())
        }
    }

    private var isCompleted: Bool { todayEntry != nil }

    /// Whether this task is worth at least the reminder threshold — drives
    /// the quiet high-value emphasis on the checkbox.
    private var isHighValue: Bool {
        task.nominalValue >= store.reminderValueThreshold
    }

    /// The number shown on the right: the actual points earned once
    /// logged, otherwise the task's representative value.
    private var displayValue: Int {
        todayEntry?.pointsEarned ?? task.nominalValue
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
                        .fill(Color(hex: store.categoryColorHex(task.category)))
                        .frame(width: 5, height: 5)

                    Text(metadataString)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
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

            // Point value — actual earned once logged, representative
            // value otherwise. A small "+" hint marks amount-logged tasks.
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(displayValue)")
                    .font(.serif(22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(isCompleted ? 0.4 : 1.0))
                if task.requiresQuantityLogging, !isCompleted {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
            }
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
        .sheet(isPresented: $showLogAmount) {
            LogQuantitySheet(task: task)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                        Theme.textPrimary.opacity(isHighValue ? 0.5 : 0.3),
                        lineWidth: 1.5
                    )
                    .frame(width: 22, height: 22)

                if isHighValue {
                    Circle()
                        .fill(Color(hex: store.categoryColorHex(task.category)).opacity(0.2))
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
        var parts = [store.categoryDisplayName(task.category)]
        switch task.scoring.type {
        case .flat:
            parts.append("Task")
        case .tiered:
            parts.append(task.scoring.unit.isEmpty ? "Tiered" : "Tiered · \(task.scoring.unit)")
        case .quantity:
            parts.append(task.scoring.unit.isEmpty ? "Quantity" : "Per \(task.scoring.unit)")
        }
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
        } else if task.requiresQuantityLogging {
            // Tiered / quantity tasks need an amount before they can score.
            showLogAmount = true
        } else {
            store.completeTask(task)
        }
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
