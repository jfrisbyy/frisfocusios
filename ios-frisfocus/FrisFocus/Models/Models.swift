//
//  Models.swift
//  FrisFocus
//
//  Domain data types for the FrisFocus Life OS — Seasons, Tasks (FFTask),
//  To-dos, LogEntries, and Notes, plus the small supporting enums.
//  Every type is Codable so the Store can round-trip the whole graph
//  through JSON in UserDefaults.
//

import Foundation

// MARK: - Enums

enum Tier: String, Codable, CaseIterable {
    case must, should, could
}

enum Category: String, Codable, CaseIterable {
    case spiritual, fitness, health, work, creative, apartment

    var displayName: String {
        switch self {
        case .spiritual: return "Spiritual"
        case .fitness: return "Fitness"
        case .health: return "Health"
        case .work: return "Work"
        case .creative: return "Creative"
        case .apartment: return "Apartment"
        }
    }

    /// Hex string for the category dot used in task metadata lines.
    var hexColor: String {
        switch self {
        case .spiritual: return "#7F77DD"
        case .fitness: return "#D85A30"
        case .health: return "#639922"
        case .work: return "#185FA5"
        case .creative: return "#993556"
        case .apartment: return "#888780"
        }
    }
}

enum CategoryTier: String, Codable {
    case primary, support, quiet
}

enum SeasonVibe: String, Codable {
    case warmForest, coolDawn, desertDusk, quietShore, deepNight, alpine
}

enum MilestoneStatus: String, Codable {
    case cleared, inMotion, upcoming
}

enum LogEntryType: String, Codable {
    case completed, skipped, penalty, boosterBonus, trainBonus
}

// MARK: - Booster Rule

/// Period over which a booster's completions are counted.
/// `.week` reuses the app's existing weekly scoring window;
/// `.month` uses the current calendar month.
enum BoosterPeriod: String, Codable, CaseIterable, Equatable {
    case week, month

    var displayName: String {
        switch self {
        case .week:  return "week"
        case .month: return "month"
        }
    }
}

/// An optional consistency rule attached to an `FFTask`. Completing the
/// task at least `timesRequired` times within the current `period`
/// awards `bonusPoints` on top of per-completion points. Unlike a
/// streak, a missed day doesn't reset anything — only the count
/// against the target matters.
struct BoosterRule: Codable, Equatable {
    var enabled: Bool = false
    var timesRequired: Int = 3
    var period: BoosterPeriod = .week
    var bonusPoints: Int = 10
}

// MARK: - Penalty Rule (task-attached weekly limit)

/// Direction of the weekly-limit test. `.moreThan` penalises
/// over-doing a task (e.g. "don't snack more than twice this week");
/// `.lessThan` penalises under-doing it (e.g. "hit the gym at least
/// three times this week").
enum PenaltyCondition: String, Codable, CaseIterable, Equatable {
    case moreThan, lessThan

    var phrase: String {
        switch self {
        case .moreThan: return "more than"
        case .lessThan: return "less than"
        }
    }

    var shortPhrase: String {
        switch self {
        case .moreThan: return "≤"
        case .lessThan: return "≥"
        }
    }
}

/// An optional weekly-limit rule attached to an `FFTask`. If the
/// task's completion count this week breaches the threshold in the
/// configured direction, `penaltyPoints` are subtracted once for the
/// week. Crossing back removes the deduction. Framed as a limit /
/// reduction goal, never as a punishment.
struct PenaltyRule: Codable, Equatable {
    var enabled: Bool = false
    var timesThreshold: Int = 2
    var condition: PenaltyCondition = .moreThan
    var penaltyPoints: Int = 10
}

// MARK: - Habit Train

/// Step inside a `HabitTrain`. Two flavors: a `.task` step references
/// an existing `FFTask` (the bridge — completing the step completes
/// that task, and a task already done today reads as complete here);
/// a `.note` step is a non-scoring cue (e.g. "drink water first").
enum TrainStepType: String, Codable, Equatable { case task, note }

