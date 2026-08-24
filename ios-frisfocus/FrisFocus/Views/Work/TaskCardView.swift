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
    /// Glass-on-sky appearance for the inline season detail: cream ink
    /// and translucent fills instead of white paper cards.
    var onSky: Bool = false

    @State private var showEdit: Bool = false
    @State private var showShareCapture: Bool = false
    @State private var showLogAmount: Bool = false
    @State private var showScheduleSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showFocusMode: Bool = false
    /// Confirmation gate while the home is travelled to a past day —
    /// history never changes by accident.
    @State private var showPastEditConfirm: Bool = false

    // Check-off weight: the checkbox compresses, overshoots, and
    // settles; one warm glint blooms out of the completed check.
    @State private var checkScale: CGFloat = 1.0
    @State private var glintScale: CGFloat = 0.4
    @State private var glintOpacity: Double = 0

    /// Today's completed entry for this task, if any. Carries the actual
    /// points earned (which, for tiered / quantity tasks, depends on the
    /// logged amount).
    private var todayEntry: LogEntry? {
        let cal = Calendar.current
        return store.logEntries.first {
            $0.taskId == task.id
                && $0.entryType == .completed
                && cal.isDate($0.date, inSameDayAs: store.displayedDay)
        }
    }

    private var isCompleted: Bool { todayEntry != nil }

    /// Proofs pinned to this task for today — surfaced as round mini
    /// previews beneath the title so the card stays compact when empty.
    private var todayProofPins: [ProofPin] {
        store.proofPins(forTaskId: task.id, on: store.displayedDay)
    }

    /// Primary ink — charcoal on paper, cream on the sky.
    private var ink: Color { onSky ? Theme.textCream : Theme.textPrimary }

    /// A gentle cue for the Season view, which now lists the full library:
    /// tasks that aren't on today's plan (and aren't already done today)
    /// read a touch quieter so the "on today" set stands out. Only in the
    /// on-sky season context — the homepage plan only shows pinned tasks.
    private var isOffToday: Bool {
        onSky && !task.isPinnedToday && !isCompleted
    }

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

    /// Every first-class booster this task feeds — directly or because a
    /// booster watches the task's whole category.
    private var referencingBoosters: [WeeklyBooster] {
        store.boosters(referencing: task)
    }

    private var penaltyStatus: (count: Int, threshold: Int, condition: PenaltyCondition, penaltyPoints: Int, breached: Bool)? {
        store.penaltyStatus(for: task)
    }

    var body: some View {
        Button(action: toggle) {
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
                            .foregroundStyle(ink.opacity(0.45))
                    }
                    Text(task.title)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(ink.opacity(isCompleted ? 0.5 : 1.0))
                        .strikethrough(isCompleted, color: ink.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: store.categoryColorHex(task.category)))
                        .frame(width: 5, height: 5)

                    Text(metadataString)
                        .font(.sans(11, weight: .regular))
                        .foregroundStyle(ink.opacity(0.6))

                    if let window = task.timeWindow {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 8, weight: .regular))
                            Text(window.displayText)
                                .font(.sans(10, weight: .medium))
                        }
                        .foregroundStyle(ink.opacity(0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(ink.opacity(onSky ? 0.12 : 0.06))
                        )
                    }
                }

                TaskProofPreviewRow(pins: todayProofPins, ink: ink)

                if !referencingBoosters.isEmpty || penaltyStatus != nil {
                    HStack(spacing: 6) {
                        ForEach(referencingBoosters) { booster in
                            let status = store.boosterStatus(for: booster)
                            BoosterProgressChip(
                                progress: status.progress,
                                required: status.required,
                                earned: status.earned,
                                period: status.period,
                                category: boosterCategory(booster)
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
                    .foregroundStyle(ink.opacity(isCompleted ? 0.4 : 1.0))
                if task.requiresQuantityLogging, !isCompleted {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(ink.opacity(0.4))
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(onSky ? Color.white.opacity(0.10) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    onSky ? Color.white.opacity(0.16) : Theme.textPrimary.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .opacity(isOffToday ? 0.62 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCompleted)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCompleted ? "Mark \(task.title) incomplete" : "Complete \(task.title)")
        .onChange(of: isCompleted) { _, done in
            if done { runCheckSettle() }
        }
        .contextMenu {
            Button {
                showShareCapture = true
            } label: {
                Label("Proof", systemImage: "camera")
            }

            // Complete / Log amount / Mark incomplete
            if isCompleted {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.uncompleteTask(task)
                } label: {
                    Label("Mark incomplete", systemImage: "arrow.uturn.backward.circle")
                }
            } else if task.requiresQuantityLogging {
                Button {
                    showLogAmount = true
                } label: {
                    Label("Log amount…", systemImage: "plus.forwardslash.minus")
                }
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.completeTask(task)
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
            }

            Divider()

            // Pin to today / Unpin from today
            if !task.isPinnedToday {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.pinTaskToToday(task)
                } label: {
                    Label("Pin to today", systemImage: "pin")
                }
            } else if canUnpinToday {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.unpinTaskFromToday(task)
                } label: {
                    Label("Unpin from today", systemImage: "pin.slash")
                }
            }

            Button {
                showScheduleSheet = true
            } label: {
                Label("Pin to days…", systemImage: "calendar")
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showFocusMode = true
            } label: {
                Label("Focus on this", systemImage: "leaf")
            }

            Divider()

            Button {
                showEdit = true
            } label: {
                Label("Edit task", systemImage: "pencil")
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete task", systemImage: "trash")
            }
        }
        .alert("Editing a previous day", isPresented: $showPastEditConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Edit this day") {
                confirmPastDayEdit()
            }
        } message: {
            Text("You're changing a past day, not today. The day's score and history will update.")
        }
        .confirmationDialog(
            "Delete \u{201C}\(task.title)\u{201D}?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete task", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                store.deleteTask(task)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Past days keep their points. The task and its schedule are removed.")
        }
        .sheet(isPresented: $showEdit) {
            NewTaskFormView(editing: task) { }
        }
        .sheet(isPresented: $showScheduleSheet) {
            TaskScheduleSheet(task: task)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showFocusMode) {
            FocusModeView(
                sessionLength: 45 * 60,
                label: task.title,
                attachments: [FocusTaskAttachment(taskId: task.id, shared: false)]
            )
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

    private func confirmPastDayEdit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let newValue = !isCompleted
        store.setTaskCompleted(task, completed: newValue, on: store.displayedDay)
    }

    // MARK: - Checkbox

    @ViewBuilder
    private var checkbox: some View {
        ZStack {
            if isCompleted {
                Circle()
                    .fill(onSky ? Color(hex: 0x9BC25B) : Theme.alertGreen)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(onSky ? Color(hex: 0x1E3007) : Theme.warmWheat)
            } else {
                Circle()
                    .stroke(
                        ink.opacity(isHighValue ? 0.5 : 0.3),
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
        .scaleEffect(checkScale)
        .background {
            // The warm glint — blooms out of the check once, then fades.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.sunWarm.opacity(0.65), Theme.sunWarm.opacity(0)],
                        center: .center,
                        startRadius: 1,
                        endRadius: 24
                    )
                )
                .frame(width: 48, height: 48)
                .scaleEffect(glintScale)
                .opacity(glintOpacity)
                .allowsHitTesting(false)
        }
        .padding(.top, 1)
        .contentShape(Rectangle())
    }

    /// The landing: compress → overshoot → rest, plus one warm glint.
    /// Runs on every completion — tap, swipe, or context menu alike.
    private func runCheckSettle() {
        checkScale = 0.72
        glintScale = 0.4
        glintOpacity = 0.85
        Task { @MainActor in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                checkScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.55)) {
                glintOpacity = 0
                glintScale = 1.6
            }
        }
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

    /// True when today's pin can be removed with one tap — a one-off
    /// pin, a `.today` schedule, or a today-dated single pin. Recurring
    /// schedules are managed through "Pin to days…" instead.
    private var canUnpinToday: Bool {
        let cal = Calendar.current
        if let oneOff = task.oneOffPinDate, cal.isDateInToday(oneOff) { return true }
        switch task.pinSchedule {
        case .today: return true
        case .singleDate(let date): return cal.isDateInToday(date)
        default: return false
        }
    }

    /// Color anchor for a booster chip on this card: the watched category
    /// for a category booster, otherwise this task's category.
    private func boosterCategory(_ booster: WeeklyBooster) -> Category {
        if case .category(let cat) = booster.reference { return cat }
        return task.category
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // A travelled past day confirms first — history never changes
        // by accident.
        if store.isViewingPast {
            showPastEditConfirm = true
            return
        }
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
