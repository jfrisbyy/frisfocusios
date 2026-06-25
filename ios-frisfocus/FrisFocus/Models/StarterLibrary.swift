//
//  StarterLibrary.swift
//  FrisFocus
//
//  The curated content behind the 60-second cold start. A person picks
//  one or more focus areas; each area instantly surfaces its Tier-1
//  starter set (6-8 broadly-useful tasks) with a deeper Tier-2 bench
//  revealed only on "Browse more". Everything is local — the tile path
//  never touches the network.
//
//  Every task carries a `lifeArea` grouping (Body, Mind & Rest, …) that
//  maps onto the app's existing `Category` so a cold-start board is
//  structured from minute one and the later season conversation inherits
//  a sorted board. Areas + groupings are friendly suggestions, never
//  hard-wired buckets: a person can rename, regroup, or remove freely.
//
//  Iconography is a single consistent SF line-icon set rendered in each
//  area's tint — no emoji anywhere.
//

import Foundation
import SwiftUI

// MARK: - Life-area grouping

/// The cross-area life-areas every starter task is tagged with. These
/// are shown as gentle groupings and map onto the app's `Category` so
/// the board plugs straight into scoring and the profile.
enum LibraryLifeArea: String, Codable, CaseIterable, Identifiable {
    case body
    case mindRest
    case work
    case faith
    case connection
    case homeMoney
    case recovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .body:       return "Body"
        case .mindRest:   return "Mind & Rest"
        case .work:       return "Work & Craft"
        case .faith:      return "Faith & Spirit"
        case .connection: return "Connection"
        case .homeMoney:  return "Home & Money"
        case .recovery:   return "Recovery & Care"
        }
    }

    /// Consistent SF line-icon for the grouping (no emoji).
    var symbol: String {
        switch self {
        case .body:       return "figure.run"
        case .mindRest:   return "brain.head.profile"
        case .work:       return "hammer"
        case .faith:      return "hands.and.sparkles"
        case .connection: return "person.2"
        case .homeMoney:  return "house"
        case .recovery:   return "heart"
        }
    }

    /// How the grouping plugs into the app's existing category system.
    var appCategory: Category {
        switch self {
        case .body:       return .fitness
        case .mindRest:   return .health
        case .work:       return .work
        case .faith:      return .spiritual
        case .connection: return .creative
        case .homeMoney:  return .apartment
        case .recovery:   return .health
        }
    }

    var tint: Color { appCategory.color }
}

// MARK: - Focus area

/// One of the ten focus areas shown on the cold-start direction grid.
struct StarterFocusArea: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    /// SF line-icon rendered in `tint`.
    let symbol: String
    private let tintHex: UInt32

    var tint: Color { Color(hex: tintHex) }

    init(id: String, title: String, subtitle: String, symbol: String, tintHex: UInt32) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tintHex = tintHex
    }
}

// MARK: - Starter task

/// A single suggested task in the library. `id` is a stable string used
/// for de-duplication across directions; a real `FFTask` (with a UUID)
/// is minted only when the board is committed.
struct StarterTask: Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    let blurb: String
    let lifeArea: LibraryLifeArea
    let focusAreaId: String
    /// 1 = surfaced first, 2 = revealed under "Browse more".
    let tier: Int
}

// MARK: - The library

