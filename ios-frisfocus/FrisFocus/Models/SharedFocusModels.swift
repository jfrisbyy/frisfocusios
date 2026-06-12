//
//  SharedFocusModels.swift
//  FrisFocus
//
//  F2 — Shared Focus Block (the Grove). A `SharedFocusBlock` ties a few
//  participants to one synchronized window. Each device runs the local
//  F1 tree + leave detection, then publishes a `FocusPresence` row —
//  coarse `state` + `leafTier`, never an exact countable ledger — so
//  friends' trees thin softly rather than expose every leave.
//
//  Privacy softening is structural: friends' trees render from
//  `LeafTier` (full / thinning / sparse), not from leave counts. Your
//  own tree uses the precise F1 leaf set locally.
//

import Foundation

/// Whether a participant is currently inside the FrisFocus app for
/// the shared block, or has stepped away. Sleep / lock is *not*
/// stepping away (carried over from F1).
enum PresenceState: String, Codable, Hashable {
    /// Invited but hasn't joined the grove yet — their tree shows a
    /// gentle "waiting" state until they arrive.
    case invited
    case inBlock
    case steppedAway
}

/// Coarse fullness bucket published for friends' trees. Maps from a
/// participant's local leaf count into three legible tiers so the
/// grove reads at a glance without surfacing a per-leave audit.
enum LeafTier: String, Codable, Hashable {
    case full
    case thinning
    case sparse

    /// Bucket a real leaf count (out of a typical 26-leaf canopy)
    /// into the privacy-safe tier published to other devices.
    static func bucket(leavesFallen: Int, of canopy: Int = 26) -> LeafTier {
        guard canopy > 0 else { return .full }
        let ratio = Double(leavesFallen) / Double(canopy)
        if ratio < 0.18 { return .full }
        if ratio < 0.45 { return .thinning }
        return .sparse
    }
}

/// One participant's presence in a shared block. Published per-device;
/// the relay (backend) fans these out to the other participants. Until
/// the backend lands, friends' rows are seeded / simulated locally.
struct FocusPresence: Codable, Identifiable, Hashable {
    var blockId: UUID
    var userId: UUID
    var state: PresenceState
    var leafTier: LeafTier
    var updatedAt: Date

    var id: String { "\(blockId.uuidString):\(userId.uuidString)" }
}

/// A shared, synchronized focus window across a small group. Each
/// participant's own device runs the F1 tree + honest leave detection
/// locally; this object just defines the window and the roster.
///
/// Capped to a small group (≈4 incl. host) per F2 — shared focus is
/// intimate by nature, not a forest.
struct SharedFocusBlock: Identifiable, Codable {
    var id: UUID = UUID()
    var hostId: UUID
    var label: String?
    var startedAt: Date
    var plannedDuration: TimeInterval
    var participantIds: [UUID]
    var endedAt: Date?

    /// Wall-clock end (start + planned).
    var plannedEndAt: Date { startedAt.addingTimeInterval(plannedDuration) }

    /// Whether this block's window is still open.
    var isActive: Bool {
        endedAt == nil && plannedEndAt > Date()
    }
}
