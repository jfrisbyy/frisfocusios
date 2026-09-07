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

/// The slots a season's areas of life map onto.
///
/// These are stable storage keys, not labels — a season renames and
/// recolors each one freely (`SeasonCategory.customName`), so "Fitness"
/// can read as "Hoop" and "Learning" as "French & Creole".
///
/// There were six. The season conversation is told it may build 2–8
/// areas and the server keeps 8, but the commit step mapped them onto
/// six slots and dropped every task belonging to a seventh or eighth
/// with no error and nothing on screen — a whole domain, silently, at
/// the last step. A life with sport, training, language study, faith,
/// work, making things and upkeep is seven areas before anyone has
/// tried to be thorough, so the slots now match what the flow promises.
enum Category: String, Codable, CaseIterable {
    case spiritual, fitness, health, work, creative, apartment
    /// Study, courses, languages, exams — practice aimed at competence
    /// rather than output.
    case learning
    /// The people in it: calls, visits, showing up for someone.
    case people

    var displayName: String {
        switch self {
        case .spiritual: return "Spiritual"
        case .fitness: return "Fitness"
        case .health: return "Health"
        case .work: return "Work"
        case .creative: return "Creative"
        case .apartment: return "Apartment"
        case .learning: return "Learning"
        case .people: return "People"
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
        case .learning: return "#3F8E8E"
        case .people: return "#C2922F"
        }
    }
}

/// Matching a season's own area names onto the eight built-in slots.
extension Category {
    /// Keywords that mean this slot, lowercased.
    private var slotKeywords: [String] {
        switch self {
        case .spiritual: return ["spirit", "faith", "prayer", "pray", "church", "god", "ministry",
                                 "meditat", "inner", "soul", "worship", "scripture", "bible", "quiet"]
        case .fitness:   return ["fitness", "train", "gym", "lift", "run", "workout", "exercise",
                                 "sport", "body", "strength", "athlet", "movement", "hoop", "basketball"]
        case .health:    return ["health", "sleep", "food", "eat", "meal", "nutrition", "diet",
                                 "weight", "hydrat", "water", "recovery", "rest", "wellbeing", "mind"]
        case .work:      return ["work", "job", "career", "business", "money", "shift", "office",
                                 "client", "professional", "income"]
        case .creative:  return ["creativ", "write", "writing", "music", "art", "draw", "paint",
                                 "design", "film", "video", "photo", "piano", "beat", "make", "craft"]
        case .apartment: return ["apartment", "home", "house", "flat", "clean", "chore", "upkeep",
                                 "space", "tidy", "laundry", "admin", "errand", "life",
                                 "place", "dish", "room", "kitchen", "garden", "car"]
        case .learning:  return ["learn", "study", "school", "class", "course", "exam", "language",
                                 "read", "french", "spanish", "certif", "skill", "practice", "revision"]
        case .people:    return ["people", "friend", "family", "relationship", "social", "connect",
                                 "love", "partner", "call", "community", "mum", "mom", "dad",
                                 "kid", "child", "son", "daughter", "parent", "mother", "father",
                                 "wife", "husband", "marriage", "brother", "sister"]
        }
    }

    /// The slot that best fits a season area called `name`.
    ///
    /// Slots used to be handed out by position — the first area the
    /// conversation listed took `.spiritual`, the second `.fitness`, and
    /// so on down `allCases`. The per-season `customName` and
    /// `customColorHex` covered that everywhere they were consulted, but
    /// a dozen places read the raw slot instead, so someone whose first
    /// area was training found their gym session filed under a header
    /// reading "Spiritual", tinted indigo against an orange season, and
    /// nudged back to life with "Quiet time has been waiting".
    ///
    /// Matching on the name fixes all of those at once for the ordinary
    /// case. `avoiding` holds the slots already handed out, so two areas
    /// never collide; when nothing matches, or the best match is taken,
    /// the first free slot is used exactly as before.
    static func bestSlot(for name: String, avoiding taken: Set<Category>) -> Category {
        let free = Category.allCases.filter { !taken.contains($0) }
        guard !free.isEmpty else { return .health }

        // Match WORDS, not raw substrings. A plain `contains` filed
        // "keeping the place from falling apart" under Creative, because
        // "falling apart" contains "art" — and it would have done the
        // same to any area whose name happens to hold "run" inside
        // "grunt" or "son" inside "reason". Keywords are stems, so a
        // word that STARTS with one is a match ("training" for "train",
        // "languages" for "language") and a word that merely contains
        // one is not.
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return free[0] }

