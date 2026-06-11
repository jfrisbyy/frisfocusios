//
//  SocialModels.swift
//  FrisFocus
//
//  Domain data types for the social layer — Friends, Circles, Signals,
//  Cheers, Story posts (with Likes / Comments), and Media. Pure data,
//  Codable, no UI dependencies. The Store owns the arrays and persists
//  them alongside the existing FrisFocus state.
//
//  Privacy lives on `SharingSettings`: each flag is granular and
//  independent. The signal generator (introduced in C2) reads those
//  flags per-viewer so the same `SignalFact` produces different text
//  for different friends.
//

import Foundation

// MARK: - Granular sharing

/// What another person is allowed to see about me. Every flag is
/// independent so the user can, e.g. share goal status without
/// surfacing specific task names. A fully-private floor always
/// remains — a generic "productive day" signal needs no flags.
struct SharingSettings: Codable, Equatable {
    var shareScore: Bool = true
    var shareGoalStatus: Bool = true
    var shareTaskNames: Bool = false
    var shareMilestones: Bool = false
    var shareMedia: Bool = true

    /// Full-tier sub-choice: when on, the viewer also sees the friend's
    /// open/incomplete items (their whole list); when off, only the
    /// things they finished. Deliberate, off by default so picking Full
    /// never silently over-shares the unfinished list.
    var showOpenItemsAtFull: Bool = false

    init(
        shareScore: Bool = true,
        shareGoalStatus: Bool = true,
        shareTaskNames: Bool = false,
        shareMilestones: Bool = false,
        shareMedia: Bool = true,
        showOpenItemsAtFull: Bool = false
    ) {
        self.shareScore = shareScore
        self.shareGoalStatus = shareGoalStatus
        self.shareTaskNames = shareTaskNames
        self.shareMilestones = shareMilestones
        self.shareMedia = shareMedia
        self.showOpenItemsAtFull = showOpenItemsAtFull
    }

    // Tolerant decoding so settings persisted before any new flag
    // landed still hydrate — every key falls back to its default.
    private enum CodingKeys: String, CodingKey {
        case shareScore, shareGoalStatus, shareTaskNames
        case shareMilestones, shareMedia, showOpenItemsAtFull
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.shareScore = (try c.decodeIfPresent(Bool.self, forKey: .shareScore)) ?? true
        self.shareGoalStatus = (try c.decodeIfPresent(Bool.self, forKey: .shareGoalStatus)) ?? true
        self.shareTaskNames = (try c.decodeIfPresent(Bool.self, forKey: .shareTaskNames)) ?? false
        self.shareMilestones = (try c.decodeIfPresent(Bool.self, forKey: .shareMilestones)) ?? false
        self.shareMedia = (try c.decodeIfPresent(Bool.self, forKey: .shareMedia)) ?? true
        self.showOpenItemsAtFull = (try c.decodeIfPresent(Bool.self, forKey: .showOpenItemsAtFull)) ?? false
    }

    // MARK: - Visibility tier bridge

    /// The human-readable tier this clearance resolves to. Full when
    /// task names are exposed (the real day); Open when only the shape
    /// is visible (score/goal, no tasks); Quiet when neither surfaces.
    var tier: VisibilityTier {
        if shareTaskNames { return .full }
        if shareScore || shareGoalStatus { return .open }
        return .quiet
    }

    /// Build a clearance from a tier. Media stays on for Open/Full so a
    /// proof can still land; the Full open-items sub-choice is carried
    /// through when provided so re-selecting Full preserves it.
    static func from(tier: VisibilityTier, showOpenItemsAtFull: Bool = false) -> SharingSettings {
        switch tier {
        case .quiet: return .quiet
        case .open:  return .open
        case .full:
            var s = SharingSettings.full
            s.showOpenItemsAtFull = showOpenItemsAtFull
            return s
        }
    }

