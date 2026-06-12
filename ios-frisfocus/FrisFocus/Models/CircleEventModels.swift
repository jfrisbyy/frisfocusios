//
//  CircleEventModels.swift
//  FrisFocus
//
//  Domain data types for circle events — a member-created gathering
//  inside a circle that everyone can RSVP to, check into while it's
//  happening, and post proofs to. Pure data, Codable, no UI deps. The
//  Store owns the arrays and persists them alongside the social graph.
//
//  An event can repeat. Rather than modelling every future instance as
//  a virtual occurrence, each occurrence is its own concrete
//  `CircleEvent` sharing a `seriesId` — so per-occurrence RSVPs,
//  check-ins, and proofs fall out naturally. The Store spawns the next
//  occurrence lazily once the current one ends.
//

import Foundation

// MARK: - RSVP

/// How a member answered an event invite. The locked default is the
/// absence of an `EventRSVP` row (no answer yet).
enum EventRSVPStatus: String, Codable, CaseIterable, Equatable {
    case going
    case maybe
    case cant

    var displayName: String {
        switch self {
        case .going: return "Going"
        case .maybe: return "Maybe"
        case .cant: return "Can't"
        }
    }

    var symbolName: String {
        switch self {
        case .going: return "checkmark.circle.fill"
        case .maybe: return "questionmark.circle.fill"
        case .cant: return "xmark.circle.fill"
        }
    }
}

/// One member's answer to an event. Stored per-occurrence so a
/// recurring series' instances each keep their own tally.
struct EventRSVP: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var eventId: UUID
    var memberId: UUID
    var status: EventRSVPStatus
    var updatedAt: Date = Date()
}

// MARK: - Check-in

/// A timestamped "I'm here" for an event. Presence is derived from
/// recent check-ins so the live "who's here now" row fills in as
/// people arrive.
struct EventCheckIn: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var eventId: UUID
    var memberId: UUID
    var at: Date = Date()
}

// MARK: - Repeat

/// How often an event repeats. `weekly` carries the chosen weekdays
/// (Calendar convention, 1 = Sunday … 7 = Saturday); the other cases
/// ignore `weekdays`.
enum EventRepeatFrequency: String, Codable, CaseIterable, Equatable {
    case none, daily, weekly, monthly

    var displayName: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Every day"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

/// The full repeat configuration on an event. `frequency == .none`
/// means a one-off; otherwise the Store spawns the next occurrence
/// when the current one ends, honoring `endDate` / `endAfterCount`.
struct EventRepeat: Codable, Equatable, Hashable {
    var frequency: EventRepeatFrequency = .none
    /// Weekdays for `weekly` (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int> = []
    /// Optional hard stop — no occurrence starts after this day.
    var endDate: Date? = nil
    /// Optional count cap — at most this many occurrences in the series.
    var endAfterCount: Int? = nil

    static let none = EventRepeat(frequency: .none)

    var repeats: Bool { frequency != .none }

    /// Short human readout for cards — "Weekly · Tue, Thu".
    var summary: String {
        switch frequency {
        case .none: return "One-time"
        case .daily: return "Repeats daily"
        case .monthly: return "Repeats monthly"
        case .weekly:
            guard !weekdays.isEmpty else { return "Repeats weekly" }
            let symbols = Calendar.current.shortWeekdaySymbols
            let names = weekdays.sorted().compactMap { idx -> String? in
                let i = idx - 1
                return symbols.indices.contains(i) ? symbols[i] : nil
            }
            return "Weekly · \(names.joined(separator: ", "))"
        }
    }
}

// MARK: - CircleEvent

/// A gathering inside a circle. Any member can create one. Carries the
/// when/where, an optional linked circle task, an optional repeat
/// schedule, and a reminder lead time. RSVPs, check-ins, and proofs
/// reference it by `id`.
struct CircleEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var circleId: UUID
    /// Shared across every occurrence spawned from a repeating event so
    /// the series can be found as a whole. A one-off uses its own id.
    var seriesId: UUID = UUID()
    var creatorId: UUID
    var title: String
    var details: String?
    var location: String?
    var startAt: Date
    /// Optional explicit end. When nil, the event is treated as a
    /// 2-hour window for the "happening now" highlight and check-in.
    var endAt: Date?
    /// Optional bridge to a shared circle task — finishing the run can
    /// count in the circle.
    var linkedCircleTaskId: UUID?
    var repeatRule: EventRepeat = .none
    /// Minutes before `startAt` to remind RSVP'd members. 0 = no reminder.
    var reminderMinutes: Int = 30
    var createdAt: Date = Date()

