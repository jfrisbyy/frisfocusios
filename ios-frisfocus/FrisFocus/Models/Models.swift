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
    case completed, skipped, penalty, boosterBonus, trainBonus, milestone
}

// MARK: - Scoring styles

/// How a daily task turns a logged amount into points.
///
/// - `.flat` — done equals a fixed number of points (the original behavior).
/// - `.tiered` — discrete levels by amount; logging awards the points of
///   the highest level the amount reaches (e.g. sleep 6h→2, 8h→4).
/// - `.quantity` — a base payout at a floor plus more per unit beyond it
///   (e.g. 200 pushups→3, then +1 every 100 after).
enum ScoringType: String, Codable, Equatable, CaseIterable {
    case flat, tiered, quantity

    var displayName: String {
        switch self {
        case .flat: return "Flat"
        case .tiered: return "Tiered"
        case .quantity: return "Quantity"
        }
    }

    var blurb: String {
        switch self {
        case .flat: return "Done is worth a fixed number of points."
        case .tiered: return "Levels by amount \u{2014} the higher you log, the more you earn."
        case .quantity: return "A base payout at a floor, plus more per unit beyond it."
        }
    }
}

/// One discrete level in a tiered task. At or above `threshold` (measured
/// in the config's `unit`), the level awards `points`. The engine awards
/// the points of the highest tier whose threshold the logged amount meets.
struct ScoreTier: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var threshold: Double
    var points: Int
}

/// The scoring shape attached to an `FFTask`. Flat tasks ignore every
/// field except their owning task's `pointValue`; tiered tasks read
/// `tiers`; quantity tasks read the `base*` / `unit*` fields.
struct ScoringConfig: Codable, Equatable {
    var type: ScoringType = .flat
    /// Human label for the logged amount: "hours", "pushups", "steps".
    var unit: String = ""

    // Tiered
    var tiers: [ScoreTier] = []

    // Quantity (increment)
    var baseThreshold: Double = 0
    var basePoints: Int = 0
    var unitSize: Double = 1
    var pointsPerUnit: Int = 0

    /// True when logging this task needs an amount (tiered / quantity).
    var requiresQuantity: Bool { type != .flat }

    /// Points earned for a logged `quantity`. `flatValue` is the owning
    /// task's `pointValue`, used by the flat style and as a safe fallback.
    func points(forQuantity quantity: Double?, flatValue: Int) -> Int {
        switch type {
        case .flat:
            return flatValue
        case .tiered:
            guard let q = quantity else { return 0 }
            return tiers.filter { q >= $0.threshold }.map(\.points).max() ?? 0
        case .quantity:
            guard let q = quantity, q >= baseThreshold else { return 0 }
            let size = unitSize <= 0 ? 1 : unitSize
            let extra = Int(((q - baseThreshold) / size).rounded(.down))
            return basePoints + extra * pointsPerUnit
        }
    }

    /// A representative "headline" value for value-based reminders,
    /// sorting, and the card readout. Flat → the task value; tiered →
    /// the top tier; quantity → the base payout.
    func headlineValue(flatValue: Int) -> Int {
        switch type {
        case .flat: return flatValue
        case .tiered: return tiers.map(\.points).max() ?? flatValue
        case .quantity: return basePoints
        }
    }

    /// Sorted tiers (ascending threshold) for display and evaluation.
    var sortedTiers: [ScoreTier] {
        tiers.sorted { $0.threshold < $1.threshold }
    }
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

/// Legacy task-attached consistency rule. Retired in favor of the
/// first-class `WeeklyBooster` below; retained only so tasks persisted
/// with an inline booster still decode and can be migrated into a
/// standalone `WeeklyBooster` on load. Do not attach new rules here.
struct BoosterRule: Codable, Equatable {
    var enabled: Bool = false
    var timesRequired: Int = 3
    var period: BoosterPeriod = .week
    var bonusPoints: Int = 10
}

/// What a first-class `WeeklyBooster` watches. A booster can track a
/// single task or an entire category (every task in that area counts
/// toward the same threshold), decoupling the reward from any one task.
enum BoosterReference: Codable, Equatable, Hashable {
    case task(UUID)
    case category(Category)
}

/// A standalone consistency reward. The referenced target (a task or a
/// whole category) must be completed at least `threshold` times within
/// the current `period` to award `bonusPoints` — all-or-nothing, once
/// per period. Unlike a streak, a missed day doesn't reset anything;
/// only the count against the target matters. Being first-class lets a
/// booster watch a category spanning several tasks, or outlive any
/// single task it once pointed at.
struct WeeklyBooster: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var seasonId: UUID? = nil
    var name: String
    var reference: BoosterReference
    var threshold: Int = 3
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

// MARK: - Negative shapes

/// How a negative (avoidance) behavior turns a logged occurrence into a
/// point deduction.
///
/// - `.perInstance` — bad every time, no acceptable amount. Each logged
///   occurrence deducts the full value.
/// - `.frequencyThreshold` — fine in moderation, costly only in excess
///   (junk food, alcohol, takeout spend). Free up to `freeCount` times
///   inside the window; every occurrence past the line deducts the value.
enum NegativeType: String, Codable, Equatable, CaseIterable {
    case perInstance
    case frequencyThreshold

