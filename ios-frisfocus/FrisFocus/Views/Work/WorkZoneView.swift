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
    @State private var showWeekSchedule: Bool = false
    @State private var showFocusStart: Bool = false
    @State private var showFocusMode: Bool = false
    @State private var showFocusGrove: Bool = false
    @State private var pendingFocusDuration: TimeInterval = 45 * 60
    @State private var pendingFocusLabel: String? = nil
    @State private var pendingFocusAttachments: [FocusTaskAttachment] = []
    @State private var pendingGroveFriendIds: [UUID] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .topTrailing) {
                ZoneHeaderView(
                    title: "Today's plan",
                    subline: store.workSubline
                )
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
                    ForEach(store.todaysPlan) { item in
                        switch item {
                        case .task(let task):
                            TaskCardView(task: task)
                        case .todo(let todo):
                            TodoCardView(todo: todo)
                        case .cadenceLink(let link):
                            CadenceRoutineRow(link: link)
                        }
                    }
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
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
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

    /// Shown when nothing is pinned for today. Dashed border, italic
    /// prompt, tap opens the capture sheet so the user can add their
    /// first item without hunting for the `+` button.
    @ViewBuilder
    private var emptyPlanCTA: some View {
        Button(action: openCaptureSheet) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Text("Pin a Task or add a To-do")
                    .font(.serifItalic(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
                Spacer(minLength: 0)
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
        .accessibilityLabel("Add a Task or To-do")
    }

    private func openCaptureSheet() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showCaptureSheet = true
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