enum StarterLibrary {
    /// The ten focus areas, in grid order.
    static let focusAreas: [StarterFocusArea] = [
        StarterFocusArea(id: "fitness", title: "Health & Fitness", subtitle: "Move more, feel good", symbol: "figure.strengthtraining.traditional", tintHex: 0xD85A30),
        StarterFocusArea(id: "faith", title: "Faith & Spirit", subtitle: "Stay close to what you believe", symbol: "hands.and.sparkles", tintHex: 0x7F77DD),
        StarterFocusArea(id: "work", title: "Work & Building", subtitle: "Build something of your own", symbol: "hammer", tintHex: 0x185FA5),
        StarterFocusArea(id: "school", title: "School & Learning", subtitle: "A season of study", symbol: "book", tintHex: 0x3F8E8E),
        StarterFocusArea(id: "calm", title: "Mental Health & Calm", subtitle: "Lower the noise", symbol: "leaf", tintHex: 0x639922),
        StarterFocusArea(id: "creative", title: "Creativity & Craft", subtitle: "Keep the work alive", symbol: "paintbrush.pointed", tintHex: 0x993556),
        StarterFocusArea(id: "money", title: "Money & Discipline", subtitle: "Build control", symbol: "banknote", tintHex: 0xBA7517),
        StarterFocusArea(id: "connection", title: "Relationships", subtitle: "Show up for your people", symbol: "person.2", tintHex: 0xC25A7A),
        StarterFocusArea(id: "recovery", title: "Recovery & Sobriety", subtitle: "One day at a time", symbol: "sunrise", tintHex: 0x2E8B6F),
        StarterFocusArea(id: "home", title: "Home & Order", subtitle: "Get your space in order", symbol: "house", tintHex: 0x8E7B60)
    ]

    static func focusArea(_ id: String) -> StarterFocusArea? {
        focusAreas.first { $0.id == id }
    }

    /// Tier-1 starter set for an area, in broad-appeal order.
    static func tier1(for areaId: String) -> [StarterTask] {
        allTasks.filter { $0.focusAreaId == areaId && $0.tier == 1 }
    }

    /// Tier-2 bench for an area, in author order.
    static func tier2(for areaId: String) -> [StarterTask] {
        allTasks.filter { $0.focusAreaId == areaId && $0.tier == 2 }
    }

    // MARK: Free-text routing (local, no network)

    /// Cheap keyword → focus-area map so common free text routes without
    /// any model call. Lowercased, substring matched.
    private static let synonyms: [String: String] = [
        "gym": "fitness", "lift": "fitness", "lifting": "fitness", "workout": "fitness",
        "fit": "fitness", "run": "fitness", "running": "fitness", "weight": "fitness",
        "exercise": "fitness", "strong": "fitness", "health": "fitness",
        "pray": "faith", "prayer": "faith", "god": "faith", "bible": "faith",
        "scripture": "faith", "faith": "faith", "church": "faith", "spirit": "faith",
        "work": "work", "founder": "work", "startup": "work", "build": "work",
        "business": "work", "side project": "work", "ship": "work",
        "school": "school", "study": "school", "exam": "school", "class": "school",
        "student": "school", "homework": "school", "learn": "school",
        "calm": "calm", "anxiety": "calm", "stress": "calm", "mental": "calm",
        "depress": "calm", "mindful": "calm", "meditat": "calm", "peace": "calm",
        "write": "creative", "writing": "creative", "music": "creative",
        "art": "creative", "create": "creative", "creative": "creative",
        "draw": "creative", "make": "creative",
        "money": "money", "save": "money", "budget": "money", "spend": "money",
        "debt": "money", "finance": "money",
        "relationship": "connection", "family": "connection", "friend": "connection",
        "love": "connection", "connect": "connection", "people": "connection",
        "sober": "recovery", "sobriety": "recovery", "clean": "recovery",
        "addict": "recovery", "recovery": "recovery", "quit": "recovery",
        "home": "home", "clean house": "home", "tidy": "home", "declutter": "home",
        "organize": "home", "order": "home"
    ]

    /// Route free text to an existing area id, or nil if genuinely
    /// unmapped (the caller then builds a general fallback board).
    static func route(freeText: String) -> String? {
        let lower = freeText.lowercased()
        for (keyword, areaId) in synonyms where lower.contains(keyword) {
            return areaId
        }
        return nil
    }

