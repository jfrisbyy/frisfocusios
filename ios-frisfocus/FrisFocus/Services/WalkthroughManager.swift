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
//     attribution; on the social half: the first friend, the first
//     proof, the first Golden Hour, the first circle, the first story
//     you can watch, the first thing you post, the first cheer, the
//     first pact, the first safety menu; and two that are about time
//     rather than a feature — the second day's rollover and the first
//     week's shape). Each fires once and, where the surface has room
//     for it, is re-accessible via a small "?".
//
//  Governing principle: mechanics are shown early (you can't discover a
//  hidden gesture by doing); concepts are explained in context. The
//  manager only tracks state — the views decide when a lesson is
//  genuinely relevant.
//

import Foundation
import Observation
import Supabase

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
    /// Points reveal — deferred until points become real. Fired from the
    /// work zone the first time today's plan actually shows a score, so
    /// the promise arrives with the number rather than ahead of it.
    static let pointsPrivate = WalkthroughLesson(
        id: "pointsPrivate",
        title: "Your points are yours.",
        message: "Friends never see them unless you choose — they encode what’s hard for you, not for anyone else.",
        icon: "lock"
    )
    /// The first real friendship — the privacy model, at the moment it
    /// stops being hypothetical.
    ///
    /// This is also the "first friend" lesson. The two were the same
    /// sentence written twice (you'll see each other's days; the numbers
    /// stay private), so there is one lesson, fired when someone is
    /// actually on the other side of it rather than on an empty People
    /// page where the promise is about nobody.
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

    // MARK: First Light · the social half

    /// The first proof someone sends you — the line between a proof and
    /// a story, drawn while one is sitting there unopened.
    static let firstProof = WalkthroughLesson(
        id: "firstProof",
        title: "A proof is for one person.",
        message: "A story goes to everyone. This went only to you, and it stays between the two of you.",
        icon: "envelope"
    )
    /// The first Golden Hour to actually fire. The blur rule is the
    /// whole module: unexplained, a wall that never clears reads as a
    /// broken app rather than a door you were late to.
    static let goldenHourWindow = WalkthroughLesson(
        id: "goldenHourWindow",
        title: "Golden Hour is now, or not at all.",
        message: "Five minutes, everyone at once. Miss it and the wall stays blurred for good.",
        icon: "sun.horizon"
    )
    /// The first circle the person stands inside.
    static let firstCircle = WalkthroughLesson(
        id: "firstCircle",
        title: "A circle is a room, not a feed.",
        message: "Everyone in it is doing the work alongside you. Nothing scrolls past — you step in and see who’s there.",
        icon: "person.3"
    )
    /// The first time someone else's story is there to watch. The two
    /// halves of the rule are stated together because they differ:
    /// general posts age out at 24h, circle clips never do (see
    /// `StoryPost.isExpired`). Told only as "stories vanish", the
    /// circle archive that quietly persists would read as a leak.
    static let storiesExpire = WalkthroughLesson(
        id: "storiesExpire",
        title: "A story lasts a day.",
        message: "After that it’s gone — not deleted, just over. Clips posted inside a circle are the exception: those stay with the circle.",
        icon: "clock"
    )
    /// The first thing the person posts themselves. The destination
    /// picker is the only privacy control that matters here, and it
    /// defaults to something — so the choice has to be named once, at
    /// the moment it was first made rather than before it means anything.
    static let whoSeesThis = WalkthroughLesson(
        id: "whoSeesThis",
        title: "Who sees it is chosen here.",
        message: "Your friends, a circle, one person — the picker decides, every time you post. Nothing travels past where you sent it.",
        icon: "eye"
    )
    /// The first cheer to land. Without this, the missing comment box
    /// under a cheer reads as something unfinished rather than the
    /// point: a cheer is a gift, not the top of a thread.
    static let cheersAreTheReply = WalkthroughLesson(
        id: "cheersAreTheReply",
        title: "A cheer is the whole reply.",
        message: "One line, one tap, and it’s said. There’s nothing to write underneath — react to it, or cheer back, and let it rest.",
        icon: "hands.clap"
    )
    /// The first pact, from either side of it.
    static let pactShape = WalkthroughLesson(
        id: "pactShape",
        title: "Two people, one window.",
        message: "The same days, the same finish line, both sides visible the whole way. There’s no winner — you get there together.",
        icon: "person.2.fill"
    )
    /// The first "…" opened on someone else's content. Each tool is
    /// named with what it actually does: "block" and "mute" are the
    /// two people reach for interchangeably and regret unevenly.
    static let safetyTools = WalkthroughLesson(
        id: "safetyTools",
        title: "The quiet menu is always there.",
        message: "Hide takes one thing off your view. Mute turns a person down without telling them. Report sends it to us. Block ends it both ways.",
        icon: "hand.raised"
    )

    // MARK: The returning day

    /// The second day. Rollover is invisible by design, which is
    /// exactly why the first one needs a sentence: an empty board on
    /// day two otherwise reads as work that was lost overnight.
    static let tomorrowStartsNew = WalkthroughLesson(
        id: "tomorrowStartsNew",
        title: "Yesterday closed where it closed.",
        message: "Today starts fresh. Rhythms you set return on their own, and anything left loose yesterday is offered back — never dragged over.",
        icon: "sunrise"
    )
    /// Around the first week, once the charts hold real days.
    static let weekShape = WalkthroughLesson(
        id: "weekShape",
        title: "A week has a shape too.",
        message: "There are enough days behind you now for this to mean something. Week, month, season — the same days, seen from further back.",
        icon: "chart.bar"
    )
}

