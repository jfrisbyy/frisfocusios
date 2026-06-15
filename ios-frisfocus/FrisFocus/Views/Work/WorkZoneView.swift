//
//  WorkZoneView.swift
//  FrisFocus
//
//  Zone 2 — wheat background. Now structured around a single
//  unified "Today's plan" section that mixes pinned Tasks and
//  dated To-dos, plus an optional "Needs You" alerts section
//  below. Loose Ends is no longer rendered here; the data still
//  lives on the Store for the future To-do library view.
//
//  When the plan is empty the section collapses to a dashed CTA
//  that opens the capture sheet — the same sheet the centre `+`
//  button uses.
//

import SwiftUI
import UIKit

struct WorkZoneView: View {
    @Environment(Store.self) private var store
    @State private var showCaptureSheet: Bool = false
    @State private var showQuickAdd: Bool = false
    @State private var showWeekSchedule: Bool = false
    @State private var showFocusStart: Bool = false
    @State private var showFocusMode: Bool = false
    @State private var showFocusGrove: Bool = false
    @State private var pendingFocusDuration: TimeInterval = 45 * 60
    @State private var pendingFocusLabel: String? = nil
    @State private var pendingFocusAttachments: [FocusTaskAttachment] = []
    @State private var pendingGroveFriendIds: [UUID] = []
    /// Confirmation gate for the long-press "clear today's plan" action.
    @State private var showClearConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .topTrailing) {
                ZoneHeaderView(
                    title: "Today's plan",
                    subline: store.workSubline
                )
                .contentShape(Rectangle())
                .contextMenu {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear today's plan", systemImage: "trash")
                    }
                }
                HStack(spacing: 8) {
                    weekScheduleButton
                    focusEntryButton
                }
                .offset(y: 4)
            }
            .padding(.top, 28)

            // Today's Plan body — habit-train rows first (so the
            // routine is legible as a single unit), then the unified
            // task / to-do list. When nothing is pinned and there are
            // no trains, fall back to the dashed CTA.
            if store.todaysPlan.isEmpty && store.habitTrains.isEmpty {
                emptyPlanCTA
            } else {
                VStack(spacing: 10) {
                    ForEach(store.habitTrains) { train in
                        HabitTrainRow(train: train)
                    }
                    if store.todaysPlan.count > Self.planScrollThreshold {
                        scrollingPlanList
                    } else {
                        ForEach(store.todaysPlan) { item in
                            planRow(for: item)
                        }
                    }
                    quickAddPill
                }
            }

            // Needs You — live alerts from missed Must-Dos + Should-Do drift
            if store.hasAlerts {
                sectionGroup(eyebrow: "Needs You") {
                    VStack(spacing: 10) {
                        ForEach(store.alerts) { alert in
                            AlertCardView(alert: alert)
                        }
                    }
                }
                .padding(.bottom, 28)
            } else {
                Spacer().frame(height: 28)
            }
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .frame(maxWidth: .infinity)
        .background(Theme.warmWheat)
        .confirmationDialog(
            "Clear today's plan?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear today's plan", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                store.clearTodaysPlan()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes everything from today. Your tasks and to-dos stay safe in your library.")
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddToDaySheet()
                .environment(store)
        }
        .sheet(isPresented: $showWeekSchedule) {
            WeekScheduleView()
                .environment(store)
        }
        .sheet(isPresented: $showFocusStart) {
            FocusStartSheet { duration, label, friendIds, attachments in
                pendingFocusDuration = duration
                pendingFocusLabel = label
                pendingFocusAttachments = attachments
                pendingGroveFriendIds = friendIds
                // Defer the full-screen cover by a tick so the start
                // sheet finishes dismissing before the focus scene
                // pushes on top of it. An empty friend list starts a
                // solo block; any friends route straight to the grove.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if friendIds.isEmpty {
                        showFocusMode = true
                    } else {
                        showFocusGrove = true
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showFocusMode) {
            FocusModeView(
                sessionLength: pendingFocusDuration,
                label: pendingFocusLabel,
                attachments: pendingFocusAttachments,
                onUpgradeToGrove: { friendIds in
                    // Mid-session: the solo tree blossoms into a grove.
                    // The active focus session persists, so the grove
                    // resumes the same wall-clock timer.
                    pendingGroveFriendIds = friendIds
                    showFocusMode = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showFocusGrove = true
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showFocusGrove) {
            SharedFocusModeView(
                sessionLength: pendingFocusDuration,
                label: pendingFocusLabel,
                participantFriendIds: pendingGroveFriendIds,
                attachments: pendingFocusAttachments
            )
        }
    }

    // MARK: - Today's plan list

    /// Once the plan grows past this many items, the mixed task/to-do
    /// list becomes a self-contained scrollable box instead of pushing
    /// the whole page taller.
    private static let planScrollThreshold: Int = 8

    /// Approximate height of a single plan row (card + inter-row spacing).
    /// Used to cap the scroll box at roughly the threshold number of rows.
    private static let approxRowHeight: CGFloat = 64

    @ViewBuilder
    private func planRow(for item: HomeRowItem) -> some View {
        switch item {
        case .task(let task):
            PlanSwipeRow(
                onComplete: { completeTaskViaSwipe(task) },
                onRemove: { removeTaskFromToday(task) }
            ) {
                TaskCardView(task: task)
            }
        case .todo(let todo):
            PlanSwipeRow(
                onComplete: { completeTodoViaSwipe(todo) },
                onRemove: { removeTodoFromToday(todo) }
            ) {
                TodoCardView(todo: todo)
            }
        case .cadenceLink(let link):
            CadenceRoutineRow(link: link)
        }
    }

    // MARK: - Swipe shortcut actions

    /// Swipe-right on a task: mark it done with its normal points. Past
    /// days and already-completed tasks are left untouched.
    private func completeTaskViaSwipe(_ task: FFTask) {
        guard !store.isViewingPast else { return }
        guard !store.hasLogEntryToday(forTaskId: task.id) else { return }
        store.captureUndo("Completed \u{201C}\(task.title)\u{201D}")
        store.completeTask(task)
    }

    /// Swipe-left on a task: take its today-pin off the plan.
    private func removeTaskFromToday(_ task: FFTask) {
        guard !store.isViewingPast else { return }
        store.unpinTaskFromToday(task)
    }

    /// Swipe-right on a to-do: mark it done with its normal points.
    private func completeTodoViaSwipe(_ todo: Todo) {
        guard !store.isViewingPast else { return }
        guard !todo.isCompleted else { return }
        store.captureUndo("Completed \u{201C}\(todo.title)\u{201D}")
        store.toggleTodo(todo)
    }

    /// Swipe-left on a to-do: take it off today's plan.
    private func removeTodoFromToday(_ todo: Todo) {
        guard !store.isViewingPast else { return }
        store.unpinTodoFromToday(todo)
    }

    /// Scrollable box for long plans — capped at ~8 rows tall with soft
    /// top/bottom fades so it's clear there's more to scroll. Blends into
    /// the page with no hard border.
    @ViewBuilder
    private var scrollingPlanList: some View {
        let maxHeight = Self.approxRowHeight * CGFloat(Self.planScrollThreshold)
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 10) {
                ForEach(store.todaysPlan) { item in
                    planRow(for: item)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: maxHeight)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.96),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Week schedule entry

    /// Small calendar button beside FOCUS — opens the weekly schedule
    /// page showing every task pinned to each day of the week.
    @ViewBuilder
    private var weekScheduleButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showWeekSchedule = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Theme.textPrimary.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(Theme.textPrimary.opacity(0.15), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weekly schedule")
    }

    // MARK: - Focus entry

    /// Quiet leaf-glyph button that opens the unified Focus setup, where
    /// the user can start solo or invite friends into a grove.
    @ViewBuilder
    private var focusEntryButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showFocusStart = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                Text("FOCUS")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Theme.alertGreen.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(Theme.alertGreen.opacity(0.25), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start focus session")
    }

    // MARK: - Empty state

    /// Shown when nothing is pinned for today. Dashed border with a short
    /// explanation that tasks live in the season and the user pins the
    /// ones to focus on today, plus the tap-to-add prompt. Tapping opens
    /// the capture sheet so the user can add their first item without
    /// hunting for the `+` button.
    @ViewBuilder
    private var emptyPlanCTA: some View {
        Button(action: openCaptureSheet) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your tasks live in your season. Pin the ones you want to focus on today.")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    Text("Pin a Task or add a To-do")
                        .font(.serifItalic(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.65))
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Theme.textPrimary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today's Plan is empty. Your tasks live in your season — pin the ones you want to focus on today, or add a to-do.")
    }

    private func openCaptureSheet() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showCaptureSheet = true
    }

    // MARK: - Quick add

    /// Soft pill below the plan items that opens the one-tap add sheet.
    /// Only shown when the plan already has content; the empty day is
    /// covered by the dashed CTA instead.
    @ViewBuilder
    private var quickAddPill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showQuickAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                Text("Add to today")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.textPrimary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(0.10), lineWidth: 0.8)
            )
        }
        .buttonStyle(QuickAddPressStyle())
        .accessibilityLabel("Add a task or to-do to today")
    }

    // MARK: - Section helper

    @ViewBuilder
    private func sectionGroup<Content: View>(
        eyebrow: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText(text: eyebrow, opacity: 0.6)
            content()
        }
    }
}

/// Gentle press-scale for the quick-add pill — a quiet shrink-and-dim
/// on touch so the tap feels responsive without pulling focus.
private struct QuickAddPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    ScrollView {
        WorkZoneView()
    }
    .environment(Store())
}
