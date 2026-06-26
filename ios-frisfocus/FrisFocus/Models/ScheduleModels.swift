//
//  ScheduleModels.swift
//  FrisFocus
//
//  The S9 agenda layer that sits on top of the existing PinSchedule /
//  TimeWindow "which days" model — without replacing any of it.
//
//  Three new ideas:
//   • `PartOfDay` — a lightweight "vibe of when" on a task (morning /
//     afternoon / evening / anytime). Orthogonal to TimeWindow.
//   • `Bucket` — a time-committed, content-open block: a category +
//     point intention with an open task slot, fulfilled by picking a
//     specific, free-logging, or just honoring the block.
//   • `DayTemplate` — a named, reusable day-shape that STAMPS its
//     elements onto a day (no live link), plus the week assignment and
//     per-day swap records that drive multi-day navigation.
//
//  Everything here is Codable so the Store can round-trip it through
//  UserDefaults alongside tasks and seasons. The witness model holds:
//  these types only describe *whether* and *what*, never grade *when*.
//

import Foundation

// MARK: - Part of day

/// A soft placement hint for a task or bucket. Distinct from a
/// `TimeWindow`: a task with a window is a hard anchor placed at its
/// real time; a task with only a `partOfDay` floats in that band as
/// "~morning"; a task with neither lives in the Anytime tray.
enum PartOfDay: String, Codable, CaseIterable, Identifiable, Hashable {
    case morning
    case afternoon
    case evening
    case anytime

    var id: String { rawValue }

    /// Title-case label for chips and pickers.
    var displayName: String {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        case .anytime:   return "Anytime"
        }
    }

    /// The "~band" label a soft-placed row shows.
    var softLabel: String {
        switch self {
        case .morning:   return "~morning"
        case .afternoon: return "~afternoon"
        case .evening:   return "~evening"
        case .anytime:   return "anytime"
        }
    }

    /// Quiet line-icon (no emoji) — a sun arc per region.
    var symbol: String {
        switch self {
        case .morning:   return "sunrise"
        case .afternoon: return "sun.max"
        case .evening:   return "sunset"
        case .anytime:   return "infinity"
        }
    }

    /// The three real bands in display order (Anytime is the tray, not
    /// a band).
    static let bands: [PartOfDay] = [.morning, .afternoon, .evening]

    /// Which band a clock time (minutes from midnight) falls into.
    /// Morning < 12:00, Afternoon 12:00–16:59, Evening ≥ 17:00.
    static func band(forMinutes minutes: Int) -> PartOfDay {
        switch minutes {
        case ..<(12 * 60):       return .morning
        case (12 * 60)..<(17 * 60): return .afternoon
        default:                 return .evening
        }
    }
}

// MARK: - Bucket

