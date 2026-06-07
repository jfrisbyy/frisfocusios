//
//  SampleData.swift
//  FrisFocus
//
//  Hardcoded data for Prompt 1 (UI-only). A later prompt replaces this
//  with real persistence.
//

import SwiftUI

// MARK: - Category

enum TaskCategory {
    case fitness
    case work
    case health
    case spiritual
    case creative

    var color: Color {
        switch self {
        case .fitness: return Theme.categoryFitness
        case .work: return Theme.categoryWork
        case .health: return Theme.categoryHealth
        case .spiritual: return Theme.categorySpiritual
        case .creative: return Theme.categoryCreative
        }
    }

    var label: String {
        switch self {
        case .fitness: return "Fitness"
        case .work: return "FrisFocus"
        case .health: return "Health"
        case .spiritual: return "Spiritual"
        case .creative: return "Creative"
        }
    }
}

// MARK: - Tier

enum TaskTier {
    case must
    case should
    case could

    var label: String {
        switch self {
        case .must: return "MUST"
        case .should: return "SHOULD"
        case .could: return "COULD"
        }
    }

    var color: Color {
        switch self {
        case .must: return Theme.alertRed
        case .should: return Theme.alertAmber
        case .could: return Theme.textSecondary
        }
    }
}

// MARK: - Today's Few task

struct TodayTask: Identifiable {
    let id = UUID()
    let title: String
    let category: TaskCategory
    let tier: TaskTier?
    let extra: String?     // e.g. "90 min"
    let points: Int
    let pinned: Bool
}

// MARK: - One-shot / Loose end

struct OneShotItem: Identifiable {
    let id = UUID()
    let title: String
    let due: String       // e.g. "Thu 2pm", "today", "no rush", "One-shot · 2d late"
    let points: Int?      // nil = no point value
    let isHero: Bool      // true for the "Call grandma" card in Today's Few
}

// MARK: - Alert

enum AlertSeverity {
    case red
    case amber

    var color: Color {
        switch self {
        case .red: return Theme.alertRed
        case .amber: return Theme.alertAmber
        }
    }

    var iconName: String {
        switch self {
        case .red: return "exclamationmark.triangle"
        case .amber: return "clock.badge.exclamationmark"
        }
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let severity: AlertSeverity
    let title: String
    let subtitle: String
}

// MARK: - Note zone

struct NoteEntry: Identifiable {
    let id = UUID()
    let time: String       // e.g. "8:14 AM"
    let label: String      // e.g. "morning pages"
    let body: String
}

struct VoiceMemo: Identifiable {
    let id = UUID()
    let duration: String   // e.g. "1:47"
    let subtitle: String
}

struct FolderTag: Identifiable {
    let id = UUID()
    let name: String
    let backgroundColor: Color
    let textColor: Color
}

// MARK: - Signal zone

struct CircleEntry: Identifiable {
    let id = UUID()
    let initial: String
    let avatarColor: Color
    let name: String
    let dayScore: Int
    let season: String
    let hasFlame: Bool
    let status: String
}

// MARK: - Sample data container

enum SampleData {
    // Sun zone
    static let dateLine = "Tue · May 26"
    static let season = "Album Season"
    static let seasonDayNumber = 23
    static let seasonDayTotal = 60
    static let todayScore = 32
    static let todayGoal = 50
    static let weekScore = 112
    static let weekGoal = 350

    // Today's Few
    static let todayTasks: [TodayTask] = [
        TodayTask(
            title: "Lift — push day",
            category: .fitness,
            tier: .must,
            extra: nil,
            points: 10,
            pinned: true
        ),
        TodayTask(
            title: "Ship v2 onboarding to TestFlight",
            category: .work,
            tier: nil,
            extra: "90 min",
            points: 15,
            pinned: true
        )
    ]

    static let todayOneShot = OneShotItem(
        title: "Call grandma",
        due: "One-shot · 2d late",
        points: 4,
        isHero: true
    )

    // Loose Ends
    static let looseEnds: [OneShotItem] = [
        OneShotItem(title: "Doctor — annual physical", due: "Thu 2pm", points: 6, isHero: false),
        OneShotItem(title: "Email landlord about the radiator", due: "today", points: 2, isHero: false),
        OneShotItem(title: "Replace bathroom lightbulb", due: "no rush", points: nil, isHero: false)
    ]

    // Needs You
    static let alerts: [AlertItem] = [
        AlertItem(
            severity: .red,
            title: "Morning prayer + reading hasn’t been logged today.",
            subtitle: "Must-Do · skipping it pulls −5 from the day"
        ),
        AlertItem(
            severity: .amber,
            title: "No Creative time logged in 6 days.",
            subtitle: "The EP doesn’t write itself. Worth 15 min today?"
        )
    ]

    // Note zone
    static let noteEntry = NoteEntry(
        time: "8:14 AM",
        label: "morning pages",
        body: "Slept rough. Mind kept circling the v2 onboarding — the empty state copy still isn’t right. Going to lift first to clear it, then sit with the screen. Don’t open Slack until after."
    )

    static let voiceMemo = VoiceMemo(
        duration: "1:47",
        subtitle: "A verse idea for Northup that came on the walk"
    )

    static let folders: [FolderTag] = [
        FolderTag(name: "Songs", backgroundColor: Theme.folderSongsBg, textColor: Theme.folderSongsText),
        FolderTag(name: "Prayer", backgroundColor: Theme.folderPrayerBg, textColor: Theme.folderPrayerText),
        FolderTag(name: "Work", backgroundColor: Theme.folderWorkBg, textColor: Theme.folderWorkText)
    ]

    // Signal zone
    static let circleEntries: [CircleEntry] = [
        CircleEntry(
            initial: "A",
            avatarColor: Theme.alertGreen,
            name: "Aaron",
            dayScore: 38,
            season: "Heal Season",
            hasFlame: true,
            status: "Hit gym + got back to writing for the first time in a week. Trying to remember it doesn’t have to be perfect."
        ),
        CircleEntry(
            initial: "M",
            avatarColor: Theme.categoryCreative,
            name: "Madison",
            dayScore: 12,
            season: "Reset Season",
            hasFlame: false,
            status: "Slow morning. Just got out of bed lol. Going to lock in this afternoon though."
        )
    ]
}