    /// Everything visible — the real day. (Alias kept for callers that
    /// referenced the original name.)
    static var openByDefault: SharingSettings { .full }

    /// Full tier: scores, tasks, milestones, media.
    static var full: SharingSettings {
        SharingSettings(
            shareScore: true,
            shareGoalStatus: true,
            shareTaskNames: true,
            shareMilestones: true,
            shareMedia: true
        )
    }

    /// Open tier: the shape — progress + rhythm, but not the tasks.
    static var open: SharingSettings {
        SharingSettings(
            shareScore: true,
            shareGoalStatus: true,
            shareTaskNames: false,
            shareMilestones: false,
            shareMedia: true
        )
    }

    /// Hit/miss only. Kept as an alias of Open for older call sites.
    static var goalOnly: SharingSettings { .open }

    /// Quiet tier: season + a mood line, no daily detail.
    static var quiet: SharingSettings {
        SharingSettings(
            shareScore: false,
            shareGoalStatus: false,
            shareTaskNames: false,
            shareMilestones: false,
            shareMedia: true
        )
    }

    /// Nothing but presence. Kept as an alias of Quiet for older call
    /// sites; quiet still allows a proof to be sent.
    static var minimal: SharingSettings { .quiet }
}

// MARK: - Friend

/// A one-to-one connection. Stores both directions of clearance so
/// the Signal engine can compose the right read for each viewer:
/// `theirClearanceToMyData` gates what they can see about me,
/// `sharesWithMe` is what they expose to me.
struct Friend: Codable, Identifiable {
    var id: UUID = UUID()
    var displayName: String
    var initials: String
    var accentColorHex: String
    var avatarURL: URL?

    /// Optional custom header background the friend set for their
    /// profile page. Optional so friends persisted before this landed
    /// decode cleanly (missing key → nil → signature-color band).
    var headerURL: URL?

    /// What this friend is allowed to see about me.
    var theirClearanceToMyData: SharingSettings = SharingSettings()

    /// Snapshot of the friend's own currently-visible state — what
    /// they share with me. In a real backend this would be fetched
    /// live; for v1 it's seeded so the UI has material to render.
    var currentSeasonName: String?
    var currentSeasonDay: Int?
    var todayScore: Int?
    var hitGoalToday: Bool?
    var lastSignalAt: Date?
    var sharesWithMe: SharingSettings = SharingSettings()

    /// When the connection began. Drives the "connected N months" line
    /// and the relationship-texture floor on the profile hub. Optional
    /// so friends persisted before this landed decode cleanly (the
    /// synthesized decoder treats a missing key as nil).
    var connectedAt: Date?

    /// Whether this friend has let me see their exact point values.
    /// Points encode what's personally hard for someone — private
    /// calibration — so they sit behind an explicit ask, never a
    /// default. nil = locked (never asked). Optional so friends
    /// persisted before this landed decode cleanly.
    var pointsAccess: PointsAccess?
}

/// The two post-ask states of the exact-points permission. The locked
/// default is the absence of a value (nil on `Friend.pointsAccess`).
enum PointsAccess: String, Codable, Equatable {
    case requested
    case granted
}

// MARK: - FFCircle

/// A goal layered onto a circle. A circle carries zero, one, or two of
/// these; its `type` is *derived* from which layers are present rather
/// than stored as a fixed identity.
///
///   • sharedList   — the old "parallel" goal: a shared checklist each
///                    member works their own copy of.
///   • sharedNumber — the old "collective" goal: one summed numeric
///                    target the group builds toward together.
enum CircleObjectiveKind: String, Codable, Equatable, Hashable {
    case sharedList
    case sharedNumber
}

/// The *shape* a circle reads as — a readout of its objective layers,
/// never stored as identity:
///   • witness    — no shared goal (presence only)
///   • parallel   — one shared checklist (a `sharedList` layer)
///   • collective — one shared number (a `sharedNumber` layer)
///   • hybrid     — both layers at once (advanced; not the default)
enum CircleType: String, Codable {
    case witness
    case parallel
    case collective
    case hybrid
}

