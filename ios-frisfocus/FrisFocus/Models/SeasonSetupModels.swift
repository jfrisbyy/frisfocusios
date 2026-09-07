//
//  SeasonSetupModels.swift
//  FrisFocus
//
//  Types for the season-setup flow (S1). Two layers:
//
//  1. Wire DTOs (`Setup*Wire`) — the JSON contract with the `season-setup`
//     edge function. The backend holds the model + system prompt + the
//     calibration validator; the app only decodes the cleaned envelope.
//  2. `RubricDraft` — the fully editable, in-memory rubric the review
//     screen mutates. Built from the wire rubric on `done:true` (or from
//     a sensible starter on skip), then frozen into the Store's Season /
//     FFTask / AvoidanceItem / WeeklyBooster graph by `startSeason(from:)`.
//
//  Daily scoring after the freeze is local math — no AI in the hot path.
//

import Foundation

// MARK: - Wire DTOs (edge-function JSON contract)

nonisolated struct SetupWireEnvelope: Codable, Sendable {
    let reply: SetupWireReply
    /// The canonical assistant turn — replayed verbatim as conversation
    /// history in the next request so the model keeps its own context.
    let raw: String
}

nonisolated struct SetupWireReply: Codable, Sendable {
    let message: String
    let threads: [SetupWireThread]?
    let teaching: String?
    /// Short tappable answers for yes/no or confirmation turns. Nil/empty
    /// for open-ended questions, which still take voice or keyboard input.
    let answerOptions: [String]?
    let done: Bool?
    let suggestedName: String?
    let suggestedLengthDays: Int?
    /// ISO `yyyy-MM-dd` end date the user named during setup, if any.
    let suggestedEndDate: String?
    /// True when the user signalled the season should run open-ended.
    let suggestedOpenEnded: Bool?
    let rubric: SetupWireRubric?

    enum CodingKeys: String, CodingKey {
        case message, threads, teaching, done, rubric
        case answerOptions = "answer_options"
        case suggestedName = "suggested_name"
        case suggestedLengthDays = "suggested_length_days"
        case suggestedEndDate = "suggested_end_date"
        case suggestedOpenEnded = "suggested_open_ended"
    }
}

nonisolated struct SetupWireThread: Codable, Sendable, Equatable {
    let name: String
    let colorHint: String?

    enum CodingKeys: String, CodingKey {
        case name
        case colorHint = "color_hint"
    }
}

nonisolated struct SetupWireRubric: Codable, Sendable {
    let dailyTarget: Int
    let weeklyTarget: Int
    let categories: [SetupWireCategory]
    let negatives: [SetupWireNegative]?
    let weeklyBoosters: [SetupWireRule]?
    let weeklyPenalties: [SetupWireRule]?
    let milestones: [SetupWireMilestone]?

    enum CodingKeys: String, CodingKey {
        case categories, negatives, milestones
        case dailyTarget = "daily_target"
        case weeklyTarget = "weekly_target"
        case weeklyBoosters = "weekly_boosters"
        case weeklyPenalties = "weekly_penalties"
    }
}

nonisolated struct SetupWireCategory: Codable, Sendable {
    let name: String
    let colorHint: String?
    let tasks: [SetupWireTask]

    enum CodingKeys: String, CodingKey {
        case name, tasks
        case colorHint = "color_hint"
    }
}

nonisolated struct SetupWireTask: Codable, Sendable {
    let name: String
    let scoringType: String
    let value: Int?
    let unit: String?
    let tiers: [SetupWireTier]?
    let baseThreshold: Double?
    let basePoints: Int?
    let unitSize: Double?
    let pointsPerUnit: Int?

    enum CodingKeys: String, CodingKey {
        case name, value, unit, tiers
        case scoringType = "scoring_type"
        case baseThreshold = "base_threshold"
        case basePoints = "base_points"
        case unitSize = "unit_size"
        case pointsPerUnit = "points_per_unit"
    }
}

nonisolated struct SetupWireTier: Codable, Sendable {
    let threshold: Double
    let points: Int
}