        // Longest keyword wins, so "reading group" prefers `.learning`
        // over a stray short match elsewhere.
        var best: (slot: Category, score: Int)? = nil
        for slot in free {
            for keyword in slot.slotKeywords {
                guard words.contains(where: { $0.hasPrefix(keyword) }) else { continue }
                if best == nil || keyword.count > best!.score {
                    best = (slot, keyword.count)
                }
            }
        }
        return best?.slot ?? free[0]
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

/// How a season reaches its end.
///
/// - `.openEnded` — runs indefinitely until the user chooses to end it.
/// - `.milestones` — completes automatically once every milestone lands.
/// - `.date` — ends on a chosen calendar date (`Season.endDate`).
///
/// Seasons persisted before this existed have a nil `endMode`; they read
/// as `.date` using their saved `lengthDays` (see `Season.resolvedEndMode`).
enum SeasonEndMode: String, Codable {
    case openEnded
    case milestones
    case date
}

enum LogEntryType: String, Codable {
    case completed, skipped, penalty, boosterBonus, trainBonus, milestone
    /// A per-step credit on a "points per step" milestone — a smaller
    /// slice of the milestone's value landing the day the step is
    /// checked off. The remainder lands as a `.milestone` entry on
    /// completion day.
    case milestoneStep
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
///
/// `nonisolated` because the setup draft types are, and they hold these.
/// The project defaults every type to the main actor, so a main-actor
/// `Equatable` conformance reached from a nonisolated `Draft` struct is a
/// warning today and an error in the Swift 6 language mode. Two integers
/// have no business being actor-bound either way.
nonisolated struct ScoreTier: Codable, Equatable, Identifiable, Sendable {
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
            // Logging zero of anything earns nothing — even when a tier
            // sits at threshold 0.
            guard let q = quantity, q > 0 else { return 0 }
            return tiers.filter { q >= $0.threshold }.map(\.points).max() ?? 0
        case .quantity:
            // Same rule: a 0-amount log never pays out, including when
            // `baseThreshold` is 0 ("any amount counts" tasks).
            guard let q = quantity, q > 0, q >= baseThreshold else { return 0 }
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

    /// The floor a completion is worth when no amount was captured —
    /// used by backdated check-offs, where asking for an exact quantity
    /// days later would be guesswork. Flat → the task value; tiered →
    /// the lowest tier; quantity → the base payout. Never zero for a
    /// real completion.
    func baselinePoints(flatValue: Int) -> Int {
        switch type {
        case .flat: return flatValue
        case .tiered: return sortedTiers.first?.points ?? flatValue
        case .quantity: return max(basePoints, 1)
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

/// What a booster's or floor's threshold actually counts.
///
/// `.days` — how many days in the period the referenced work happened.
/// `.sum` — the total of the task's own logged units across the period:
///   150,000 steps, 1,500 pushups, ten lessons.
///
/// Everything used to be a day count, so a volume goal could not be
/// stated at all. "1500 pushups this week" had to become "pushups on
/// N days", which is a different promise and a much easier one.
///
/// Optional-with-a-resolver rather than defaulted, because synthesized
/// `Decodable` throws on a missing key instead of falling back to a
/// property default — a plain `var metric = .days` would fail to decode
/// every booster already on disk.
nonisolated enum BoosterMetric: String, Codable, Equatable, Sendable {
    case days, sum
}

/// What a first-class `WeeklyBooster` watches. A booster can track a
/// single task or an entire category (every task in that area counts
/// toward the same threshold), decoupling the reward from any one task.
enum BoosterReference: Codable, Equatable, Hashable {
    case task(UUID)
    case category(Category)
    /// Watches nothing — a weekly goal the person ticks off themselves.
    ///
    /// Some of the best weekly rules are not counts of anything the app
    /// can see. "The apartment is clean at the end of the week" is a
    /// STATE; "finish the book" is a one-off that happens to belong to
    /// this week rather than to the season. Both were unrepresentable
    /// while every weekly rule had to point at a daily task and count
    /// it, and forcing them into a daily task got the timing wrong —
    /// the whole point is that it is judged once, at the end.
    case manual
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
    /// See `BoosterMetric`. Nil reads as `.days`, which is what every
    /// booster written before this existed meant.
    var metric: BoosterMetric? = nil
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
struct PenaltyRule: Codable, Equatable, Identifiable {
    /// Identifies this rule's own deduction in the log. Without it a
    /// task could only ever carry one floor: the ledger keyed penalties
    /// by TASK, so a second rule's charge was indistinguishable from
    /// the first's and would have been swept away with it.
    var id: UUID = UUID()
    var enabled: Bool = false
    var timesThreshold: Int = 2
    var condition: PenaltyCondition = .moreThan
    var penaltyPoints: Int = 10
    /// See `BoosterMetric`. Nil reads as `.days`. A floor like "less
    /// than 400 pushups in a week" is a sum, not a day count, and could
    /// not be expressed while every threshold counted days.
    var metric: BoosterMetric? = nil

    var resolvedMetric: BoosterMetric { metric ?? .days }

    // Decoded by hand because `id` is non-optional with a default, and
    // synthesized Decodable throws on a missing key rather than falling
    // back to it — which would have failed every penalty rule already
    // persisted, taking its whole task down with it.
    private enum CodingKeys: String, CodingKey {
        case id, enabled, timesThreshold, condition, penaltyPoints, metric
    }

    init(
        id: UUID = UUID(),
        enabled: Bool = false,
        timesThreshold: Int = 2,
        condition: PenaltyCondition = .moreThan,
        penaltyPoints: Int = 10,
        metric: BoosterMetric? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.timesThreshold = timesThreshold
        self.condition = condition
        self.penaltyPoints = penaltyPoints
        self.metric = metric
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        timesThreshold = try c.decodeIfPresent(Int.self, forKey: .timesThreshold) ?? 2
        let rawCondition = (try? c.decodeIfPresent(String.self, forKey: .condition)) ?? nil
        condition = rawCondition.flatMap(PenaltyCondition.init(rawValue:)) ?? .moreThan
        penaltyPoints = try c.decodeIfPresent(Int.self, forKey: .penaltyPoints) ?? 10
        let rawMetric = (try? c.decodeIfPresent(String.self, forKey: .metric)) ?? nil
        metric = rawMetric.flatMap(BoosterMetric.init(rawValue:))
    }
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
    /// - `.tiered` — one slip is one thing, several in a day is another.
    ///   The day's total is set by the highest tier it reaches, so a
    ///   second drink doesn't add to the first, it REPLACES the charge
    ///   with a bigger one. This is the shape people actually keep by
    ///   hand as two paired rows ("Alcohol" and "Alcohol 2+"), which is
    ///   a trap when modelled literally: two independent items with no
    ///   mutual exclusion charge both on the same night.
    case tiered

    var displayName: String {
        switch self {
        case .perInstance:        return "Every time"
        case .frequencyThreshold: return "In excess"
        case .tiered:             return "Gets worse"
        }
    }

    var blurb: String {
        switch self {
        case .perInstance:
            return "Bad every time \u{2014} each one costs points."
        case .frequencyThreshold:
            return "Fine in moderation \u{2014} free up to a limit, then it counts."
        case .tiered:
            return "One is one thing \u{2014} several in a day costs much more."
        }
    }
}

/// One step of a `.tiered` negative: at `threshold` occurrences in a
/// day, the day's TOTAL charge becomes `points`.
///
/// Totals, not increments, because that is how people describe it —
/// "one drink is minus three, two or more is minus fifteen" means
/// fifteen altogether, not eighteen. The per-occurrence charge is the
/// difference between the tier you just reached and the one you were
/// on, which keeps the running total honest and keeps undo exact.
nonisolated struct NegativeTier: Codable, Equatable, Hashable, Sendable {
    var threshold: Int
    var points: Int
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
    /// The steps of a `.tiered` negative, lowest threshold first. Empty
    /// for every other shape.
    var tiers: [NegativeTier] = []
    var createdAt: Date = Date()

    /// The day's total charge once `count` occurrences have happened —
    /// the highest tier the count has reached, or nothing below the
    /// first one.
    func tieredTotal(for count: Int) -> Int {
        guard count > 0 else { return 0 }
        return tiers
            .filter { $0.threshold <= count }
            .map { abs($0.points) }
            .max() ?? 0
    }

    // Backward-compatible decoding so avoidance items persisted before
    // `negativeType` / `window` / `freeCount` existed still hydrate.
    // Missing keys fall through to the property defaults.
    private enum CodingKeys: String, CodingKey {
        case id, name, pointsPerOccurrence, seasonId, note, category,
             negativeType, window, freeCount, tiers, createdAt
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
        tiers: [NegativeTier] = [],
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
        self.tiers = tiers.sorted { $0.threshold < $1.threshold }
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
        // Read the shape through its raw string: a value written by a
        // newer build degrades to the flat every-time shape instead of
        // throwing away the whole item.
        let rawType = (try? c.decodeIfPresent(String.self, forKey: .negativeType)) ?? nil
        self.negativeType = rawType.flatMap(NegativeType.init(rawValue:)) ?? .perInstance
        self.window = try c.decodeIfPresent(NegativeWindow.self, forKey: .window) ?? .weekly
        self.freeCount = try c.decodeIfPresent(Int.self, forKey: .freeCount) ?? 0
        self.tiers = ((try? c.decodeIfPresent([NegativeTier].self, forKey: .tiers)) ?? nil ?? [])
            .sorted { $0.threshold < $1.threshold }
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
        try c.encode(tiers, forKey: .tiers)
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

/// An optional daily time window attached to a scheduled Task —
/// "7:00–8:00 AM". Stored as minutes from local midnight so the value
/// is calendar-day agnostic and applies to every day the task is
/// pinned. Used by the task card's quiet time chip and the weekly
/// schedule's arrange-by-time agenda.
struct TimeWindow: Codable, Equatable, Hashable {
    /// Start of the window, minutes from local midnight (0...1439).
    var startMinutes: Int
    /// End of the window, minutes from local midnight (0...1439).
    var endMinutes: Int

    /// `Date` on the given day at `startMinutes`, for pickers/format.
    func startDate(on day: Date = Date()) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .minute, value: startMinutes, to: cal.startOfDay(for: day)) ?? day
    }

    /// `Date` on the given day at `endMinutes`, for pickers/format.
    func endDate(on day: Date = Date()) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .minute, value: endMinutes, to: cal.startOfDay(for: day)) ?? day
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Compact display string — "7:00–8:00 AM". When both ends share
    /// the same day-period suffix, the first one is dropped.
    var displayText: String {
        let start = Self.timeFormatter.string(from: startDate())
        let end = Self.timeFormatter.string(from: endDate())
        // Drop a shared trailing " AM"/" PM" from the first time.
        for suffix in [" AM", " PM", " am", " pm"] {
            if start.hasSuffix(suffix), end.hasSuffix(suffix) {
                return "\(start.dropLast(suffix.count))–\(end)"
            }
        }
        return "\(start)–\(end)"
    }

    /// Start-only display — "7:00 AM". Used by agenda rows.
    var startText: String {
        Self.timeFormatter.string(from: startDate())
    }
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

/// One smaller goal inside a Milestone. Plain checkmark by default;
/// when the owning milestone uses "points per step", `pointValue` is
/// credited to the day the step is checked off.
struct MilestoneStep: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    /// Canonical sort key — reordering rewrites indices.
    var orderIndex: Int = 0
    /// Per-step credit, used only when the milestone's `pointsPerStep`
    /// is on. Zero means "progress only" even in that mode.
    var pointValue: Int = 0
    var completedDate: Date? = nil

    var isCompleted: Bool { completedDate != nil }
}

/// What kind of media a `MilestoneAttachment` carries.
enum MilestoneAttachmentKind: String, Codable, Equatable {
    case photo, voiceMemo, video
}

/// A photo, video clip, or voice memo documenting a milestone's
/// journey. The file lives in the Documents directory under `filename`
/// (same convention as note media), so the absolute path survives
/// container moves.
struct MilestoneAttachment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var kind: MilestoneAttachmentKind
    var filename: String
    /// Voice memo / video clip length; nil for photos.
    var duration: TimeInterval? = nil
    var createdAt: Date = Date()
    /// True when this media is a composed proof card — overlay,
    /// captions, and stickers baked in. Proof attachments get the
    /// signature edge in the journey UI.
    var isProof: Bool = false

    var url: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(filename)
    }
}

// Backward-compatible Codable: attachments persisted before videos /
// proofs existed still decode cleanly — missing keys fall through to
// the property defaults.
extension MilestoneAttachment {
    private enum CodingKeys: String, CodingKey {
        case id, kind, filename, duration, createdAt, isProof
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.kind = try c.decode(MilestoneAttachmentKind.self, forKey: .kind)
        self.filename = try c.decode(String.self, forKey: .filename)
        self.duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.isProof = try c.decodeIfPresent(Bool.self, forKey: .isProof) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(filename, forKey: .filename)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isProof, forKey: .isProof)
    }
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
    /// Smaller goals the milestone is broken into, in `orderIndex` order.
    var steps: [MilestoneStep] = []
    /// An optional, user-chosen target date for this milestone. When set,
    /// surfaces wherever the milestone is shown ("by Oct 12"); when nil the
    /// milestone simply reads as part of the list. Replaces the old
    /// auto-assigned `weekNumber` scheduling.
    var targetDate: Date? = nil
    /// Photos and voice memos documenting the process, in attach order.
    var attachments: [MilestoneAttachment] = []
    /// Journal notes linked to this milestone.
    var linkedNoteIds: [UUID] = []
    /// When true, each step's `pointValue` is credited the day it's
    /// checked off and the remainder lands at completion. When false
    /// (default), steps are progress-only and the full `pointValue`
    /// lands at completion.
    var pointsPerStep: Bool = false

    var isCompleted: Bool { completedDate != nil }

    /// Steps in display order.
    var sortedSteps: [MilestoneStep] {
        steps.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// 0...1 — fraction of steps done. A completed milestone always
    /// reads full; a milestone with no steps reads 0 until completed.
    var stepProgress: Double {
        if isCompleted { return 1 }
        guard !steps.isEmpty else { return 0 }
        return Double(steps.filter(\.isCompleted).count) / Double(steps.count)
    }

    /// Photo attachments only, oldest first — the card thumbnails.
    var photoAttachments: [MilestoneAttachment] {
        attachments.filter { $0.kind == .photo }.sorted { $0.createdAt < $1.createdAt }
    }
}

// Backward-compatible Codable: milestones persisted before steps /
// attachments / note links / points-per-step existed still decode
// cleanly — missing keys fall through to the property defaults.
extension Milestone {
    private enum CodingKeys: String, CodingKey {
        case id, seasonId, weekNumber, title, status, pointValue,
             completedDate, steps, targetDate, attachments, linkedNoteIds, pointsPerStep
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.seasonId = try c.decode(UUID.self, forKey: .seasonId)
        self.weekNumber = try c.decode(Int.self, forKey: .weekNumber)
        self.title = try c.decode(String.self, forKey: .title)
        self.status = try c.decode(MilestoneStatus.self, forKey: .status)
        self.pointValue = try c.decodeIfPresent(Int.self, forKey: .pointValue) ?? 0
        self.completedDate = try c.decodeIfPresent(Date.self, forKey: .completedDate)
        self.steps = try c.decodeIfPresent([MilestoneStep].self, forKey: .steps) ?? []
        self.targetDate = try c.decodeIfPresent(Date.self, forKey: .targetDate)
        self.attachments = try c.decodeIfPresent([MilestoneAttachment].self, forKey: .attachments) ?? []
        self.linkedNoteIds = try c.decodeIfPresent([UUID].self, forKey: .linkedNoteIds) ?? []
        self.pointsPerStep = try c.decodeIfPresent(Bool.self, forKey: .pointsPerStep) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(seasonId, forKey: .seasonId)
        try c.encode(weekNumber, forKey: .weekNumber)
        try c.encode(title, forKey: .title)
        try c.encode(status, forKey: .status)
        try c.encode(pointValue, forKey: .pointValue)
        try c.encodeIfPresent(completedDate, forKey: .completedDate)
        try c.encode(steps, forKey: .steps)
        try c.encodeIfPresent(targetDate, forKey: .targetDate)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(linkedNoteIds, forKey: .linkedNoteIds)
        try c.encode(pointsPerStep, forKey: .pointsPerStep)
    }
}

struct Season: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var lengthDays: Int
    var startDate: Date
    /// The exact moment this season was committed (full timestamp, not
    /// start-of-day). Used to scope the live daily score so a new season
    /// started midway through a day begins at zero — activity logged
    /// earlier that day (under the previous season) no longer counts.
    /// Optional so seasons persisted before this field decode cleanly;
    /// nil falls back to `startDate`.
    var startedAt: Date? = nil
    var vibe: SeasonVibe
    var dailyGoal: Int
    var weeklyGoal: Int
    var categories: [SeasonCategory]
    var milestones: [Milestone]

    /// How this season ends. Optional so seasons persisted before flexible
    /// length decode cleanly; a nil value reads as `.date` (legacy
    /// fixed-length behavior) via `resolvedEndMode`.
    var endMode: SeasonEndMode? = nil
    /// The chosen end date when `endMode == .date`. Nil for the other modes
    /// and for legacy seasons (which fall back to `lengthDays`).
    var endDate: Date? = nil

    // MARK: Season look (published to friends via the season card)

    /// The curated cover this season wears on profile pages
    /// (a `SeasonCoverKind` raw value). Nil → header photo or the
    /// accent band. Optional so persisted seasons decode cleanly.
    var coverId: String?
    /// The owner-chosen signature color hex. Nil → the auto-assigned
    /// account accent.
    var accentHex: String?
    /// True while this season was built by the 60-second cold start and
    /// hasn't yet been graduated through the season conversation. The
    /// invitation card shows only while this holds; the conversation edits
    /// this same season in place (never spawns a parallel one) and clears
    /// the flag on completion. Optional-with-default so persisted seasons
    /// decode cleanly (legacy seasons read as false — fully realized).
    var isProvisional: Bool = false
    /// A short "why this season" line shown under the season title.
    var intention: String?
    /// A small owner-set status under the intention on the profile
    /// card ("resting this week", "locked in"). Optional so persisted
    /// seasons decode cleanly; published to friends via the season card.
    var moodLine: String?
}

extension Season {
    /// The effective end mode — legacy seasons (nil `endMode`) read as
    /// `.date`, preserving their original fixed-length behavior.
    var resolvedEndMode: SeasonEndMode { endMode ?? .date }