extension CircleType {
    /// The objective layers that define this shape. Witness has none;
    /// hybrid carries both.
    var objectives: [CircleObjectiveKind] {
        switch self {
        case .witness: return []
        case .parallel: return [.sharedList]
        case .collective: return [.sharedNumber]
        case .hybrid: return [.sharedList, .sharedNumber]
        }
    }

    /// Derive the shape from a set of layers. Both layers → hybrid; a
    /// shared list → parallel; a shared number → collective; none →
    /// witness. The type is always a readout, never stored as identity.
    init(objectives: [CircleObjectiveKind]) {
        let hasList = objectives.contains(.sharedList)
        let hasNumber = objectives.contains(.sharedNumber)
        if hasList && hasNumber { self = .hybrid }
        else if hasList { self = .parallel }
        else if hasNumber { self = .collective }
        else { self = .witness }
    }

    /// True when this shape carries a shared checklist layer.
    var hasSharedList: Bool { objectives.contains(.sharedList) }
    /// True when this shape carries a shared number layer.
    var hasSharedNumber: Bool { objectives.contains(.sharedNumber) }
}

/// Time-boxed circles end on a fixed date and archive when reached.
/// Ongoing circles run indefinitely until a member leaves the group.
enum CircleTimeframe: Codable, Equatable {
    case timeBoxed(endDate: Date)
    case ongoing
}

// MARK: - The group's story (CR2)

/// How a chapter of a circle's life ended. Drives the warm lookback in
/// "Our story" — honest about what happened, never a scoreboard.
enum CircleChapterOutcome: String, Codable, Equatable {
    case ongoing      // the current chapter — still being lived
    case completed    // a goal the group finished together and is proud of
    case setAside     // a goal set aside — its data sleeps (dormant), never gone
    case returned     // returned to presence-only (Witness)
}

/// One stretch of a circle's life: which objective layers were active,
/// when it ran, and how it ended. A circle keeps a timeline of these so
/// the group can look back on everything they've done together. Chapters
/// are pure history — the live `type` is always derived from the
/// circle's current `objectives`, not from the chapter list.
struct CircleChapter: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// The objective layers active during this chapter ([] = Witness).
    var objectives: [CircleObjectiveKind]
    /// Warm human label, e.g. "Run a 5K", "1000 miles", or "Just present".
    var title: String
    /// Optional supporting line, e.g. the target or a short task summary.
    var detail: String?
    var startedAt: Date
    /// nil while this is the current chapter.
    var endedAt: Date?
    var outcome: CircleChapterOutcome
    /// Display name of whoever opened this chapter (the switch actor).
    var actorName: String?

    /// The shape this chapter ran as, derived from its layers.
    var type: CircleType { CircleType(objectives: objectives) }
    /// The current chapter has no end date yet.
    var isCurrent: Bool { endedAt == nil }
}

