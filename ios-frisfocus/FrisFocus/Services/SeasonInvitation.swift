//
//  SeasonInvitation.swift
//  FrisFocus
//
//  The home invitation card's brain: a purely LOCAL, templated pull toward
//  the deeper season conversation. No timers, no push, no model. It shows
//  ONLY when a concrete observation exists about how the person is actually
//  using their provisional cold-start season, and stays silent otherwise.
//
//  Dismiss is guilt-free and non-final: "Not now" quiets one observation,
//  which never returns — but a DIFFERENT, sharper observation may surface
//  later. After a sustained stretch (a few dismissals or ~30 days) the card
//  retires from home entirely; the conversation stays reachable from
//  settings and season detail.
//

import Foundation

/// The kinds of observation, in the order they're considered. North star
/// wins ties; the data-driven ones (consistency, gap) rank above the
/// always-available custom-heavy fallback so the copy sharpens over time.
enum SeasonInvitationKind: String, Codable, CaseIterable {
    case northStar
    case consistency
    case gap
    case customHeavy
}

/// A concrete, ready-to-show invitation: which observation, and the exact
/// templated copy (filled from local stats).
struct SeasonInvitation: Equatable {
    /// Where "talk it through" actually goes. Neglect and momentum are
    /// about ONE thing, so they open the scoped tune-up for that thing;
    /// only the custom-heavy pitch still earns the full conversation —
    /// repricing a hand-built board genuinely is season work.
    enum Target: Equatable {
        case season
        case task(UUID)
        case milestone(UUID)
    }

    let kind: SeasonInvitationKind
    let headline: String
    let cta: String
    let target: Target
}

/// Per-season persistence for the card: which observations have been
/// quieted, how many times, and whether it's retired. Keyed by season id
/// so a fresh season starts the card over. UserDefaults-backed and tiny.
enum SeasonInvitationStore {
    private static let dismissedPrefix = "seasonInvitation.dismissed."

    private static func key(for seasonId: UUID) -> String {
        dismissedPrefix + seasonId.uuidString
    }

    /// Observation kinds the person has quieted for this season.
    static func dismissedKinds(for seasonId: UUID) -> Set<SeasonInvitationKind> {
        let raw = UserDefaults.standard.stringArray(forKey: key(for: seasonId)) ?? []
        return Set(raw.compactMap(SeasonInvitationKind.init(rawValue:)))
    }

    /// Quiet one observation. It never returns; a different one still can.
    static func dismiss(_ kind: SeasonInvitationKind, for seasonId: UUID) {
        var current = dismissedKinds(for: seasonId)
        current.insert(kind)
        UserDefaults.standard.set(current.map(\.rawValue), forKey: key(for: seasonId))
    }

    /// The card retires once the person has quieted it a few times.
    static let retireAfterDismissals = 3
    /// …or after this many days into the season, whichever comes first.
    static let retireAfterDays = 30
}