    /// The targets a season falls back to when nothing carries forward
    /// and nothing has been chosen yet. Named rather than repeated as
    /// literals so "the starting target" is one fact in one place.
    static let defaultDailyGoal = 50
    static let defaultWeeklyGoal = 350
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
    /// One-shot "pin to today" that layers ON TOP of `pinSchedule`,
    /// so pinning a recurring task to an extra day never destroys its
    /// weekly schedule. Day rollover sweeps stale values.
    var oneOffPinDate: Date? = nil
    /// One-shot "skip from today's plan" that layers ON TOP of
    /// `pinSchedule`, suppressing a recurring task for a single day
    /// without touching its repeat pattern. Set by "Clear today's plan";
    /// day rollover sweeps stale values so the task returns on schedule.
    var skipDate: Date? = nil
    /// Optional daily time window ("7:00–8:00 AM") applied to every
    /// day this task is pinned. Drives the card's time chip and the
    /// weekly schedule's agenda ordering.
    var timeWindow: TimeWindow? = nil
    /// Soft placement — a "vibe of when" used by the agenda day view.
    /// Orthogonal to `timeWindow`: a task with a window is a hard anchor;
    /// a task with only a `partOfDay` floats in that band; a task with
    /// neither lives in the Anytime tray. Defaults to `.anytime` so
    /// tasks persisted before this field decode unchanged.
    var partOfDay: PartOfDay = .anytime
    /// Set when this task was placed on a specific day by a day template,
    /// so a later swap can clear exactly the template's stamped elements
    /// while preserving manual additions. Nil for normal tasks.
    var templateStamp: TemplateStamp? = nil
    var booster: BoosterRule? = nil
    var penalty: PenaltyRule? = nil
    /// Further weekly floors beyond the first.
    ///
    /// A task could only ever carry one, and the setup commit took the
    /// FIRST match and dropped the rest without a word — so a person who
    /// wanted both "at least three runs" and "at least 15km" lost one
    /// silently. The editor still edits the primary; these come from the
    /// conversation, which can now say more than one thing about a week.
    var extraPenalties: [PenaltyRule] = []

