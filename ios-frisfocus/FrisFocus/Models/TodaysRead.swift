//
//  TodaysRead.swift
//  FrisFocus
//
//  The once-daily "read on today" — one bounded LLM call per user per
//  active day, cached. These types model the call result and the cache
//  envelope. `nonisolated` so JSONDecoder can build them off the main
//  actor.
//

import Foundation

/// What the read's single CTA button does.
nonisolated enum ReadCTAType: String, Codable, Sendable {
    case startFocus = "start_focus"
    case openTask = "open_task"
    case openRoutine = "open_routine"
    case rest
    case none
}

/// A hint the model returns for tinting the panel. Honest to the read.
nonisolated enum ReadTone: String, Codable, Sendable {
    case focus
    case encourage
    case rest
    case calm
}

/// The model's structured answer (matches the edge function's JSON).
nonisolated struct ReadPayload: Codable, Sendable {
    let read: String
    let ctaLabel: String?
    let ctaType: ReadCTAType
    let ctaTargetId: String?
    let tone: ReadTone

    enum CodingKeys: String, CodingKey {
        case read
        case ctaLabel = "cta_label"
        case ctaType = "cta_type"
        case ctaTargetId = "cta_target_id"
        case tone
    }
}

/// The cached read for a given active day, with the bookkeeping needed to
/// gate re-calls ("Think again").
nonisolated struct TodaysRead: Codable, Sendable, Equatable {
    let payload: ReadPayload
    /// Start-of-day key the read was generated for ("2026-06-21").
    let dayKey: String
    /// A coarse fingerprint of the day's state when this read was made.
    /// "Think again" is only allowed when the live hash differs.
    let stateHash: String
    /// How many times the read has been (re)generated today. Capped.
    let recallCount: Int
    let generatedAt: Date

    static func == (lhs: TodaysRead, rhs: TodaysRead) -> Bool {
        lhs.dayKey == rhs.dayKey
            && lhs.stateHash == rhs.stateHash
            && lhs.recallCount == rhs.recallCount
            && lhs.payload.read == rhs.payload.read
    }
}

// MARK: - Equatable for ReadPayload (so TodaysRead synthesises cleanly)
extension ReadPayload: Equatable {
    static func == (lhs: ReadPayload, rhs: ReadPayload) -> Bool {
        lhs.read == rhs.read
            && lhs.ctaLabel == rhs.ctaLabel
            && lhs.ctaType == rhs.ctaType
            && lhs.ctaTargetId == rhs.ctaTargetId
            && lhs.tone == rhs.tone
    }
}