/// A group sharing a goal. For `parallel` circles `tasks` is the
/// shared list and per-member completion is recorded in
/// `CircleTaskCompletion`. For `collective` circles `collectiveTarget`
/// is the shared goal and per-member progress lives in
/// `CircleContribution`.
///
/// Named `FFCircle` (not `Circle`) so it doesn't shadow SwiftUI's
/// `Circle` shape inside the view layer.
struct FFCircle: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    /// The shared goals layered onto this circle (0, 1, or 2). The
    /// circle's `type` is derived from these — the durable group +
    /// always-on presence are constant; only the layers vary.
    var objectives: [CircleObjectiveKind]
    var timeframe: CircleTimeframe
    var memberIds: [UUID]
    var tasks: [CircleTask]
    var collectiveUnit: String?
    var collectiveTarget: Double?
    var collectiveProgress: Double?
    var createdAt: Date = Date()

    /// The circle's lifetime story — each stretch it ran as Witness, a
    /// shared list, a shared number, or both. The last open chapter
    /// (`endedAt == nil`) is the one being lived now. Empty for circles
    /// persisted before chapters landed; the Store backfills an opening
    /// chapter on load so every circle has a timeline.
    var chapters: [CircleChapter] = []

    /// The circle's shape, derived from its objective layers — Witness
    /// (no layers), Parallel (a shared list), Collective (one number), or
    /// Hybrid (both).
    var type: CircleType { CircleType(objectives: objectives) }

    /// Whether a shared checklist layer is currently active.
    var hasSharedList: Bool { objectives.contains(.sharedList) }
    /// Whether a shared number layer is currently active.
    var hasSharedNumber: Bool { objectives.contains(.sharedNumber) }

    /// The chapter being lived right now (last open one), if any.
    var currentChapter: CircleChapter? { chapters.last { $0.endedAt == nil } }

    /// Past chapters, newest first — the group's completed lookback.
    var pastChapters: [CircleChapter] {
        chapters.filter { $0.endedAt != nil }.sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }

    // MARK: - Roles + governance (C11)

    /// Whoever created the circle. Exactly one per circle. Optional so
    /// circles persisted before the role layer landed decode cleanly
    /// (the Store backfills `nil` to the first member on load).
    var ownerId: UUID?

    /// Members the owner has promoted to admin. Admins can manage
    /// tasks + members but can't delete the circle or transfer
    /// ownership. Empty by default — a flat friend squad never needs
    /// to touch this.
    var adminIds: [UUID] = []

    /// Opt-in governance: when on, member-initiated task changes
    /// become pending `CircleTaskRequest`s for owner/admin review.
    /// Off by default so default circles behave exactly as they
    /// always have — zero added friction.
    var membersCanProposeTasks: Bool = false

    /// Returns the role a given user holds in this circle. Members
    /// outside the roster still resolve to `.member` so callers can
    /// query freely without pre-filtering.
    func role(forUserId userId: UUID) -> CircleRole {
        if let ownerId, ownerId == userId { return .owner }
        if adminIds.contains(userId) { return .admin }
        return .member
    }

    /// True for owner or admin — the two roles that can directly
    /// mutate the shared task list and approve member requests.
    func canManageTasks(userId: UUID) -> Bool {
        let r = role(forUserId: userId)
        return r == .owner || r == .admin
    }

    /// True when a member-side task change must go through the
    /// approval queue rather than apply directly. Owners/admins
    /// always bypass the queue.
    func requiresRequest(forUserId userId: UUID) -> Bool {
        guard membersCanProposeTasks else { return false }
        return !canManageTasks(userId: userId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, objectives, timeframe, memberIds, tasks
        case collectiveUnit, collectiveTarget, collectiveProgress, createdAt
        case ownerId, adminIds, membersCanProposeTasks, chapters
        // Legacy key: circles persisted before the layer model stored a
        // bare `type`. Kept so old data migrates and a back-compat
        // readout is still written.
        case type
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: CircleType,
        timeframe: CircleTimeframe,
        memberIds: [UUID],
        tasks: [CircleTask],
        collectiveUnit: String? = nil,
        collectiveTarget: Double? = nil,
        collectiveProgress: Double? = nil,
        createdAt: Date = Date(),
        ownerId: UUID? = nil,
        adminIds: [UUID] = [],
        membersCanProposeTasks: Bool = false,
        chapters: [CircleChapter] = []
    ) {
        self.id = id
        self.name = name
        self.objectives = type.objectives
        self.timeframe = timeframe
        self.memberIds = memberIds
        self.tasks = tasks
        self.collectiveUnit = collectiveUnit
        self.collectiveTarget = collectiveTarget
        self.collectiveProgress = collectiveProgress
        self.createdAt = createdAt
        self.ownerId = ownerId
        self.adminIds = adminIds
        self.membersCanProposeTasks = membersCanProposeTasks
        self.chapters = chapters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.timeframe = try c.decode(CircleTimeframe.self, forKey: .timeframe)
        self.memberIds = try c.decode([UUID].self, forKey: .memberIds)
        self.tasks = try c.decode([CircleTask].self, forKey: .tasks)
        self.collectiveUnit = try c.decodeIfPresent(String.self, forKey: .collectiveUnit)
        self.collectiveTarget = try c.decodeIfPresent(Double.self, forKey: .collectiveTarget)
        self.collectiveProgress = try c.decodeIfPresent(Double.self, forKey: .collectiveProgress)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        self.adminIds = (try c.decodeIfPresent([UUID].self, forKey: .adminIds)) ?? []
        self.membersCanProposeTasks = (try c.decodeIfPresent(Bool.self, forKey: .membersCanProposeTasks)) ?? false
        self.chapters = (try c.decodeIfPresent([CircleChapter].self, forKey: .chapters)) ?? []

        // Migration: prefer explicit objective layers; fall back to the
        // legacy `type`; finally infer from the payload so nothing
        // decodes to an empty shape by accident.
        if let objs = try c.decodeIfPresent([CircleObjectiveKind].self, forKey: .objectives) {
            self.objectives = objs
        } else if let legacy = try c.decodeIfPresent(CircleType.self, forKey: .type) {
            self.objectives = legacy.objectives
        } else if !self.tasks.isEmpty {
            self.objectives = [.sharedList]
        } else if self.collectiveTarget != nil || self.collectiveUnit != nil {
            self.objectives = [.sharedNumber]
        } else {
            self.objectives = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(objectives, forKey: .objectives)
        // Back-compat readout so an older build still finds a `type`.
        try c.encode(type, forKey: .type)
        try c.encode(timeframe, forKey: .timeframe)
        try c.encode(memberIds, forKey: .memberIds)
        try c.encode(tasks, forKey: .tasks)
        try c.encodeIfPresent(collectiveUnit, forKey: .collectiveUnit)
        try c.encodeIfPresent(collectiveTarget, forKey: .collectiveTarget)
        try c.encodeIfPresent(collectiveProgress, forKey: .collectiveProgress)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(ownerId, forKey: .ownerId)
        try c.encode(adminIds, forKey: .adminIds)
        try c.encode(membersCanProposeTasks, forKey: .membersCanProposeTasks)
        try c.encode(chapters, forKey: .chapters)
    }
}

/// A shared task inside a parallel circle. `linkedPersonalTaskId`
/// bridges to one of the user's personal `FFTask`s — completing one
/// completes both, so a "morning run" inside the circle can be the
/// same activity as the user's personal "morning run" task.
struct CircleTask: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var pointValue: Int?
    var linkedPersonalTaskId: UUID?
}

