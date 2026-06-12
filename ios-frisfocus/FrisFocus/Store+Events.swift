//
//  Store+Events.swift
//  FrisFocus
//
//  Circle events: creation, RSVP, live check-in, event proofs, the
//  cross-circle "Upcoming" glance, recurrence spawning, and reminder
//  scheduling. Events are concrete per-occurrence rows sharing a
//  `seriesId`; the next occurrence of a repeating event is spawned
//  lazily once the current one ends so per-occurrence RSVPs, check-ins,
//  and proofs fall out for free.
//

import Foundation
import UserNotifications

extension Store {
    // MARK: - Queries

    /// Every event in a circle, sorted soonest-first.
    func events(forCircleId circleId: UUID) -> [CircleEvent] {
        circleEvents
            .filter { $0.circleId == circleId }
            .sorted { $0.startAt < $1.startAt }
    }

    /// Upcoming + currently-happening events in a circle, soonest first.
    func upcomingEvents(forCircleId circleId: UUID, now: Date = Date()) -> [CircleEvent] {
        events(forCircleId: circleId)
            .filter { !$0.isPast(at: now) }
            .sorted { $0.startAt < $1.startAt }
    }

    /// Finished events in a circle, most-recent first.
    func pastEvents(forCircleId circleId: UUID, now: Date = Date()) -> [CircleEvent] {
        events(forCircleId: circleId)
            .filter { $0.isPast(at: now) }
            .sorted { $0.startAt > $1.startAt }
    }

    /// An event by id.
    func event(by id: UUID) -> CircleEvent? {
        circleEvents.first { $0.id == id }
    }

    /// Circles the current user belongs to.
    private var myCircleIds: Set<UUID> {
        Set(circles.filter { $0.memberIds.contains(currentUserId) }.map(\.id))
    }