/// A time-bound container with a category + point intention but an open
/// task slot — a "time-bound mini-category." Honoring the block (doing
/// *something* in-category in the protected time) is the scored thing;
/// logging a specific inside just records *what*, it doesn't re-score.
///
/// A bucket resolves onto days exactly like a task: through its
/// `pinSchedule` (+ one-off / skip overrides). It's placed in a band by
/// its `timeWindow` when hard-timed, otherwise by its `partOfDay`.
struct Bucket: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: Category
    /// The bucket's own point value — credited once when the block is
    /// honored. This is the witnessed, scored thing.
    var pointValue: Int = 5
    /// Hard time commitment ("7–8"). When set, the bucket is placed at
    /// its real time; when nil it floats in `partOfDay`'s band.
    var timeWindow: TimeWindow? = nil
    /// Soft placement when there's no hard window.
    var partOfDay: PartOfDay = .anytime
    /// Which days this bucket appears, reusing the task day-engine.
    var pinSchedule: PinSchedule = .none
    /// One-off "do today" pin layered on top of the schedule.
    var oneOffPinDate: Date? = nil
    /// One-off "not today" suppression layered on top of the schedule.
    var skipDate: Date? = nil
    /// Specific activities that fit the block, offered in the fulfill
    /// sheet (e.g. "Strength session", "Run", "Yoga / mobility").
    var candidateTitles: [String] = []
    /// Stamp provenance — set when this bucket was placed by a template
    /// onto a specific day, so a later swap can clear exactly the
    /// template's elements while leaving manual additions alone.
    var templateStamp: TemplateStamp? = nil
    var createdAt: Date = Date()

    // Backward-compatible decode tolerant of any future-added keys.
    private enum CodingKeys: String, CodingKey {
        case id, title, category, pointValue, timeWindow, partOfDay,
             pinSchedule, oneOffPinDate, skipDate, candidateTitles,
             templateStamp, createdAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: Category,
        pointValue: Int = 5,
        timeWindow: TimeWindow? = nil,
        partOfDay: PartOfDay = .anytime,
        pinSchedule: PinSchedule = .none,
        oneOffPinDate: Date? = nil,
        skipDate: Date? = nil,
        candidateTitles: [String] = [],
        templateStamp: TemplateStamp? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.pointValue = pointValue
        self.timeWindow = timeWindow
        self.partOfDay = partOfDay
        self.pinSchedule = pinSchedule
        self.oneOffPinDate = oneOffPinDate
        self.skipDate = skipDate
        self.candidateTitles = candidateTitles
        self.templateStamp = templateStamp
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try c.decode(String.self, forKey: .title)
        self.category = try c.decode(Category.self, forKey: .category)
        self.pointValue = try c.decodeIfPresent(Int.self, forKey: .pointValue) ?? 5
        self.timeWindow = try c.decodeIfPresent(TimeWindow.self, forKey: .timeWindow)
        self.partOfDay = try c.decodeIfPresent(PartOfDay.self, forKey: .partOfDay) ?? .anytime
        self.pinSchedule = try c.decodeIfPresent(PinSchedule.self, forKey: .pinSchedule) ?? .none
        self.oneOffPinDate = try c.decodeIfPresent(Date.self, forKey: .oneOffPinDate)
        self.skipDate = try c.decodeIfPresent(Date.self, forKey: .skipDate)
        self.candidateTitles = try c.decodeIfPresent([String].self, forKey: .candidateTitles) ?? []
        self.templateStamp = try c.decodeIfPresent(TemplateStamp.self, forKey: .templateStamp)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
        try c.encode(pointValue, forKey: .pointValue)
        try c.encodeIfPresent(timeWindow, forKey: .timeWindow)
        try c.encode(partOfDay, forKey: .partOfDay)
        try c.encode(pinSchedule, forKey: .pinSchedule)
        try c.encodeIfPresent(oneOffPinDate, forKey: .oneOffPinDate)
        try c.encodeIfPresent(skipDate, forKey: .skipDate)
        try c.encode(candidateTitles, forKey: .candidateTitles)
        try c.encodeIfPresent(templateStamp, forKey: .templateStamp)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

extension Bucket {
    /// True when this bucket appears on the given calendar day. Mirrors
    /// `FFTask.isPinnedFor` exactly so days self-assemble consistently.
    func isPinnedFor(_ date: Date) -> Bool {
        let cal = Calendar.current
        if let skip = skipDate, cal.isDate(date, inSameDayAs: skip) { return false }
        if let oneOff = oneOffPinDate, cal.isDate(date, inSameDayAs: oneOff) { return true }
        switch pinSchedule {
        case .none: return false
        case .today: return cal.isDateInToday(date)
        case .singleDate(let target): return cal.isDate(date, inSameDayAs: target)
        case .daysOfWeek(let days): return days.contains(cal.component(.weekday, from: date))
        case .daily: return true
        }
    }

    /// The band this bucket sits in — derived from its time when hard-
    /// timed, otherwise its soft placement.
    var resolvedBand: PartOfDay {
        if let window = timeWindow {
            return PartOfDay.band(forMinutes: window.startMinutes)
        }
        return partOfDay == .anytime ? .anytime : partOfDay
    }
}

// MARK: - Template stamp provenance

/// Marks an element (task or bucket) as having been placed on a
/// specific day by a template. Lets a swap clear exactly a template's
/// stamped elements for that one day while preserving manual additions.
struct TemplateStamp: Codable, Equatable, Hashable {
    var templateId: UUID
    /// The day this element was stamped onto, as a `yyyy-MM-dd` key.
    var dayKey: String
}

// MARK: - Day templates

/// What kind of element a template carries.
enum TemplateElementKind: String, Codable, Equatable, Hashable {
    case task
    case bucket
}

/// One element-shape inside a `DayTemplate` — enough to materialize a
/// real task or bucket pinned to a single day when stamped.
struct DayTemplateElement: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var kind: TemplateElementKind
    var title: String
    var category: Category
    var pointValue: Int
    /// Hard time commitment, if any.
    var timeWindow: TimeWindow? = nil
    /// Soft placement when there's no window.
    var partOfDay: PartOfDay = .anytime
    /// Candidate specifics — buckets only.
    var candidateTitles: [String] = []
}

/// A named, saved day-shape: a set of element-shapes (anchors, buckets,
/// soft tasks) with their times/bands. Templates STAMP onto days — they
/// instantiate their elements as single-date items, then the link is
/// done (editing a template only changes future stampings).
struct DayTemplate: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// A one-line preview ("slow morning · long workout · family time").
    var previewLine: String = ""
    var elements: [DayTemplateElement] = []
    var createdAt: Date = Date()
}

// MARK: - Week assignment & day swaps

/// Maps one weekday (1 = Sunday … 7 = Saturday) to a template, so the
/// default week self-assembles its named shapes.
struct WeekTemplateAssignment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var weekday: Int
    var templateId: UUID
}

/// Records that a specific day has been swapped to a template,
/// remembering the template it replaced so the swap is reversible with
/// one tap ("↩ Back to [previous]").
struct DaySwapRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    /// `yyyy-MM-dd` key for the swapped day.
    var dayKey: String
    var templateId: UUID
    /// The template that was running before the swap (nil if none).
    var previousTemplateId: UUID? = nil
    var swappedAt: Date = Date()
}

// MARK: - Day-key helper

enum AgendaDayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Canonical `yyyy-MM-dd` key for a calendar day.
    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }
}
