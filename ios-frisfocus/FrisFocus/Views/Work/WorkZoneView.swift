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
    @Environment(WalkthroughManager.self) private var walkthrough
    /// The finished task whose proof camera is open (swipe-to-capture).
    @State private var proofTask: FFTask?
    @State private var showQuickAdd: Bool = false
    @State private var showAgenda: Bool = false
    /// The flexible block whose honor sheet is open (tapped on the flat list).
    @State private var fulfillBucket: Bucket?
    /// One-time gentle teaching line for the hidden swipe shortcuts —
    /// device-local, gone forever once any swipe lands or it's dismissed.
    @AppStorage("hasSeenPlanSwipeHint") private var hasSeenSwipeHint: Bool = false
    /// Auto-present the agenda once per session when the user has set it
    /// as their default day view.
    @State private var didAutoPresentAgenda: Bool = false
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
                    planMenuButton
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
                    if showsSwipeHint {
                        swipeHintRow
                    }
                    quickAddPill
                }
            }

            // Needs You — smart, ranked, tappable triage + Today's Read.
            NeedsYouSection(
                onStartFocus: { task in startFocus(on: task) },
                onQuickAdd: { showQuickAdd = true }
            )
        }
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .frame(maxWidth: .infinity)
        .background(Theme.warmWheat)
        .onAppear {
            store.needsYou.rolloverIfNeeded()
            if store.agendaIsDefaultDayView && !didAutoPresentAgenda && !store.isViewingPast {
                didAutoPresentAgenda = true
                showAgenda = true
            }
        }
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
        .fullScreenCover(item: $proofTask) { task in
            CaptureView(
                mode: .generalPost,
                initialTaskSticker: TaskStickerBlock(task: task, isChecked: true)
            )
            .environment(store)
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddToDaySheet()
                .environment(store)
        }
        .sheet(item: $fulfillBucket) { bucket in
            BucketFulfillSheet(bucket: bucket)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showAgenda) {
            AgendaDayView(onSwitchToList: { showAgenda = false })
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
                onRemove: { removeTaskFromToday(task) },
                isCompleted: store.hasLogEntryToday(forTaskId: task.id),
                onCaptureProof: { captureProof(for: task) }
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
        case .bucket(let bucket):
            PlanSwipeRow(
                onComplete: { honorBucketViaSwipe(bucket) },
                onRemove: { removeBucketFromToday(bucket) }
            ) {
                BucketBlockRow(bucket: bucket) {
                    guard !store.isViewingPast else { return }
                    fulfillBucket = bucket
                }
            }
        }
    }

    // MARK: - Focus from a Needs You card

    /// Start a solo focus block on a specific task, labelled with its
    /// title. Routes through the same full-screen focus flow the FOCUS
    /// button uses.
    private func startFocus(on task: FFTask) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pendingFocusDuration = TimeInterval((task.estimatedMinutes ?? 45) * 60)
        pendingFocusLabel = task.title
        pendingFocusAttachments = []
        pendingGroveFriendIds = []
        showFocusMode = true
    }

    // MARK: - Swipe shortcut actions

    /// Swipe-right on a task: mark it done with its normal points. Past
    /// days and already-completed tasks are left untouched.
    private func completeTaskViaSwipe(_ task: FFTask) {
        guard !store.isViewingPast else { return }
        markSwipeHintSeen()
        guard !store.hasLogEntryToday(forTaskId: task.id) else { return }
        store.captureUndo("Completed \u{201C}\(task.title)\u{201D}")
        store.completeTask(task)
    }

    /// Swipe-right on a finished task: open the camera to capture proof.
    /// During the mechanics tour, this performed gesture is what advances
    /// the swipe-to-capture lesson.
    private func captureProof(for task: FFTask) {
        guard !store.isViewingPast else { return }
        markSwipeHintSeen()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if walkthrough.tourActive && walkthrough.tourStep == .swipeCapture {
            walkthrough.advanceTour()
        }
        proofTask = task
    }

    /// Swipe-left on a task: take its today-pin off the plan.
    private func removeTaskFromToday(_ task: FFTask) {
        guard !store.isViewingPast else { return }
        markSwipeHintSeen()
        store.unpinTaskFromToday(task)
    }

    /// Swipe-right on a to-do: mark it done with its normal points.
    private func completeTodoViaSwipe(_ todo: Todo) {
        guard !store.isViewingPast else { return }
        markSwipeHintSeen()
        guard !todo.isCompleted else { return }
        store.captureUndo("Completed \u{201C}\(todo.title)\u{201D}")
        store.toggleTodo(todo)
    }

    /// Swipe-left on a to-do: take it off today's plan.
    private func removeTodoFromToday(_ todo: Todo) {
        guard !store.isViewingPast else { return }
        markSwipeHintSeen()
        store.unpinTodoFromToday(todo)
    }

    /// Swipe-right on a flexible block: honor it at its own value. The
    /// tap path (honor sheet) is where a specific gets named — the swipe
    /// is the quick "block honored" shortcut.
    private func honorBucketViaSwipe(_ bucket: Bucket) {
        guard !store.isViewingPast else { return }
        markSwipeHintSeen()
        guard !store.hasLogEntryToday(forBucketId: bucket.id) else { return }
        store.honorBucket(bucket)
    }

    /// Swipe-left on a flexible block: take it off today only —
    /// recurring blocks return on their normal schedule.
    private func removeBucketFromToday(_ bucket: Bucket) {
        guard !store.isViewingPast else { return }
        markSwipeHintSeen()
        store.captureUndo("Took \u{201C}\(bucket.title)\u{201D} off today")
        store.skipBucketToday(bucket)
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

    /// Labeled agenda button beside FOCUS — opens the agenda day view
    /// (bands, buckets, and the week strip). A list/agenda toggle inside
    /// returns to this flat plan. Labeled so the second way to arrange
    /// the day is discoverable, not a mystery glyph.
    @ViewBuilder
    private var weekScheduleButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAgenda = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                Text("AGENDA")
                    .font(.sans(10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
            }
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
        .accessibilityLabel("Agenda — arrange your day in blocks and bands")
    }

    // MARK: - Plan options menu

    /// Visible ⋯ entry for plan-level actions — the same actions the
    /// hidden long-press context menu offers (plus quick add and the
    /// agenda), so nothing lives only behind a gesture.
    @ViewBuilder
    private var planMenuButton: some View {
        Menu {
            Button {
                showQuickAdd = true
            } label: {
                Label("Add to today", systemImage: "plus")
            }
            Button {
                showAgenda = true
            } label: {
                Label("Open agenda", systemImage: "calendar")
            }
            Divider()
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Clear today's plan", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
                .frame(height: 13)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Theme.textPrimary.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(Theme.textPrimary.opacity(0.15), lineWidth: 0.6)
                )
        }
        .accessibilityLabel("Plan options")
    }

    // MARK: - One-time swipe hint

    /// Whether the gentle swipe-shortcut teaching line shows beneath the
    /// plan — only on the live day, only until any swipe lands (or it's
    /// dismissed), and never during the guided tour.
    private var showsSwipeHint: Bool {
        !hasSeenSwipeHint
            && !store.isViewingPast
            && !walkthrough.tourActive
            && !store.todaysPlan.isEmpty
    }

    /// Marks the hint as permanently seen — called by every swipe
    /// shortcut and the hint's own dismiss button.
    private func markSwipeHintSeen() {
        guard !hasSeenSwipeHint else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            hasSeenSwipeHint = true
        }
    }

    /// A quiet one-line teaching row: swipe right completes, swipe left
    /// takes an item off today. Dismissible, and auto-dismisses the
    /// first time either gesture is actually used.
    @ViewBuilder
    private var swipeHintRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text("Swipe a row right to complete it, left to take it off today.")
                .font(.serifItalic(12))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                markSwipeHintSeen()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    .padding(6)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss swipe hint")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.035))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
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
        showQuickAdd = true
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
        .buttonStyle(.pressableCard)
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

#Preview {
    ScrollView {
        WorkZoneView()
    }
    .environment(Store())
}