    /// The user's next events across every circle they're in — upcoming
    /// or happening now, soonest first. Drives the homescreen glance.
    /// Events the user said "Can't" to are dropped so the glance stays
    /// about things they plan to attend.
    func myUpcomingEvents(limit: Int = 3, now: Date = Date()) -> [CircleEvent] {
        let mine = myCircleIds
        return circleEvents
            .filter { mine.contains($0.circleId) && !$0.isPast(at: now) }
            .filter { myRSVPStatus(forEventId: $0.id) != .cant }
            .sorted { $0.startAt < $1.startAt }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Create / edit / delete

    /// Create an event in a circle. Returns the new event. When a
    /// repeat rule is set, this is the first concrete occurrence of the
    /// series; later occurrences are spawned lazily as it ends.
    @discardableResult
    func createEvent(
        circleId: UUID,
        title: String,
        details: String?,
        location: String?,
        startAt: Date,
        endAt: Date?,
        linkedCircleTaskId: UUID?,
        repeatRule: EventRepeat,
        reminderMinutes: Int
    ) -> CircleEvent {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = CircleEvent(
            circleId: circleId,
            creatorId: currentUserId,
            title: trimmedTitle.isEmpty ? "Event" : trimmedTitle,
            details: details?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            location: location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            startAt: startAt,
            endAt: endAt,
            linkedCircleTaskId: linkedCircleTaskId,
            repeatRule: repeatRule,
            reminderMinutes: reminderMinutes
        )
        circleEvents.append(event)
        // The creator is presumed going.
        setRSVP(eventId: event.id, status: .going)
        persistAll()
        scheduleReminder(for: event)
        return event
    }

    /// Spin up a brand-new shared circle task and return its id, so an
    /// event can be linked to a task that didn't exist yet.
    @discardableResult
    func addCircleTask(circleId: UUID, title: String, pointValue: Int?) -> UUID? {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }) else { return nil }
        let task = CircleTask(title: title, pointValue: pointValue, linkedPersonalTaskId: nil)
        circles[ci].tasks.append(task)
        persistAll()
        return task.id
    }

    /// Remove an event and everything attached to it (RSVPs, check-ins).
    /// Event proofs already posted to the circle story are left in place.
    func deleteEvent(_ eventId: UUID) {
        circleEvents.removeAll { $0.id == eventId }
        eventRSVPs.removeAll { $0.eventId == eventId }
        eventCheckIns.removeAll { $0.eventId == eventId }
        cancelReminder(eventId: eventId)
        persistAll()
    }

    /// True when the current user may edit/delete an event — the
    /// creator or anyone who can manage the circle (owner/admin).
    func canManageEvent(_ event: CircleEvent) -> Bool {
        if event.creatorId == currentUserId { return true }
        if let circle = circle(by: event.circleId) { return canManageTasks(in: circle) }
        return false
    }

    // MARK: - RSVP

    /// The current user's RSVP to an event, if answered.
    func myRSVPStatus(forEventId eventId: UUID) -> EventRSVPStatus? {
        rsvpStatus(eventId: eventId, memberId: currentUserId)
    }

    /// A member's RSVP to an event, if answered.
    func rsvpStatus(eventId: UUID, memberId: UUID) -> EventRSVPStatus? {
        eventRSVPs.first { $0.eventId == eventId && $0.memberId == memberId }?.status
    }

    /// Set (or toggle off) the current user's RSVP. Tapping the
    /// already-selected status clears the answer.
    func setRSVP(eventId: UUID, status: EventRSVPStatus) {
        if let idx = eventRSVPs.firstIndex(where: { $0.eventId == eventId && $0.memberId == currentUserId }) {
            if eventRSVPs[idx].status == status {
                eventRSVPs.remove(at: idx)
            } else {
                eventRSVPs[idx].status = status
                eventRSVPs[idx].updatedAt = Date()
            }
        } else {
            eventRSVPs.append(EventRSVP(eventId: eventId, memberId: currentUserId, status: status))
        }
        persistAll()
        // A fresh "Can't" should stop the reminder; switching back
        // re-arms it.
        if let event = event(by: eventId) {
            if myRSVPStatus(forEventId: eventId) == .cant {
                cancelReminder(eventId: eventId)
            } else {
                scheduleReminder(for: event)
            }
        }
    }

    /// Members who answered a given way for an event.
    func rsvpMembers(eventId: UUID, status: EventRSVPStatus) -> [UUID] {
        eventRSVPs.filter { $0.eventId == eventId && $0.status == status }.map(\.memberId)
    }

    /// Count of a given RSVP answer for an event.
    func rsvpCount(eventId: UUID, status: EventRSVPStatus) -> Int {
        eventRSVPs.filter { $0.eventId == eventId && $0.status == status }.count
    }

    // MARK: - Check-in

    /// How long a check-in counts as "here right now" before it fades.
    private static let presenceWindow: TimeInterval = 20 * 60

    /// True when the current user has an active check-in for the event.
    func isCheckedIn(eventId: UUID, now: Date = Date()) -> Bool {
        eventCheckIns.contains {
            $0.eventId == eventId
                && $0.memberId == currentUserId
                && now.timeIntervalSince($0.at) < Self.presenceWindow
        }
    }

    /// Stamp the current user present at an event. Idempotent within the
    /// presence window. Only meaningful while the event is happening.
    func checkIn(eventId: UUID) {
        guard !isCheckedIn(eventId: eventId) else { return }
        eventCheckIns.append(EventCheckIn(eventId: eventId, memberId: currentUserId))
        persistAll()
    }

    /// Member ids checked in within the presence window, most-recent
    /// arrivals last. Powers the live "who's here now" row.
    func presentMembers(eventId: UUID, now: Date = Date()) -> [UUID] {
        var seen: Set<UUID> = []
        var ordered: [UUID] = []
        for checkIn in eventCheckIns
            .filter({ $0.eventId == eventId && now.timeIntervalSince($0.at) < Self.presenceWindow })
            .sorted(by: { $0.at < $1.at }) {
            if seen.insert(checkIn.memberId).inserted { ordered.append(checkIn.memberId) }
        }
        return ordered
    }

    /// Everyone who ever checked into the event (for the "who showed up"
    /// lookback on a finished event), in arrival order.
    func attendees(eventId: UUID) -> [UUID] {
        var seen: Set<UUID> = []
        var ordered: [UUID] = []
        for checkIn in eventCheckIns.filter({ $0.eventId == eventId }).sorted(by: { $0.at < $1.at }) {
            if seen.insert(checkIn.memberId).inserted { ordered.append(checkIn.memberId) }
        }
        return ordered
    }

    // MARK: - Event proofs

    /// Proofs posted to a specific event — its own archive, pulled by
    /// `eventId` regardless of what's still live in the circle story.
    /// Newest first.
    func eventProofs(eventId: UUID) -> [StoryPost] {
        storyPosts
            .filter { $0.eventId == eventId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Count of proofs filed under an event.
    func eventProofCount(eventId: UUID) -> Int {
        storyPosts.filter { $0.eventId == eventId }.count
    }

    // MARK: - Recurrence

    /// Lazily spawn the next occurrence of any repeating series whose
    /// latest occurrence has ended, honoring the end date / count caps.
    /// Cheap and idempotent — safe to call on load and when opening a
    /// circle.
    func refreshRecurringEvents(now: Date = Date()) {
        var added: [CircleEvent] = []
        let bySeries = Dictionary(grouping: circleEvents, by: { $0.seriesId })
        for (_, occurrences) in bySeries {
            guard let template = occurrences.first(where: { $0.repeatRule.repeats }),
                  let latest = occurrences.max(by: { $0.startAt < $1.startAt }) else { continue }
            // Only spawn once the latest occurrence is over and there's
            // no future one already waiting.
            guard latest.isPast(at: now) else { continue }
            let rule = template.repeatRule
            if let cap = rule.endAfterCount, occurrences.count >= cap { continue }
            guard let nextStart = Self.nextOccurrence(after: latest.startAt, rule: rule, now: now) else { continue }
            if let end = rule.endDate, nextStart > end { continue }

            let duration = latest.endAt.map { $0.timeIntervalSince(latest.startAt) }
            var next = template
            next.id = UUID()
            next.startAt = nextStart
            next.endAt = duration.map { nextStart.addingTimeInterval($0) }
            next.createdAt = now
            added.append(next)
        }
        guard !added.isEmpty else { return }
        circleEvents.append(contentsOf: added)
        persistAll()
        for event in added { scheduleReminder(for: event) }
    }

    /// Next start date strictly after `previous`, respecting the rule.
    /// Walks forward so a long-dormant series catches up to the next
    /// future slot rather than scheduling something already past.
    private static func nextOccurrence(after previous: Date, rule: EventRepeat, now: Date) -> Date? {
        let cal = Calendar.current
        func advance(_ date: Date) -> Date? {
            switch rule.frequency {
            case .none: return nil
            case .daily: return cal.date(byAdding: .day, value: 1, to: date)
            case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
            case .weekly:
                // Step a day at a time until we land on a selected weekday.
                let days = rule.weekdays.isEmpty ? [cal.component(.weekday, from: previous)] : Array(rule.weekdays)
                var cursor = cal.date(byAdding: .day, value: 1, to: date)
                for _ in 0..<14 {
                    guard let c = cursor else { return nil }
                    if days.contains(cal.component(.weekday, from: c)) { return c }
                    cursor = cal.date(byAdding: .day, value: 1, to: c)
                }
                return cursor
            }
        }
        var candidate = advance(previous)
        // Catch up past any slots that are already gone.
        var guardCount = 0
        while let c = candidate, c <= now, guardCount < 400 {
            candidate = advance(c)
            guardCount += 1
        }
        return candidate
    }

    // MARK: - Reminders

    private func reminderIdentifier(eventId: UUID) -> String { "event-reminder-\(eventId.uuidString)" }

    /// Schedule a local pre-event reminder for the current user, unless
    /// they declined or the lead time has already passed. Replaces any
    /// existing reminder for the same event.
    func scheduleReminder(for event: CircleEvent, now: Date = Date()) {
        cancelReminder(eventId: event.id)
        guard event.reminderMinutes > 0 else { return }
        guard myRSVPStatus(forEventId: event.id) != .cant else { return }
        let fireDate = event.startAt.addingTimeInterval(-Double(event.reminderMinutes) * 60)
        guard fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = circle(by: event.circleId)?.name ?? "Circle event"
        let lead = event.reminderMinutes >= 60
            ? "soon"
            : "in \(event.reminderMinutes) min"
        content.body = "\(event.title) starts \(lead)"
        content.sound = .default
        content.userInfo = ["route": "circle", "circleId": event.circleId.uuidString]

        let interval = max(1, fireDate.timeIntervalSince(now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminderIdentifier(eventId: event.id),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[Events] reminder schedule failed: \(error)") }
        }
    }

    /// Drop any pending reminder for an event.
    func cancelReminder(eventId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderIdentifier(eventId: eventId)])
    }
}

private extension String {
    /// nil when the trimmed string is empty, the value otherwise.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
