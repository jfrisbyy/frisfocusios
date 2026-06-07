//
//  ForwardSentence.swift
//  FrisFocus
//
//  The italic line that sits low in the Sun zone, just above the
//  ridges. Reads differently depending on time of day and how many
//  points the user has left to reach goal. Returns a single phrase
//  chosen from a small set of editorial sentences:
//
//    Morning, plenty left:   "a fresh morning · 42 to go"
//    Mid-day to afternoon:    "28 to a productive day"
//    Evening, close to goal:  "3 to go · day's almost won"
//    Goal hit:                "day won · breathe"
//
//  All copy is small and quiet — matches the locked design's
//  "calm beats loud" principle.
//

import Foundation

enum ForwardSentence {
    /// Returns the line that fits this moment of the day given the
    /// current score / goal.
    ///
    /// - Parameter dayProgress: 0 at sunrise, 1 at sunset (clamped).
    static func sentence(
        score: Int,
        goal: Int,
        dayProgress: Double
    ) -> String {
        let remaining = max(0, goal - score)

        if remaining == 0 {
            return "day won · breathe"
        }

        // Evening — past ~80 % of the day, we frame it as "almost won"
        if dayProgress >= 0.80 {
            return "\(remaining) to go · day's almost won"
        }

        // Early morning — first ~20 % of the day. Fresh framing.
        if dayProgress < 0.20 {
            return "a fresh morning · \(remaining) to go"
        }

        // Mid-day to afternoon — the default working voice.
        return "\(remaining) to a productive day"
    }
}
