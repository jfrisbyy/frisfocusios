//
//  GoldenHourModels.swift
//  FrisFocus
//
//  Golden Hour is its own ephemeral module — fully separate from circle
//  stories and proof threads. Once a day, every member of a circle is
//  pinged at the exact same instant, has a strict 5-minute window to
//  capture what they're working on, and 1 hour from the fire moment to
//  view the shared wall. Then the media is deleted for real; only the
//  attendance residue (who made it, streaks) survives.
//
//  Everything here is deterministic on purpose: every member's device
//  computes the *same* fire instant for a given circle + day with no
//  server cron — which is what makes the synchronized local
//  notifications line up across the whole group.
//

import Foundation

// MARK: - Scheduling mode

/// How a circle decides when its daily Golden Hour fires.
nonisolated enum GoldenHourMode: String, Codable, Sendable, CaseIterable {
    /// The circle picked one fixed daily moment.
    case fixed
    /// A rotating member secretly picks today's time; if they forget,
    /// the deterministic surprise time kicks in so no day is skipped.
    case turns
    /// A pseudo-random moment within working hours (9 AM–6 PM), derived
    /// from the circle id + day so every device lands on the same instant.
    case surprise

    var title: String {
        switch self {
        case .fixed: return "Same time daily"
        case .turns: return "Members take turns"
        case .surprise: return "Surprise"
        }
    }

    var blurb: String {
        switch self {
        case .fixed: return "The circle picks one moment — same time, every day."
        case .turns: return "Each day one member secretly sets the time. Forget, and a surprise time fires instead."
        case .surprise: return "A random moment between 9 AM and 6 PM. Nobody knows when."
        }
    }

    var icon: String {
        switch self {
        case .fixed: return "clock.fill"
        case .turns: return "person.2.fill"
        case .surprise: return "sparkles"
        }
    }
}

// MARK: - Settings

/// One circle's Golden Hour configuration (mirrors `golden_hour_settings`).
struct GoldenHourSettings: Identifiable, Equatable {
    let circleId: UUID
    var enabled: Bool
    var mode: GoldenHourMode
    /// Minutes from local midnight (fixed mode), in `timeZone`.
    var fireMinute: Int
    /// IANA identifier of the timezone the schedule is anchored to —
    /// captured from whoever configured it, so the instant is identical
    /// for every member no matter where they are.
    var timeZone: String

    var id: UUID { circleId }

    static func defaults(circleId: UUID) -> GoldenHourSettings {
        GoldenHourSettings(
            circleId: circleId,
            enabled: false,
            mode: .surprise,
            fireMinute: 20 * 60,
            timeZone: TimeZone.current.identifier
        )
    }
}

// MARK: - Pick (turns mode)

/// Today's secret time chosen by the rotating picker (mirrors
/// `golden_hour_picks`). Secret from humans — the UI never shows other
/// members the time — but readable by member devices so everyone can
/// schedule the same synchronized alert.
struct GoldenHourPick: Equatable {
    let circleId: UUID
    let day: String
    let pickerId: String
    let fireMinute: Int
}

// MARK: - Post

/// One member's capture for one day (mirrors `golden_hour_posts`).
/// `mediaPath` goes nil after the sweep deletes the bytes — the row
/// survives as the attendance/streak residue.
struct GoldenHourPost: Identifiable, Hashable {
    let id: UUID
    let circleId: UUID
    let day: String
    let userId: String
    let mediaPath: String?
    let mediaKind: ProofMediaKind
    let mediaDuration: Double?
    let firedAt: Date
    let postedAt: Date
    let secondsToSpare: Int?
}

// MARK: - Phase

/// Where one circle's daily moment sits right now.
nonisolated enum GoldenHourPhase: Equatable, Sendable {
    /// Today's moment hasn't fired yet. Nothing surfaces.
    case upcoming
    /// The 5-minute capture window is open.
    case live
    /// Captures are locked; the wall is viewable until the hour ends.
    case viewing
    /// The hour has passed — only the attendance residue remains.
    case over
}

// MARK: - Moment

/// One concrete fire instant for one circle + day, with the derived
/// capture/viewing deadlines. All clocks tick from `fireAt`.
struct GoldenHourMoment: Equatable {
    let circleId: UUID
    let day: String
    let fireAt: Date

    var captureClosesAt: Date { fireAt.addingTimeInterval(GoldenHourSchedule.captureWindow) }
    var wallClosesAt: Date { fireAt.addingTimeInterval(GoldenHourSchedule.viewingWindow) }

    func phase(at now: Date) -> GoldenHourPhase {
        if now < fireAt { return .upcoming }
        if now < captureClosesAt { return .live }
        if now < wallClosesAt { return .viewing }
        return .over
    }
}

// MARK: - Schedule math

nonisolated enum GoldenHourSchedule {
    /// Strict capture window: 5 minutes from the fire instant.
    static let captureWindow: TimeInterval = 5 * 60
    /// The wall stays viewable for 1 hour from the fire instant.
    static let viewingWindow: TimeInterval = 60 * 60

    /// Surprise window bounds, minutes from midnight (9 AM ..< 6 PM).
    static let surpriseStartMinute = 9 * 60
    static let surpriseEndMinute = 18 * 60

    /// The same `yyyy-MM-dd` key every member computes for a given
    /// instant, anchored to the circle's schedule timezone.
    static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// The absolute instant `minute` minutes after midnight of `day` in
    /// `timeZone` — identical on every device.
    static func fireDate(day: String, minute: Int, timeZone: TimeZone) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let midnight = f.date(from: day) else { return nil }
        return midnight.addingTimeInterval(TimeInterval(minute * 60))
    }

    /// Deterministic FNV-1a hash of circle + day → a surprise minute in
    /// working hours. Every member's device computes the same value.
    static func surpriseMinute(circleId: UUID, day: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(circleId.uuidString.lowercased())#\(day)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let span = UInt64(surpriseEndMinute - surpriseStartMinute)
        return surpriseStartMinute + Int(hash % span)
    }

    /// Turns-mode rotation: a stable index into the sorted member ids,
    /// advancing by one each day. Deterministic so the whole circle
    /// agrees on whose turn it is without any coordination.
    static func pickerIndex(day: String, timeZone: TimeZone, memberCount: Int) -> Int? {
        guard memberCount > 0,
              let midnight = fireDate(day: day, minute: 0, timeZone: timeZone) else { return nil }
        let dayNumber = Int(midnight.timeIntervalSince1970 / 86_400)
        return ((dayNumber % memberCount) + memberCount) % memberCount
    }

    /// "m:ss" countdown text, clamped at zero.
    static func countdownString(until target: Date, from now: Date) -> String {
        let remaining = max(0, Int(target.timeIntervalSince(now).rounded(.down)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    /// "mm:ss" wall-timer text for longer spans (up to the hour).
    static func wallCountdownString(until target: Date, from now: Date) -> String {
        let remaining = max(0, Int(target.timeIntervalSince(now).rounded(.down)))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
}
