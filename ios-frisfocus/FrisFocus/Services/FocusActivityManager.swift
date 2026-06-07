//
//  FocusActivityManager.swift
//  FrisFocus
//
//  F3 — App-side controller for the focus-block Live Activity. Starts
//  one activity when a session begins, pushes a state update each
//  time a leaf falls, and ends it when the session closes. The
//  countdown itself uses ActivityKit's timer-interval rendering, so
//  we only need to push on real state changes — not on every second.
//

import ActivityKit
import Foundation
import os.log

/// Lightweight wrapper around `Activity<FocusActivityAttributes>`. The
/// active activity reference is kept in a singleton because the
/// session lifecycle outlives the focus screen (we want the activity
/// to follow the session, not the view).
@MainActor
final class FocusActivityManager {
    static let shared = FocusActivityManager()
    private init() {}

    private let log = Logger(subsystem: "app.rork.FrisFocus", category: "FocusActivity")
    private var activity: Activity<FocusActivityAttributes>?

    /// Starts a Live Activity for the given focus session if Live
    /// Activities are enabled. Safe to call when one is already
    /// running — it'll no-op so we don't stack duplicates.
    func start(
        startedAt: Date,
        plannedDuration: TimeInterval,
        label: String?,
        canopyTotal: Int
    ) {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.debug("Live Activities disabled by the user; skipping start.")
            return
        }

        let attributes = FocusActivityAttributes(label: label)
        let state = FocusActivityAttributes.ContentState(
            startedAt: startedAt,
            plannedDuration: plannedDuration,
            leavesFallen: 0,
            canopyTotal: canopyTotal
        )
        let content = ActivityContent(
            state: state,
            staleDate: startedAt.addingTimeInterval(plannedDuration + 60)
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            log.error("Failed to start focus Live Activity: \(String(describing: error))")
        }
    }

    /// Pushes the latest leaf count to the running activity. Cheap —
    /// only call on real state changes (e.g. when a leaf falls).
    func update(
        startedAt: Date,
        plannedDuration: TimeInterval,
        leavesFallen: Int,
        canopyTotal: Int
    ) {
        guard let activity else { return }
        let state = FocusActivityAttributes.ContentState(
            startedAt: startedAt,
            plannedDuration: plannedDuration,
            leavesFallen: leavesFallen,
            canopyTotal: canopyTotal
        )
        let content = ActivityContent(
            state: state,
            staleDate: startedAt.addingTimeInterval(plannedDuration + 60)
        )
        Task {
            await activity.update(content)
        }
    }

    /// Ends the running activity and clears the local reference. The
    /// banner is removed immediately so the lock screen doesn't keep
    /// a stale focus block after the session closes.
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