/// One ordered step in a habit train. `orderIndex` is the canonical
/// sort key; the builder uses drag-to-reorder to rewrite indices.
struct HabitTrainStep: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var orderIndex: Int
    var type: TrainStepType
    var taskId: UUID? = nil      // when type == .task
    var noteText: String? = nil  // when type == .note
}

/// A named, ordered routine made of steps. Completing every task-step
/// in `steps` on the same calendar day awards `bonusPoints` once via a
/// `.trainBonus` LogEntry that folds into the daily / weekly total.
/// Note steps never score and don't gate the bonus.
struct HabitTrain: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var trainDescription: String? = nil
    var bonusPoints: Int = 10
    var seasonId: UUID? = nil
    var steps: [HabitTrainStep] = []
    var createdAt: Date = Date()
}

// MARK: - Avoidance Items (standalone)

/// A standalone behavior the user wants to reduce — not tied to a
/// positive task. Each logged occurrence deducts
/// `pointsPerOccurrence` from the weekly total in real time.
struct AvoidanceItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var pointsPerOccurrence: Int
    var seasonId: UUID? = nil
    var note: String? = nil
    var createdAt: Date = Date()
}

/// A single timestamped occurrence of an `AvoidanceItem`.
/// Logged in the Store alongside a matching `.penalty` LogEntry that
/// folds the deduction into the existing daily / weekly score.
struct AvoidanceOccurrence: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var itemId: UUID
    var date: Date = Date()
    var pointsDeducted: Int
    /// Id of the matching `LogEntry` so an undo can remove both
    /// records atomically without scanning by date heuristics.
    var logEntryId: UUID
}

/// Eight palette options a NoteFolder can use as its tint. Lives in
/// Models (Foundation-only) as a raw String so it round-trips through
/// JSON cleanly; the Theme extension in Theme.swift wires each case to
/// a real SwiftUI `Color`.
enum FolderColor: String, Codable, CaseIterable, Identifiable, Equatable {
    case purple
    case green
    case blue
    case pink
    case orange
    case amber
    case grey
    case dusk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .purple: return "Purple"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .pink:   return "Pink"
        case .orange: return "Orange"
        case .amber:  return "Amber"
        case .grey:   return "Grey"
        case .dusk:   return "Dusk"
        }
    }
}

// MARK: - Pin Schedule

/// How a Task earns its way onto today's plan.
///
/// - `.none` — not pinned anywhere.
/// - `.today` — one-shot pin that auto-clears at the next day rollover.
/// - `.singleDate` — pinned to one specific calendar day.
/// - `.daysOfWeek` — recurring weekly. Weekday integers follow
///   Calendar's convention (1 = Sunday … 7 = Saturday).
/// - `.daily` — pinned every day.
enum PinSchedule: Codable, Equatable {
    case none
    case today
    case singleDate(Date)
    case daysOfWeek(Set<Int>)
    case daily
}

// MARK: - Season

struct SeasonCategory: Codable, Identifiable {
    var id: UUID = UUID()
    var category: Category
    var tier: CategoryTier
}

struct Milestone: Codable, Identifiable {
    var id: UUID = UUID()
    var seasonId: UUID
    var weekNumber: Int
    var title: String
    var status: MilestoneStatus
}

struct Season: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var lengthDays: Int
    var startDate: Date
    var vibe: SeasonVibe
    var dailyGoal: Int
    var weeklyGoal: Int
    var categories: [SeasonCategory]
    var milestones: [Milestone]
}

// MARK: - Tasks / To-dos / Log / Notes

