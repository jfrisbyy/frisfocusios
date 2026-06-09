//
//  Store+Cadence.swift
//  FrisFocus
//
//  The Esengo link — FrisFocus's scoring side of the Cadence bridge.
//  FrisFocus reads Cadence's honest outcome events and credits points
//  on its own; Cadence never learns of points, seasons, or tasks.
//
//  Everything here is gated on `cadenceConnected` so a FrisFocus-only
//  user never sees a trace of it. Credit is idempotent (one credit per
//  link per local day, plus a consumed-event-id backstop) and honest
//  (only `verified` events score; unknown nights stay neutral).
//

import Foundation

extension Store {

    // MARK: - Derived link lists

    /// Linked routines you launch-and-run that are scheduled for today.
    /// These appear in Today's Plan. Empty unless Cadence is connected.
    var todaysCadenceLinks: [CadenceLink] {
        guard cadenceConnected else { return [] }
        let today = Date()
        return cadenceLinks.filter { $0.type == .launchRun && $0.recurrence.matches(today) }
    }

    /// Passive-outcome links (sleep / focus / wind-down). These live in
    /// the Season view, never in Today's Plan.
    var passiveCadenceLinks: [CadenceLink] {
        guard cadenceConnected else { return [] }
        return cadenceLinks.filter { $0.type == .passiveOutcome }
    }

    /// Passive-outcome links feeding a given season (or unseasoned).
    func passiveCadenceLinks(forSeason seasonId: UUID) -> [CadenceLink] {
        passiveCadenceLinks.filter { $0.seasonId == nil || $0.seasonId == seasonId }
    }

    // MARK: - Link CRUD + opt-in

    func addCadenceLink(_ link: CadenceLink) {
        cadenceLinks.append(link)
        persistAll()
    }

    /// Remove a link. Any points it already earned stay in the log —
    /// switching the link off never erases honest history.
    func removeCadenceLink(_ link: CadenceLink) {
        cadenceLinks.removeAll { $0.id == link.id }
        persistAll()
    }

    /// Opt in / out of the link. Connecting also clears the one-time
    /// invite so it doesn't reappear.
    func setCadenceConnected(_ connected: Bool) {
        cadenceConnected = connected
        if connected { cadenceInviteDismissed = true }
        persistAll()
    }

    func dismissCadenceInvite() {
        cadenceInviteDismissed = true
        persistAll()
    }

    func setCadenceSurfacePointsSocially(_ on: Bool) {
        cadenceSurfacePointsSocially = on
        persistAll()
    }

    // MARK: - Earned state (launch-run)

    /// Today's `.completed` credit entry for a launch-run link, if any.
    func cadenceEarnedEntryToday(linkId: UUID) -> LogEntry? {
        let cal = Calendar.current
        return logEntries.first { entry in
            entry.cadenceLinkId == linkId
                && entry.entryType == .completed
                && cal.isDateInToday(entry.date)
        }
    }

    func isCadenceLinkEarnedToday(_ link: CadenceLink) -> Bool {
        cadenceEarnedEntryToday(linkId: link.id) != nil
    }

    /// Compact time the link was earned today ("7:12a"), for the row's
    /// "✓ earned from Cadence · {time}" subline.
    func cadenceEarnedTimeLabel(_ link: CadenceLink) -> String? {
        guard let entry = cadenceEarnedEntryToday(linkId: link.id) else { return nil }
        return Store.compactTimeLabel(entry.date)
    }

    func cadenceEarnedPoints(_ link: CadenceLink) -> Int? {
        cadenceEarnedEntryToday(linkId: link.id)?.pointsEarned
    }

    // MARK: - Fulfilled state (passive)

    /// The most recent fill for a passive link within the last ~18h, so
    /// a sleep summary recorded this morning still reads as "last night".
    func latestCadenceFulfillment(for link: CadenceLink) -> CadenceOutcomeFulfillment? {
        cadenceOutcomeFulfillments
            .filter { $0.linkId == link.id }
            .sorted { $0.date > $1.date }
            .first { Date().timeIntervalSince($0.date) <= 18 * 3600 }
    }

    func isPassiveOutcomeFulfilled(_ link: CadenceLink) -> Bool {
        latestCadenceFulfillment(for: link) != nil
    }

    // MARK: - Privacy

    /// Today's score as the friend-facing layer would see it: Cadence
    /// sleep/focus points are excluded unless the user opted in to
    /// surface them socially. (Their own Season total always includes
    /// them via `todayScore`.)
    var socialVisibleTodayScore: Int {
        let cal = Calendar.current
        return logEntries
            .filter { cal.isDateInToday($0.date) }
            .filter { cadenceSurfacePointsSocially || $0.cadenceLinkId == nil }
            .map { $0.pointsEarned }
            .reduce(0, +)
    }

    // MARK: - Credit (the read side of the seam)

    /// Credit a launch-run routine completion. One credit per link per
    /// local day. No social signal — Cadence points are private by
    /// default (per the privacy decision).
    @discardableResult
    func creditCadenceRoutine(link: CadenceLink, occurredAt: Date) -> Bool {
        let cal = Calendar.current
        let already = logEntries.contains { entry in
            entry.cadenceLinkId == link.id
                && entry.entryType == .completed
                && cal.isDate(entry.date, inSameDayAs: occurredAt)
        }
        guard !already else { return false }

        let pts = min(max(link.points, 0), CadenceLink.pointCeiling)
        logEntries.append(LogEntry(
            date: occurredAt,
            taskId: nil,
            todoId: nil,
            cadenceLinkId: link.id,
            pointsEarned: pts,
            entryType: .completed
        ))
        persistAll()
        return true
    }