nonisolated struct SetupWireNegative: Codable, Sendable {
    let name: String
    let negativeType: String
    let value: Int
    let window: String?
    let freeCount: Int?
    /// `tiered` only: the steps, lowest first. Each `points` is the
    /// day's TOTAL cost once that many have happened, not an addition
    /// to the step below.
    let tiers: [SetupWireTier]?

    enum CodingKeys: String, CodingKey {
        case name, value, window, tiers
        case negativeType = "negative_type"
        case freeCount = "free_count"
    }
}

nonisolated struct SetupWireRule: Codable, Sendable {
    let name: String
    let references: String?
    /// "days" (a count of days in the week), "sum" (a weekly total of
    /// the task's own units), or "manual" (nothing is counted — the
    /// person ticks it at the end of the week; boosters only). Absent
    /// reads as "days".
    let metric: String?
    let threshold: Int?
    let value: Int
}

nonisolated struct SetupWireMilestoneStep: Codable, Sendable {
    let name: String
    let value: Int?
}

nonisolated struct SetupWireMilestone: Codable, Sendable {
    let name: String
    let value: Int
    /// The stages of a decomposed goal. The prompt has always told the
    /// model to stage a big destination; there was no channel for it, so
    /// every rung burned a whole milestone slot.
    let steps: [SetupWireMilestoneStep]?
}

// MARK: - Conversation surface state

/// A recognized focus area shown as a live chip + a colored tick on the
/// orb arc. `arcPosition` records where on the arc the thread first
/// appeared, so ticks stay planted as the orb keeps climbing.
struct SetupThread: Identifiable, Equatable, Codable {
    var id: String { name.lowercased() }
    var name: String
    var colorHex: String
    var arcPosition: Double
}

// MARK: - Resumable conversation snapshot

/// A full snapshot of an in-progress setup conversation, persisted so the
/// user can leave and pick the exact same chat back up later. Only the
/// pre-rubric conversation is captured — once the rubric is produced the
/// flow advances to review and the snapshot is cleared.
nonisolated struct SetupConversationSnapshot: Codable, Sendable {
    /// The running message history replayed to keep the model's context.
    var history: [AIMessage]
    var currentMessage: String
    var lastAnswer: String?
    var priorMessage: String?
    var threads: [SetupThread]
    var teaching: String?
    var arcProgress: Double
    var userTurns: Int
    var savedAt: Date
    /// The board as it stands, including every review-screen edit.
    /// Optional so snapshots written before this decode cleanly.
    var draft: RubricDraft? = nil
    /// Which screen they were on: "conversation", "review", "naming".
    var stage: String? = nil
    var suggestedName: String? = nil
    var suggestedLengthDays: Int? = nil
    var suggestedEndDate: Date? = nil
    var suggestedOpenEnded: Bool? = nil
    /// True when this board came from Skip rather than the conversation.
    /// Without it a resumed skip lost the "back to guided setup" escape
    /// hatch, which is the only way to undo an accidental Skip.
    var usedStarter: Bool? = nil

    /// How long ago this was put down, phrased for the resume card, or
    /// nil when it was minutes ago and saying so would be noise.
    ///
    /// `savedAt` was written on every exchange and read by nothing, so
    /// "Continue where you left off" said exactly the same thing after
    /// three minutes and after three months — and a resumed conversation
    /// opened mid-drill on a question the person had no memory of being
    /// asked.
    var pausedLabel: String? {
        let elapsed = Date().timeIntervalSince(savedAt)
        let hour = 3600.0, day = 86_400.0
        switch elapsed {
        case ..<hour: return nil
        case ..<day: return "paused a few hours ago"
        case ..<(2 * day): return "paused yesterday"
        case ..<(30 * day):
            let days = Int((elapsed / day).rounded())
            return "paused \(days) days ago"
        default: return "paused a while ago"
        }
    }

    /// Whole days since this was put down, for telling the model the
    /// person stepped away. Zero for a same-day resume.
    var pausedDays: Int {
        max(0, Int(Date().timeIntervalSince(savedAt) / 86_400))
    }

    /// A short human hint for the resume card — the last thing discussed.
    var hint: String {
        // A snapshot saved on the review screen holds the REVEAL as its
        // current message, so the resume card used to show the first
        // ninety characters of a closing recap — "here's your season" —
        // over a board that is one tap from starting. Say where they
        // actually are instead.
        switch stage {
        case "review": return usedStarter == true
            ? "Your starter board, ready to edit"
            : "Your season is built \u{2014} review and start it"
        case "naming": return "Just needs a name"
        default: break
        }
        let trimmed = currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Picking up where you left off" }
        if trimmed.count <= 90 { return trimmed }
        let cut = trimmed.prefix(90)
        return cut.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}

// MARK: - Editable draft rubric (review screen)

nonisolated struct DraftCategory: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
}