/// A repeatable, point-bearing activity from the user's library.
/// Prefixed `FF` so the type doesn't collide with Swift Concurrency's `Task`.
struct FFTask: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var category: Category
    var pointValue: Int
    var tier: Tier
    var skipPenalty: Int?
    var estimatedMinutes: Int?
    var pinSchedule: PinSchedule = .none
    var booster: BoosterRule? = nil
    var penalty: PenaltyRule? = nil

    // Backward-compatible decoding so persisted tasks predating
    // `booster` / `penalty` still hydrate. Missing keys fall through
    // to the property defaults.
    private enum CodingKeys: String, CodingKey {
        case id, title, category, pointValue, tier, skipPenalty, estimatedMinutes, pinSchedule, booster, penalty
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: Category,
        pointValue: Int,
        tier: Tier,
        skipPenalty: Int? = nil,
        estimatedMinutes: Int? = nil,
        pinSchedule: PinSchedule = .none,
        booster: BoosterRule? = nil,
        penalty: PenaltyRule? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.pointValue = pointValue
        self.tier = tier
        self.skipPenalty = skipPenalty
        self.estimatedMinutes = estimatedMinutes
        self.pinSchedule = pinSchedule
        self.booster = booster
        self.penalty = penalty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try c.decode(String.self, forKey: .title)
        self.category = try c.decode(Category.self, forKey: .category)
        self.pointValue = try c.decode(Int.self, forKey: .pointValue)
        self.tier = try c.decode(Tier.self, forKey: .tier)
        self.skipPenalty = try c.decodeIfPresent(Int.self, forKey: .skipPenalty)
        self.estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        self.pinSchedule = try c.decodeIfPresent(PinSchedule.self, forKey: .pinSchedule) ?? .none
        self.booster = try c.decodeIfPresent(BoosterRule.self, forKey: .booster)
        self.penalty = try c.decodeIfPresent(PenaltyRule.self, forKey: .penalty)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
        try c.encode(pointValue, forKey: .pointValue)
        try c.encode(tier, forKey: .tier)
        try c.encodeIfPresent(skipPenalty, forKey: .skipPenalty)
        try c.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        try c.encode(pinSchedule, forKey: .pinSchedule)
        try c.encodeIfPresent(booster, forKey: .booster)
        try c.encodeIfPresent(penalty, forKey: .penalty)
    }
}

/// A one-time to-do item. Deliberately simpler than a Task — no
/// category, no tier, just a title, an optional date, and an optional
/// point reward. `pointValue == nil` means a pure list item (no score).
struct Todo: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var dueDate: Date?
    var pointValue: Int?
    var isCompleted: Bool = false
    var completedAt: Date?
}

/// Record that a Task or To-do happened (or was skipped / penalised)
/// on a given day. The day's score is the sum of `pointsEarned` for
/// that date.
struct LogEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var taskId: UUID?
    var todoId: UUID?
    var trainId: UUID? = nil
    /// Set when this entry credits (or penalises) a linked Cadence
    /// routine / outcome rather than a native Task or To-do. Lets the
    /// plan row find today's "earned from Cadence" entry and keeps
    /// Cadence-derived points distinguishable for the social-privacy
    /// layer. Optional so entries persisted before the link decode cleanly.
    var cadenceLinkId: UUID? = nil
    var pointsEarned: Int
    var entryType: LogEntryType = .completed
}

/// A user-created bucket for grouping Notes. Stores a name plus a
/// tint from the palette so the same folder reads consistently across
/// pills, lists, and detail screens. Folders live in the Store and
/// notes reference one by `folderId` (optional — a Note can be unfiled).
struct NoteFolder: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorKey: FolderColor
}

/// Free-form journal entry — text body, voice memo, or both. The voice
/// memo is stored on disk under `voiceMemoFilename`; resolve it through
/// the computed `voiceMemoURL` to get a usable `URL` (the absolute
/// Documents path can change between launches).
///
/// `isPinned` floats the note above the day-grouped flow in the library
/// and folder pages. The custom Codable conformance below makes the
/// flag tolerate older persisted payloads that predate it.
/// A single voice-memo attachment on a Note. A note can carry any
/// number of these; they're rendered in `createdAt` order. The audio
/// file lives on disk under `filename`; resolve via `NoteVoiceMemo.url`.
struct NoteVoiceMemo: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var filename: String
    var duration: TimeInterval
    var createdAt: Date = Date()

    var url: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(filename)
    }
}

struct Note: Codable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var body: String?
    /// Ordered list of voice memos attached to this note. Multiple are
    /// allowed; new takes append. Legacy single-memo notes are migrated
    /// into this array on decode (see Codable conformance below).
    var voiceMemos: [NoteVoiceMemo] = []
    var folderId: UUID?
    var label: String?
    var isPinned: Bool = false
}

