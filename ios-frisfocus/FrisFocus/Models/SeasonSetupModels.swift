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

    enum CodingKeys: String, CodingKey {
        case name, value, window
        case negativeType = "negative_type"
        case freeCount = "free_count"
    }
}

nonisolated struct SetupWireRule: Codable, Sendable {
    let name: String
    let references: String?
    let threshold: Int?
    let value: Int
}

nonisolated struct SetupWireMilestone: Codable, Sendable {
    let name: String
    let value: Int
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

    /// A short human hint for the resume card — the last thing discussed.
    var hint: String {
        let trimmed = currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Picking up where you left off" }
        if trimmed.count <= 90 { return trimmed }
        let cut = trimmed.prefix(90)
        return cut.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}

// MARK: - Editable draft rubric (review screen)

struct DraftCategory: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
}

struct DraftTask: Identifiable, Equatable {
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

struct DraftNegative: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var shape: NegativeType = .perInstance
    var value: Int = 3
    var window: NegativeWindow = .weekly
    var freeCount: Int = 2
}

struct DraftBooster: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var referenceName: String
    var threshold: Int = 3
    var value: Int = 10
}

struct DraftWeeklyPenalty: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var referenceName: String
    var threshold: Int = 2
    var value: Int = 10
}

struct DraftMilestone: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var value: Int = 60
}

/// The whole editable board. Mutated freely on the review screen, then
/// frozen once via `Store.startSeason(from:...)`.
struct RubricDraft: Equatable {
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

        for wireCategory in wire.categories.prefix(6) {
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
            DraftNegative(
                name: wireNegative.name,
                shape: wireNegative.negativeType == "frequency_threshold" ? .frequencyThreshold : .perInstance,
                value: max(1, wireNegative.value),
                window: wireNegative.window == "monthly" ? .monthly : .weekly,
                freeCount: max(0, wireNegative.freeCount ?? 2)
            )
        }
        boosters = (wire.weeklyBoosters ?? []).map {
            DraftBooster(name: $0.name, referenceName: $0.references ?? "", threshold: max(1, $0.threshold ?? 3), value: max(1, $0.value))
        }
        weeklyPenalties = (wire.weeklyPenalties ?? []).map {
            DraftWeeklyPenalty(name: $0.name, referenceName: $0.references ?? "", threshold: max(1, $0.threshold ?? 2), value: max(1, $0.value))
        }
        milestones = (wire.milestones ?? []).map {
            DraftMilestone(name: $0.name, value: max(1, $0.value))
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