    /// Every weekly floor on this task, primary first.
    var allPenalties: [PenaltyRule] {
        ([penalty].compactMap { $0 } + extraPenalties).filter(\.enabled)
    }
    /// The scoring shape (flat / tiered / quantity). Defaults to flat so
    /// every task scored before this field existed reads as a flat
    /// `pointValue` task with no behavior change.
    var scoring: ScoringConfig = ScoringConfig()
    /// Manual position within its agenda band, set when the user drags
    /// to reorder. `nil` means "unsorted" — the band falls back to its
    /// sensible default order (timed by time, the rest by title), so
    /// nothing changes for people who never reorder.
    var agendaOrder: Int? = nil
    /// A quiet association to a north-star milestone this task plausibly
    /// builds toward ("builds toward your 10K"), set at cold start by a
    /// local keyword/category match. Purely a display hint — it never
    /// changes scoring or the board. Nil for tasks with no clear link.
    var milestoneLink: String? = nil
    /// True when the person added this task in their own words during the
    /// cold start (flagged in the placement tray). Feeds the "you know what
    /// matters" invitation observation; never shown as a badge. Defaults
    /// false so tasks persisted before this field decode unchanged.
    var isCustom: Bool = false

    // Backward-compatible decoding so persisted tasks predating
    // `booster` / `penalty` / `scoring` still hydrate. Missing keys fall
    // through to the property defaults.
    private enum CodingKeys: String, CodingKey {
        case id, title, category, pointValue, tier, skipPenalty, estimatedMinutes, pinSchedule, oneOffPinDate, skipDate, timeWindow, partOfDay, templateStamp, booster, penalty, extraPenalties, scoring, agendaOrder, milestoneLink, isCustom
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
        oneOffPinDate: Date? = nil,
        skipDate: Date? = nil,
        timeWindow: TimeWindow? = nil,
        partOfDay: PartOfDay = .anytime,
        templateStamp: TemplateStamp? = nil,
        booster: BoosterRule? = nil,
        penalty: PenaltyRule? = nil,
        scoring: ScoringConfig = ScoringConfig(),
        agendaOrder: Int? = nil,
        milestoneLink: String? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.pointValue = pointValue
        self.tier = tier
        self.skipPenalty = skipPenalty
        self.estimatedMinutes = estimatedMinutes
        self.pinSchedule = pinSchedule
        self.oneOffPinDate = oneOffPinDate
        self.skipDate = skipDate
        self.timeWindow = timeWindow
        self.partOfDay = partOfDay
        self.templateStamp = templateStamp
        self.booster = booster
        self.penalty = penalty
        self.scoring = scoring
        self.agendaOrder = agendaOrder
        self.milestoneLink = milestoneLink
        self.isCustom = isCustom
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
        self.oneOffPinDate = try c.decodeIfPresent(Date.self, forKey: .oneOffPinDate)
        self.skipDate = try c.decodeIfPresent(Date.self, forKey: .skipDate)
        self.timeWindow = try c.decodeIfPresent(TimeWindow.self, forKey: .timeWindow)
        self.partOfDay = try c.decodeIfPresent(PartOfDay.self, forKey: .partOfDay) ?? .anytime
        self.templateStamp = try c.decodeIfPresent(TemplateStamp.self, forKey: .templateStamp)
        self.booster = try c.decodeIfPresent(BoosterRule.self, forKey: .booster)
        self.penalty = try c.decodeIfPresent(PenaltyRule.self, forKey: .penalty)
        self.extraPenalties = try c.decodeIfPresent([PenaltyRule].self, forKey: .extraPenalties) ?? []
        self.scoring = try c.decodeIfPresent(ScoringConfig.self, forKey: .scoring) ?? ScoringConfig()
        self.agendaOrder = try c.decodeIfPresent(Int.self, forKey: .agendaOrder)
        self.milestoneLink = try c.decodeIfPresent(String.self, forKey: .milestoneLink)
        self.isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
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
        try c.encodeIfPresent(oneOffPinDate, forKey: .oneOffPinDate)
        try c.encodeIfPresent(skipDate, forKey: .skipDate)
        try c.encodeIfPresent(timeWindow, forKey: .timeWindow)
        try c.encode(partOfDay, forKey: .partOfDay)
        try c.encodeIfPresent(templateStamp, forKey: .templateStamp)
        try c.encodeIfPresent(booster, forKey: .booster)
        try c.encodeIfPresent(penalty, forKey: .penalty)
        try c.encode(extraPenalties, forKey: .extraPenalties)
        try c.encode(scoring, forKey: .scoring)
        try c.encodeIfPresent(agendaOrder, forKey: .agendaOrder)
        try c.encodeIfPresent(milestoneLink, forKey: .milestoneLink)
        try c.encode(isCustom, forKey: .isCustom)
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
    /// Set when this entry credits an honored `Bucket` (a time-bound,
    /// content-open block). The bucket scores once for honoring the
    /// block; a logged specific is recorded in `title`, not re-scored.
    /// `nil` for everything else and entries persisted before buckets.
    var bucketId: UUID? = nil
    /// Set when this entry credits one checked-off step of a
    /// "points per step" milestone, so unchecking can reverse exactly
    /// this credit. `nil` for everything else.
    var milestoneStepId: UUID? = nil
    /// Set when this entry is a first-class `WeeklyBooster` payout. Lets
    /// award-once-per-period dedup and the day breakdown identify which
    /// booster fired without leaning on `taskId`. `nil` for non-booster
    /// entries and entries persisted before boosters became first-class.
    var boosterId: UUID? = nil
    /// Set when this entry is one task's weekly-floor deduction. A task
    /// may carry several floors, so the charge has to name which.
    var penaltyRuleId: UUID? = nil
    /// The amount logged for a tiered / quantity task (hours, reps, steps),
    /// kept so the row can show what was logged and so an edit can
    /// recompute. `nil` for flat tasks and non-task entries.
    var quantity: Double? = nil
    var pointsEarned: Int
    var entryType: LogEntryType = .completed
    /// Snapshot of the item's name at the moment it was logged, so the
    /// day breakdown can always show WHAT happened even after the
    /// source task / to-do / routine is deleted. `nil` for entries
    /// persisted before this landed (labels fall back to live lookups).
    var title: String? = nil
}

/// A user-created bucket for grouping Notes. Stores a name plus a
/// tint from the palette so the same folder reads consistently across
/// pills, lists, and detail screens. Folders live in the Store and
/// notes reference one by `folderId` (optional — a Note can be unfiled).
struct NoteFolder: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorKey: FolderColor
    /// Last local edit — drives latest-wins conflict resolution in
    /// the notes sync layer. Defaults tolerate pre-sync payloads.
    var updatedAt: Date = Date()
}

// Backward-compatible Codable: folders persisted before `updatedAt`
// existed still decode cleanly (missing key → now).
extension NoteFolder {
    private enum CodingKeys: String, CodingKey {
        case id, name, colorKey, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.colorKey = try c.decode(FolderColor.self, forKey: .colorKey)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(colorKey, forKey: .colorKey)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
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

/// What kind of media a `NotePhoto` slot carries. Video clips arrived
/// with proof attachments; the type keeps its original name so every
/// persisted note decodes unchanged.
enum NoteMediaKind: String, Codable, Equatable {
    case photo, video
}

/// A single photo or short video attached to a Note. The file lives on
/// disk in the Documents directory under `filename`; resolve via
/// `url`. A note can carry any number, rendered in `createdAt` order.
struct NotePhoto: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var filename: String
    var createdAt: Date = Date()
    /// Photo or video clip. Defaults so pre-video payloads decode.
    var kind: NoteMediaKind = .photo
    /// Clip length; nil for photos.
    var duration: TimeInterval? = nil
    /// True when this media is a composed proof card — overlay,
    /// captions, and stickers baked in. Proofs get the signature edge
    /// in the photo grid.
    var isProof: Bool = false