extension Note {
    /// Convenience accessor for the first voice memo's filename, kept
    /// for back-compat with callers that predate the multi-memo array.
    /// New code should iterate `voiceMemos` directly.
    var voiceMemoFilename: String? { voiceMemos.first?.filename }

    /// Duration of the first attached voice memo, if any.
    var voiceMemoDuration: TimeInterval? { voiceMemos.first?.duration }

    /// Resolve the on-disk URL for the first attached voice memo.
    var voiceMemoURL: URL? { voiceMemos.first?.url }

    /// True when either text or audio is attached. Used by the
    /// homepage to skip rendering empty entries defensively.
    var hasContent: Bool {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmedBody.isEmpty || !voiceMemos.isEmpty
    }
}

// MARK: - Backward-compatible Codable for Note
//
// We declare both sides of Codable explicitly so notes persisted before
// `isPinned` existed still decode cleanly. Missing keys fall through to
// the property defaults via `decodeIfPresent`.
extension Note {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, body, voiceMemoFilename, voiceMemoDuration,
             voiceMemos, folderId, label, isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false

        // Prefer the new array shape; fall back to the legacy single-memo
        // fields so notes persisted before multi-memo support still hydrate.
        if let memos = try c.decodeIfPresent([NoteVoiceMemo].self, forKey: .voiceMemos) {
            self.voiceMemos = memos
        } else if let legacyName = try c.decodeIfPresent(String.self, forKey: .voiceMemoFilename) {
            let legacyDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .voiceMemoDuration) ?? 0
            self.voiceMemos = [
                NoteVoiceMemo(
                    filename: legacyName,
                    duration: legacyDuration,
                    createdAt: self.createdAt
                )
            ]
        } else {
            self.voiceMemos = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encode(voiceMemos, forKey: .voiceMemos)
        try c.encodeIfPresent(folderId, forKey: .folderId)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(isPinned, forKey: .isPinned)
    }
}

// MARK: - Pin schedule helpers

extension FFTask {
    /// True when this Task's schedule pins it to the given calendar day.
    func isPinnedFor(_ date: Date) -> Bool {
        let cal = Calendar.current
        switch pinSchedule {
        case .none:
            return false
        case .today:
            // `.today` means "pinned for whatever today is when checked".
            // Compared against the real today so the flag clears once
            // the day rolls over (rollover also resets it to `.none`).
            return cal.isDateInToday(date)
        case .singleDate(let target):
            return cal.isDate(date, inSameDayAs: target)
        case .daysOfWeek(let days):
            let weekday = cal.component(.weekday, from: date)
            return days.contains(weekday)
        case .daily:
            return true
        }
    }

    /// Convenience for the common "is this on today's plan?" check.
    /// Backed by `isPinnedFor(_:)` so every existing call site keeps
    /// working without rewrites.
    var isPinnedToday: Bool {
        isPinnedFor(Date())
    }
}

// MARK: - Home composition

/// A single row in Today's Plan — either a repeatable Task or a dated
/// To-do, both reusing their own card view. Identifiable by the
/// underlying object's id so SwiftUI can diff a heterogeneous list.
enum HomeRowItem: Identifiable {
    case task(FFTask)
    case todo(Todo)
    case cadenceLink(CadenceLink)

    var id: UUID {
        switch self {
        case .task(let t): return t.id
        case .todo(let td): return td.id
        case .cadenceLink(let link): return link.id
        }
    }
}

// MARK: - To-do due text

extension Todo {
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Editorial, lowercase phrasing for the metadata row:
    /// `today`, `tomorrow`, `Thu`, `May 28`, `2d late`, `no rush`.
    var dueText: String {
        guard let due = dueDate else { return "no rush" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dueDay = cal.startOfDay(for: due)
        let days = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0

        if days == 0 { return "today" }
        if days < 0 {
            let late = -days
            return late == 1 ? "1d late" : "\(late)d late"
        }
        if days == 1 { return "tomorrow" }
        if days <= 7 { return Self.weekdayFormatter.string(from: due) }
        return Self.monthDayFormatter.string(from: due)
    }
}