    /// A sensible blended "showing up" board for an unmapped intent —
    /// never blocks the user, never invents a bad task.
    static func generalBoard() -> [StarterTask] {
        let ids = ["fit-move", "calm-checkin", "work-deep", "calm-outside", "connection-reach", "home-bed", "fit-sleep"]
        return ids.compactMap { id in allTasks.first { $0.id == id } }
    }

    // MARK: All tasks

    static let allTasks: [StarterTask] = healthFitness + faithSpirit + workBuilding
        + schoolLearning + mentalCalm + creativityCraft + moneyDiscipline
        + relationships + recoverySobriety + homeOrder

    // MARK: 1. Health & Fitness

    private static let healthFitness: [StarterTask] = [
        StarterTask(id: "fit-move", label: "Morning movement", blurb: "A walk, a stretch — anything before the day starts.", lifeArea: .body, focusAreaId: "fitness", tier: 1),
        StarterTask(id: "fit-strength", label: "Strength session", blurb: "Lift, bodyweight, or resistance.", lifeArea: .body, focusAreaId: "fitness", tier: 1),
        StarterTask(id: "fit-steps", label: "Hit your steps", blurb: "Keep the body moving through the day.", lifeArea: .body, focusAreaId: "fitness", tier: 1),
        StarterTask(id: "fit-meals", label: "Real meals", blurb: "Eat like you respect yourself today.", lifeArea: .body, focusAreaId: "fitness", tier: 1),
        StarterTask(id: "fit-water", label: "Water", blurb: "Actually drink it.", lifeArea: .body, focusAreaId: "fitness", tier: 1),
        StarterTask(id: "fit-sleep", label: "Sleep by a set time", blurb: "The workout that happens lying down.", lifeArea: .mindRest, focusAreaId: "fitness", tier: 1),
        StarterTask(id: "fit-stretch", label: "Stretch or mobility", blurb: "Ten minutes, joints and all.", lifeArea: .body, focusAreaId: "fitness", tier: 1),
        StarterTask(id: "fit-cardio", label: "Cardio / conditioning", blurb: "A run or an easy zone-2 session.", lifeArea: .body, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-protein", label: "Protein with every meal", blurb: "Build the day around it.", lifeArea: .body, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-cold", label: "Cold shower / contrast", blurb: "A jolt of reset.", lifeArea: .recovery, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-foam", label: "Foam roll / recover", blurb: "Let the body catch up.", lifeArea: .recovery, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-track", label: "Track one lift's progress", blurb: "Watch a number climb.", lifeArea: .body, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-sun", label: "Sunlight in the morning", blurb: "Set the clock straight.", lifeArea: .mindRest, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-rest", label: "Rest day, on purpose", blurb: "Recovery is training too.", lifeArea: .recovery, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-stand", label: "Stand / move every hour", blurb: "Break up the sitting.", lifeArea: .body, focusAreaId: "fitness", tier: 2),
        StarterTask(id: "fit-caffeine", label: "Caffeine cutoff", blurb: "Protect tonight's sleep.", lifeArea: .mindRest, focusAreaId: "fitness", tier: 2)
    ]

    // MARK: 2. Faith & Spirit

    private static let faithSpirit: [StarterTask] = [
        StarterTask(id: "faith-pray", label: "Daily prayer", blurb: "Start or close the day in it.", lifeArea: .faith, focusAreaId: "faith", tier: 1),
        StarterTask(id: "faith-read", label: "Read scripture", blurb: "Even a few verses.", lifeArea: .faith, focusAreaId: "faith", tier: 1),
        StarterTask(id: "faith-quiet", label: "A quiet moment", blurb: "Sit with it, no phone.", lifeArea: .faith, focusAreaId: "faith", tier: 1),
        StarterTask(id: "faith-gratitude", label: "Gratitude", blurb: "Name what you're thankful for.", lifeArea: .faith, focusAreaId: "faith", tier: 1),
        StarterTask(id: "faith-value", label: "Live a value today", blurb: "One deliberate act.", lifeArea: .faith, focusAreaId: "faith", tier: 1),
        StarterTask(id: "faith-gather", label: "Gather / attend", blurb: "Be with your people in it.", lifeArea: .connection, focusAreaId: "faith", tier: 1),
        StarterTask(id: "faith-study", label: "Study a passage deeply", blurb: "Go past the surface.", lifeArea: .faith, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-memorize", label: "Memorize a verse", blurb: "Carry it with you.", lifeArea: .faith, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-service", label: "Service to someone", blurb: "Faith with hands.", lifeArea: .connection, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-journal", label: "Journal a reflection", blurb: "Think it through on paper.", lifeArea: .faith, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-fast", label: "Fast (meal / media)", blurb: "Make a little room.", lifeArea: .faith, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-examine", label: "Examine the day before bed", blurb: "Look back honestly.", lifeArea: .faith, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-tithe", label: "Tithe / give", blurb: "Put it where your heart is.", lifeArea: .homeMoney, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-worship", label: "Worship / music", blurb: "Let it lift you.", lifeArea: .faith, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-reach", label: "Reach out to someone struggling", blurb: "Be the answer to a prayer.", lifeArea: .connection, focusAreaId: "faith", tier: 2),
        StarterTask(id: "faith-sabbath", label: "Rest the sabbath", blurb: "Stop, on purpose.", lifeArea: .recovery, focusAreaId: "faith", tier: 2)
    ]

    // MARK: 3. Work & Building

    private static let workBuilding: [StarterTask] = [
        StarterTask(id: "work-deep", label: "Deep work block", blurb: "One real, uninterrupted session.", lifeArea: .work, focusAreaId: "work", tier: 1),
        StarterTask(id: "work-ship", label: "Ship something", blurb: "Move the thing forward, however small.", lifeArea: .work, focusAreaId: "work", tier: 1),
        StarterTask(id: "work-mit", label: "Most important task first", blurb: "Before the noise.", lifeArea: .work, focusAreaId: "work", tier: 1),
        StarterTask(id: "work-user", label: "Talk to a user", blurb: "Get outside your own head.", lifeArea: .connection, focusAreaId: "work", tier: 1),
        StarterTask(id: "work-plan", label: "Plan tomorrow", blurb: "Five minutes, end of day.", lifeArea: .work, focusAreaId: "work", tier: 1),
        StarterTask(id: "work-learn", label: "Learn", blurb: "Read, a course, a skill you're missing.", lifeArea: .mindRest, focusAreaId: "work", tier: 1),
        StarterTask(id: "work-nomtg", label: "No meetings before a set time", blurb: "Protect the morning.", lifeArea: .work, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-inbox", label: "Inbox to zero, once", blurb: "Clear the deck.", lifeArea: .work, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-outreach", label: "Outreach (cold or warm)", blurb: "One message that matters.", lifeArea: .connection, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-public", label: "Build in public", blurb: "Share the progress.", lifeArea: .work, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-numbers", label: "Review your numbers", blurb: "Eyes on the dashboard.", lifeArea: .homeMoney, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-hard", label: "One hard conversation", blurb: "The one you're avoiding.", lifeArea: .connection, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-single", label: "Single-task, no tab-switching", blurb: "One thing at a time.", lifeArea: .work, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-close", label: "Close the laptop by a set time", blurb: "Call it a day.", lifeArea: .mindRest, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-review", label: "Weekly review", blurb: "Zoom out once a week.", lifeArea: .work, focusAreaId: "work", tier: 2),
        StarterTask(id: "work-network", label: "One new connection", blurb: "Widen the circle.", lifeArea: .connection, focusAreaId: "work", tier: 2)
    ]

    // MARK: 4. School & Learning

    private static let schoolLearning: [StarterTask] = [
        StarterTask(id: "school-study", label: "Focused study block", blurb: "Phone away, real work.", lifeArea: .work, focusAreaId: "school", tier: 1),
        StarterTask(id: "school-attend", label: "Show up to class", blurb: "Half the battle.", lifeArea: .work, focusAreaId: "school", tier: 1),
        StarterTask(id: "school-review", label: "Review today's notes", blurb: "Before they go cold.", lifeArea: .work, focusAreaId: "school", tier: 1),
        StarterTask(id: "school-read", label: "Read the assigned material", blurb: "Keep up with it.", lifeArea: .mindRest, focusAreaId: "school", tier: 1),
        StarterTask(id: "school-ahead", label: "Work ahead on one assignment", blurb: "Buy yourself room.", lifeArea: .work, focusAreaId: "school", tier: 1),
        StarterTask(id: "school-sleep", label: "Sleep enough to think", blurb: "The brain needs it.", lifeArea: .mindRest, focusAreaId: "school", tier: 1),
        StarterTask(id: "school-help", label: "Office hours / ask for help", blurb: "Don't stay stuck.", lifeArea: .connection, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-practice", label: "Practice problems", blurb: "Reps beat re-reading.", lifeArea: .work, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-recall", label: "Flashcards / active recall", blurb: "Test yourself.", lifeArea: .work, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-group", label: "Group study", blurb: "Learn out loud.", lifeArea: .connection, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-outline", label: "Outline before writing", blurb: "Find the shape first.", lifeArea: .work, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-deadlines", label: "Plan the week's deadlines", blurb: "No surprises.", lifeArea: .work, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-teach", label: "Teach it to someone", blurb: "The real test of knowing.", lifeArea: .connection, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-sprints", label: "Break study into sprints", blurb: "Focus, then breathe.", lifeArea: .work, focusAreaId: "school", tier: 2),
        StarterTask(id: "school-eat", label: "Eat before exams", blurb: "Don't run on empty.", lifeArea: .body, focusAreaId: "school", tier: 2)
    ]

    // MARK: 5. Mental Health & Calm

    private static let mentalCalm: [StarterTask] = [
        StarterTask(id: "calm-checkin", label: "Check in with yourself", blurb: "How am I, really.", lifeArea: .recovery, focusAreaId: "calm", tier: 1),
        StarterTask(id: "calm-move", label: "Move your body", blurb: "The simplest reset.", lifeArea: .body, focusAreaId: "calm", tier: 1),
        StarterTask(id: "calm-outside", label: "Get outside", blurb: "Light and air.", lifeArea: .mindRest, focusAreaId: "calm", tier: 1),
        StarterTask(id: "calm-scroll", label: "Limit the doomscroll", blurb: "A real cutoff.", lifeArea: .mindRest, focusAreaId: "calm", tier: 1),
        StarterTask(id: "calm-connect", label: "One real connection", blurb: "Text or call someone.", lifeArea: .connection, focusAreaId: "calm", tier: 1),
        StarterTask(id: "calm-wind", label: "Wind down before bed", blurb: "No screens, low lights.", lifeArea: .mindRest, focusAreaId: "calm", tier: 1),
        StarterTask(id: "calm-breath", label: "Breathwork / meditate", blurb: "A few slow minutes.", lifeArea: .recovery, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-journal", label: "Journal what's heavy", blurb: "Get it out of your head.", lifeArea: .recovery, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-win", label: "One small win, on purpose", blurb: "Stack a little momentum.", lifeArea: .recovery, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-tidy", label: "Tidy one space", blurb: "Outer order, inner calm.", lifeArea: .homeMoney, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-no", label: "Say no to one thing", blurb: "Protect your energy.", lifeArea: .recovery, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-therapy", label: "Therapy / appointment", blurb: "Keep the support going.", lifeArea: .recovery, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-grat", label: "Gratitude, three things", blurb: "Tilt toward the good.", lifeArea: .faith, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-offphone", label: "Time off the phone, fully", blurb: "Unplug for real.", lifeArea: .mindRest, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-ask", label: "Ask for help with one thing", blurb: "You don't carry it alone.", lifeArea: .connection, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-meds", label: "Take meds / vitamins", blurb: "The boring basics.", lifeArea: .recovery, focusAreaId: "calm", tier: 2),
        StarterTask(id: "calm-nature", label: "Be in nature", blurb: "Let it settle you.", lifeArea: .mindRest, focusAreaId: "calm", tier: 2)
    ]

    // MARK: 6. Creativity & Craft

    private static let creativityCraft: [StarterTask] = [
        StarterTask(id: "create-make", label: "Make something today", blurb: "Words, sound, anything.", lifeArea: .work, focusAreaId: "creative", tier: 1),
        StarterTask(id: "create-practice", label: "Show up to the practice", blurb: "Instrument, page, or tool.", lifeArea: .work, focusAreaId: "creative", tier: 1),
        StarterTask(id: "create-capture", label: "Capture ideas", blurb: "Don't let them slip.", lifeArea: .work, focusAreaId: "creative", tier: 1),
        StarterTask(id: "create-study", label: "Study the greats", blurb: "Read, listen, watch with intent.", lifeArea: .mindRest, focusAreaId: "creative", tier: 1),
        StarterTask(id: "create-finish", label: "Finish, don't just start", blurb: "Close one small loop.", lifeArea: .work, focusAreaId: "creative", tier: 1),
        StarterTask(id: "create-share", label: "Share your work", blurb: "Let it be seen.", lifeArea: .connection, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-pages", label: "Daily pages / free-write", blurb: "Clear the channel.", lifeArea: .work, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-fundamental", label: "Practice a fundamental", blurb: "Sharpen the basics.", lifeArea: .work, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-collab", label: "Collaborate with someone", blurb: "Make it bigger than you.", lifeArea: .connection, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-edit", label: "Edit / revise", blurb: "The work behind the work.", lifeArea: .work, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-archive", label: "Build the archive", blurb: "Keep what you make.", lifeArea: .work, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-risk", label: "One creative risk", blurb: "Try the scary idea.", lifeArea: .work, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-refill", label: "Step away to refill the well", blurb: "Rest feeds the work.", lifeArea: .recovery, focusAreaId: "creative", tier: 2),
        StarterTask(id: "create-setup", label: "Set up tomorrow's session", blurb: "Make starting easy.", lifeArea: .work, focusAreaId: "creative", tier: 2)
    ]

    // MARK: 7. Money & Discipline

    private static let moneyDiscipline: [StarterTask] = [
        StarterTask(id: "money-balance", label: "Check your balance", blurb: "Eyes open, no flinching.", lifeArea: .homeMoney, focusAreaId: "money", tier: 1),
        StarterTask(id: "money-log", label: "Log what you spent today", blurb: "Know where it goes.", lifeArea: .homeMoney, focusAreaId: "money", tier: 1),
        StarterTask(id: "money-nospend", label: "No-spend on your weak spot", blurb: "Skip the usual leak.", lifeArea: .homeMoney, focusAreaId: "money", tier: 1),
        StarterTask(id: "money-save", label: "Move money to savings / debt", blurb: "Pay your future first.", lifeArea: .homeMoney, focusAreaId: "money", tier: 1),
        StarterTask(id: "money-cook", label: "Cook instead of order", blurb: "The cheapest good meal.", lifeArea: .body, focusAreaId: "money", tier: 1),
        StarterTask(id: "money-pack", label: "Pack lunch / coffee at home", blurb: "Small leaks, big sum.", lifeArea: .homeMoney, focusAreaId: "money", tier: 2),
        StarterTask(id: "money-subs", label: "Review subscriptions", blurb: "Cut what you forgot.", lifeArea: .homeMoney, focusAreaId: "money", tier: 2),
        StarterTask(id: "money-goal", label: "One step on a financial goal", blurb: "Inch the needle.", lifeArea: .homeMoney, focusAreaId: "money", tier: 2),
        StarterTask(id: "money-side", label: "Side-income hour", blurb: "Build another stream.", lifeArea: .work, focusAreaId: "money", tier: 2),
        StarterTask(id: "money-wait", label: "Wait 24h before buying", blurb: "Beat the impulse.", lifeArea: .homeMoney, focusAreaId: "money", tier: 2),
        StarterTask(id: "money-read", label: "Read on money", blurb: "Get a little wiser.", lifeArea: .mindRest, focusAreaId: "money", tier: 2),
        StarterTask(id: "money-bill", label: "Pay a bill on time", blurb: "No late fees.", lifeArea: .homeMoney, focusAreaId: "money", tier: 2),
        StarterTask(id: "money-sell", label: "Sell one unused thing", blurb: "Turn clutter into cash.", lifeArea: .homeMoney, focusAreaId: "money", tier: 2)
    ]

    // MARK: 8. Relationships & Connection

    private static let relationships: [StarterTask] = [
        StarterTask(id: "connection-reach", label: "Reach out to someone first", blurb: "Make the move.", lifeArea: .connection, focusAreaId: "connection", tier: 1),
        StarterTask(id: "connection-present", label: "Real presence", blurb: "Phone down with people.", lifeArea: .connection, focusAreaId: "connection", tier: 1),
        StarterTask(id: "connection-care", label: "One act of care", blurb: "Small and deliberate.", lifeArea: .connection, focusAreaId: "connection", tier: 1),
        StarterTask(id: "connection-check", label: "Check on someone struggling", blurb: "Just ask how they are.", lifeArea: .connection, focusAreaId: "connection", tier: 1),
        StarterTask(id: "connection-time", label: "Quality time", blurb: "Make the plan, keep it.", lifeArea: .connection, focusAreaId: "connection", tier: 1),
        StarterTask(id: "connection-family", label: "Call family", blurb: "Hear a familiar voice.", lifeArea: .connection, focusAreaId: "connection", tier: 2),
        StarterTask(id: "connection-appreciate", label: "Express appreciation out loud", blurb: "Say the kind thing.", lifeArea: .connection, focusAreaId: "connection", tier: 2),
        StarterTask(id: "connection-repair", label: "Repair one tension", blurb: "Mend a small rift.", lifeArea: .connection, focusAreaId: "connection", tier: 2),
        StarterTask(id: "connection-ontime", label: "Be on time for people", blurb: "Respect their time.", lifeArea: .connection, focusAreaId: "connection", tier: 2),
        StarterTask(id: "connection-listen", label: "Listen without fixing", blurb: "Just be there.", lifeArea: .connection, focusAreaId: "connection", tier: 2),
        StarterTask(id: "connection-plan", label: "Plan a date / hang", blurb: "Put it on the calendar.", lifeArea: .connection, focusAreaId: "connection", tier: 2),
        StarterTask(id: "connection-remember", label: "Remember the small thing", blurb: "It means a lot.", lifeArea: .connection, focusAreaId: "connection", tier: 2),
        StarterTask(id: "connection-boundary", label: "Set a kind boundary", blurb: "Care includes limits.", lifeArea: .recovery, focusAreaId: "connection", tier: 2)
    ]

    // MARK: 9. Recovery & Sobriety

    private static let recoverySobriety: [StarterTask] = [
        StarterTask(id: "recover-clean", label: "Stay clean today", blurb: "The only day that counts.", lifeArea: .recovery, focusAreaId: "recovery", tier: 1),
        StarterTask(id: "recover-name", label: "Name the urge if it comes", blurb: "Don't hide it.", lifeArea: .recovery, focusAreaId: "recovery", tier: 1),
        StarterTask(id: "recover-reach", label: "Reach your person / group", blurb: "You're not alone in it.", lifeArea: .connection, focusAreaId: "recovery", tier: 1),
        StarterTask(id: "recover-replace", label: "Replace the ritual", blurb: "A walk, a call, a craft.", lifeArea: .recovery, focusAreaId: "recovery", tier: 1),
        StarterTask(id: "recover-basics", label: "Sleep and eat", blurb: "The boring armor.", lifeArea: .body, focusAreaId: "recovery", tier: 1),
        StarterTask(id: "recover-meeting", label: "Meeting / group", blurb: "Show up to the room.", lifeArea: .connection, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-journal", label: "Journal the trigger", blurb: "Learn the pattern.", lifeArea: .recovery, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-grat", label: "Gratitude list", blurb: "Count today's good.", lifeArea: .faith, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-move", label: "Move when it's loud", blurb: "Walk it off.", lifeArea: .body, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-avoid", label: "Avoid the known place / time", blurb: "Don't tempt it.", lifeArea: .recovery, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-help", label: "Help someone else in it", blurb: "Pass it on.", lifeArea: .connection, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-read", label: "Read recovery material", blurb: "Keep the mind on it.", lifeArea: .mindRest, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-count", label: "Celebrate the day count, quietly", blurb: "Honor the streak.", lifeArea: .recovery, focusAreaId: "recovery", tier: 2),
        StarterTask(id: "recover-amends", label: "Make amends, one step", blurb: "Mend what you can.", lifeArea: .connection, focusAreaId: "recovery", tier: 2)
    ]

    // MARK: 10. Home & Order

    private static let homeOrder: [StarterTask] = [
        StarterTask(id: "home-bed", label: "Make the bed", blurb: "Win the first thing.", lifeArea: .homeMoney, focusAreaId: "home", tier: 1),
        StarterTask(id: "home-reset", label: "One reset", blurb: "A counter, a room, a corner.", lifeArea: .homeMoney, focusAreaId: "home", tier: 1),
        StarterTask(id: "home-avoided", label: "Handle one avoided task", blurb: "The one nagging at you.", lifeArea: .homeMoney, focusAreaId: "home", tier: 1),
        StarterTask(id: "home-plan", label: "Plan tomorrow's day", blurb: "Set up your morning.", lifeArea: .work, focusAreaId: "home", tier: 1),
        StarterTask(id: "home-dishes", label: "Dishes done before bed", blurb: "Wake up to a clean sink.", lifeArea: .homeMoney, focusAreaId: "home", tier: 1),
        StarterTask(id: "home-laundry", label: "Laundry cycle", blurb: "Keep it moving.", lifeArea: .homeMoney, focusAreaId: "home", tier: 2),
        StarterTask(id: "home-declutter", label: "15-min declutter", blurb: "Lighten the load.", lifeArea: .homeMoney, focusAreaId: "home", tier: 2),
        StarterTask(id: "home-mealprep", label: "Meal prep", blurb: "Future-you says thanks.", lifeArea: .body, focusAreaId: "home", tier: 2),
        StarterTask(id: "home-message", label: "Answer the avoided message", blurb: "Clear the open loop.", lifeArea: .connection, focusAreaId: "home", tier: 2),
        StarterTask(id: "home-errand", label: "One errand", blurb: "Knock it out.", lifeArea: .homeMoney, focusAreaId: "home", tier: 2),
        StarterTask(id: "home-plants", label: "Water the plants", blurb: "Tend the small things.", lifeArea: .homeMoney, focusAreaId: "home", tier: 2),
        StarterTask(id: "home-papers", label: "Inbox / papers sort", blurb: "Tame the pile.", lifeArea: .work, focusAreaId: "home", tier: 2),
        StarterTask(id: "home-clothes", label: "Prep clothes for tomorrow", blurb: "One less morning decision.", lifeArea: .homeMoney, focusAreaId: "home", tier: 2)
    ]
}
