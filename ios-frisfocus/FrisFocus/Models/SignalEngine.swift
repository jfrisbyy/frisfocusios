//
//  SignalEngine.swift
//  FrisFocus
//
//  Privacy-aware signal generator. Turns a person's `SignalFact`s into
//  the one-line "what they've been up to" text that appears on friend
//  cards and stories. The same fact produces different copy for
//  different viewers because the engine reads each `SharingSettings`
//  flag before rendering.
//
//  The privacy floor is: nothing specific is shown to a viewer who
//  isn't cleared for it. A `minimal` viewer will only ever see fully
//  generic phrasing. A `goalOnly` viewer can hear about goal status
//  but never a task name. Only `shareTaskNames`-cleared viewers see
//  names of completed Tasks (or honored user overrides).
//

import Foundation

/// Pure-function helper, no state. Each call is `(facts, clearance)`
/// in, `String` out. The Store calls into this from
/// `headlineFromFriend(_:)` so views stay simple.
struct SignalEngine {

    /// Lower number = higher priority. Thresholds always win.
    /// Returns rank second, milestones third, single Must-Do
    /// completions next, and volume highs fall to the bottom.
    static func priority(_ kind: SignalKind) -> Int {
        switch kind {
        case .threshold: return 0
        case .returning: return 1
        case .milestone: return 2
        case .mustDo:    return 3
        case .volumeHigh: return 4
        }
    }

    /// The headline signal line for `owner`, as seen by a viewer with
    /// `clearance`. Returns a generic fallback if nothing specific is
    /// shareable. `now` is injectable so unit-style verifications can
    /// pin a fixed day.
    static func headline(for ownerId: UUID,
                         facts: [SignalFact],
                         clearance: SharingSettings,
                         now: Date = Date()) -> String {
        let cal = Calendar.current
        let todays = facts.filter {
            $0.ownerId == ownerId && cal.isDate($0.date, inSameDayAs: now)
        }

        // Honored override wins, but is still privacy-gated. We can't
        // parse user-written text for sensitive content, so the rule
        // is conservative: overrides only surface to task-name-cleared
        // viewers. Lower-clearance viewers fall through to generated
        // generic signal so we never leak specifics by accident.
        if let override = todays.compactMap(\.userOverrideText).first {
            if clearance.shareTaskNames {
                return override
            }
            // fall through into the ranked render below
        }

        let ranked = todays
            .filter { canShow($0, to: clearance) }
            .sorted { priority($0.kind) < priority($1.kind) }

        if let top = ranked.first {
            return render(top, clearance: clearance)
        }

        return genericFallback(facts: todays, clearance: clearance)
    }

    // MARK: - Privacy gates

    /// Whether the fact can be shown to this viewer at all (before we
    /// even decide on wording). Some kinds always have a generic
    /// floor — those return true here and the render step degrades
    /// the wording downstream.
    private static func canShow(_ fact: SignalFact, to clearance: SharingSettings) -> Bool {
        switch fact.kind {
        case .threshold:
            // Numeric "score / goal" needs `shareScore`; pure "hit
            // goal" only needs `shareGoalStatus`. Either is enough
            // to surface a threshold fact.
            return clearance.shareGoalStatus || clearance.shareScore

        case .returning:
            // A return can always degrade to "back at it"; name gating
            // happens in `render`.
            return true

        case .milestone:
            return clearance.shareMilestones

        case .mustDo:
            // Must-Do completions always have a generic "productive
            // day" floor; name gating happens in `render`.
            return true

        case .volumeHigh:
            return clearance.shareScore || clearance.shareGoalStatus
        }
    }

    // MARK: - Render

    /// Translate the top-ranked fact into the most-specific copy the
    /// viewer is allowed to see. Privacy floor: every branch that
    /// would otherwise expose a task name checks `shareTaskNames`
    /// first; every branch with a number checks `shareScore`.
    private static func render(_ fact: SignalFact, clearance: SharingSettings) -> String {
        switch fact.kind {
        case .threshold:
            if let s = fact.score, let g = fact.goal, clearance.shareScore {
                return s >= g
                    ? "Hit today\u{2019}s goal \u{2014} \(s) of \(g)"
                    : "\(s) of \(g) today"
            }
            return "Hit today\u{2019}s goal"

        case .returning:
            if clearance.shareTaskNames, let task = fact.taskName {
                return "Back to \(task) after a while"
            }
            if clearance.shareTaskNames, let cat = fact.category {
                return "First \(cat.lowercased()) in a while"
            }
            return "Back at it today"

        case .milestone:
            if clearance.shareMilestones,
               let title = fact.milestoneTitle,
               let done = fact.milestoneDone,
               let total = fact.milestoneTotal {
                return "\(done) of \(total) \u{2014} \(title)"
            }
            return "Moving on a goal"

        case .mustDo:
            if clearance.shareTaskNames, let task = fact.taskName {
                return "\(task) \u{2014} done"
            }
            return "A productive day"

        case .volumeHigh:
            if clearance.shareScore, let s = fact.score {
                return "Biggest day this season \u{2014} \(s)"
            }
            return "A strong day"
        }
    }

    /// When nothing specific is shareable, say the most we're allowed
    /// to. Empty facts → "quiet day"; otherwise we reach for goal
    /// status if the viewer has clearance, then fall through to a
    /// fully generic floor.
    private static func genericFallback(facts: [SignalFact],
                                        clearance: SharingSettings) -> String {
        if facts.isEmpty {
            return "A quiet day so far"
        }
        if clearance.shareGoalStatus {
            let hitGoal = facts.contains { $0.kind == .threshold }
            return hitGoal ? "Hit today\u{2019}s goal" : "Working toward today\u{2019}s goal"
        }
        return "Having a productive day"
    }
}
