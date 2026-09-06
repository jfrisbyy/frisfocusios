//
//  Store+Reminders.swift
//  FrisFocus
//
//  On-device plan reminders. Four kinds, each individually switchable:
//   • Morning preview   — one note with the day's plan count.
//   • Timed windows     — a task's "7:00–8:00" window just opened.
//   • Part-of-day nudge — morning / afternoon / evening begins, naming
//                         what floats in that band.
//   • Evening check-in  — only if things are still open, naming how many.
//
//  Everything is scheduled locally from the resolved plan (today +
//  tomorrow), rescheduled off the Store's single write path
//  (`flushPendingSaves`) so every mutation — check-offs, pins, plan
//  edits, day rollover — refreshes the schedule without any call site
//  needing to remember. Completing a task therefore cancels its
//  reminders within moments.
//

import Foundation
import UserNotifications

// MARK: - Preferences

/// Per-kind reminder switches. Device-local (like notification settings
/// themselves), persisted directly in UserDefaults — deliberately outside
/// the account sync envelope.
nonisolated struct PlanReminderPrefs: Codable, Equatable, Sendable {
    var morningDigest: Bool = true
    var timedWindows: Bool = true
    var partOfDayNudge: Bool = true
    var eveningCheckIn: Bool = true

    static let storageKey = "planReminderPrefs.v1"

    static func load() -> PlanReminderPrefs {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(PlanReminderPrefs.self, from: data) else {
            return PlanReminderPrefs()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Debounce handle for reminder rebuilds — a burst of check-offs costs
/// one reschedule. File-scope because extensions can't add storage.
private var planReminderRefreshTask: Task<Void, Never>?

// MARK: - Store extension

extension Store {
    /// The current reminder switches. Setting reschedules immediately.
    var planReminderPrefs: PlanReminderPrefs {
        get { PlanReminderPrefs.load() }
        set {
            newValue.save()
            schedulePlanReminderRefresh()
        }
    }

    /// Debounced entry point — safe to call from any mutation path.
    func schedulePlanReminderRefresh() {
        planReminderRefreshTask?.cancel()
        planReminderRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await self?.reschedulePlanReminders()
        }
    }

    /// Rebuild every pending plan reminder from the current state.
    /// Clears first, so demo mode / sign-out / an emptied plan always
    /// converge on "no reminders".
    func reschedulePlanReminders() async {
        let center = UNUserNotificationCenter.current()

        // Sweep everything we own (identifiers are namespaced "plan-").
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("plan-") }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }

        // Only a real (non-demo, initialized) install gets reminders.
        guard appMode == .clean else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        let prefs = planReminderPrefs
        guard prefs.morningDigest || prefs.timedWindows
            || prefs.partOfDayNudge || prefs.eveningCheckIn else { return }

        let cal = Calendar.current
        let now = Date()

        for dayOffset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) else { continue }
            let pinned = tasksPinned(on: day)
            let doneIds = completedTaskIds(on: day)
            let unfinished = pinned.filter { !doneIds.contains($0.id) }
            let openTodos = todos.filter { todo in
                guard todo.pointValue != nil, todo.completedAt == nil,
                      let due = todo.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: day)
            }

            // 1. Morning preview — 8:15.
            if prefs.morningDigest {
                let count = unfinished.count + openTodos.count
                if count > 0, let fire = time(8, 15, on: day, cal: cal), fire > now {
                    let body = count == 1
                        ? "One thing on the board — the sun is waiting."
                        : "\(count) things on the board — the sun is waiting."
                    schedule(
                        center: center,
                        id: "plan-d\(dayOffset)-digest",
                        title: "Today's plan",
                        body: body,
                        fireDate: fire,
                        cal: cal
                    )
                }
            }

            // 2. Timed windows — at each unfinished task's window start.
            if prefs.timedWindows {
                let timed = unfinished
                    .filter { $0.timeWindow != nil }
                    .sorted { ($0.timeWindow?.startMinutes ?? 0) < ($1.timeWindow?.startMinutes ?? 0) }
                    .prefix(8)
                for task in timed {
                    guard let window = task.timeWindow else { continue }
                    let fire = window.startDate(on: day)
                    guard fire > now else { continue }
                    schedule(
                        center: center,
                        id: "plan-d\(dayOffset)-task-\(task.id.uuidString)",
                        title: task.title,
                        body: "Your \(window.displayText) window is open.",
                        fireDate: fire,
                        cal: cal
                    )
                }
            }

            // 3. Part-of-day nudges — one per band that holds floaters.
            if prefs.partOfDayNudge {
                let bandTimes: [(PartOfDay, Int, Int)] = [
                    (.morning, 9, 0),
                    (.afternoon, 12, 30),
                    (.evening, 17, 30)
                ]
                for (band, hour, minute) in bandTimes {
                    let floating = unfinished.filter { $0.timeWindow == nil && $0.partOfDay == band }
                    guard !floating.isEmpty,
                          let fire = time(hour, minute, on: day, cal: cal),
                          fire > now else { continue }
                    let names = floating.prefix(2).map(\.title).joined(separator: ", ")
                    let extra = floating.count > 2 ? " +\(floating.count - 2) more" : ""
                    schedule(
                        center: center,
                        id: "plan-d\(dayOffset)-band-\(band.rawValue)",
                        title: "\(band.displayName) begins",
                        body: "Floating in your \(band.displayName.lowercased()): \(names)\(extra).",
                        fireDate: fire,
                        cal: cal
                    )
                }
            }

            // 4. Evening check-in — today only, and only if something's open.
            if prefs.eveningCheckIn && dayOffset == 0 {
                let remaining = unfinished.count + openTodos.count
                if remaining > 0, let fire = time(19, 30, on: day, cal: cal), fire > now {
                    let body = remaining == 1
                        ? "1 still open — there's light left today."
                        : "\(remaining) still open — there's light left today."
                    schedule(
                        center: center,
                        id: "plan-d0-evening",
                        title: "Before the sun sets",
                        body: body,
                        fireDate: fire,
                        cal: cal
                    )
                }
            }
        }
    }

    // MARK: Helpers

    /// Task ids with a completed log entry on the given day — read from
    /// the ledger directly so time-travel (`viewingDay`) never skews the
    /// schedule.
    private func completedTaskIds(on day: Date) -> Set<UUID> {
        let cal = Calendar.current
        return Set(logEntries.compactMap { entry -> UUID? in
            guard entry.entryType == .completed,
                  cal.isDate(entry.date, inSameDayAs: day) else { return nil }
            return entry.taskId
        })
    }

    private func time(_ hour: Int, _ minute: Int, on day: Date, cal: Calendar) -> Date? {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private func schedule(
        center: UNUserNotificationCenter,
        id: String,
        title: String,
        body: String,
        fireDate: Date,
        cal: Calendar
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": "home"]

        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { Log.reminders.error("schedule failed for \(id): \(error)") }
        }
    }
}