    var displayName: String {
        switch self {
        case .perInstance:        return "Every time"
        case .frequencyThreshold: return "In excess"
        }
    }

    var blurb: String {
        switch self {
        case .perInstance:
            return "Bad every time \u{2014} each one costs points."
        case .frequencyThreshold:
            return "Fine in moderation \u{2014} free up to a limit, then it counts."
        }
    }
}

/// The window over which a frequency-threshold negative's free allowance
/// is counted and reset.
enum NegativeWindow: String, Codable, Equatable, CaseIterable {
    case weekly, monthly

    /// Bare noun for inline copy: "this week" / "this month".
    var displayName: String {
        switch self {
        case .weekly:  return "week"
        case .monthly: return "month"
        }
    }
}

// MARK: - Avoidance Items (standalone)

/// A standalone behavior the user wants to reduce — not tied to a
/// positive task. A `.perInstance` negative deducts `pointsPerOccurrence`
/// every time it's logged; a `.frequencyThreshold` negative is free up to
/// `freeCount` occurrences inside its `window`, then deducts the value
/// for each one past the line. Deductions fold into the score via
/// matching `.penalty` LogEntries.
struct AvoidanceItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// The point value of a chargeable occurrence. For `.perInstance`
    /// every occurrence costs this; for `.frequencyThreshold` only the
    /// occurrences past `freeCount` cost this.
    var pointsPerOccurrence: Int
    var seasonId: UUID? = nil
    var note: String? = nil
    /// Optional category link so a negative can sit under the area it
    /// pulls down (e.g. a "doomscroll" negative under Work). Optional so
    /// occurrences persisted before this field still decode.
    var category: Category? = nil
    /// Which negative shape this is. Defaults to `.perInstance` so items
    /// persisted before negative shapes existed read as flat every-time
    /// negatives with no behavior change.
    var negativeType: NegativeType = .perInstance
    /// The free-allowance window for `.frequencyThreshold`. Ignored by
    /// `.perInstance`.
    var window: NegativeWindow = .weekly
    /// How many occurrences are free inside the window before deductions
    /// begin. Ignored by `.perInstance`.
    var freeCount: Int = 0
    var createdAt: Date = Date()

    // Backward-compatible decoding so avoidance items persisted before
    // `negativeType` / `window` / `freeCount` existed still hydrate.
    // Missing keys fall through to the property defaults.
    private enum CodingKeys: String, CodingKey {
        case id, name, pointsPerOccurrence, seasonId, note, category,
             negativeType, window, freeCount, createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        pointsPerOccurrence: Int,
        seasonId: UUID? = nil,
        note: String? = nil,
        category: Category? = nil,
        negativeType: NegativeType = .perInstance,
        window: NegativeWindow = .weekly,
        freeCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.pointsPerOccurrence = pointsPerOccurrence
        self.seasonId = seasonId
        self.note = note
        self.category = category
        self.negativeType = negativeType
        self.window = window
        self.freeCount = freeCount
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.pointsPerOccurrence = try c.decode(Int.self, forKey: .pointsPerOccurrence)
        self.seasonId = try c.decodeIfPresent(UUID.self, forKey: .seasonId)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.category = try c.decodeIfPresent(Category.self, forKey: .category)
        self.negativeType = try c.decodeIfPresent(NegativeType.self, forKey: .negativeType) ?? .perInstance
        self.window = try c.decodeIfPresent(NegativeWindow.self, forKey: .window) ?? .weekly
        self.freeCount = try c.decodeIfPresent(Int.self, forKey: .freeCount) ?? 0
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(pointsPerOccurrence, forKey: .pointsPerOccurrence)
        try c.encodeIfPresent(seasonId, forKey: .seasonId)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encode(negativeType, forKey: .negativeType)
        try c.encode(window, forKey: .window)
        try c.encode(freeCount, forKey: .freeCount)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

extension AvoidanceItem {
    /// True when this negative uses the free-allowance / running-counter
    /// shape rather than charging every occurrence.
    var usesFreeAllowance: Bool { negativeType == .frequencyThreshold }
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
    /// Per-season rename. When non-nil, replaces the built-in display
    /// name everywhere this category is shown in the season.
    var customName: String? = nil
    /// Per-season recolor as `#RRGGBB`. When non-nil, replaces the
    /// built-in swatch color.
    var customColorHex: String? = nil
}

struct Milestone: Codable, Identifiable {
    var id: UUID = UUID()
    var seasonId: UUID
    var weekNumber: Int
    var title: String
    var status: MilestoneStatus
    /// A deliberately large one-time reward, credited once on the day the
    /// milestone is completed. May exceed the daily target by design.
    var pointValue: Int = 0
    /// The day this milestone was achieved. `nil` means not yet done;
    /// scoring credits `pointValue` to this day's total.
    var completedDate: Date? = nil

