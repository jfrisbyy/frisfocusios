//
//  MechanicsTourOverlay.swift
//  FrisFocus
//
//  Layer A — the interactive mechanics tour. A soft scrim dims the page
//  (never a harsh cutout) while a coachmark + gesture hint prompts the
//  real action on the real UI below. The scrim never blocks touches,
//  so the user performs the actual action and the real result teaches.
//
//  Seven beats, in the order a real day works:
//   1. pinFirst     — pull a task from the season onto today (the plan
//                     starts empty on purpose; nothing is auto-assigned).
//                     Advances when anything lands on today's plan.
//   2. checkOff     — tap the circle; the sun rises. Advances on the check.
//   3. swipeCapture — swipe a finished task to open the proof camera,
//                     and the other way to take a row off today.
//   4. quantity     — log an amount (only when the plan has one).
//                     Advances when an amount is actually logged.
//   5. rhythm       — give a task a recurring schedule in the REAL
//                     editor (presented from the card's button).
//                     Advances when a recurring schedule is saved.
//   6. agenda       — tap the real AGENDA pill; meet bands, flexible
//                     blocks, and day templates. Advances when the
//                     agenda closes.
//   7. sunset       — the close: tomorrow starts new, rhythms return.
//
//  "Skip tour" is the only skip. Every other button DOES something —
//  a stuck user gets a "Next" (or "Do it for me") fallback after a few
//  seconds, so the tour can never trap.
//

import SwiftUI
import UIKit

struct MechanicsTourOverlay: View {
    @Environment(Store.self) private var store
    @Environment(WalkthroughManager.self) private var walkthrough
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reveals the tap-through fallback after a short idle, so a stuck
    /// user is never trapped. Reset on every step change.
    @State private var showFallback = false
    @State private var fallbackTask: Task<Void, Never>?
    /// The task whose schedule editor the rhythm lesson opened.
    @State private var scheduleTarget: FFTask?

