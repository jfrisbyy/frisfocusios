//
//  Store+Grove.swift
//  FrisFocus
//
//  Derived state for the shared focus grove (F2): co-focus streaks
//  (focusing with the same friend on consecutive days), recent grove
//  history, and combined recap stats. All computed from the persisted
//  `sharedFocusBlocks` ledger — no extra storage.
//

import Foundation
import UserNotifications

extension Store {
    /// Completed grove sessions that included me, newest first.
    var recentGroves: [SharedFocusBlock] {
        sharedFocusBlocks
            .filter { $0.participantIds.contains(currentUserId) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// All distinct local days (start-of-day) on which I shared a grove
    /// with `friendId`, newest first.
    private func coFocusDays(with friendId: UUID) -> [Date] {
        let cal = Calendar.current
        let days = sharedFocusBlocks
            .filter { $0.participantIds.contains(currentUserId) && $0.participantIds.contains(friendId) }
            .map { cal.startOfDay(for: $0.startedAt) }
        return Array(Set(days)).sorted(by: >)
    }

    /// Consecutive-day streak of focusing with `friendId`. Counts back
    /// from today (or yesterday, so a streak doesn't break until a full
    /// day is missed). Returns 0 when there's no recent co-focus.
    func coFocusStreak(with friendId: UUID) -> Int {
        let cal = Calendar.current
        let days = coFocusDays(with: friendId)
        guard let latest = days.first else { return 0 }
        let today = cal.startOfDay(for: Date())
        let gap = cal.dateComponents([.day], from: latest, to: today).day ?? 99
        // The most recent co-focus must be today or yesterday to keep
        // the streak alive.
        guard gap <= 1 else { return 0 }

        var streak = 1
        var cursor = latest
        let daySet = Set(days)
        while let prev = cal.date(byAdding: .day, value: -1, to: cursor),
              daySet.contains(prev) {
            streak += 1
            cursor = prev
        }
        return streak
    }

    /// The friend I've focused with most recently in a grove, if any.
    func mostRecentGroveFriendId() -> UUID? {
        for block in recentGroves {
            if let fid = block.participantIds.first(where: { $0 != currentUserId }) {
                return fid
            }
        }
        return nil
    }

    /// Combined minutes I've focused across every grove (planned length
    /// summed) — a warm lifetime tally for the recap footer.
    var totalGroveMinutes: Int {
        recentGroves.reduce(0) { $0 + max(0, Int($1.plannedDuration / 60)) }
    }

    /// Fire a quick, wordless cheer to a friend mid-grove — a gentle
    /// "I see you" that lands in their cheer feed and pushes a nudge.
    func sendQuickCheer(to friendId: UUID) {
        let cheer = Cheer(
            fromFriendId: currentUserId,
            fromName: "You",
            fromInitials: "Y",
            fromColorHex: "2C2C2A",
            toUserId: friendId,
            message: "cheering you on in the grove"
        )
        cheers.append(cheer)
        persistAll()
        social?.cheerSent(cheer)
    }

    // MARK: - Scheduling

    /// Upcoming scheduled groves with a live next-occurrence, soonest
    /// first. One-offs already in the past are dropped.
    var upcomingGroves: [ScheduledGrove] {
        scheduledGroves
            .compactMap { grove -> (ScheduledGrove, Date)? in
                guard let next = grove.nextOccurrence() else { return nil }
                return (grove, next)
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    /// The very next scheduled grove, if any.
    var nextScheduledGrove: ScheduledGrove? { upcomingGroves.first }

    /// Add a scheduled grove and arm its reminder + friend invites.
    @discardableResult
    func addScheduledGrove(
        friendIds: [UUID],
        plannedDuration: TimeInterval,
        startAt: Date,
        recurrence: GroveRecurrence,
        label: String?
    ) -> ScheduledGrove {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let grove = ScheduledGrove(
            label: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            friendIds: Array(friendIds.prefix(3)),
            plannedDuration: plannedDuration,
            startAt: startAt,
            recurrence: recurrence
        )
        scheduledGroves.append(grove)
        persistAll()
        armReminder(for: grove)
        return grove
    }

    /// Remove a scheduled grove and cancel its reminder.
    func removeScheduledGrove(_ id: UUID) {
        scheduledGroves.removeAll { $0.id == id }
        persistAll()
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["grove-\(id.uuidString)"])
    }

    /// Schedule a local reminder a few minutes before the grove starts.
    private func armReminder(for grove: ScheduledGrove) {
        guard let next = grove.nextOccurrence() else { return }
        let fireAt = next.addingTimeInterval(-5 * 60)
        guard fireAt > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Grove starting soon"
        let labelPart = grove.label.map { "\($0) · " } ?? ""
        content.body = "\(labelPart)Your shared focus starts in 5 minutes. Plant your tree."
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireAt
        )
        let repeats = grove.recurrence != .once
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: repeats
                ? Calendar.current.dateComponents([.hour, .minute], from: fireAt)
                : comps,
            repeats: repeats
        )
        let request = UNNotificationRequest(
            identifier: "grove-\(grove.id.uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