/// Per-member completion of a circle task on a specific day.
/// Parallel circles use these to derive each member's progress
/// ratio (e.g. "Aaron 3/3, Madison 2/3").
struct CircleTaskCompletion: Codable, Identifiable {
    var id: UUID = UUID()
    var circleId: UUID
    var circleTaskId: UUID
    var memberId: UUID
    var date: Date
}

/// A member's contribution toward a collective circle's shared
/// target (e.g. "added 6 miles toward the 1000 mile circle").
struct CircleContribution: Codable, Identifiable {
    var id: UUID = UUID()
    var circleId: UUID
    var memberId: UUID
    var amount: Double
    var date: Date
}

// MARK: - Signal

/// The kind of moment a `SignalFact` represents. The signal generator
/// (C2) maps each kind plus the viewer's clearance to user-facing copy.
enum SignalKind: String, Codable {
    case threshold
    case returning
    case milestone
    case mustDo
    case volumeHigh
}

/// Source-of-truth facts about a moment in someone's day. The
/// viewer-facing text is generated at read time so the same fact can
/// surface differently for different friends depending on their
/// clearance. `userOverrideText` lets the owner pin a custom line
/// over the generated text for the day.
struct SignalFact: Codable, Identifiable {
    var id: UUID = UUID()
    var ownerId: UUID
    var kind: SignalKind
    var date: Date
    var createdAt: Date = Date()

