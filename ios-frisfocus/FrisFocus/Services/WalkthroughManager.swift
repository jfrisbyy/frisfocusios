//
//  WalkthroughManager.swift
//  FrisFocus
//
//  The first-run teaching layer, in two parts:
//
//   • Layer A — the interactive MECHANICS tour. Seven doing-lessons the
//     user performs right after their season lands, on the real UI:
//     pull a task from the season onto today (the board starts empty —
//     nothing is auto-assigned), check it off and watch the sun rise,
//     swipe a finished task to capture proof, log an amount (only when
//     the plan has one), give a task a recurring rhythm in the real
//     schedule editor, open the agenda to meet blocks and templates,
//     and the sunset close. Every step advances on the real performed
//     action, every step is skippable, and the whole tour runs once.
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

    /// The ordered doing-lessons, in the order a real day works:
    /// build the plan → do the work → set up the rhythm that carries
    /// tomorrow. `pinFirst` opens the run when today is empty (the
    /// default for a fresh season — tasks live in the season, unpinned).
    /// `quantity` joins only when the plan actually holds a tiered /
    /// increment task. `sunset` is the final beat — tomorrow's promise
    /// and the quiet widget suggestion.
    enum MechanicsStep: Int, Equatable {
        /// Pull the first task from the season board onto today's plan.
        case pinFirst
        /// Tap the circle — the sun rises.
        case checkOff
        /// Swipe a finished task to capture proof.
        case swipeCapture
        /// Log an amount on a tiered/increment task.
        case quantity
        /// Give a task a recurring rhythm (every day / chosen weekdays).
        case rhythm
        /// Open the agenda — bands, flexible blocks, day templates.
        case agenda
        /// The close: tomorrow starts new; rhythms return on their own.
        case sunset
    }

    /// True while the interactive mechanics tour is running.
    var tourActive: Bool = false
    /// The step currently being taught, or nil when idle.
    var tourStep: MechanicsStep? = nil

    /// Whether the quantity lesson applies — refreshed live as the plan
    /// changes (the user builds the plan mid-tour, so this can't be
    /// frozen at start).
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

    /// Begin the mechanics tour, unless it has already run. Starts at
    /// the pin lesson when today's plan is empty (the fresh-season
    /// default), otherwise straight at the first check.
    func startMechanicsTour(startsAtPinning: Bool, includesQuantity: Bool) {
        guard !mechanicsTourCompleted, !tourActive else { return }
        tourIncludesQuantity = includesQuantity
        tourActive = true
        tourStep = startsAtPinning ? .pinFirst : .checkOff
    }

    /// Keep the quantity lesson's availability honest as the plan
    /// changes mid-tour (the user pins tasks during the first step).
    func setQuantityAvailable(_ available: Bool) {
        tourIncludesQuantity = available
    }

    /// Move to the next applicable step, or finish the tour.
    func advanceTour() {
        guard tourActive else { return }
        switch tourStep {
        case .pinFirst:
            tourStep = .checkOff
        case .checkOff:
            tourStep = .swipeCapture
        case .swipeCapture:
            tourStep = tourIncludesQuantity ? .quantity : .rhythm
        case .quantity:
            tourStep = .rhythm
        case .rhythm:
            tourStep = .agenda
        case .agenda:
            tourStep = .sunset
        case .sunset, .none:
            finishTour()
        }
    }

    /// Skip the rest of the tour and jump straight to the live app.
    func skipTour() { finishTour() }

    /// Re-run the guided tour on demand (from the "How FrisFocus
    /// moves" sheet) — works even after the first run completed.
    func replayMechanicsTour(startsAtPinning: Bool, includesQuantity: Bool) {
        guard !tourActive else { return }
        tourIncludesQuantity = includesQuantity
        tourActive = true
        tourStep = startsAtPinning ? .pinFirst : .checkOff
    }

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