nonisolated struct DraftTask: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var categoryId: UUID
    var shape: ScoringType = .flat
    /// Flat value; for tiered/quantity it mirrors the headline value.
    var value: Int = 3
    var unit: String = ""
    var tiers: [ScoreTier] = []
    var baseThreshold: Double = 1
    var basePoints: Int = 3
    var unitSize: Double = 1
    var pointsPerUnit: Int = 1

    /// Headline points for the row readout (top tier / base / flat value).
    var headlineValue: Int {
        switch shape {
        case .flat: return value
        case .tiered: return tiers.map(\.points).max() ?? value
        case .quantity: return basePoints
        }
    }

    /// Compact shape descriptor: "6h→2 · 8h→4 · tiered", "+1 per 50 reps".
    var shapeSummary: String? {
        switch shape {
        case .flat:
            return nil
        case .tiered:
            let steps = tiers.sorted { $0.threshold < $1.threshold }
                .map { "\(Self.trim($0.threshold))\(unitAbbrev)→\($0.points)" }
                .joined(separator: " · ")
            return steps.isEmpty ? "tiered" : "\(steps) · tiered"
        case .quantity:
            return "\(Self.trim(baseThreshold))\(unitAbbrev)→\(basePoints) · +\(pointsPerUnit) per \(Self.trim(unitSize))"
        }
    }

    private var unitAbbrev: String {
        guard let first = unit.first else { return "" }
        return String(first)
    }

    private static func trim(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

nonisolated struct DraftNegative: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var shape: NegativeType = .perInstance
    var value: Int = 3
    var window: NegativeWindow = .weekly
    var freeCount: Int = 2
    /// `.tiered` only: the day's total cost at each step.
    var tiers: [NegativeTier] = []

    // Synthesized `Decodable` throws on a missing key for anything that
    // isn't Optional, so a draft saved before tiers existed would fail
    // to decode and take the whole resumed conversation with it.
    enum CodingKeys: String, CodingKey {
        case id, name, shape, value, window, freeCount, tiers
    }

    init(
        id: UUID = UUID(),
        name: String,
        shape: NegativeType = .perInstance,
        value: Int = 3,
        window: NegativeWindow = .weekly,
        freeCount: Int = 2,
        tiers: [NegativeTier] = []
    ) {
        self.id = id
        self.name = name
        self.shape = shape
        self.value = value
        self.window = window
        self.freeCount = freeCount
        self.tiers = tiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.shape = try c.decodeIfPresent(NegativeType.self, forKey: .shape) ?? .perInstance
        self.value = try c.decodeIfPresent(Int.self, forKey: .value) ?? 3
        self.window = try c.decodeIfPresent(NegativeWindow.self, forKey: .window) ?? .weekly
        self.freeCount = try c.decodeIfPresent(Int.self, forKey: .freeCount) ?? 2
        self.tiers = try c.decodeIfPresent([NegativeTier].self, forKey: .tiers) ?? []
    }
}

nonisolated struct DraftBooster: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var referenceName: String
    var metric: BoosterMetric = .days
    var threshold: Int = 3
    var value: Int = 10
    /// A weekly goal that watches nothing and is ticked by hand — the
    /// only shape for an end-of-week state or a weekly one-off.
    var isManual: Bool = false
}

