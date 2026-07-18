//
//  SeasonCardModels.swift
//  FrisFocus
//
//  The public "season card" — the small, friend-readable summary of a
//  person's season life that powers the poster profile pages. The
//  owner's device builds it from the live Season (+ archived past
//  seasons) and publishes it to `profiles.season_card` as JSON;
//  friends decode it straight off the profile row.
//
//  Pure data, Codable, no UI dependencies. Everything is optional and
//  decoded tolerantly so cards written by newer builds still parse.
//

import Foundation

// MARK: - Season covers

/// The curated set of atmospheric season covers a person can pick for
/// their profile poster. Raw values are stored in the season card, so
/// they must stay stable.
nonisolated enum SeasonCoverKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case firstLight
    case goldenHour
    case harvest
    case deepWinter
    case nightSky
    case coastline
    case forest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstLight: return "First light"
        case .goldenHour: return "Golden hour"
        case .harvest: return "Harvest"
        case .deepWinter: return "Deep winter"
        case .nightSky: return "Night sky"
        case .coastline: return "Coastline"
        case .forest: return "Forest"
        }
    }
}

// MARK: - Past season summary

/// One archived season, kept as a small chapter card: what it was
/// called, when it ran, and how many milestones landed.
nonisolated struct PastSeasonSummary: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var startDate: Date
    var endDate: Date
    var milestonesReached: Int = 0
    var milestonesTotal: Int = 0
    var coverId: String?
    var accentHex: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, startDate, endDate, milestonesReached, milestonesTotal, coverId, accentHex
    }

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date,
        milestonesReached: Int = 0,
        milestonesTotal: Int = 0,
        coverId: String? = nil,
        accentHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.milestonesReached = milestonesReached
        self.milestonesTotal = milestonesTotal
        self.coverId = coverId
        self.accentHex = accentHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.name = (try c.decodeIfPresent(String.self, forKey: .name)) ?? "A season"
        self.startDate = (try c.decodeIfPresent(Date.self, forKey: .startDate)) ?? Date()
        self.endDate = (try c.decodeIfPresent(Date.self, forKey: .endDate)) ?? Date()
        self.milestonesReached = (try c.decodeIfPresent(Int.self, forKey: .milestonesReached)) ?? 0
        self.milestonesTotal = (try c.decodeIfPresent(Int.self, forKey: .milestonesTotal)) ?? 0
        self.coverId = try c.decodeIfPresent(String.self, forKey: .coverId)
        self.accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex)
    }

    /// "ran 6 weeks" / "ran 12 days" — the human length line.
    var ranDescription: String {
        let days = max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        if days >= 14 {
            let weeks = days / 7
            return "ran \(weeks) week\(weeks == 1 ? "" : "s")"
        }
        return "ran \(days) day\(days == 1 ? "" : "s")"
    }
}

// MARK: - Card milestone

/// One of the season's destinations, as friends may see it: its name,
/// whether it landed (and when), and live step progress for the one
/// in flight. Shared only at tiers that already see goal progress —
/// the viewer side gates rendering.
nonisolated struct SeasonCardMilestone: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var weekNumber: Int = 1
    /// Optional user-chosen target date — friends see "by Oct 12" when set.
    var targetDate: Date?
    var isDone: Bool = false
    var completedDate: Date?
    var stepsDone: Int?
    var stepsTotal: Int?

    private enum CodingKeys: String, CodingKey {
        case id, title, weekNumber, targetDate, isDone, completedDate, stepsDone, stepsTotal
    }

    init(
        id: UUID = UUID(),
        title: String,
        weekNumber: Int = 1,
        targetDate: Date? = nil,
        isDone: Bool = false,
        completedDate: Date? = nil,
        stepsDone: Int? = nil,
        stepsTotal: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.weekNumber = weekNumber
        self.targetDate = targetDate
        self.isDone = isDone
        self.completedDate = completedDate
        self.stepsDone = stepsDone
        self.stepsTotal = stepsTotal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? "A destination"
        self.weekNumber = (try c.decodeIfPresent(Int.self, forKey: .weekNumber)) ?? 1
        self.targetDate = try c.decodeIfPresent(Date.self, forKey: .targetDate)
        self.isDone = (try c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        self.completedDate = try c.decodeIfPresent(Date.self, forKey: .completedDate)
        self.stepsDone = try c.decodeIfPresent(Int.self, forKey: .stepsDone)
        self.stepsTotal = try c.decodeIfPresent(Int.self, forKey: .stepsTotal)
    }
}

// MARK: - Season card