    var url: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(filename)
    }
}

// Backward-compatible Codable: note photos persisted before videos /
// proofs existed still decode cleanly.
extension NotePhoto {
    private enum CodingKeys: String, CodingKey {
        case id, filename, createdAt, kind, duration, isProof
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.filename = try c.decode(String.self, forKey: .filename)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.kind = try c.decodeIfPresent(NoteMediaKind.self, forKey: .kind) ?? .photo
        self.duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        self.isProof = try c.decodeIfPresent(Bool.self, forKey: .isProof) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(filename, forKey: .filename)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encode(isProof, forKey: .isProof)
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
    /// Photos attached to this note, in attach order.
    var photos: [NotePhoto] = []
    /// Free-form tags (no leading #; lowercase-insensitive matching is
    /// handled at the Store level). Only surfaced when the user has
    /// opted into tags.
    var tags: [String] = []
    var folderId: UUID?
    var label: String?
    var isPinned: Bool = false
    /// Last local edit — drives latest-wins conflict resolution in the
    /// notes sync layer.
    var updatedAt: Date = Date()
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

    /// True when text, audio, or a photo is attached. Used by the
    /// homepage to skip rendering empty entries defensively.
    var hasContent: Bool {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmedBody.isEmpty || !voiceMemos.isEmpty || !photos.isEmpty
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
             voiceMemos, photos, tags, folderId, label, isPinned, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.photos = try c.decodeIfPresent([NotePhoto].self, forKey: .photos) ?? []
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? self.createdAt

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
        try c.encode(photos, forKey: .photos)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(folderId, forKey: .folderId)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Pin schedule helpers

extension FFTask {
    /// True when this Task's schedule pins it to the given calendar day.
    /// A one-off pin (`oneOffPinDate`) layers on top of the schedule so
    /// "pin to today" never erases a recurring weekly pattern.
    func isPinnedFor(_ date: Date) -> Bool {
        let cal = Calendar.current
        // A per-day skip (from "Clear today's plan") suppresses the task
        // for that one day, overriding both the one-off pin and the
        // recurring schedule. The repeat pattern itself is untouched.
        if let skip = skipDate, cal.isDate(date, inSameDayAs: skip) {
            return false
        }
        if let oneOff = oneOffPinDate, cal.isDate(date, inSameDayAs: oneOff) {
            return true
        }
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

/// A single row in Today's Plan — a repeatable Task, a dated To-do,
/// a linked Cadence routine, or a flexible block (bucket) from the
/// agenda. Identifiable by the underlying object's id so SwiftUI can
/// diff a heterogeneous list.
enum HomeRowItem: Identifiable {
    case task(FFTask)
    case todo(Todo)
    case cadenceLink(CadenceLink)
    case bucket(Bucket)

    var id: UUID {
        switch self {
        case .task(let t): return t.id
        case .todo(let td): return td.id
        case .cadenceLink(let link): return link.id
        case .bucket(let b): return b.id
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
