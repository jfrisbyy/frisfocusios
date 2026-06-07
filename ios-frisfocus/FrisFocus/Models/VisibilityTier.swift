//
//  VisibilityTier.swift
//  FrisFocus
//
//  The three levels of trust a person can extend to someone viewing
//  them. What you see of a friend depends on the tier THEY set for you
//  — their dial, never yours, shown honestly. The tier is derived from
//  the granular `SharingSettings` flags so the signal engine and the
//  existing per-flag plumbing keep working unchanged; the tier is just
//  the human-readable shape on top.
//
//   • quiet — shares a little: just their season + a mood line.
//   • open  — shares the shape: progress, rhythm, momentum (no tasks).
//   • full  — shares everything: the real day, routines, checklists.
//

import Foundation

/// A person's chosen visibility level for one viewer. Ordered quiet →
/// open → full so callers can compare openness if needed.
enum VisibilityTier: String, Codable, CaseIterable, Equatable {
    case quiet
    case open
    case full

    /// Short uppercase tag used in eyebrows and the spectrum explainer.
    var tag: String {
        switch self {
        case .quiet: return "QUIET"
        case .open:  return "OPEN"
        case .full:  return "FULL"
        }
    }

    /// The setter-side phrasing ("they share …"), used when the friend
    /// is choosing what to reveal.
    var shareVerb: String {
        switch self {
        case .quiet: return "Shares a little"
        case .open:  return "Shares the shape"
        case .full:  return "Shares everything"
        }
    }

    /// The viewer-side label rendered on the friend profile — names the
    /// tier so the user understands why the page is the shape it is.
    /// `name` is the friend's display name.
    func viewerLabel(name: String) -> String {
        switch self {
        case .quiet: return "\(name) shares a little with you"
        case .open:  return "\(name) shares the shape with you"
        case .full:  return "\(name) shares their full day with you"
        }
    }

    /// One-line explanation of exactly what this tier exposes. Used in
    /// the sharing-settings picker and the spectrum explainer.
    var detail: String {
        switch self {
        case .quiet: return "Just your season & a mood. No detail."
        case .open:  return "Progress & rhythm — but not the actual tasks."
        case .full:  return "The real day — routines, tasks, checklists, all of it."
        }
    }
}