    // Tolerant decoding so events persisted before any field landed
    // still hydrate — missing keys fall back to the property defaults.
    private enum CodingKeys: String, CodingKey {
        case id, circleId, seriesId, creatorId, title, details, location
        case startAt, endAt, linkedCircleTaskId, repeatRule, reminderMinutes, createdAt
    }

    init(
        id: UUID = UUID(),
        circleId: UUID,
        seriesId: UUID = UUID(),
        creatorId: UUID,
        title: String,
        details: String? = nil,
        location: String? = nil,
        startAt: Date,
        endAt: Date? = nil,
        linkedCircleTaskId: UUID? = nil,
        repeatRule: EventRepeat = .none,
        reminderMinutes: Int = 30,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.circleId = circleId
        self.seriesId = seriesId
        self.creatorId = creatorId
        self.title = title
        self.details = details
        self.location = location
        self.startAt = startAt
        self.endAt = endAt
        self.linkedCircleTaskId = linkedCircleTaskId
        self.repeatRule = repeatRule
        self.reminderMinutes = reminderMinutes
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.circleId = try c.decode(UUID.self, forKey: .circleId)
        self.seriesId = try c.decodeIfPresent(UUID.self, forKey: .seriesId) ?? self.id
        self.creatorId = try c.decode(UUID.self, forKey: .creatorId)
        self.title = try c.decode(String.self, forKey: .title)
        self.details = try c.decodeIfPresent(String.self, forKey: .details)
        self.location = try c.decodeIfPresent(String.self, forKey: .location)
        self.startAt = try c.decode(Date.self, forKey: .startAt)
        self.endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        self.linkedCircleTaskId = try c.decodeIfPresent(UUID.self, forKey: .linkedCircleTaskId)
        self.repeatRule = try c.decodeIfPresent(EventRepeat.self, forKey: .repeatRule) ?? .none
        self.reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? 30
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(circleId, forKey: .circleId)
        try c.encode(seriesId, forKey: .seriesId)
        try c.encode(creatorId, forKey: .creatorId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encode(startAt, forKey: .startAt)
        try c.encodeIfPresent(endAt, forKey: .endAt)
        try c.encodeIfPresent(linkedCircleTaskId, forKey: .linkedCircleTaskId)
        try c.encode(repeatRule, forKey: .repeatRule)
        try c.encode(reminderMinutes, forKey: .reminderMinutes)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

extension CircleEvent {
    /// The effective end of the event window — explicit `endAt` when
    /// set, otherwise two hours after the start.
    var effectiveEnd: Date {
        endAt ?? startAt.addingTimeInterval(2 * 60 * 60)
    }

    /// True while the event is live — between its start and effective
    /// end. Drives the "Happening now" highlight and the check-in CTA.
    func isHappeningNow(at now: Date = Date()) -> Bool {
        now >= startAt && now <= effectiveEnd
    }

    /// True once the event's window has fully passed.
    func isPast(at now: Date = Date()) -> Bool {
        now > effectiveEnd
    }

    /// True before the event starts.
    func isUpcoming(at now: Date = Date()) -> Bool {
        now < startAt
    }

    /// When early check-in opens — one hour before the start.
    var checkInOpensAt: Date {
        startAt.addingTimeInterval(-60 * 60)
    }

    /// True while check-in is allowed: from one hour before the start
    /// through the event's effective end. Drives the check-in bar on
    /// the event page (the "starting soon" early window + live window).
    func isCheckInOpen(at now: Date = Date()) -> Bool {
        now >= checkInOpensAt && now <= effectiveEnd
    }
}