/// What the server holds about someone's teaching progress.
private nonisolated struct WalkthroughProgressRow: Decodable, Sendable {
    let seenLessons: [String]?
    let tourCompleted: Bool?
    enum CodingKeys: String, CodingKey {
        case seenLessons = "seen_lessons"
        case tourCompleted = "tour_completed"
    }
}

private nonisolated struct WalkthroughProgressUpsert: Encodable, Sendable {
    let userId: String
    let seenLessons: [String]
    let tourCompleted: Bool
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case seenLessons = "seen_lessons"
        case tourCompleted = "tour_completed"
        case updatedAt = "updated_at"
    }
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

    /// Lesson ids the user has already been shown.
    private(set) var seen: Set<String>

    // MARK: - One voice at a time

    /// The one lesson currently on screen, app-wide.
    ///
    /// Surfaces used to raise lessons independently, so two could try to
    /// rise at once and only one sheet can. The work zone had to guard
    /// against the read lesson explicitly, by name — a rule every new
    /// surface would have had to remember, and forget. Claiming through a
    /// single slot makes "one voice at a time" a property of the manager
    /// instead.
    private(set) var presenting: String?

    /// Lessons fired since the app came up.
    ///
    /// A person adding four friends on a Sunday should not be met with
    /// four cards. Teaching is spent at most once per session, which over
    /// a couple of weeks delivers the whole curriculum without a single
    /// day of it feeling like a tutorial.
    private var spentThisSession: Int = 0
    private let sessionBudget = 1

    /// Ask to present a lesson. `false` means someone else has the floor,
    /// this session's teaching is already spent, or it has been seen.
    ///
    /// The mechanics tour is deliberately outside this: it is one
    /// continuous experience the person opted into, not an interruption.
    func claim(_ lesson: WalkthroughLesson) -> Bool {
        guard !tourActive else { return false }
        guard presenting == nil else { return false }
        guard spentThisSession < sessionBudget else { return false }
        guard shouldFire(lesson) else { return false }
        presenting = lesson.id
        spentThisSession += 1
        return true
    }

    /// Hand the floor back. Safe to call for a lesson that never held it,
    /// so a view's dismissal path needs no bookkeeping of its own.
    func release(_ lesson: WalkthroughLesson) {
        guard presenting == lesson.id else { return }
        presenting = nil
    }

    // MARK: - Storage

    private let defaults = UserDefaults.standard
    private let seenKey = "walkthrough.seenLessons.v1"
    private let tourDoneKey = "walkthrough.mechanicsTour.done.v1"

    /// Whose progress is loaded. Nil while signed out, when the local
    /// cache stands alone.
    private var myUserId: String?

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
        pushProgress()
    }

    // MARK: - Contextual lesson control

    /// Whether a concept lesson should fire on genuine first-use.
    ///
    /// Private on purpose. Surfaces used to ask this directly and raise
    /// their own sheet, which is how one page ended up checking another
    /// page's lesson by name to avoid colliding with it. `claim` is the
    /// only way in now, so the collision rule lives here instead of
    /// being re-derived by every new surface. A deliberate re-open (the
    /// "?") is the one thing that bypasses all of it — it sets the
    /// view's own sheet state and never asks the manager at all.
    private func shouldFire(_ lesson: WalkthroughLesson) -> Bool {
        !seen.contains(lesson.id)
    }

    /// Record a lesson as seen so it never auto-fires again (it can still
    /// be resurfaced manually via a "?").
    func markSeen(_ lesson: WalkthroughLesson) {
        guard !seen.contains(lesson.id) else { return }
        seen.insert(lesson.id)
        defaults.set(Array(seen), forKey: seenKey)
        pushProgress()
    }

    // MARK: - Account sync

    /// Adopt an account's progress.
    ///
    /// Merged rather than replaced: the local cache may hold lessons seen
    /// while signed out, or on this device before the account existed, and
    /// re-teaching something is worse than skipping it. The union is also
    /// the only merge that cannot resurrect a lesson someone has already
    /// dismissed on another device.
    func setUserId(_ userId: String?) {
        guard myUserId != userId else { return }
        myUserId = userId
        guard userId != nil else { return }
        Task { await loadProgress() }
    }

    private func loadProgress() async {
        guard let myUserId else { return }
        do {
            let rows: [WalkthroughProgressRow] = try await supabase
                .from("walkthrough_progress")
                .select("seen_lessons, tour_completed")
                .eq("user_id", value: myUserId)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else {
                // Nothing stored yet — publish what this device knows so
                // an existing user's progress is not lost the first time
                // they reach a second device.
                pushProgress()
                return
            }
            let remoteSeen = Set(row.seenLessons ?? [])
            if !remoteSeen.isSubset(of: seen) {
                seen.formUnion(remoteSeen)
                defaults.set(Array(seen), forKey: seenKey)
            }
            if row.tourCompleted == true, !mechanicsTourCompleted {
                defaults.set(true, forKey: tourDoneKey)
            }
            // Anything this device knew that the server did not now goes up.
            if !Set(row.seenLessons ?? []).isSuperset(of: seen)
                || (mechanicsTourCompleted && row.tourCompleted != true) {
                pushProgress()
            }
        } catch {
            // Teaching is not worth an error state. A failed read simply
            // leaves the local cache in charge, which is what shipped
            // before this table existed.
            Log.walkthrough.error("progress load failed: \(error)")
        }
    }

    /// Fire-and-forget: the local cache is already authoritative for this
    /// launch, so a failed write costs a replay on another device at worst.
    private func pushProgress() {
        guard let myUserId else { return }
        let payload = WalkthroughProgressUpsert(
            userId: myUserId,
            seenLessons: Array(seen),
            tourCompleted: mechanicsTourCompleted,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        Task {
            do {
                try await supabase
                    .from("walkthrough_progress")
                    .upsert(payload, onConflict: "user_id")
                    .execute()
            } catch {
                Log.walkthrough.error("progress push failed: \(error)")
            }
        }
    }
}