    var taskName: String?
    var category: String?
    var daysSince: Int?
    var milestoneTitle: String?
    var milestoneDone: Int?
    var milestoneTotal: Int?
    var score: Int?
    var goal: Int?

    var userOverrideText: String?
}

// MARK: - Cheer

/// A brief encouragement sent to someone. Lands on their homepage
/// Season zone the day it was sent, then fades. Stored permanently
/// so future analytics or history features can replay them.
struct Cheer: Codable, Identifiable {
    var id: UUID = UUID()
    var fromFriendId: UUID
    var fromName: String
    var fromInitials: String
    var fromColorHex: String
    var toUserId: UUID
    var message: String
    var sentAt: Date = Date()
    var readAt: Date?
    /// When the recipient swiped the cheer off the homepage. The
    /// cheer stays in the store (history is preserved), but it no
    /// longer surfaces in `activeCheersToday` once this is set.
    var dismissedAt: Date?

    /// True only on the local day the cheer was sent. The homepage
    /// Season zone shows active cheers; older cheers stay in the
    /// store but don't surface there.
    var isActiveToday: Bool {
        Calendar.current.isDateInToday(sentAt)
    }
}

// MARK: - Story posts, likes, comments

/// A media moment or a caption-only update. General friend posts
/// expire 24h after creation; circle clips (anything with a
/// `circleId`) never expire and persist for the life of the circle.
/// `attachedCircleTaskId` is the "earned" badge — the specific circle
/// task this clip documents.
struct StoryPost: Codable, Identifiable {
    var id: UUID = UUID()
    var authorId: UUID
    var createdAt: Date = Date()
    var caption: String?
    var mediaId: UUID?
    var circleId: UUID?
    var attachedCircleTaskId: UUID?

    var isCircleClip: Bool { circleId != nil }

    /// Returns true for general posts older than 24h. Circle clips
    /// never expire — they're archived for the circle's life.
    func isExpired(now: Date = Date()) -> Bool {
        guard circleId == nil else { return false }
        return now.timeIntervalSince(createdAt) > 24 * 60 * 60
    }
}

/// A like reaction on a story post. Stored per friend so the UI can
/// render avatars / counts without an extra fetch.
struct Like: Codable, Identifiable {
    var id: UUID = UUID()
    var postId: UUID
    var fromFriendId: UUID
    var fromName: String
    var createdAt: Date = Date()
}

/// One person who's seen a story post, for the read-only "Seen by"
/// list. `didReact` marks a soft heart beside anyone who liked it.
/// Derived locally (no backend) and stable across renders.
struct StoryViewer: Identifiable {
    let friend: Friend
    let didReact: Bool
    var id: UUID { friend.id }
}

/// A comment on a story post. Initials are cached so the avatar bubble
/// renders without resolving the friend on every render.
struct Comment: Codable, Identifiable {
    var id: UUID = UUID()
    var postId: UUID
    var fromFriendId: UUID
    var fromName: String
    var fromInitials: String
    var text: String
    var createdAt: Date = Date()
}

// MARK: - Media

enum MediaType: String, Codable {
    case photo
    case video
}

/// A photo or video clip. `localURL` is the on-device file once
/// captured; `remoteURL` is the uploaded version once the (future)
/// backend syncs it. `durationSeconds` is video-only.
struct MediaAsset: Codable, Identifiable {
    var id: UUID = UUID()
    var type: MediaType
    var localURL: URL?
    var remoteURL: URL?
    var thumbnailURL: URL?
    var durationSeconds: Double?
    var createdAt: Date = Date()
}
