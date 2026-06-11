//
//  CircleSharedTasksSection.swift
//  FrisFocus
//
//  "The work" — the shared task list inside a parallel circle's detail
//  page. Each row carries a working checkbox (toggles the current
//  user's `CircleTaskCompletion` for today, with the circle→personal
//  bridge applied when a `linkedPersonalTaskId` is set), the task
//  title, a link-status subline ("linked to your {category} board" or
//  "circle only · tap to link"), and a right-aligned done/hollow
//  glyph.
//
//  Parent (CircleDetailView) owns the circle and supplies a closure
//  for "tap to link", which navigates to the C5 picker once that
//  lands; until then the closure presents a placeholder so the seam
//  reads cleanly.
//

import SwiftUI
import UIKit

struct CircleSharedTasksSection: View {
    @Environment(Store.self) private var store
    let circle: FFCircle
    let scope: CircleScope
    let onLinkTap: (CircleTask) -> Void
    /// Press-and-hold a task to add a photo/video to the circle's story
    /// for that specific task — mirrors the home "Today's Plan" cards.
    let onAddToStory: (CircleTask) -> Void

    init(
        circle: FFCircle,
        scope: CircleScope = .today,
        onLinkTap: @escaping (CircleTask) -> Void,
        onAddToStory: @escaping (CircleTask) -> Void
    ) {
        self.circle = circle
        self.scope = scope
        self.onLinkTap = onLinkTap
        self.onAddToStory = onAddToStory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 4)

            Text(sublineText)
                .font(.serifItalic(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(circle.tasks) { task in
                    SharedTaskRow(
                        circleId: circle.id,
                        task: task,
                        scope: scope,
                        onLinkTap: { onLinkTap(task) },
                        onAddToStory: { onAddToStory(task) }
                    )
                }
            }
        }
    }

    private var sublineText: String {
        switch scope {
        case .today: return "your progress today"
        case .overall: return "your progress over the whole run"
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("The work")
                .font(.serif(20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text("\(circle.tasks.count) TASK\(circle.tasks.count == 1 ? "" : "S")")
                .font(.sans(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
    }
}

// MARK: - Task row

private struct SharedTaskRow: View {
    @Environment(Store.self) private var store
    let circleId: UUID
    let task: CircleTask
    let scope: CircleScope
    let onLinkTap: () -> Void
    let onAddToStory: () -> Void

    /// Today's completion state — the only thing the checkbox can
    /// ever mutate, regardless of scope (you can't unwind history).
    private var isCompletedToday: Bool {
        store.hasUserCompletedCircleTaskToday(
            circleId: circleId,
            circleTaskId: task.id
        )
    }

    /// Total lifetime completion count for the current user on this
    /// task across the circle's whole timeframe.
    private var lifetimeCount: Int {
        store.userCompletionCount(circleId: circleId, circleTaskId: task.id)
    }

    /// Whether the row reads as "done" in the current scope. Drives
    /// the strikethrough only — the checkbox still mirrors today.
    private var readsAsDone: Bool {
        switch scope {
        case .today: return isCompletedToday
        case .overall: return lifetimeCount > 0
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(readsAsDone, color: Theme.textPrimary.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)

                linkSubline
            }

            Spacer(minLength: 8)

            rightIndicator
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .contextMenu {
            Button {
                onAddToStory()
            } label: {
                Label("Add to story", systemImage: "camera")
            }

            if task.linkedPersonalTaskId == nil {
                Button {
                    onLinkTap()
                } label: {
                    Label("Link to your season task", systemImage: "link.badge.plus")
                }
            }
        }
    }

    private var checkbox: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) {
                store.toggleCircleTaskCompletion(circleId: circleId, task: task)
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(
                        isCompletedToday ? Theme.alertGreen : Theme.textPrimary.opacity(0.35),
                        lineWidth: 1.4
                    )
                    .background(
                        Circle()
                            .fill(isCompletedToday ? Theme.alertGreen : Color.clear)
                    )
                    .frame(width: 24, height: 24)

                if isCompletedToday {
                    Image(systemName: "checkmark")
                        .font(.sans(11, weight: .bold))
                        .foregroundStyle(Theme.textCream)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompletedToday ? "Mark not done" : "Mark done")
    }

    @ViewBuilder
    private var linkSubline: some View {
        if let linkedId = task.linkedPersonalTaskId,
           let personal = store.personalTask(by: linkedId) {
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.sans(10, weight: .semibold))
                Text("linked to your \(personal.category.displayName.lowercased()) board")
                    .font(.sans(12, weight: .regular))
            }
            .foregroundStyle(Theme.alertGreen)
        } else {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onLinkTap()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "link.badge.plus")
                        .font(.sans(10, weight: .semibold))
                    Text("circle only · tap to link")
                        .font(.sans(12, weight: .regular))
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link to a personal task")
        }
    }

    @ViewBuilder
    private var rightIndicator: some View {
        switch scope {
        case .today:
            if isCompletedToday {
                Text("done")
                    .font(.sans(11, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(Theme.alertGreen)
                    .textCase(.uppercase)
            } else {
                Image(systemName: "circle")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.25))
            }
        case .overall:
            if lifetimeCount > 0 {
                Text("\u{00D7}\(lifetimeCount)")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.alertGreen)
                    .monospacedDigit()
            } else {
                Image(systemName: "circle")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(0.25))
            }
        }
    }
}

#Preview {
    let store = Store()
    return ScrollView {
        if let parallel = store.circles.first(where: { $0.type == .parallel }) {
            CircleSharedTasksSection(circle: parallel, scope: .today, onLinkTap: { _ in }, onAddToStory: { _ in })
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 24)
        }
    }
    .background(Theme.warmWheat)
    .environment(store)
}