    /// Credit a passive outcome (sleep / focus / wind-down). Writes both
    /// the scoring `LogEntry` and a `CadenceOutcomeFulfillment` carrying
    /// the human summary for the Season row. One fill per link per day.
    @discardableResult
    func creditCadenceOutcome(link: CadenceLink, occurredAt: Date, summary: String) -> Bool {
        let cal = Calendar.current
        let already = cadenceOutcomeFulfillments.contains { fill in
            fill.linkId == link.id && cal.isDate(fill.date, inSameDayAs: occurredAt)
        }
        guard !already else { return false }

        let pts = min(max(link.points, 0), CadenceLink.pointCeiling)
        logEntries.append(LogEntry(
            date: occurredAt,
            taskId: nil,
            todoId: nil,
            cadenceLinkId: link.id,
            pointsEarned: pts,
            entryType: .completed
        ))
        cadenceOutcomeFulfillments.append(CadenceOutcomeFulfillment(
            linkId: link.id,
            date: occurredAt,
            summary: summary,
            points: pts
        ))
        persistAll()
        return true
    }

    /// Apply one outcome event idempotently and return whether it should
    /// be marked consumed in the backend. Verified-false events are
    /// recorded (consumed) but never scored — honest tracking.
    @discardableResult
    func applyCadenceEvent(_ event: CadenceOutcomeEventRow) -> Bool {
        if consumedCadenceEventIds.contains(event.id) { return true }
        let occurredAt = Store.parseCadenceDate(event.occurredAt) ?? Date()

        defer {
            consumedCadenceEventIds.insert(event.id)
            persistAll()
        }

        // Honest tracking: an unknown / unverified night neither awards
        // nor penalises — it stays neutral.
        guard event.verified else { return true }

        switch event.eventType {
        case "routine_completed":
            if let rid = event.routineId,
               let link = cadenceLinks.first(where: { $0.type == .launchRun && $0.routineId == rid }) {
                creditCadenceRoutine(link: link, occurredAt: occurredAt)
            }

        case "sleep_summary":
            let minutes = event.metrics.durationMinutes ?? 0
            let verdictOK = (event.metrics.verdict ?? "good").lowercased() != "unknown"
            guard verdictOK else { break }
            for link in cadenceLinks where link.type == .passiveOutcome && link.outcomeKind == .sleepDuration {
                let needed = (link.threshold ?? CadenceOutcomeKind.sleepDuration.defaultThreshold) * 60
                if minutes >= needed {
                    creditCadenceOutcome(link: link, occurredAt: occurredAt, summary: Store.sleepSummary(minutes: minutes))
                }
            }

        case "focus_block":
            let minutes = event.metrics.minutes ?? 0
            for link in cadenceLinks where link.type == .passiveOutcome && link.outcomeKind == .focusBlock {
                let needed = link.threshold ?? CadenceOutcomeKind.focusBlock.defaultThreshold
                if minutes >= needed {
                    creditCadenceOutcome(link: link, occurredAt: occurredAt, summary: Store.focusSummary(minutes: minutes))
                }
            }

        case "wind_down_timing":
            if let completed = Store.minutesFromMidnight(event.metrics.completedAtLocal) {
                for link in cadenceLinks where link.type == .passiveOutcome && link.outcomeKind == .windDownTiming {
                    let by = link.threshold ?? CadenceOutcomeKind.windDownTiming.defaultThreshold
                    if completed <= by {
                        creditCadenceOutcome(link: link, occurredAt: occurredAt, summary: Store.windDownSummary(minutes: completed))
                    }
                }
            }

        default:
            break
        }
        return true
    }

    // MARK: - Formatting helpers

    static func parseCadenceDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Minutes-from-midnight (local) from an ISO timestamp or "HH:mm".
    static func minutesFromMidnight(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = parseCadenceDate(raw) {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        let parts = raw.split(separator: ":")
        if parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            return Double(h * 60 + m)
        }
        return nil
    }

    /// "7:12a" / "9:45p" — compact, matching the reference earned subline.
    static func compactTimeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        let hm = f.string(from: date)
        let suffix = Calendar.current.component(.hour, from: date) < 12 ? "a" : "p"
        return hm + suffix
    }

    static func sleepSummary(minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return String(format: "%dh %02dm last night", h, m)
    }

    static func focusSummary(minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        if h > 0 { return String(format: "%dh %02dm focused today", h, m) }
        return "\(Int(minutes))m focused today"
    }

    static func windDownSummary(minutes: Double) -> String {
        "by \(CadenceOutcomeKind.clockLabel(minutes: minutes))"
    }

    #if DEBUG
    /// Developer-only: synthesize tonight's verified outcomes locally so
    /// the earned / fulfilled states are reviewable in the simulator
    /// without a live Cadence app. Production credit flows from real
    /// `cadence_outcome_events` via `applyCadenceEvent`.
    func debugSimulateCadenceOutcomes() {
        let now = Date()
        for link in cadenceLinks {
            switch link.type {
            case .launchRun:
                creditCadenceRoutine(link: link, occurredAt: now)
            case .passiveOutcome:
                guard let kind = link.outcomeKind else { continue }
                let summary: String
                switch kind {
                case .sleepDuration:
                    summary = Store.sleepSummary(minutes: (link.threshold ?? 6) * 60 + 40)
                case .focusBlock:
                    summary = Store.focusSummary(minutes: (link.threshold ?? 60) + 5)
                case .windDownTiming:
                    summary = Store.windDownSummary(minutes: (link.threshold ?? 23 * 60) - 12)
                }
                creditCadenceOutcome(link: link, occurredAt: now, summary: summary)
            }
        }
    }
    #endif
}