nonisolated struct DraftWeeklyPenalty: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var referenceName: String
    var metric: BoosterMetric = .days
    var threshold: Int = 2
    var value: Int = 10
}

nonisolated struct DraftMilestoneStep: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var value: Int = 0
}

nonisolated struct DraftMilestone: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var value: Int = 60
    var steps: [DraftMilestoneStep] = []
}

/// The whole editable board. Mutated freely on the review screen, then
/// frozen once via `Store.startSeason(from:...)`.
/// The whole editable board.
///
/// `Codable` so review-screen edits can survive a force-quit. They used
/// to live only in memory: someone could spend five minutes correcting
/// values, get killed by the OS, resume — and find the AI's ORIGINAL
/// numbers back, with nothing saying their corrections had ever
/// existed. The conversation was recoverable; the work done on top of
/// it was not.
nonisolated struct RubricDraft: Equatable, Codable, Sendable {
    var dailyTarget: Int = 30
    var weeklyTarget: Int = 180
    var categories: [DraftCategory] = []
    var tasks: [DraftTask] = []
    var negatives: [DraftNegative] = []
    var boosters: [DraftBooster] = []
    var weeklyPenalties: [DraftWeeklyPenalty] = []
    var milestones: [DraftMilestone] = []

    func tasks(in category: DraftCategory) -> [DraftTask] {
        tasks.filter { $0.categoryId == category.id }
    }

    // MARK: From the wire

    /// Build an editable draft from the validated backend rubric.
    init(wire: SetupWireRubric) {
        dailyTarget = max(1, wire.dailyTarget)
        weeklyTarget = max(dailyTarget, wire.weeklyTarget)

        for wireCategory in wire.categories.prefix(8) {
            let category = DraftCategory(
                name: wireCategory.name,
                colorHex: wireCategory.colorHint ?? "#7F77DD"
            )
            categories.append(category)
            for wireTask in wireCategory.tasks {
                var task = DraftTask(name: wireTask.name, categoryId: category.id)
                switch wireTask.scoringType {
                case "tiered":
                    task.shape = .tiered
                    task.unit = wireTask.unit ?? "amount"
                    task.tiers = (wireTask.tiers ?? []).map {
                        ScoreTier(threshold: $0.threshold, points: $0.points)
                    }
                    task.value = task.tiers.map(\.points).max() ?? 3
                case "increment":
                    task.shape = .quantity
                    task.unit = wireTask.unit ?? "units"
                    task.baseThreshold = wireTask.baseThreshold ?? 1
                    task.basePoints = wireTask.basePoints ?? 3
                    task.unitSize = max(1, wireTask.unitSize ?? 1)
                    task.pointsPerUnit = max(1, wireTask.pointsPerUnit ?? 1)
                    task.value = task.basePoints
                default:
                    task.shape = .flat
                    task.value = max(1, wireTask.value ?? 3)
                }
                tasks.append(task)
            }
        }

        negatives = (wire.negatives ?? []).map { wireNegative in
            let tiers = (wireNegative.tiers ?? [])
                // A task tier's threshold is a measurement (7.5 hours of
                // sleep); a negative's is a COUNT of occurrences in a
                // day, and the two share one wire type.
                .map { NegativeTier(threshold: max(1, Int($0.threshold.rounded())), points: max(1, $0.points)) }
                .sorted { $0.threshold < $1.threshold }
            let shape: NegativeType = {
                switch wireNegative.negativeType {
                case "frequency_threshold": return .frequencyThreshold
                // A single step is a per-instance charge in disguise.
                case "tiered" where tiers.count >= 2: return .tiered
                default: return .perInstance
                }
            }()
            return DraftNegative(
                name: wireNegative.name,
                shape: shape,
                value: max(1, shape == .tiered ? (tiers.last?.points ?? wireNegative.value) : wireNegative.value),
                window: wireNegative.window == "monthly" ? .monthly : .weekly,
                freeCount: max(0, wireNegative.freeCount ?? 2),
                tiers: shape == .tiered ? tiers : []
            )
        }
        // A rule has to name a task the board actually holds. The server
        // blanks a reference it cannot match but keeps the rule, so an
        // orphan used to arrive here, render on the review screen as
        // "5\u{00D7} \u{00B7} " with nothing after the dot, and then be deleted
        // without a word at commit. Shown, edited, gone.
        //
        // Nothing here is silently lost now. A booster becomes a weekly
        // goal the person ticks themselves \u{2014} the thing was real, only
        // the counting was impossible. A floor has no such fallback (a
        // penalty rule lives ON a task), so it is dropped at the door
        // rather than after the person has looked at it.
        let boardNames = Set(tasks.map { $0.name.lowercased() })
        boosters = (wire.weeklyBoosters ?? []).map {
            let named = $0.references?.trimmingCharacters(in: .whitespaces) ?? ""
            let resolves = boardNames.contains(named.lowercased())
            let manual = $0.metric == "manual" || !resolves
            return DraftBooster(
                name: $0.name,
                referenceName: manual ? "" : named,
                metric: $0.metric == "sum" ? .sum : .days,
                threshold: max(1, $0.threshold ?? 3),
                value: max(1, $0.value),
                isManual: manual
            )
        }
        weeklyPenalties = (wire.weeklyPenalties ?? []).compactMap {
            let named = $0.references?.trimmingCharacters(in: .whitespaces) ?? ""
            guard boardNames.contains(named.lowercased()) else { return nil }
            return DraftWeeklyPenalty(
                name: $0.name,
                referenceName: named,
                metric: $0.metric == "sum" ? .sum : .days,
                threshold: max(1, $0.threshold ?? 2),
                value: max(1, $0.value)
            )
        }
        milestones = (wire.milestones ?? []).map { wireMilestone in
            DraftMilestone(
                name: wireMilestone.name,
                value: max(1, wireMilestone.value),
                steps: (wireMilestone.steps ?? []).enumerated().map { _, step in
                    DraftMilestoneStep(name: step.name, value: max(0, step.value ?? 0))
                }
            )
        }
    }

    // MARK: Starter (skip fallback)

    private init() {}

    /// A small, sensible starter board for users who skip the conversation.
    /// Calm by design — easy to edit down or build up on the review screen.
    static func starter() -> RubricDraft {
        var draft = RubricDraft()
        let body = DraftCategory(name: "Body", colorHex: "#D85A30")
        let mind = DraftCategory(name: "Mind", colorHex: "#7F77DD")
        let home = DraftCategory(name: "Life", colorHex: "#C2922F")
        draft.categories = [body, mind, home]
        draft.tasks = [
            DraftTask(name: "Move for 30 minutes", categoryId: body.id, shape: .flat, value: 5),
            {
                var sleep = DraftTask(name: "Sleep", categoryId: body.id)
                sleep.shape = .tiered
                sleep.unit = "hours"
                sleep.tiers = [ScoreTier(threshold: 6, points: 2), ScoreTier(threshold: 8, points: 4)]
                sleep.value = 4
                return sleep
            }(),
            DraftTask(name: "Read 10 pages", categoryId: mind.id, shape: .flat, value: 3),
            DraftTask(name: "A quiet 10 minutes", categoryId: mind.id, shape: .flat, value: 3),
            DraftTask(name: "Reset one room", categoryId: home.id, shape: .flat, value: 2),
            DraftTask(name: "Real meal, not grabbed", categoryId: home.id, shape: .flat, value: 2),
        ]
        draft.negatives = [
            DraftNegative(name: "Doomscroll session", shape: .perInstance, value: 3),
            DraftNegative(name: "Takeout", shape: .frequencyThreshold, value: 4, window: .weekly, freeCount: 2),
        ]
        draft.boosters = [
            DraftBooster(name: "Move four days", referenceName: "Move for 30 minutes", threshold: 4, value: 10)
        ]
        draft.dailyTarget = 12
        draft.weeklyTarget = 72
        return draft
    }
}
