//
//  MilestoneNudgeService.swift
//  FrisFocus
//
//  One gentle local notification per milestone: when its target week
//  arrives and it isn't done yet, a single nudge reminds the user it's
//  in motion. Never repeats — scheduling uses a stable identifier per
//  milestone, so refreshes replace rather than stack, and completing
//  or deleting a milestone cancels its pending nudge.
//
//  Tapping the nudge routes to the milestone's page via the same
//  deep-link path pushes use (`route: "milestone"` in userInfo).
//

import Foundation
import UserNotifications

enum MilestoneNudgeService {
    private static func identifier(for milestoneId: UUID) -> String {
        "milestone-nudge-\(milestoneId.uuidString)"
    }

    /// 9 AM local on the morning of the milestone's target date. Returns
    /// nil for unscheduled milestones (no target date) — they get no nudge.
    private static func nudgeDate(for milestone: Milestone, in season: Season) -> Date? {
        guard let target = milestone.targetDate else { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: target)
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)
    }

    /// Re-schedule pending nudges to match the season's current
    /// milestones. Completed milestones, past target weeks, and deleted
    /// milestones all lose their pending nudge. Safe to call often.
    static func refresh(for season: Season) {
        let center = UNUserNotificationCenter.current()
        let validIds = Set(season.milestones.map { identifier(for: $0.id) })

        Task {
            // Drop nudges for milestones that no longer exist.
            let pending = await center.pendingNotificationRequests()
            let stale = pending
                .map(\.identifier)
                .filter { $0.hasPrefix("milestone-nudge-") && !validIds.contains($0) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }

            for milestone in season.milestones {
                let id = identifier(for: milestone.id)
                guard !milestone.isCompleted,
                      let fireDate = nudgeDate(for: milestone, in: season),
                      fireDate > Date()
                else {
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = "Milestone day"
                content.body = "“\(milestone.title)” is aimed at today — \(milestone.pointValue) pts when you land it."
                content.sound = .default
                content.userInfo = [
                    "route": "milestone",
                    "milestoneId": milestone.id.uuidString
                ]

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                do {
                    try await center.add(request)
                } catch {
                    Log.milestoneNudge.error("schedule failed for \(milestone.title): \(error)")
                }
            }
        }
    }
}