    var body: some View {
        if walkthrough.tourActive, let step = walkthrough.tourStep {
            ZStack(alignment: .bottom) {
                // Soft scrim — dims the page but passes every touch
                // through to the real cards beneath.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                card(for: step)
                    .padding(.horizontal, Theme.pageHorizontalPadding)
                    .padding(.bottom, 128)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .id(step)
            }
            .animation(
                reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.86),
                value: step
            )
            .onAppear {
                armFallback()
                walkthrough.setQuantityAvailable(planHasQuantity)
            }
            .onChange(of: step) { _, _ in armFallback() }
            .onDisappear { fallbackTask?.cancel() }
            // The pin lesson advances the moment anything real lands on
            // today's plan — a pinned task, a new to-do, either counts.
            // (Reads the LIVE step so a stale body capture can't misfire.)
            .onChange(of: planCount) { old, new in
                if walkthrough.tourStep == .pinFirst, new > old {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    walkthrough.advanceTour()
                }
            }
            // The rhythm lesson advances when a recurring schedule is
            // actually saved — from the sheet below OR any other surface
            // (hold-menu → "Pin to days…", the agenda, the full editor).
            .onChange(of: recurringCount) { old, new in
                if walkthrough.tourStep == .rhythm, new > old {
                    scheduleTarget = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    walkthrough.advanceTour()
                }
            }
            // The quantity lesson advances on the amount actually being
            // logged — the "Log" button in the amount sheet, never a
            // plain check-off, which would let a flat task stand in for
            // the one lesson that is about amounts.
            // (Reads the LIVE step, same as the watchers above.)
            .onChange(of: quantityLogCount) { old, new in
                if walkthrough.tourStep == .quantity, new > old {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    walkthrough.advanceTour()
                }
            }
            // Keep the quantity lesson honest as the plan is built mid-tour.
            .onChange(of: planHasQuantity) { _, has in
                walkthrough.setQuantityAvailable(has)
            }
            // The REAL schedule editor, presented straight from the
            // rhythm card — the user picks days and saves for real.
            .sheet(item: $scheduleTarget) { task in
                TaskScheduleSheet(task: task)
                    .environment(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Step cards

    @ViewBuilder
    private func card(for step: WalkthroughManager.MechanicsStep) -> some View {
        switch step {
        case .pinFirst:
            CoachmarkCard(
                title: "Your tasks live in your season — today starts empty.",
                message: "Nothing is scheduled for you. Tap \u{201C}Pin a Task or add a To-do\u{201D} below and pull what matters onto today. Choosing the day's few is the whole ritual.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Do it for me" : nil,
                onContinue: showFallback ? { pinTopTaskForMe() } : nil
            ) { TapPulseHint() }

        case .checkOff:
            CoachmarkCard(
                title: "Tap the circle to check it off.",
                message: "Your sun rises a little with every task you complete — that’s your day, at a glance.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Next" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil
            ) { TapPulseHint() }

        case .swipeCapture:
            CoachmarkCard(
                title: "Swipe a finished task to capture it.",
                message: "It opens the camera to snap proof — the lift, the meal, the moment. Then you choose who sees it; proofs go only to the friends you pick. Swipe left instead and the row steps off today, back to your season.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Next" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil
            ) { SwipeArrowHint() }

        case .quantity:
            CoachmarkCard(
                title: "Some tasks track an amount.",
                message: "Enter how much, not just done — the sun knows the difference between a step and a mile.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Next" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil
            ) { TapPulseHint() }

        case .rhythm:
            CoachmarkCard(
                title: "Some things repeat. Give one a rhythm.",
                message: "Every day, or just the weekdays you choose — a rhythm walks the task onto those days by itself. Later, hold any card \u{2192} \u{201C}Pin to days\u{2026}\u{201D} does the same.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Next" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil,
                actionTitle: "Set a rhythm",
                onAction: { presentScheduleEditor() }
            ) { RhythmHint() }

        case .agenda:
            CoachmarkCard(
                title: "Shape the day in blocks.",
                message: "Tap AGENDA above your plan: morning, afternoon and evening bands, flexible blocks like \u{201C}Movement\u{201D} with options inside, and day templates you can stamp onto weekdays.",
                onSkip: { walkthrough.skipTour() },
                continueTitle: showFallback ? "Next" : nil,
                onContinue: showFallback ? { walkthrough.advanceTour() } : nil
            ) { TapPulseHint() }

        case .sunset:
            // The closing beat — tomorrow's promise, plus the one quiet,
            // pull-only suggestion (no permission ask, no notification).
            CoachmarkCard(
                title: "Tomorrow the sun starts new.",
                message: "Tonight this day closes. Rhythms return on their days by themselves; everything else waits in your season until you pin it. If you'd like your sun nearby, the FrisFocus widget lives on your home screen — add it any time from its edit mode.",
                onSkip: nil,
                actionTitle: "Done",
                onAction: { walkthrough.advanceTour() }
            ) { SunsetHint() }
        }
    }

    // MARK: - Live reads

    /// Everything on today's plan — tasks, to-dos, blocks, routines.
    private var planCount: Int { store.todaysPlan.count }

    /// Whether the plan currently holds a tiered / increment task.
    private var planHasQuantity: Bool {
        store.todaysPlan.contains { item in
            if case .task(let task) = item { return task.requiresQuantityLogging }
            return false
        }
    }

    /// How many board tasks carry a recurring schedule right now.
    private var recurringCount: Int {
        store.tasks.filter(\.hasRecurringSchedule).count
    }

    /// How many log entries carry an amount. Only `completeTask(_:quantity:)`
    /// writes a non-nil quantity, and the only caller that passes one is the
    /// amount sheet's "Log" button — so a rise here means precisely "the
    /// person just logged how much", which is the lesson being taught.
    private var quantityLogCount: Int {
        store.logEntries.filter { $0.quantity != nil }.count
    }

    // MARK: - Step actions

    /// "Do it for me" on the pin lesson: place the most valuable
    /// unpinned board task onto today — the plan-count watcher advances
    /// the tour, so the user still sees the real mechanism fire.
    private func pinTopTaskForMe() {
        guard let top = store.tasks
            .filter({ !$0.isPinnedToday })
            .max(by: { $0.nominalValue < $1.nominalValue })
        else {
            walkthrough.advanceTour()
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.pinTaskToToday(top)
    }

    /// Open the real schedule editor for the best rhythm candidate: a
    /// plan task without a rhythm first, then any board task without
    /// one, then any task at all.
    private func presentScheduleEditor() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let planTasks: [FFTask] = store.todaysPlan.compactMap { item in
            if case .task(let task) = item { return task }
            return nil
        }
        let target = planTasks.first(where: { !$0.hasRecurringSchedule })
            ?? store.tasks.first(where: { !$0.hasRecurringSchedule })
            ?? planTasks.first
            ?? store.tasks.first
        guard let target else {
            walkthrough.advanceTour()
            return
        }
        scheduleTarget = target
    }

    /// Show the tap-through fallback after a short idle on each step.
    private func armFallback() {
        fallbackTask?.cancel()
        showFallback = false
        fallbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showFallback = true }
        }
    }
}

// MARK: - Schedule helpers

private extension FFTask {
    /// True when this task returns on its own — every day or on chosen
    /// weekdays. One-off pins and single dates don't count as a rhythm.
    var hasRecurringSchedule: Bool {
        switch pinSchedule {
        case .daily, .daysOfWeek:
            return true
        default:
            return false
        }
    }
}
