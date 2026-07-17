//
//  ColdStartContext.swift
//  FrisFocus
//
//  The warm-start envelope handed to the season conversation so the chat
//  NEVER opens cold. Serialized into the `season-setup` edge call as
//  `cold_start_context`; the server's system prompt (PART W) consumes it
//  to reference what the person already chose, built, and did.
//
//  Entry paths produce different richness: the day-1 "talk it through"
//  fork sends directions/sub-directions only; the invitation card,
//  settings resume, and season detail send the full picture (board +
//  logs + north stars). Any subset may be empty — the app serializes
//  exactly what exists, and a nil envelope is omitted from the call
//  entirely so legacy conversations run unchanged.
//

import Foundation

nonisolated struct ColdStartContext: Codable, Sendable, Equatable {
    /// The focus directions the person chose (life areas / free-text).
    let directions: [String]
    /// Sub-direction chips picked inside a direction ("Basketball").
    let subDirections: [String]
    /// The priced board — one entry per placed task.
    let board: [BoardItem]
    /// Free-written milestones (north stars), in the person's own words.
    let northStars: [String]
    /// Per-task activity so far, summarized locally.
    let logs: [LogSummary]
    /// Distinct days the person has been active since the season began.
    let daysActive: Int

    nonisolated struct BoardItem: Codable, Sendable, Equatable {
        let label: String
        /// "floor" | "normal" | "ideal" — the effort band it was placed in.
        let band: String
        /// Rank inside the band (0 = takes the most out of you).
        let bandRank: Int
        /// The invisible priced value (never shown to the user).
        let value: Int
        let isCustom: Bool

        enum CodingKeys: String, CodingKey {
            case label, band, value
            case bandRank = "band_rank"
            case isCustom = "is_custom"
        }
    }

    nonisolated struct LogSummary: Codable, Sendable, Equatable {
        let task: String
        /// Total completions since the season began.
        let completions: Int
        /// Distinct days this task was completed.
        let daysActive: Int

        enum CodingKeys: String, CodingKey {
            case task, completions
            case daysActive = "days_active"
        }
    }

    enum CodingKeys: String, CodingKey {
        case directions, board, logs
        case subDirections = "sub_directions"
        case northStars = "north_stars"
        case daysActive = "days_active"
    }

    /// True when there's genuinely nothing to say — the caller should omit
    /// the envelope so the conversation runs exactly as before.
    var isEmpty: Bool {
        directions.isEmpty && subDirections.isEmpty && board.isEmpty
            && northStars.isEmpty && logs.isEmpty
    }

    /// A minimal, directions-only envelope for the day-1 fork — the chat
    /// knows what the person is focused on, nothing more.
    static func directionsOnly(directions: [String], subDirections: [String]) -> ColdStartContext {
        ColdStartContext(
            directions: directions,
            subDirections: subDirections,
            board: [],
            northStars: [],
            logs: [],
            daysActive: 0
        )
    }
}