    var isCompleted: Bool { completedDate != nil }
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
    /// Legacy priority tier. Retired from the UI and all scoring/reminder
    /// behavior in favor of value-based reminders; retained (defaulted)
    /// only so tasks persisted before the switch still decode. Do not
    /// branch on this.
    var tier: Tier = .should
    var skipPenalty: Int?
    var estimatedMinutes: Int?
    var pinSchedule: PinSchedule = .none
    var booster: BoosterRule? = nil
    var penalty: PenaltyRule? = nil
    /// The scoring shape (flat / tiered / quantity). Defaults to flat so
    /// every task scored before this field existed reads as a flat
    /// `pointValue` task with no behavior change.
    var scoring: ScoringConfig = ScoringConfig()

    // Backward-compatible decoding so persisted tasks predating
    // `booster` / `penalty` / `scoring` still hydrate. Missing keys fall
    // through to the property defaults.
    private enum CodingKeys: String, CodingKey {
        case id, title, category, pointValue, tier, skipPenalty, estimatedMinutes, pinSchedule, booster, penalty, scoring
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: Category,
        pointValue: Int,
        tier: Tier = .should,
        skipPenalty: Int? = nil,
        estimatedMinutes: Int? = nil,
        pinSchedule: PinSchedule = .none,
        booster: BoosterRule? = nil,
        penalty: PenaltyRule? = nil,
        scoring: ScoringConfig = ScoringConfig()
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
        self.scoring = scoring
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try c.decode(String.self, forKey: .title)
        self.category = try c.decode(Category.self, forKey: .category)
        self.pointValue = try c.decode(Int.self, forKey: .pointValue)
        self.tier = try c.decodeIfPresent(Tier.self, forKey: .tier) ?? .should
        self.skipPenalty = try c.decodeIfPresent(Int.self, forKey: .skipPenalty)
        self.estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        self.pinSchedule = try c.decodeIfPresent(PinSchedule.self, forKey: .pinSchedule) ?? .none
        self.booster = try c.decodeIfPresent(BoosterRule.self, forKey: .booster)
        self.penalty = try c.decodeIfPresent(PenaltyRule.self, forKey: .penalty)
        self.scoring = try c.decodeIfPresent(ScoringConfig.self, forKey: .scoring) ?? ScoringConfig()
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
        try c.encode(scoring, forKey: .scoring)
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
    /// Set when this entry credits a completed `Milestone` (a large,
    /// one-time reward landing on the day it was achieved).
    var milestoneId: UUID? = nil
    /// Set when this entry is a first-class `WeeklyBooster` payout. Lets
    /// award-once-per-period dedup and the day breakdown identify which
    /// booster fired without leaning on `taskId`. `nil` for non-booster
    /// entries and entries persisted before boosters became first-class.
    var boosterId: UUID? = nil
    /// The amount logged for a tiered / quantity task (hours, reps, steps),
    /// kept so the row can show what was logged and so an edit can
    /// recompute. `nil` for flat tasks and non-task entries.
    var quantity: Double? = nil
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

    /// The representative point value used for value-based reminders,
    /// emphasis, and the card readout — resolves the right number across
    /// flat / tiered / quantity shapes.
    var nominalValue: Int {
        scoring.headlineValue(flatValue: pointValue)
    }

    /// True when completing this task needs an amount entry (tiered /
    /// quantity) rather than a single check.
    var requiresQuantityLogging: Bool {
        scoring.requiresQuantity
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