/// The friend-readable summary of a person's season life. Published as
/// JSON in `profiles.season_card` by the owner's device, decoded by
/// everyone who renders their profile.
nonisolated struct SeasonCard: Codable, Equatable, Sendable {
    var coverId: String?
    var accentHex: String?
    var intention: String?
    var seasonName: String?
    var seasonStartDate: Date?
    var seasonLengthDays: Int?
    var milestonesDone: Int?
    var milestonesTotal: Int?
    var pastSeasons: [PastSeasonSummary] = []

    /// Total distinct days this person has ever shown up — the one
    /// number that matters on the identity card.
    var lifetimeDays: Int?
    /// A small owner-set status under the intention ("resting this
    /// week", "locked in"). Visible to friends until changed.
    var moodLine: String?
    /// The season's destinations with names + status, for the vertical
    /// timeline. Viewer-gated to tiers that see goal progress.
    var milestones: [SeasonCardMilestone] = []

    private enum CodingKeys: String, CodingKey {
        case coverId, accentHex, intention, seasonName
        case seasonStartDate, seasonLengthDays
        case milestonesDone, milestonesTotal, pastSeasons
        case lifetimeDays, moodLine, milestones
    }

    init(
        coverId: String? = nil,
        accentHex: String? = nil,
        intention: String? = nil,
        seasonName: String? = nil,
        seasonStartDate: Date? = nil,
        seasonLengthDays: Int? = nil,
        milestonesDone: Int? = nil,
        milestonesTotal: Int? = nil,
        pastSeasons: [PastSeasonSummary] = [],
        lifetimeDays: Int? = nil,
        moodLine: String? = nil,
        milestones: [SeasonCardMilestone] = []
    ) {
        self.coverId = coverId
        self.accentHex = accentHex
        self.intention = intention
        self.seasonName = seasonName
        self.seasonStartDate = seasonStartDate
        self.seasonLengthDays = seasonLengthDays
        self.milestonesDone = milestonesDone
        self.milestonesTotal = milestonesTotal
        self.pastSeasons = pastSeasons
        self.lifetimeDays = lifetimeDays
        self.moodLine = moodLine
        self.milestones = milestones
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.coverId = try c.decodeIfPresent(String.self, forKey: .coverId)
        self.accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex)
        self.intention = try c.decodeIfPresent(String.self, forKey: .intention)
        self.seasonName = try c.decodeIfPresent(String.self, forKey: .seasonName)
        self.seasonStartDate = try c.decodeIfPresent(Date.self, forKey: .seasonStartDate)
        self.seasonLengthDays = try c.decodeIfPresent(Int.self, forKey: .seasonLengthDays)
        self.milestonesDone = try c.decodeIfPresent(Int.self, forKey: .milestonesDone)
        self.milestonesTotal = try c.decodeIfPresent(Int.self, forKey: .milestonesTotal)
        self.pastSeasons = (try c.decodeIfPresent([PastSeasonSummary].self, forKey: .pastSeasons)) ?? []
        self.lifetimeDays = try c.decodeIfPresent(Int.self, forKey: .lifetimeDays)
        self.moodLine = try c.decodeIfPresent(String.self, forKey: .moodLine)
        self.milestones = (try c.decodeIfPresent([SeasonCardMilestone].self, forKey: .milestones)) ?? []
    }

    /// The chosen cover, when the raw id resolves to a known kind.
    var cover: SeasonCoverKind? {
        coverId.flatMap(SeasonCoverKind.init(rawValue:))
    }

    /// Whether this card carries no real season identity — used so an
    /// empty card can never be published over a friend-visible one that
    /// still has content.
    var isEmpty: Bool {
        (intention?.isEmpty ?? true)
            && (seasonName?.isEmpty ?? true)
            && (moodLine?.isEmpty ?? true)
            && coverId == nil
            && milestones.isEmpty
            && pastSeasons.isEmpty
    }

    /// 1-based day into the current season, clamped to its length when
    /// one was published. Nil when the card carries no start date.
    var currentDay: Int? {
        guard let start = seasonStartDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: start),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        let day = max(1, days + 1)
        if let length = seasonLengthDays, length > 0 { return min(day, length) }
        return day
    }

    // MARK: JSON bridge

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Encode this card to the JSON string stored on the profile row.
    func encodedJSON() -> String? {
        guard let data = try? Self.encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a card from a profile row's raw JSON. Nil-tolerant — a
    /// missing or malformed payload simply yields no card.
    static func decode(fromJSON string: String?) -> SeasonCard? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(SeasonCard.self, from: data)
    }
}
