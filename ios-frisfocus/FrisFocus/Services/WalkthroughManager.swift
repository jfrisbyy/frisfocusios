//
//  WalkthroughManager.swift
//  FrisFocus
//
//  The first-run teaching layer, in two parts:
//
//   • Layer A — the interactive MECHANICS tour. A handful of gesture
//     lessons the user performs right after setup (check a task off,
//     swipe a finished task to capture, log a quantity). It advances on
//     the real performed gesture, is always skippable, and runs once.
//
//   • Layer B — the contextual CONCEPT layer. Quiet just-in-time lessons
//     that fire the first time the user naturally reaches each surface
//     (the day's shape, a full day, the privacy model, the read, share
//     attribution). Each fires once and is re-accessible via a small "?".
//
//  Governing principle: mechanics are shown early (you can't discover a
//  hidden gesture by doing); concepts are explained in context. The
//  manager only tracks state — the views decide when a lesson is
//  genuinely relevant.
//

import Foundation
import Observation

/// One concept lesson in the contextual (Layer B) layer. Mechanics are
/// taught by the interactive tour; these teach the non-obvious *ideas*.
nonisolated struct WalkthroughLesson: Identifiable, Equatable {
    let id: String
    /// Serif-italic title, in the FrisFocus voice (calm, a little literary).
    let title: String
    /// Plain supporting line.
    let message: String
    /// A line-icon (SF Symbol) shown beside the title — never an emoji.
    let icon: String

    /// First time the day's ring/shape is meaningful (a few tasks in).
    static let dayShape = WalkthroughLesson(
        id: "dayShape",
        title: "You don’t chase a number here.",
        message: "You chase the shape of a good day. The sun fills as you do what matters — that’s the whole game.",
        icon: "sun.max"
    )
    /// First full day — a celebration, not instruction.
    static let fullDay = WalkthroughLesson(
        id: "fullDay",
        title: "A full day.",
        message: "Every sun risen. This is what a complete day looks like — quietly, all of it.",
        icon: "sun.max.fill"
    )
    /// Points reveal — deferred until points become real (the season
    /// conversation). Defined here, fired by that flow when it exists.
    static let pointsPrivate = WalkthroughLesson(
        id: "pointsPrivate",
        title: "Your points are yours.",
        message: "Friends never see them unless you choose — they encode what’s hard for you, not for anyone else.",
        icon: "lock"
    )
    /// First visit to the People surface — the privacy model.
    static let peoplePrivacy = WalkthroughLesson(
        id: "peoplePrivacy",
        title: "You’ll see the shape of their days.",
        message: "And they’ll see yours. The numbers stay private unless you share them.",
        icon: "person.2"
    )
    /// First time Needs You has a read available.
    static let theRead = WalkthroughLesson(
        id: "theRead",
        title: "When you’re scattered, ask for a read.",
        message: "It points at the one thing worth doing — and sometimes it tells you to rest.",
        icon: "sparkles"
    )
    /// First share / camera-roll save — attribution.
    static let shareAttribution = WalkthroughLesson(
        id: "shareAttribution",
        title: "Anything you share outside carries your name.",
        message: "Inside FrisFocus, it’s just for your people. Outside, it goes out as yours.",
        icon: "square.and.arrow.up"
    )
}

@MainActor
@Observable
final class WalkthroughManager {

    // MARK: - Layer A · Mechanics tour

    /// The ordered gesture lessons. `quantity` is included only when the
    /// board actually has a tiered/increment task.
    enum MechanicsStep: Int, Equatable {
        case checkOff
        case swipeCapture
        case quantity
    }

    /// True while the interactive mechanics tour is running.
    var tourActive: Bool = false
    /// The step currently being taught, or nil when idle.
    var tourStep: MechanicsStep? = nil

    /// Whether this run includes the quantity lesson (set at start).
    private var tourIncludesQuantity: Bool = false

    // MARK: - Layer B · Contextual concept lessons

    /// Lesson ids the user has already been shown (persisted locally).
    private(set) var seen: Set<String>

    // MARK: - Storage

    private let defaults = UserDefaults.standard
    private let seenKey = "walkthrough.seenLessons.v1"
    private let tourDoneKey = "walkthrough.mechanicsTour.done.v1"

    init() {
        seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
    }

    // MARK: - Tour control

    /// True once the mechanics tour has completed or been skipped.
    var mechanicsTourCompleted: Bool { defaults.bool(forKey: tourDoneKey) }

    /// Begin the mechanics tour, unless it has already run.
    func startMechanicsTour(includesQuantity: Bool) {
        guard !mechanicsTourCompleted, !tourActive else { return }
        tourIncludesQuantity = includesQuantity
        tourActive = true
        tourStep = .checkOff
    }

    /// Move to the next applicable step, or finish the tour.
    func advanceTour() {
        guard tourActive else { return }
        switch tourStep {
        case .checkOff:
            tourStep = .swipeCapture
        case .swipeCapture:
            if tourIncludesQuantity {
                tourStep = .quantity
            } else {
                finishTour()
            }
        case .quantity, .none:
            finishTour()
        }
    }

    /// Skip the rest of the tour and jump straight to the live app.
    func skipTour() { finishTour() }

    private func finishTour() {
        tourActive = false
        tourStep = nil
        defaults.set(true, forKey: tourDoneKey)
    }

    // MARK: - Contextual lesson control

    /// Whether a concept lesson should fire on genuine first-use.
    func shouldFire(_ lesson: WalkthroughLesson) -> Bool {
        !seen.contains(lesson.id)
    }

    /// Record a lesson as seen so it never auto-fires again (it can still
    /// be resurfaced manually via a "?").
    func markSeen(_ lesson: WalkthroughLesson) {
        guard !seen.contains(lesson.id) else { return }
        seen.insert(lesson.id)
        defaults.set(Array(seen), forKey: seenKey)
    }
}
