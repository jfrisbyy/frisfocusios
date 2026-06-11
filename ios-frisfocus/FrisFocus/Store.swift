//
//  Store.swift
//  FrisFocus
//
//  The app's single source of truth. Holds the current Season, Tasks,
//  To-dos, LogEntries, and Notes — and persists them as JSON in
//  UserDefaults. On first launch the Store seeds itself so the home
//  screen has data to read on its very first render.
//
//  Views read it via `@Environment(Store.self)`. After any mutation,
//  call `persistAll()` so the change survives the next launch.
//

import Foundation
import Observation

@Observable
final class Store {
    // MARK: - State

    var currentSeason: Season { didSet { markDirty(.season) } }
    var tasks: [FFTask] = [] { didSet { markDirty(.tasks) } }
    var todos: [Todo] = [] { didSet { markDirty(.todos) } }
    var logEntries: [LogEntry] = [] { didSet { markDirty(.logEntries) } }
    var notes: [Note] = [] { didSet { markDirty(.notes) } }
    var folders: [NoteFolder] = [] { didSet { markDirty(.folders) } }

    // MARK: - Social

    /// Stable per-install identity for "me". Generated once on first
    /// launch and persisted under its own key so DEBUG migrations of
    /// the data model don't reset who the user is.
    var currentUserId: UUID = UUID()

    var friends: [Friend] = [] { didSet { markDirty(.friends) } }
    var circles: [FFCircle] = [] { didSet { markDirty(.circles) } }
    var circleTaskCompletions: [CircleTaskCompletion] = [] { didSet { markDirty(.circleTaskCompletions) } }
    var circleContributions: [CircleContribution] = [] { didSet { markDirty(.circleContributions) } }
    var signalFacts: [SignalFact] = [] { didSet { markDirty(.signalFacts) } }
    var cheers: [Cheer] = [] { didSet { markDirty(.cheers) } }
    var storyPosts: [StoryPost] = [] { didSet { markDirty(.storyPosts) } }
    var likes: [Like] = [] { didSet { markDirty(.likes) } }
    var comments: [Comment] = [] { didSet { markDirty(.comments) } }
    var mediaAssets: [MediaAsset] = [] { didSet { markDirty(.mediaAssets) } }

    /// Privately-sent photos/videos (the counterpart to the public
    /// 24h `storyPosts`). One row per recipient — picking several
    /// friends writes one share each. Seeded with a couple of
    /// incoming examples so the Direct surface reads alive on first
    /// launch.
    var directShares: [DirectShare] = [] { didSet { markDirty(.directShares) } }

    /// Set of story post ids the current user has played back. Drives
    /// the three-state story avatar ring (no story / watched / new)
    /// on the friends rail. Persisted under its own key so it
    /// survives relaunch; missing on first load is treated as empty.
    var viewedStoryPostIds: Set<UUID> = [] { didSet { markDirty(.viewedStoryPostIds) } }

    // MARK: - Avoidance (penalties)

    /// User-defined behaviors to reduce. Standalone, not tied to a
    /// positive task. Each logged occurrence deducts points in real
    /// time via a matching `.penalty` LogEntry.
    var avoidanceItems: [AvoidanceItem] = [] { didSet { markDirty(.avoidanceItems) } }
    var avoidanceOccurrences: [AvoidanceOccurrence] = [] { didSet { markDirty(.avoidanceOccurrences) } }

    // MARK: - Habit Trains

    /// Named, ordered routines made of task / note steps. Daily
    /// completion of every task-step awards `bonusPoints` once via a
    /// `.trainBonus` LogEntry.
    var habitTrains: [HabitTrain] = [] { didSet { markDirty(.habitTrains) } }

    // MARK: - Weekly boosters (first-class)

    /// Standalone consistency rewards. Each watches a task or a whole
    /// category and pays out all-or-nothing once its count threshold is
    /// reached within the period. First-class so a booster can span
    /// several tasks (a category) and survive any single task's deletion.
    var boosters: [WeeklyBooster] = [] { didSet { markDirty(.boosters) } }

    // MARK: - Cadence link (Esengo)

    /// FrisFocus-side link records binding a Cadence routine (or an
    /// outcome rule) to FrisFocus scoring. Surfaced only while
    /// `cadenceConnected` is true. The link enriches FrisFocus; it is
    /// never load-bearing.
    var cadenceLinks: [CadenceLink] = [] { didSet { markDirty(.cadenceLinks) } }

    /// Recorded passive-outcome fills (sleep / focus / wind-down) so the
    /// Season view can show "✓ 6h 40m last night" + the credited points.
    var cadenceOutcomeFulfillments: [CadenceOutcomeFulfillment] = [] { didSet { markDirty(.cadenceOutcomeFulfillments) } }

    /// Outcome-event ids already scored. A local idempotency backstop on
    /// top of the backend `consumed_by_frisfocus` flag so a verified
    /// event is never double-counted.
    var consumedCadenceEventIds: Set<UUID> = [] { didSet { markDirty(.consumedCadenceEventIds) } }

    /// Whether the user opted in to the Cadence link. Gates every link
    /// surface; false means none of the link UI appears.
    var cadenceConnected: Bool = false { didSet { markDirty(.settings) } }

    /// One-time "Connect Cadence" invite dismissal.
    var cadenceInviteDismissed: Bool = false { didSet { markDirty(.settings) } }

    /// Privacy: sleep/focus-derived points stay hidden from the
    /// friend-facing layer unless the user opts in here.
    var cadenceSurfacePointsSocially: Bool = false { didSet { markDirty(.settings) } }

    // MARK: - Reminders (value-based)

    /// Value-based reminders surface only unfinished tasks worth at
    /// least this many points. The single user-facing reminder control,
    /// replacing the retired MUST/SHOULD/COULD priority tiers. Gentle by
    /// design — low-value habits never nag.
    var reminderValueThreshold: Int = 8 { didSet { markDirty(.settings) } }

    // MARK: - Pacts

    /// Two-person, time-boxed shared commitments. A pact is the
    /// witness-model reframe of a 1v1 — symmetric mutual visibility,
    /// no winner field. Lives alongside circles but on its own surface.
    var pacts: [Pact] = [] { didSet { markDirty(.pacts) } }
    var pactCompletions: [PactCompletion] = [] { didSet { markDirty(.pactCompletions) } }

    // MARK: - Circle governance (C11)

    /// Pending / resolved member-initiated proposals to mutate a
    /// circle's shared task list. Only created when a circle has
    /// `membersCanProposeTasks == true` AND the requester isn't a
    /// curator (owner/admin). Resolved rows are kept so the
    /// requester can see the outcome.
    var circleTaskRequests: [CircleTaskRequest] = [] { didSet { markDirty(.circleTaskRequests) } }

    // MARK: - Focus (F1)

    /// Completed focus sessions, newest last. The active session lives
    /// in `activeFocusSession` until it ends, at which point it's
    /// appended here and persisted to focus history.
    var focusSessions: [FocusSession] = [] { didSet { markDirty(.focusSessions) } }

    /// In-flight focus block. Observers (`FocusModeView`) read and
    /// mutate this via the Store helpers below — `startFocusSession`,
    /// `recordFocusLeave`, `closeOpenFocusLeave`, `endFocusSession`.
    /// Lives in memory; persistence happens when the session ends.
    var activeFocusSession: FocusSession? = nil

    // MARK: - Shared Focus (F2)

    /// Completed shared focus blocks, newest last. Persisted alongside
    /// solo focus history for review.
    var sharedFocusBlocks: [SharedFocusBlock] = [] { didSet { markDirty(.sharedFocusBlocks) } }

    /// In-flight shared block. Same lifecycle pattern as solo focus —
    /// lives in memory until the window closes, then it's appended to
    /// `sharedFocusBlocks` and persisted.
    var activeSharedFocusBlock: SharedFocusBlock? = nil

    /// Per-participant presence for the active shared block. Coarse
    /// only — `LeafTier` + `PresenceState`, never an exact leave
    /// count. Until the backend relays real presence, friends' rows
    /// here are seeded / simulated locally.
    var focusPresences: [FocusPresence] = []

    /// Transient signal published when a train completion bonus is
    /// awarded. Views observe it for a one-shot toast.
    var pendingTrainAward: TrainAward? = nil

    func clearPendingTrainAward() {
        pendingTrainAward = nil
    }

    /// Re-entrancy guard for the cross-task bridge. The circle→personal
    /// hop (`setPersonalTaskCompleted(_:completed:mirror:)`) flips this
    /// to `true` before calling into `completeTask` / `uncompleteTask`,
    /// so the personal-side path knows not to mirror back into the
    /// circle ledger it was just called from. Without this flag, a
    /// single tap would oscillate between the two stores.
    private var isMirroringFromCircle: Bool = false

    /// Transient signal published when a booster is earned. Views can
    /// observe it to render a one-time toast and call `clearPendingBoosterAward()`
    /// to dismiss. Not persisted — it lives in memory until consumed.
    var pendingBoosterAward: BoosterAward? = nil

    func clearPendingBoosterAward() {
        pendingBoosterAward = nil
    }


    // MARK: - Persistence keys

    private enum Keys {
        static let currentSeason = "currentSeason"
        static let tasks = "tasks"
        static let todos = "todos"
        static let logEntries = "logEntries"
        static let notes = "notes"
        static let folders = "folders"
        static let lastRollover = "lastRolloverDate"
        static let modelVersion = "modelVersion"

        // Identity — preserved across model-version bumps so the
        // same install keeps the same user id forever, even after a
        // DEBUG data wipe.
        static let currentUserId = "currentUserId"

        // Social graph
        static let friends = "friends"
        static let circles = "circles"
        static let circleTaskCompletions = "circleTaskCompletions"
        static let circleContributions = "circleContributions"
        static let signalFacts = "signalFacts"
        static let cheers = "cheers"
        static let storyPosts = "storyPosts"
        static let likes = "likes"
        static let comments = "comments"
        static let mediaAssets = "mediaAssets"
        static let avoidanceItems = "avoidanceItems"
        static let avoidanceOccurrences = "avoidanceOccurrences"
        static let habitTrains = "habitTrains"
        static let boosters = "boosters"
        static let viewedStoryPostIds = "viewedStoryPostIds"
        static let pacts = "pacts"
        static let pactCompletions = "pactCompletions"
        static let circleTaskRequests = "circleTaskRequests"
        static let focusSessions = "focusSessions"
        static let sharedFocusBlocks = "sharedFocusBlocks"
        static let directShares = "directShares"

        // Cadence link (Esengo)
        static let cadenceLinks = "cadenceLinks"
        static let cadenceOutcomeFulfillments = "cadenceOutcomeFulfillments"
        static let consumedCadenceEventIds = "consumedCadenceEventIds"
        static let cadenceConnected = "cadenceConnected"
        static let cadenceInviteDismissed = "cadenceInviteDismissed"
        static let cadenceSurfacePointsSocially = "cadenceSurfacePointsSocially"
        static let reminderValueThreshold = "reminderValueThreshold"

        // Legacy keys cleared by the DEBUG migration below.
        static let legacyOneShots = "oneShots"
    }

    /// Bumped whenever the on-disk shape changes incompatibly. The
    /// migration block in `init` clears persisted data when an older
    /// `modelVersion` is found.
    private static let currentModelVersion = 13

    private let userDefaults = UserDefaults.standard

    // MARK: - Init

    init() {
        #if DEBUG
        // Clear stale persisted data from prior model shapes so a
        // returning developer build doesn't crash decoding old
        // payloads into the new schema. `currentUserId` is
        // deliberately *not* in this list — identity stays stable
        // across DEBUG wipes.
        let storedVersion = userDefaults.integer(forKey: Keys.modelVersion)
        if storedVersion < Store.currentModelVersion {
            userDefaults.removeObject(forKey: Keys.currentSeason)
            userDefaults.removeObject(forKey: Keys.tasks)
            userDefaults.removeObject(forKey: Keys.todos)
            userDefaults.removeObject(forKey: Keys.legacyOneShots)
            userDefaults.removeObject(forKey: Keys.logEntries)
            userDefaults.removeObject(forKey: Keys.notes)
            userDefaults.removeObject(forKey: Keys.folders)
            userDefaults.removeObject(forKey: Keys.lastRollover)
            userDefaults.removeObject(forKey: Keys.friends)
            userDefaults.removeObject(forKey: Keys.circles)
            userDefaults.removeObject(forKey: Keys.circleTaskCompletions)
            userDefaults.removeObject(forKey: Keys.circleContributions)
            userDefaults.removeObject(forKey: Keys.signalFacts)
            userDefaults.removeObject(forKey: Keys.cheers)
            userDefaults.removeObject(forKey: Keys.storyPosts)
            userDefaults.removeObject(forKey: Keys.directShares)
            userDefaults.removeObject(forKey: Keys.likes)
            userDefaults.removeObject(forKey: Keys.comments)
            userDefaults.removeObject(forKey: Keys.mediaAssets)
            userDefaults.removeObject(forKey: Keys.avoidanceItems)
            userDefaults.removeObject(forKey: Keys.avoidanceOccurrences)
            userDefaults.removeObject(forKey: Keys.habitTrains)
            userDefaults.removeObject(forKey: Keys.boosters)
            userDefaults.removeObject(forKey: Keys.viewedStoryPostIds)
            userDefaults.removeObject(forKey: Keys.pacts)
            userDefaults.removeObject(forKey: Keys.pactCompletions)
            userDefaults.removeObject(forKey: Keys.circleTaskRequests)
            userDefaults.removeObject(forKey: Keys.cadenceLinks)
            userDefaults.removeObject(forKey: Keys.cadenceOutcomeFulfillments)
            userDefaults.removeObject(forKey: Keys.consumedCadenceEventIds)
            userDefaults.removeObject(forKey: Keys.cadenceConnected)
            userDefaults.removeObject(forKey: Keys.cadenceInviteDismissed)
            userDefaults.removeObject(forKey: Keys.cadenceSurfacePointsSocially)
            userDefaults.set(Store.currentModelVersion, forKey: Keys.modelVersion)
        }
        #else
        // RELEASE: persisted data is NEVER wiped on a model-version bump.
        // Before the stamp moves forward, snapshot every key's raw bytes
        // once (backup.v{old}.{key}) so a failed decode under the new
        // shape stays recoverable, then carry the data forward.
        let storedVersion = userDefaults.integer(forKey: Keys.modelVersion)
        if storedVersion < Store.currentModelVersion {
            Store.backupPersistedData(fromVersion: storedVersion)
            userDefaults.set(Store.currentModelVersion, forKey: Keys.modelVersion)
        }
        #endif

        // Load or mint the per-install user id. Persisted under its
        // own key so a model-version bump (above) doesn't reset who
        // the user is — the same install keeps the same id forever.
        if let stored = userDefaults.string(forKey: Keys.currentUserId),
           let uuid = UUID(uuidString: stored) {
            self.currentUserId = uuid
        } else {
            let minted = UUID()
            self.currentUserId = minted
            userDefaults.set(minted.uuidString, forKey: Keys.currentUserId)
        }

        let storedSeasonData = userDefaults.data(forKey: Keys.currentSeason)
        let hasPersistedData = storedSeasonData != nil || userDefaults.data(forKey: Keys.tasks) != nil
        if hasPersistedData {
            // Returning user — load everything we've persisted.
            if let storedSeasonData,
               let season = try? JSONDecoder().decode(Season.self, from: storedSeasonData) {
                self.currentSeason = season
            } else {
                // Season bytes exist but can't be read under the current
                // shape (or are missing while other data survives).
                // Preserve the raw bytes for recovery and start a fresh
                // season — never reseed demo data over real history.
                if let storedSeasonData {
                    userDefaults.set(storedSeasonData, forKey: "recovery.\(Keys.currentSeason)")
                    print("[Store] Season decode failed — raw data preserved under 'recovery.\(Keys.currentSeason)'.")
                }
                self.currentSeason = Store.seedSeason()
            }
            self.tasks = Store.loadArray(Keys.tasks) ?? []
            self.todos = Store.loadArray(Keys.todos) ?? []
            self.logEntries = Store.loadArray(Keys.logEntries) ?? []
            self.notes = Store.loadArray(Keys.notes) ?? []
            self.folders = Store.loadArray(Keys.folders) ?? []
            self.friends = Store.loadArray(Keys.friends) ?? []
            self.circles = Store.loadArray(Keys.circles) ?? []
            self.circleTaskCompletions = Store.loadArray(Keys.circleTaskCompletions) ?? []
            self.circleContributions = Store.loadArray(Keys.circleContributions) ?? []
            self.signalFacts = Store.loadArray(Keys.signalFacts) ?? []
            self.cheers = Store.loadArray(Keys.cheers) ?? []
            self.storyPosts = Store.loadArray(Keys.storyPosts) ?? []
            self.directShares = Store.loadArray(Keys.directShares) ?? []
            self.likes = Store.loadArray(Keys.likes) ?? []
            self.comments = Store.loadArray(Keys.comments) ?? []
            self.mediaAssets = Store.loadArray(Keys.mediaAssets) ?? []
            self.avoidanceItems = Store.loadArray(Keys.avoidanceItems) ?? []
            self.avoidanceOccurrences = Store.loadArray(Keys.avoidanceOccurrences) ?? []
            self.habitTrains = Store.loadArray(Keys.habitTrains) ?? []
            self.boosters = Store.loadArray(Keys.boosters) ?? []
            if let ids: [UUID] = Store.loadArray(Keys.viewedStoryPostIds) {
                self.viewedStoryPostIds = Set(ids)
            }
            self.pacts = Store.loadArray(Keys.pacts) ?? []
            self.pactCompletions = Store.loadArray(Keys.pactCompletions) ?? []
            self.circleTaskRequests = Store.loadArray(Keys.circleTaskRequests) ?? []
            self.focusSessions = Store.loadArray(Keys.focusSessions) ?? []
            self.sharedFocusBlocks = Store.loadArray(Keys.sharedFocusBlocks) ?? []
            self.cadenceLinks = Store.loadArray(Keys.cadenceLinks) ?? []
            self.cadenceOutcomeFulfillments = Store.loadArray(Keys.cadenceOutcomeFulfillments) ?? []
            if let ids: [UUID] = Store.loadArray(Keys.consumedCadenceEventIds) {
                self.consumedCadenceEventIds = Set(ids)
            }
            self.cadenceConnected = userDefaults.bool(forKey: Keys.cadenceConnected)
            self.cadenceInviteDismissed = userDefaults.bool(forKey: Keys.cadenceInviteDismissed)
            self.cadenceSurfacePointsSocially = userDefaults.bool(forKey: Keys.cadenceSurfacePointsSocially)
            if userDefaults.object(forKey: Keys.reminderValueThreshold) != nil {
                self.reminderValueThreshold = userDefaults.integer(forKey: Keys.reminderValueThreshold)
            }
            // One-time migration: lift any legacy task-attached booster
            // rules into first-class WeeklyBoosters referencing that
            // task, then detach the inline rule. Guarded on the absence
            // of the boosters key so it runs at most once per install.
            if userDefaults.data(forKey: Keys.boosters) == nil {
                var migrated: [WeeklyBooster] = []
                for i in self.tasks.indices {
                    if let rule = self.tasks[i].booster, rule.enabled {
                        migrated.append(WeeklyBooster(
                            seasonId: self.currentSeason.id,
                            name: self.tasks[i].title,
                            reference: .task(self.tasks[i].id),
                            threshold: rule.timesRequired,
                            period: rule.period,
                            bonusPoints: rule.bonusPoints
                        ))
                    }
                    self.tasks[i].booster = nil
                }
                self.boosters = migrated
                dirtyKeys.formUnion([.tasks, .boosters])
                flushPendingSaves()
            }

            // Back-fill ownerId on any circle persisted before the
            // role layer landed so role lookups never return
            // .member for the actual creator.
            for i in self.circles.indices where self.circles[i].ownerId == nil {
                self.circles[i].ownerId = self.circles[i].memberIds.first
            }
            // Back-fill a founding chapter on any circle persisted before
            // the group-story layer landed so "Our story" always has a
            // timeline to look back on.
            self.circles = Store.withChapterTimelines(self.circles)
        } else {
            // First launch — seed and immediately persist. Social
            // seeds run in dependency order: friends → circles →
            // completions / contributions, then media → posts →
            // reactions (likes, comments).
            self.currentSeason = Store.seedSeason()
            self.tasks = Store.seedTasks()
            self.todos = Store.seedTodos()
            self.logEntries = Store.seedLogEntries()
            self.folders = Store.seedFolders()
            self.notes = Store.seedNotes()

            let seededFriends = Store.seedFriends()
            let seededCircles = Store.seedCircles(
                friends: seededFriends,
                userId: self.currentUserId
            )
            let seededMedia = Store.seedMediaAssets()
            let seededPosts = Store.seedStoryPosts(
                friends: seededFriends,
                circles: seededCircles,
                mediaAssets: seededMedia
            )

            self.friends = seededFriends
            self.circles = Store.withChapterTimelines(seededCircles)
            self.circleTaskCompletions = Store.seedCircleTaskCompletions(
                circles: seededCircles,
                friends: seededFriends,
                userId: self.currentUserId
            )
            self.circleContributions = Store.seedCircleContributions(
                circles: seededCircles,
                friends: seededFriends,
                userId: self.currentUserId
            )
            self.signalFacts = Store.seedSignalFacts(friends: seededFriends)
            self.cheers = Store.seedCheers(
                friends: seededFriends,
                userId: self.currentUserId
            )
            self.mediaAssets = seededMedia

            // The user's own story so the posted state is demoable.
            let myStories = Store.seedMyStoryPosts(userId: self.currentUserId)
            self.storyPosts = seededPosts + myStories

            self.directShares = Store.seedDirectShares(
                friends: seededFriends,
                userId: self.currentUserId,
                mediaAssets: seededMedia
            )
            var seededLikes = Store.seedLikes(posts: seededPosts, friends: seededFriends)
            if let mine = myStories.first {
                seededLikes += Store.seedMyLikes(post: mine, friends: seededFriends)
            }
            self.likes = seededLikes
            self.comments = Store.seedComments(posts: seededPosts, friends: seededFriends)
            let seededPacts = Store.seedPacts(friends: seededFriends, userId: self.currentUserId)
            self.pacts = seededPacts
            self.pactCompletions = Store.seedPactCompletions(
                pacts: seededPacts,
                userId: self.currentUserId
            )

            // First-launch seed: assignments inside `init` don't fire
            // `didSet`, so mark everything dirty and write it through now.
            markAllDirty()
            flushPendingSaves()
        }
    }

    // MARK: - Persistence
    //
    // Targeted, batched saving. Every persisted property marks its own
    // `DataKey` dirty via `didSet`, so a flush writes *only* the
    // collections that actually changed — checking one task off no
    // longer re-serializes ~30 arrays. `persistAll()` keeps its name
    // (61+ call sites) but now just schedules a debounced flush, so
    // rapid taps coalesce into a single write off the render path. A
    // safety flush runs when the app heads to the background.

    /// One persistable slice of the Store. Each case maps to a single
    /// UserDefaults key.
    enum DataKey: CaseIterable {
        case season, tasks, todos, logEntries, notes, folders
        case friends, circles, circleTaskCompletions, circleContributions
        case signalFacts, cheers, storyPosts, directShares, likes, comments, mediaAssets
        case avoidanceItems, avoidanceOccurrences, habitTrains, boosters
        case viewedStoryPostIds, pacts, pactCompletions, circleTaskRequests
        case focusSessions, sharedFocusBlocks
        case cadenceLinks, cadenceOutcomeFulfillments, consumedCadenceEventIds
        case settings
    }

    /// Collections mutated since the last flush.
    @ObservationIgnored private var dirtyKeys: Set<DataKey> = []
    /// The pending debounced flush, if one is scheduled.
    @ObservationIgnored private var pendingFlush: Task<Void, Never>?

    private func markDirty(_ key: DataKey) {
        dirtyKeys.insert(key)
    }

    private func markAllDirty() {
        dirtyKeys = Set(DataKey.allCases)
    }

    /// Decode a persisted array. A decode failure never crashes and
    /// never silently discards bytes: the raw data is preserved under a
    /// recovery key and the failure is logged before falling back.
    private static func loadArray<T: Decodable>(_ key: String) -> [T]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            UserDefaults.standard.set(data, forKey: "recovery.\(key)")
            print("[Store] Decode failed for '\(key)' — raw data preserved under 'recovery.\(key)': \(error)")
            return nil
        }
    }

    /// Schedule a save of everything that changed. Mutations mark their
    /// own collections dirty (`didSet`), so despite the historical name
    /// this writes only the dirty slices — debounced 250 ms so a burst
    /// of check-offs costs one write.
    func persistAll() {
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !dirtyKeys.isEmpty else { return }
        pendingFlush?.cancel()
        pendingFlush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.flushPendingSaves()
        }
    }

    /// Write every dirty collection now. Called by the debounce, and as
    /// a safety net when the app heads to the background.
    func flushPendingSaves() {
        pendingFlush?.cancel()
        pendingFlush = nil
        guard !dirtyKeys.isEmpty else { return }
        let keys = dirtyKeys
        dirtyKeys = []
        let encoder = JSONEncoder()
        for key in keys {
            write(key, with: encoder)
        }
    }

    private func write(_ key: DataKey, with encoder: JSONEncoder) {
        switch key {
        case .season: setJSON(currentSeason, forKey: Keys.currentSeason, encoder: encoder)
        case .tasks: setJSON(tasks, forKey: Keys.tasks, encoder: encoder)
        case .todos: setJSON(todos, forKey: Keys.todos, encoder: encoder)
        case .logEntries: setJSON(logEntries, forKey: Keys.logEntries, encoder: encoder)
        case .notes: setJSON(notes, forKey: Keys.notes, encoder: encoder)
        case .folders: setJSON(folders, forKey: Keys.folders, encoder: encoder)
        case .friends: setJSON(friends, forKey: Keys.friends, encoder: encoder)
        case .circles: setJSON(circles, forKey: Keys.circles, encoder: encoder)
        case .circleTaskCompletions: setJSON(circleTaskCompletions, forKey: Keys.circleTaskCompletions, encoder: encoder)
        case .circleContributions: setJSON(circleContributions, forKey: Keys.circleContributions, encoder: encoder)
        case .signalFacts: setJSON(signalFacts, forKey: Keys.signalFacts, encoder: encoder)
        case .cheers: setJSON(cheers, forKey: Keys.cheers, encoder: encoder)
        case .storyPosts: setJSON(storyPosts, forKey: Keys.storyPosts, encoder: encoder)
        case .directShares: setJSON(directShares, forKey: Keys.directShares, encoder: encoder)
        case .likes: setJSON(likes, forKey: Keys.likes, encoder: encoder)
        case .comments: setJSON(comments, forKey: Keys.comments, encoder: encoder)
        case .mediaAssets: setJSON(mediaAssets, forKey: Keys.mediaAssets, encoder: encoder)
        case .avoidanceItems: setJSON(avoidanceItems, forKey: Keys.avoidanceItems, encoder: encoder)
        case .avoidanceOccurrences: setJSON(avoidanceOccurrences, forKey: Keys.avoidanceOccurrences, encoder: encoder)
        case .habitTrains: setJSON(habitTrains, forKey: Keys.habitTrains, encoder: encoder)
        case .boosters: setJSON(boosters, forKey: Keys.boosters, encoder: encoder)
        case .viewedStoryPostIds: setJSON(Array(viewedStoryPostIds), forKey: Keys.viewedStoryPostIds, encoder: encoder)
        case .pacts: setJSON(pacts, forKey: Keys.pacts, encoder: encoder)
        case .pactCompletions: setJSON(pactCompletions, forKey: Keys.pactCompletions, encoder: encoder)
        case .circleTaskRequests: setJSON(circleTaskRequests, forKey: Keys.circleTaskRequests, encoder: encoder)
        case .focusSessions: setJSON(focusSessions, forKey: Keys.focusSessions, encoder: encoder)
        case .sharedFocusBlocks: setJSON(sharedFocusBlocks, forKey: Keys.sharedFocusBlocks, encoder: encoder)
        case .cadenceLinks: setJSON(cadenceLinks, forKey: Keys.cadenceLinks, encoder: encoder)
        case .cadenceOutcomeFulfillments: setJSON(cadenceOutcomeFulfillments, forKey: Keys.cadenceOutcomeFulfillments, encoder: encoder)
        case .consumedCadenceEventIds: setJSON(Array(consumedCadenceEventIds), forKey: Keys.consumedCadenceEventIds, encoder: encoder)
        case .settings:
            userDefaults.set(cadenceConnected, forKey: Keys.cadenceConnected)
            userDefaults.set(cadenceInviteDismissed, forKey: Keys.cadenceInviteDismissed)
            userDefaults.set(cadenceSurfacePointsSocially, forKey: Keys.cadenceSurfacePointsSocially)
            userDefaults.set(reminderValueThreshold, forKey: Keys.reminderValueThreshold)
        }
    }

    private func setJSON<T: Encodable>(_ value: T, forKey key: String, encoder: JSONEncoder) {
        do {
            userDefaults.set(try encoder.encode(value), forKey: key)
        } catch {
            print("[Store] Encode failed for '\(key)': \(error)")
        }
    }

    // MARK: - Migration safety

    /// Every key the Store persists — the list a release-version bump
    /// snapshots before any new code touches the data.
    private static let allPersistedKeys: [String] = [
        Keys.currentSeason, Keys.tasks, Keys.todos, Keys.logEntries,
        Keys.notes, Keys.folders, Keys.friends, Keys.circles,
        Keys.circleTaskCompletions, Keys.circleContributions,
        Keys.signalFacts, Keys.cheers, Keys.storyPosts, Keys.directShares,
        Keys.likes, Keys.comments, Keys.mediaAssets, Keys.avoidanceItems,
        Keys.avoidanceOccurrences, Keys.habitTrains, Keys.boosters,
        Keys.viewedStoryPostIds, Keys.pacts, Keys.pactCompletions,
        Keys.circleTaskRequests, Keys.focusSessions, Keys.sharedFocusBlocks,
        Keys.cadenceLinks, Keys.cadenceOutcomeFulfillments,
        Keys.consumedCadenceEventIds
    ]

    /// One-time, pre-migration snapshot: copy each key's raw bytes to
    /// `backup.v{oldVersion}.{key}` so a failed decode under the new
    /// shape can always be recovered instead of lost.
    private static func backupPersistedData(fromVersion version: Int) {
        let defaults = UserDefaults.standard
        for key in allPersistedKeys {
            let backupKey = "backup.v\(version).\(key)"
            guard defaults.object(forKey: backupKey) == nil,
                  let data = defaults.data(forKey: key) else { continue }
            defaults.set(data, forKey: backupKey)
        }
    }

    // MARK: - Focus (F1) actions

    /// Begin a focus block. Replaces any previous active session
    /// (there should never be one — but if a crash left a stale
    /// in-memory record, the new start wins). Returns the started
    /// session for the caller's convenience.
    @discardableResult
    func startFocusSession(
        plannedDuration: TimeInterval,
        label: String? = nil,
        linkedTaskId: UUID? = nil
    ) -> FocusSession {
        let session = FocusSession(
            label: label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : label,
            startedAt: Date(),
            plannedDuration: plannedDuration,
            linkedTaskId: linkedTaskId
        )
        activeFocusSession = session
        return session
    }

    /// Append a fresh `FocusLeave` (open — no `awaySeconds` yet) to the
    /// active session. Called when the lifecycle classifier decides a
    /// background event is a real leave, not a screen-lock.
    func recordFocusLeave(at date: Date = Date()) {
        guard var session = activeFocusSession else { return }
        session.leaves.append(FocusLeave(leftAt: date, awaySeconds: nil))
        activeFocusSession = session
    }

    /// Close the most recent open leave by stamping `awaySeconds`.
    /// No-op when there's no open leave (e.g. after a screen lock,
    /// which never opened one in the first place).
    func closeOpenFocusLeave(at date: Date = Date()) {
        guard var session = activeFocusSession else { return }
        guard let idx = session.leaves.lastIndex(where: { $0.awaySeconds == nil }) else { return }
        let leftAt = session.leaves[idx].leftAt
        session.leaves[idx].awaySeconds = max(0, date.timeIntervalSince(leftAt))
        activeFocusSession = session
    }

    /// Finalise the active session. Stamps `endedAt`, closes any open
    /// leave, appends to `focusSessions`, and — if the block was clean
    /// and links a personal task — credits that task once for today.
    /// Persists everything.
    func endFocusSession(at date: Date = Date()) {
        guard var session = activeFocusSession else { return }
        if session.leaves.last?.awaySeconds == nil, !session.leaves.isEmpty {
            closeOpenFocusLeave(at: date)
            session = activeFocusSession ?? session
        }
        session.endedAt = date

        // Credit the linked task only on a clean block — and only if
        // it isn't already completed today (`completeTask` guards
        // against double-counting on its own, but checking here keeps
        // the intent legible).
        if session.clean, let linkedId = session.linkedTaskId,
           let task = personalTask(by: linkedId),
           !hasLogEntryToday(forTaskId: linkedId) {
            completeTask(task)
        }

        focusSessions.append(session)
        activeFocusSession = nil
        persistAll()
    }

    // MARK: - Shared Focus (F2) actions

    /// Begin a shared focus block with the given friend ids (capped
    /// to 3 friends + me = 4 trees in the grove). Seeds initial
    /// `inBlock / .full` presence for every participant and a soft
    /// varied state for friends so the grove demonstrates the
    /// three tiers immediately even without a backend relay.
    @discardableResult
    func startSharedFocusBlock(
        friendIds: [UUID],
        plannedDuration: TimeInterval,
        label: String? = nil
    ) -> SharedFocusBlock {
        let capped = Array(friendIds.prefix(3))
        let participantIds = [currentUserId] + capped
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = SharedFocusBlock(
            hostId: currentUserId,
            label: (trimmedLabel?.isEmpty ?? true) ? nil : trimmedLabel,
            startedAt: Date(),
            plannedDuration: plannedDuration,
            participantIds: participantIds
        )
        activeSharedFocusBlock = block

        // Seed presence: me in-block, full canopy; friends start
        // in-block but with a softly varied tier so the grove reads
        // as a living scene from the first frame.
        var seeded: [FocusPresence] = [
            FocusPresence(
                blockId: block.id,
                userId: currentUserId,
                state: .inBlock,
                leafTier: .full,
                updatedAt: Date()
            )
        ]
        let tiers: [LeafTier] = [.full, .thinning, .full, .sparse]
        for (i, fid) in capped.enumerated() {
            seeded.append(
                FocusPresence(
                    blockId: block.id,
                    userId: fid,
                    state: .inBlock,
                    leafTier: tiers[i % tiers.count],
                    updatedAt: Date()
                )
            )
        }
        focusPresences = seeded
        return block
    }

    /// Publish (locally update) my own presence for the active shared
    /// block. Called from `SharedFocusModeView` when the F1 lifecycle
    /// classifier flips state or when my leaf count crosses a tier
    /// boundary. Coarse on purpose — `LeafTier`, not exact count.
    func publishMyFocusPresence(state: PresenceState, leafTier: LeafTier) {
        guard let block = activeSharedFocusBlock else { return }
        let new = FocusPresence(
            blockId: block.id,
            userId: currentUserId,
            state: state,
            leafTier: leafTier,
            updatedAt: Date()
        )
        if let idx = focusPresences.firstIndex(where: { $0.userId == currentUserId }) {
            focusPresences[idx] = new
        } else {
            focusPresences.append(new)
        }
    }

    /// Local simulation hook — randomly evolve a friend's presence so
    /// the grove demonstrates the "stepped away" + nudge flow without
    /// a backend. No-op once the relay is wired.
    func simulateFriendPresenceTick() {
        guard let block = activeSharedFocusBlock else { return }
        let friendIds = block.participantIds.filter { $0 != currentUserId }
        guard let pick = friendIds.randomElement() else { return }
        guard let idx = focusPresences.firstIndex(where: { $0.userId == pick }) else { return }
        var p = focusPresences[idx]
        // Toggle stepped-away with a low probability; when it flips
        // back to in-block, nudge the tier toward thinning to suggest
        // a few leaves fell while they were gone.
        if p.state == .inBlock {
            if Double.random(in: 0...1) < 0.35 {
                p.state = .steppedAway
            }
        } else {
            p.state = .inBlock
            if p.leafTier == .full {
                p.leafTier = .thinning
            } else if p.leafTier == .thinning && Double.random(in: 0...1) < 0.5 {
                p.leafTier = .sparse
            }
        }
        p.updatedAt = Date()
        focusPresences[idx] = p
    }

    /// Stamp `endedAt` on the active shared block, append to history,
    /// and clear in-memory presence. Solo F1 credit for a clean block
    /// is handled separately by `endFocusSession` on the per-device
    /// solo session that ran inside the grove.
    func endSharedFocusBlock(at date: Date = Date()) {
        guard var block = activeSharedFocusBlock else { return }
        block.endedAt = date
        sharedFocusBlocks.append(block)
        activeSharedFocusBlock = nil
        focusPresences = []
        persistAll()
    }

    /// Friends who can be invited to a shared focus block. Right now
    /// every friend qualifies; future iterations may gate this on
    /// sharing settings or presence.
    var sharedFocusInviteCandidates: [Friend] {
        friends
    }
}

// MARK: - Derived state
//
// Computed properties that summarise the stored arrays for the home
// screen. They read observable state, so any view that touches them
// will re-render automatically when the underlying logs / season change.

extension Store {
    /// Sum of points earned today, by the local calendar day.
    var todayScore: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return logEntries
            .filter { cal.isDate($0.date, inSameDayAs: today) }
            .map { $0.pointsEarned }
            .reduce(0, +)
    }

    /// Sum of points earned this calendar week. The week boundary follows
    /// the user's calendar locale (Sunday in en_US, Monday elsewhere).
    var weekScore: Int {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return logEntries
            .filter { $0.date >= week.start && $0.date < week.end }
            .map { $0.pointsEarned }
            .reduce(0, +)
    }

    /// Sun brightness — score / goal ratio, floored at 5 %, capped at 100 %.
    /// Drives the global opacity of every sun layer.
    var sunBrightness: Double {
        let goal = max(1, currentSeason.dailyGoal)
        let progress = Double(todayScore) / Double(goal)
        return max(0.05, min(progress, 1.0))
    }

    /// Sun scale — grows from 60 % at zero points to 100 % at goal.
    var sunScale: Double {
        0.6 + (sunBrightness * 0.4)
    }

    /// The italic line that sits under the score. Reads the score against
    /// the goal and the current hour to choose a fitting phrase.
    var forwardSentence: String {
        let score = todayScore
        let goal = currentSeason.dailyGoal
        let hour = Calendar.current.component(.hour, from: Date())

        if score < 0 {
            return "the day's not over"
        }
        if score >= goal {
            return score == goal
                ? "productive day locked in"
                : "\(score - goal) over goal, no need to push"
        }
        if score == 0 {
            if hour < 10 {
                return "a fresh morning · \(goal) to a productive day"
            }
            return "\(goal) to a productive day"
        }
        return "\(goal - score) to a productive day"
    }

    /// 1-based day count into the current season, clamped to `1...lengthDays`.
    /// Both endpoints are normalised to `startOfDay` so the boundary is
    /// integer-aligned regardless of time-of-day drift.
    var currentSeasonDay: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: currentSeason.startDate)
        let today = cal.startOfDay(for: Date())
        let days = cal.dateComponents([.day], from: start, to: today).day ?? 0
        return min(max(days + 1, 1), currentSeason.lengthDays)
    }

    // MARK: - Home composition

    /// True if a completed LogEntry exists for the given task on today's
    /// local calendar day. Drives the checkbox state in `TaskCardView`.
    func hasLogEntryToday(forTaskId taskId: UUID) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return logEntries.contains { entry in
            entry.taskId == taskId
                && cal.isDate(entry.date, inSameDayAs: today)
                && entry.entryType == .completed
        }
    }

    /// Today's Plan: every Task whose pin schedule matches today, plus
    /// any pointed To-do whose due date is today or in the past.
    /// Completed Tasks stay visible so the checkbox can be untoggled.
    var todaysPlan: [HomeRowItem] {
        var items: [HomeRowItem] = []

        for task in tasks where task.isPinnedToday {
            items.append(.task(task))
        }

        // Linked Cadence routines you launch-and-run, scheduled for
        // today. They sit in the plan like a task but open Cadence to
        // run; passive outcomes never appear here (they live in Season).
        for link in todaysCadenceLinks {
            items.append(.cadenceLink(link))
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for todo in todos {
            if let due = todo.dueDate, todo.pointValue != nil,
               cal.isDate(due, inSameDayAs: today) || due < today {
                items.append(.todo(todo))
            }
        }

        return items
    }

    /// Everything else from `todos`: future-dated items, undated items,
    /// and pointless list-only items. Whatever doesn't qualify for
    /// Today's Plan falls into Loose Ends. (The Loose Ends section is
    /// removed from the homepage in Prompt 2g; the property survives
    /// for now as a transitional read.)
    var looseEnds: [Todo] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return todos.filter { todo in
            if let due = todo.dueDate, todo.pointValue != nil,
               cal.isDate(due, inSameDayAs: today) || due < today {
                return false
            }
            return true
        }
    }

    /// Dynamic subline for the unified Today's Plan section. Counts read
    /// live from the store and parts drop out when their count is zero.
    /// When the plan is empty, returns a quiet placeholder so the section
    /// header still has something below it.
    var workSubline: String {
        let pinned = tasks.filter { $0.isPinnedToday }.count
        let todoCount = todaysPlan.reduce(into: 0) { partial, item in
            if case .todo = item { partial += 1 }
        }
        let cadenceCount = todaysCadenceLinks.count
        let alertCount = alerts.count

        if pinned == 0 && todoCount == 0 && cadenceCount == 0 {
            return "no plan locked in yet"
        }

        var parts: [String] = []
        if pinned > 0 {
            parts.append("\(pinned) pinned")
        }
        if todoCount > 0 {
            parts.append("\(todoCount) to-do\(todoCount == 1 ? "" : "s")")
        }
        if cadenceCount > 0 {
            parts.append("\(cadenceCount) from Cadence")
        }
        if alertCount > 0 {
            parts.append("\(alertCount) need\(alertCount == 1 ? "s" : "") you")
        }
        return parts.joined(separator: " · ")
    }

    /// The Needs You list — Must-Dos that haven't been logged today
    /// (after 10 AM) plus Should-Do drift across non-Quiet categories
    /// where the most recent log is 7+ days old. Limited to one drift
    /// alert per category to avoid flooding the section.
    var alerts: [AlertItem] {
        var result: [AlertItem] = []
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)

        // Quiet hours: nothing surfaces before 10 AM or after 10 PM so a
        // reminder is always a gentle daytime nudge, never late-night
        // pressure.
        guard hour >= 10 && hour < 22 else { return [] }

        // 1. Higher-value unfinished tasks pinned for today. Value-based
        //    (replaces the retired MUST/SHOULD/COULD tiers): only items
        //    worth at least the reminder threshold surface, so low-value
        //    habits never nag. Highest value first.
        let highValueOpen = tasks
            .filter {
                $0.isPinnedToday
                    && $0.nominalValue >= reminderValueThreshold
                    && !hasLogEntryToday(forTaskId: $0.id)
            }
            .sorted { $0.nominalValue > $1.nominalValue }

        for task in highValueOpen {
            let hasSkip = (task.skipPenalty ?? 0) < 0
            let subtitle: String = {
                if let penalty = task.skipPenalty, penalty < 0 {
                    return "Worth \(task.nominalValue) · skipping pulls \u{2212}\(abs(penalty)) from the day"
                }
                return "Worth \(task.nominalValue) · still open today"
            }()
            result.append(AlertItem(
                severity: hasSkip ? .red : .amber,
                title: "\(task.title) is still open.",
                subtitle: subtitle
            ))
        }

        // Linked Cadence routines with an opt-in skip penalty not yet
        // run. Value/penalty-based now — the retired tier no longer gates
        // this. Routines without a skip penalty enrich, never pressure.
        for link in todaysCadenceLinks where (link.skipPenalty ?? 0) < 0 {
            guard !isCadenceLinkEarnedToday(link) else { continue }
            let penalty = abs(link.skipPenalty ?? 0)
            result.append(AlertItem(
                severity: .red,
                title: "\(link.routineName) hasn\u{2019}t been run \(link.runWord).",
                subtitle: "Skipping it pulls \u{2212}\(penalty) from the day"
            ))
        }

        // 2. Category drift in non-Quiet categories: the most recent
        //    completion of a meaningful (>= threshold) task is 7+ days
        //    ago (or never). One drift alert per category.
        let quietCategories: Set<Category> = Set(
            currentSeason.categories
                .filter { $0.tier == .quiet }
                .map(\.category)
        )
        var coveredCategories: Set<Category> = []

        for task in tasks where !quietCategories.contains(task.category) && task.nominalValue >= reminderValueThreshold {
            guard !coveredCategories.contains(task.category) else { continue }

            let mostRecent = logEntries
                .filter { $0.taskId == task.id && $0.entryType == .completed }
                .map(\.date)
                .max()

            let daysSince: Int = {
                guard let mostRecent else { return Int.max }
                return cal.dateComponents([.day], from: mostRecent, to: now).day ?? Int.max
            }()

            guard daysSince >= 7 else { continue }
            coveredCategories.insert(task.category)

            let timePhrase: String = {
                if daysSince >= 30 { return "in a while" }
                return "in \(daysSince) days"
            }()

            result.append(AlertItem(
                severity: .amber,
                title: "No \(categoryDisplayName(task.category)) time logged \(timePhrase).",
                subtitle: driftSubtitle(for: task.category)
            ))
        }

        return result
    }

    /// True when the Needs You section should render at all.
    var hasAlerts: Bool { !alerts.isEmpty }

    /// Editorial nudge copy paired to each category for drift alerts.
    private func driftSubtitle(for category: Category) -> String {
        switch category {
        case .creative: return "The EP doesn\u{2019}t write itself. Worth 15 min today?"
        case .spiritual: return "Quiet time matters. A few minutes is enough."
        case .fitness: return "The body forgets. Time for a session?"
        case .health: return "Small habits compound. Pick one to do today."
        case .work: return "Pick one small thing \u{2014} 30 minutes."
        case .apartment: return "Small fixes pile up if you let them."
        }
    }

    // MARK: - Notes

    /// All notes created today, oldest first. The Note zone iterates this.
    var todaysNotes: [Note] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return notes
            .filter { cal.isDate($0.createdAt, inSameDayAs: today) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Folders sorted alphabetically. Used by every folder pill row,
    /// the picker sheet, and the Notes library filter strip.
    var sortedFolders: [NoteFolder] {
        folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Look up the folder a note belongs to, if any. Returns nil for
    /// unfiled notes or when the folderId no longer matches anything.
    func folder(for note: Note) -> NoteFolder? {
        guard let id = note.folderId else { return nil }
        return folders.first { $0.id == id }
    }

    /// Number of notes currently filed under a given folder.
    func notesCount(in folder: NoteFolder) -> Int {
        notes.reduce(into: 0) { sum, note in
            if note.folderId == folder.id { sum += 1 }
        }
    }

    /// Which subset of the notes library to slice for grouping.
    enum NoteSelection: Equatable {
        case all
        case folder(UUID)
        case unfiled
    }

    /// Group every note matching `selection` by start-of-day, with the
    /// newest day first and notes within each day in newest-first
    /// order. The library view consumes this to build its day sections.
    func notesGroupedByDay(selection: NoteSelection) -> [(date: Date, notes: [Note])] {
        let filtered = notesInSelection(selection)
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.createdAt) }
        return grouped
            .map { (date: $0.key, notes: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    /// Pinned notes matching `selection`, newest first. Floats above
    /// the day-grouped flow in the library and folder pages.
    func pinnedNotes(selection: NoteSelection) -> [Note] {
        notesInSelection(selection)
            .filter { $0.isPinned }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Same shape as `notesGroupedByDay` but excludes pinned notes so
    /// the library can render Pinned + Day groups without duplication.
    func unpinnedNotesGroupedByDay(selection: NoteSelection) -> [(date: Date, notes: [Note])] {
        let filtered = notesInSelection(selection).filter { !$0.isPinned }
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.createdAt) }
        return grouped
            .map { (date: $0.key, notes: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    /// Case-insensitive flat search across body, label, and folder
    /// name. Restricted to the active `selection` so chip filters and
    /// the search query compose. Pinned matches sort to the top.
    func searchNotes(query: String, selection: NoteSelection) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()

        return notesInSelection(selection)
            .filter { matches(note: $0, query: q) }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
    }

    // MARK: - Private helpers

    private func notesInSelection(_ selection: NoteSelection) -> [Note] {
        switch selection {
        case .all: return notes
        case .folder(let id): return notes.filter { $0.folderId == id }
        case .unfiled: return notes.filter { $0.folderId == nil }
        }
    }

    private func matches(note: Note, query lowercaseQuery: String) -> Bool {
        if let body = note.body, body.lowercased().contains(lowercaseQuery) { return true }
        if let label = note.label, label.lowercased().contains(lowercaseQuery) { return true }
        if let folder = folder(for: note),
           folder.name.lowercased().contains(lowercaseQuery) {
            return true
        }
        return false
    }

    // MARK: - Actions

    /// Mark a Task as completed for today. Idempotent — a second call is
    /// a no-op so accidental double-taps don't double-count points.
    ///
    /// On a fresh completion we also record any signal-worthy facts:
    /// a `.returning` or `.mustDo` signal for the task itself (subject
    /// to the tier filter), and a `.threshold` signal if this entry is
    /// the one that pushed today's score across the goal.
    ///
    /// If this personal task is linked to a circle task via
    /// `linkedPersonalTaskId`, the personal→circle bridge fires at the
    /// end so the matching `CircleTaskCompletion` lands too — unless
    /// we're already inside a circle→personal mirror, in which case
    /// `isMirroringFromCircle` short-circuits the bridge to break the
    /// loop.
    func completeTask(_ task: FFTask, quantity: Double? = nil) {
        guard !hasLogEntryToday(forTaskId: task.id) else { return }

        // Detect whether this completion is a "return" — no completed
        // LogEntry for this task in the prior 5 days. A task with no
        // history at all is *not* a return; it's brand new.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let lastCompletion = logEntries
            .filter { $0.taskId == task.id && $0.entryType == .completed }
            .map(\.date)
            .max()

        let isReturn: Bool
        let daysSince: Int?
        if let last = lastCompletion {
            let lastDay = cal.startOfDay(for: last)
            let gap = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
            isReturn = gap >= 5
            daysSince = isReturn ? gap : nil
        } else {
            isReturn = false
            daysSince = nil
        }

        let scoreBefore = todayScore

        // Points by the task's scoring shape: flat → its value; tiered →
        // the highest level the logged amount reaches; quantity → base
        // payout plus per-unit beyond the floor.
        let earned = task.scoring.points(forQuantity: quantity, flatValue: task.pointValue)

        let entry = LogEntry(
            date: Date(),
            taskId: task.id,
            todoId: nil,
            quantity: quantity,
            pointsEarned: earned,
            entryType: .completed
        )
        logEntries.append(entry)

        // Record signals after the entry exists so `todayScore`
        // reflects the new total when the threshold check fires.
        recordSignalIfWorthy(forTask: task, isReturn: isReturn, daysSince: daysSince)
        maybeRecordGoalCrossedSignal(scoreBefore: scoreBefore)

        // Booster evaluation runs after the completion is committed so
        // the freshly-added LogEntry counts toward the period total.
        // Every first-class booster the task feeds (direct or via its
        // category) is checked; award-once-per-period is enforced inside.
        evaluateBoostersAfterCompletion(task)

        // Weekly-limit penalty resolution: apply or revoke once for
        // the week depending on whether the condition currently holds.
        evaluatePenaltyForTask(task)

        // Habit-train evaluation: if this completion was the last
        // task-step in any train, fold its bonus in once for today.
        evaluateTrainsAfterTaskChange(taskId: task.id)

        persistAll()

        if !isMirroringFromCircle {
            mirrorPersonalCompletionToCircles(taskId: task.id, completed: true)
        }
    }

    /// Undo today's completion of a Task. Removes every matching
    /// `.completed` LogEntry on the local day, and tidies up any
    /// task-bound signal facts (mustDo / returning) so a momentarily
    /// toggled task doesn't leave a phantom headline behind. Threshold
    /// facts are left in place — they reflect a moment, not the
    /// current state of the score.
    func uncompleteTask(_ task: FFTask) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        logEntries.removeAll { entry in
            entry.taskId == task.id
                && cal.isDate(entry.date, inSameDayAs: today)
                && entry.entryType == .completed
        }
        signalFacts.removeAll { fact in
            guard fact.ownerId == currentUserId,
                  cal.isDate(fact.date, inSameDayAs: today),
                  fact.taskName == task.title
            else { return false }
            return fact.kind == .mustDo || fact.kind == .returning
        }

        // If undoing this completion drops any referencing booster below
        // its threshold for the current period, pull the bonus entry back.
        revokeBoostersIfNoLongerEarned(task)

        // Re-evaluate the weekly-limit penalty too: an undo can flip
        // a `.moreThan` rule out of penalty range, or push a
        // `.lessThan` rule into it.
        evaluatePenaltyForTask(task)

        // Revoke any train bonuses that were earned today and depended
        // on the just-undone completion.
        evaluateTrainsAfterTaskChange(taskId: task.id)

        persistAll()

        if !isMirroringFromCircle {
            mirrorPersonalCompletionToCircles(taskId: task.id, completed: false)
        }
    }

    /// Personal→circle direction of the cross-task bridge. For every
    /// `CircleTask` linked to `taskId`, set the current user's
    /// `CircleTaskCompletion` for today to match `completed`. No-op
    /// when there's nothing to do (already in the target state) so
    /// repeated taps don't churn the ledger or persistence.
    private func mirrorPersonalCompletionToCircles(taskId: UUID, completed: Bool) {
        let cal = Calendar.current
        let today = Date()
        var changed = false

        for circle in circles {
            for ct in circle.tasks where ct.linkedPersonalTaskId == taskId {
                let hasCompletion = circleTaskCompletions.contains { c in
                    c.circleId == circle.id
                        && c.circleTaskId == ct.id
                        && c.memberId == currentUserId
                        && cal.isDate(c.date, inSameDayAs: today)
                }
                if completed && !hasCompletion {
                    circleTaskCompletions.append(
                        CircleTaskCompletion(
                            circleId: circle.id,
                            circleTaskId: ct.id,
                            memberId: currentUserId,
                            date: today
                        )
                    )
                    changed = true
                } else if !completed && hasCompletion {
                    circleTaskCompletions.removeAll { c in
                        c.circleId == circle.id
                            && c.circleTaskId == ct.id
                            && c.memberId == currentUserId
                            && cal.isDate(c.date, inSameDayAs: today)
                    }
                    changed = true
                }
            }
        }

        if changed { persistAll() }
    }

    // MARK: - Signal facts

    /// Record a signal fact for a Task completion, if the tier rules
    /// allow it. Could-Do tier never signals — those are routine and
    /// shouldn't fill friends' headlines. A return (no completion in
    /// the prior 5 days) always signals as `.returning` for non-Could
    /// tiers; a single Must-Do completion signals as `.mustDo`.
    /// Should-Do completions that aren't returns are intentionally
    /// quiet.
    func recordSignalIfWorthy(forTask task: FFTask, isReturn: Bool, daysSince: Int?) {
        // Value-based gating (replaces the retired MUST/SHOULD/COULD
        // tiers): a return to any task is always worth a quiet signal;
        // a routine completion only signals when the task is high-value,
        // so low-value habits never flood a friend's headline.
        let isHighValue = task.nominalValue >= reminderValueThreshold
        guard isReturn || isHighValue else { return }

        let kind: SignalKind = isReturn ? .returning : .mustDo

        let fact = SignalFact(
            ownerId: currentUserId,
            kind: kind,
            date: Date(),
            taskName: task.title,
            category: task.category.displayName,
            daysSince: daysSince
        )
        signalFacts.append(fact)
        persistAll()
    }

    /// Record a threshold fact unconditionally. Callers should guard
    /// against duplicate-per-day firing themselves; the internal
    /// `maybeRecordGoalCrossedSignal(scoreBefore:)` does this for the
    /// completion paths automatically.
    func recordGoalCrossedSignal(score: Int, goal: Int) {
        let fact = SignalFact(
            ownerId: currentUserId,
            kind: .threshold,
            date: Date(),
            score: score,
            goal: goal
        )
        signalFacts.append(fact)
        persistAll()
    }

    /// Record a milestone-progress fact. Exposed for future surfaces
    /// (milestone-cleared celebrations, season summaries) that want
    /// to push a one-line signal into a friend's feed without a Task
    /// completion to anchor it.
    func recordMilestoneSignal(title: String, done: Int, total: Int) {
        let fact = SignalFact(
            ownerId: currentUserId,
            kind: .milestone,
            date: Date(),
            milestoneTitle: title,
            milestoneDone: done,
            milestoneTotal: total
        )
        signalFacts.append(fact)
        persistAll()
    }

    /// Fire a `.threshold` fact the first time today's score crosses
    /// the season's daily goal. `scoreBefore` is the total prior to
    /// the just-appended LogEntry. Idempotent across the day: skipped
    /// if a threshold fact already exists for the user today.
    private func maybeRecordGoalCrossedSignal(scoreBefore: Int) {
        let goal = currentSeason.dailyGoal
        let scoreAfter = todayScore
        guard scoreBefore < goal, scoreAfter >= goal else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let alreadyRecorded = signalFacts.contains { fact in
            fact.ownerId == currentUserId
                && fact.kind == .threshold
                && cal.isDate(fact.date, inSameDayAs: today)
        }
        guard !alreadyRecorded else { return }

        recordGoalCrossedSignal(score: scoreAfter, goal: goal)
    }

    /// Pin (or clear) a user-written headline for today. Clears any
    /// prior override fact created today before appending the new one
    /// so we never end up with stacked overrides. Passing `nil` (or
    /// an empty/whitespace-only string) removes the override and
    /// lets the generated headline surface again.
    func setMySignalOverride(_ text: String?) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        signalFacts.removeAll { fact in
            fact.ownerId == currentUserId
                && cal.isDate(fact.date, inSameDayAs: today)
                && fact.userOverrideText != nil
        }

        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            var fact = SignalFact(
                ownerId: currentUserId,
                kind: .mustDo,
                date: Date()
            )
            fact.userOverrideText = trimmed
            signalFacts.append(fact)
        }
        persistAll()
    }

    /// The headline string for a friend, as *this* user is allowed to
    /// see it. Prefers the engine's render of any locally-known
    /// signal facts; falls back to the friend's seeded snapshot
    /// fields (`todayScore`, `hitGoalToday`) when no facts exist —
    /// still gated by `sharesWithMe`. Returns a quiet floor as a
    /// last resort so a friend card always has something to render.
    func headlineFromFriend(_ friend: Friend) -> String {
        let theirFacts = signalFacts.filter { $0.ownerId == friend.id }
        if !theirFacts.isEmpty {
            return SignalEngine.headline(
                for: friend.id,
                facts: theirFacts,
                clearance: friend.sharesWithMe
            )
        }

        if friend.sharesWithMe.shareScore, let s = friend.todayScore {
            return "\(s) logged today"
        }
        if friend.sharesWithMe.shareGoalStatus, let hit = friend.hitGoalToday {
            return hit ? "Hit today\u{2019}s goal" : "Working toward today\u{2019}s goal"
        }
        return "Quiet today"
    }

    // MARK: - Circle task actions

    /// True when the current user has logged a `CircleTaskCompletion`
    /// for this circle task on today's local day. Drives the parallel
    /// detail's checkbox state and the `{done}/{total}` segment count.
    func hasUserCompletedCircleTaskToday(circleId: UUID, circleTaskId: UUID) -> Bool {
        let cal = Calendar.current
        let today = Date()
        return circleTaskCompletions.contains { c in
            c.circleId == circleId
                && c.circleTaskId == circleTaskId
                && c.memberId == currentUserId
                && cal.isDate(c.date, inSameDayAs: today)
        }
    }

    /// Total lifetime completions of a specific circle task by the
    /// current user across the circle's whole timeframe. Powers the
    /// `Overall` scope's `×N` count on the parallel detail page.
    func userCompletionCount(circleId: UUID, circleTaskId: UUID) -> Int {
        circleTaskCompletions.filter { c in
            c.circleId == circleId
                && c.circleTaskId == circleTaskId
                && c.memberId == currentUserId
        }.count
    }

    /// Distinct circle clips (`StoryPost`s with this `circleId`)
    /// created on today's local day. Used to decide whether the
    /// parallel detail's story strip should appear at all.
    func circleClipsToday(circleId: UUID) -> [StoryPost] {
        let cal = Calendar.current
        let today = Date()
        return storyPosts.filter { post in
            guard post.circleId == circleId else { return false }
            return cal.isDate(post.createdAt, inSameDayAs: today)
        }
    }

    /// Look up a personal FFTask by id. Used by the circle→personal
    /// bridge to resolve a `linkedPersonalTaskId` into the live task
    /// the existing `completeTask` / `uncompleteTask` paths want.
    func personalTask(by id: UUID) -> FFTask? {
        tasks.first { $0.id == id }
    }

    /// Toggle the current user's completion of a circle task for today.
    /// If the task carries a `linkedPersonalTaskId`, the matching
    /// personal `FFTask` is also toggled — each side awards its own
    /// points independently. The `mirror: false` hop into
    /// `setPersonalTaskCompleted` is the loop guard: the personal-side
    /// completion path never calls back into circle completions, so a
    /// single toggle moves both ledgers exactly once. C5 lands the
    /// personal→circle direction on top of this same hook.
    func toggleCircleTaskCompletion(circleId: UUID, task: CircleTask) {
        let cal = Calendar.current
        let today = Date()

        let existing = circleTaskCompletions.first { c in
            c.circleId == circleId
                && c.circleTaskId == task.id
                && c.memberId == currentUserId
                && cal.isDate(c.date, inSameDayAs: today)
        }

        let nowCompleted: Bool
        if let existing {
            circleTaskCompletions.removeAll { $0.id == existing.id }
            nowCompleted = false
        } else {
            circleTaskCompletions.append(
                CircleTaskCompletion(
                    circleId: circleId,
                    circleTaskId: task.id,
                    memberId: currentUserId,
                    date: today
                )
            )
            nowCompleted = true
        }

        if let linkedId = task.linkedPersonalTaskId {
            setPersonalTaskCompleted(linkedId, completed: nowCompleted, mirror: false)
        }

        persistAll()
    }

    /// Apply a target completion state to a personal `FFTask`.
    /// `mirror: false` indicates the call is the result of a circle→
    /// personal bridge and must not re-enter the circle ledger. The
    /// `mirror: true` hook is reserved for C5's personal→circle
    /// direction; today it's accepted but unused.
    func setPersonalTaskCompleted(_ taskId: UUID, completed: Bool, mirror: Bool) {
        guard let task = personalTask(by: taskId) else { return }
        let alreadyCompleted = hasLogEntryToday(forTaskId: taskId)

        // `mirror == false` means the call originated from the circle
        // ledger and the personal-side completion must NOT mirror back
        // into circles. Stash the previous value so nested calls (none
        // today, but cheap insurance) restore the flag cleanly.
        let previousFlag = isMirroringFromCircle
        isMirroringFromCircle = !mirror
        defer { isMirroringFromCircle = previousFlag }

        if completed && !alreadyCompleted {
            completeTask(task)
        } else if !completed && alreadyCompleted {
            uncompleteTask(task)
        }
    }

    // MARK: - Circle task linking

    /// Bridge a circle task to one of the user's personal `FFTask`s.
    /// Enforces single-link-per-personal-task by clearing any other
    /// `linkedPersonalTaskId` pointing at this personal task before
    /// writing the new one, so the picker can present "already linked
    /// elsewhere" as a soft constraint while the store stays consistent.
    func linkCircleTask(circleId: UUID, circleTaskId: UUID, personalTaskId: UUID) {
        for ci in circles.indices {
            for ti in circles[ci].tasks.indices {
                if circles[ci].tasks[ti].linkedPersonalTaskId == personalTaskId {
                    circles[ci].tasks[ti].linkedPersonalTaskId = nil
                }
            }
        }
        guard let ci = circles.firstIndex(where: { $0.id == circleId }),
              let ti = circles[ci].tasks.firstIndex(where: { $0.id == circleTaskId })
        else { return }
        circles[ci].tasks[ti].linkedPersonalTaskId = personalTaskId
        persistAll()
    }

    /// Drop the bridge on a circle task. The two ledgers remain as
    /// they were — past completions on either side stay; only future
    /// toggles stop mirroring.
    func unlinkCircleTask(circleId: UUID, circleTaskId: UUID) {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }),
              let ti = circles[ci].tasks.firstIndex(where: { $0.id == circleTaskId })
        else { return }
        circles[ci].tasks[ti].linkedPersonalTaskId = nil
        persistAll()
    }

    /// First `(circleId, circleTaskId, circleName, circleTaskTitle)`
    /// pointing at this personal task, if any. Used by the linking
    /// picker to flag personal tasks already bridged to another circle
    /// task and to surface where they're linked.
    func circleTaskLinked(toPersonalTaskId personalTaskId: UUID)
        -> (circleId: UUID, circleTaskId: UUID, circleName: String, taskTitle: String)?
    {
        for circle in circles {
            for ct in circle.tasks where ct.linkedPersonalTaskId == personalTaskId {
                return (circle.id, ct.id, circle.name, ct.title)
            }
        }
        return nil
    }

    // MARK: - Circle roles + governance (C11)

    /// The role the current user holds inside `circle`. Convenience
    /// over `FFCircle.role(forUserId:)` so views can drop `userId`.
    func myRole(in circle: FFCircle) -> CircleRole {
        circle.role(forUserId: currentUserId)
    }

    /// True when the current user can directly mutate the shared task
    /// list (owner or admin). Drives whether the settings UI shows
    /// task edit/delete controls versus the propose flow.
    func canManageTasks(in circle: FFCircle) -> Bool {
        circle.canManageTasks(userId: currentUserId)
    }

    /// True when the current user is the owner. Owner-only controls
    /// (governance toggle, transfer, admin promotion) gate on this.
    func isOwner(of circle: FFCircle) -> Bool {
        circle.role(forUserId: currentUserId) == .owner
    }

    /// All pending requests for a given circle, oldest first so the
    /// review surface lists them in arrival order.
    func pendingRequests(forCircleId circleId: UUID) -> [CircleTaskRequest] {
        circleTaskRequests
            .filter { $0.circleId == circleId && $0.status == .pending }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Count of pending requests for a circle. Used for the small
    /// badge that surfaces on the settings row when there's review
    /// work waiting.
    func pendingRequestCount(forCircleId circleId: UUID) -> Int {
        circleTaskRequests.reduce(0) { partial, r in
            partial + ((r.circleId == circleId && r.status == .pending) ? 1 : 0)
        }
    }

    /// Flip the governance toggle. Owner-only. When turning it off,
    /// any still-pending requests are left in place — the owner can
    /// resolve or reject them from the queue.
    func setMembersCanProposeTasks(_ value: Bool, in circleId: UUID) {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }),
              isOwner(of: circles[ci])
        else { return }
        circles[ci].membersCanProposeTasks = value
        persistAll()
    }

    /// Promote a member to admin. Owner-only. No-op if the target
    /// isn't a member or is already admin/owner.
    func promoteToAdmin(userId: UUID, in circleId: UUID) {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }),
              isOwner(of: circles[ci]),
              circles[ci].memberIds.contains(userId),
              circles[ci].role(forUserId: userId) == .member
        else { return }
        circles[ci].adminIds.append(userId)
        persistAll()
    }

    /// Demote an admin back to plain member. Owner-only.
    func demoteFromAdmin(userId: UUID, in circleId: UUID) {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }),
              isOwner(of: circles[ci])
        else { return }
        circles[ci].adminIds.removeAll { $0 == userId }
        persistAll()
    }

    /// Hand ownership to another member. Owner-only. The new owner
    /// is removed from the admin list (owner outranks admin) and the
    /// previous owner stays in the circle as a plain member.
    func transferOwnership(to userId: UUID, in circleId: UUID) {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }),
              isOwner(of: circles[ci]),
              circles[ci].memberIds.contains(userId),
              userId != currentUserId
        else { return }
        circles[ci].ownerId = userId
        circles[ci].adminIds.removeAll { $0 == userId }
        persistAll()
    }

    /// Drop a member from the circle. Owner or admin. Owners can't
    /// be removed; they must transfer ownership first. Past
    /// completions / contributions stay in history.
    func removeMember(userId: UUID, from circleId: UUID) {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }) else { return }
        guard canManageTasks(in: circles[ci]) else { return }
        // Owner can't be kicked.
        if circles[ci].ownerId == userId { return }
        // Admins can't remove other admins or the owner; only the owner can.
        if circles[ci].adminIds.contains(userId), !isOwner(of: circles[ci]) { return }
        circles[ci].memberIds.removeAll { $0 == userId }
        circles[ci].adminIds.removeAll { $0 == userId }
        persistAll()
    }

    // MARK: - Circle shared-task mutation (gated by governance)

    /// Apply or queue an add-task action. Returns `true` when the
    /// change applied directly to the circle, `false` when it became
    /// a pending `CircleTaskRequest`. Callers can use the return to
    /// confirm "queued for review" copy.
    @discardableResult
    func addOrProposeCircleTask(circleId: UUID, draft: CircleTaskDraft) -> Bool {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }) else { return false }
        let circle = circles[ci]
        if circle.requiresRequest(forUserId: currentUserId) {
            circleTaskRequests.append(
                CircleTaskRequest(
                    circleId: circleId,
                    requesterId: currentUserId,
                    type: .add,
                    taskData: draft,
                    existingTaskId: nil
                )
            )
            persistAll()
            return false
        }
        guard circle.canManageTasks(userId: currentUserId) else { return false }
        circles[ci].tasks.append(
            CircleTask(
                title: draft.title,
                pointValue: draft.pointValue,
                linkedPersonalTaskId: draft.linkedPersonalTaskId
            )
        )
        persistAll()
        return true
    }

    /// Apply or queue an edit-task action.
    @discardableResult
    func editOrProposeCircleTask(
        circleId: UUID,
        existingTaskId: UUID,
        draft: CircleTaskDraft
    ) -> Bool {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }) else { return false }
        let circle = circles[ci]
        if circle.requiresRequest(forUserId: currentUserId) {
            circleTaskRequests.append(
                CircleTaskRequest(
                    circleId: circleId,
                    requesterId: currentUserId,
                    type: .edit,
                    taskData: draft,
                    existingTaskId: existingTaskId
                )
            )
            persistAll()
            return false
        }
        guard circle.canManageTasks(userId: currentUserId) else { return false }
        guard let ti = circles[ci].tasks.firstIndex(where: { $0.id == existingTaskId }) else { return false }
        circles[ci].tasks[ti].title = draft.title
        circles[ci].tasks[ti].pointValue = draft.pointValue
        circles[ci].tasks[ti].linkedPersonalTaskId = draft.linkedPersonalTaskId
        persistAll()
        return true
    }

    /// Apply or queue a delete-task action.
    @discardableResult
    func deleteOrProposeCircleTask(circleId: UUID, existingTaskId: UUID) -> Bool {
        guard let ci = circles.firstIndex(where: { $0.id == circleId }) else { return false }
        let circle = circles[ci]
        if circle.requiresRequest(forUserId: currentUserId) {
            let snapshot = circle.tasks.first { $0.id == existingTaskId }
            let draft = snapshot.map { CircleTaskDraft(from: $0) }
                ?? CircleTaskDraft(title: "(removed task)")
            circleTaskRequests.append(
                CircleTaskRequest(
                    circleId: circleId,
                    requesterId: currentUserId,
                    type: .delete,
                    taskData: draft,
                    existingTaskId: existingTaskId
                )
            )
            persistAll()
            return false
        }
        guard circle.canManageTasks(userId: currentUserId) else { return false }
        circles[ci].tasks.removeAll { $0.id == existingTaskId }
        // Sweep completions for the removed task so progress reads stay clean.
        circleTaskCompletions.removeAll { $0.circleTaskId == existingTaskId }
        persistAll()
        return true
    }

    /// Approve a pending request. Owner/admin only. Applies the
    /// proposed change to the live circle and records who reviewed.
    func approveRequest(_ requestId: UUID) {
        guard let ri = circleTaskRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = circleTaskRequests[ri]
        guard request.status == .pending,
              let ci = circles.firstIndex(where: { $0.id == request.circleId }),
              canManageTasks(in: circles[ci])
        else { return }

        switch request.type {
        case .add:
            circles[ci].tasks.append(
                CircleTask(
                    title: request.taskData.title,
                    pointValue: request.taskData.pointValue,
                    linkedPersonalTaskId: request.taskData.linkedPersonalTaskId
                )
            )
        case .edit:
            if let existingId = request.existingTaskId,
               let ti = circles[ci].tasks.firstIndex(where: { $0.id == existingId }) {
                circles[ci].tasks[ti].title = request.taskData.title
                circles[ci].tasks[ti].pointValue = request.taskData.pointValue
                circles[ci].tasks[ti].linkedPersonalTaskId = request.taskData.linkedPersonalTaskId
            }
        case .delete:
            if let existingId = request.existingTaskId {
                circles[ci].tasks.removeAll { $0.id == existingId }
                circleTaskCompletions.removeAll { $0.circleTaskId == existingId }
            }
        }

        circleTaskRequests[ri].status = .approved
        circleTaskRequests[ri].reviewedById = currentUserId
        circleTaskRequests[ri].reviewedAt = Date()
        persistAll()
    }

    /// Reject a pending request. Owner/admin only. Records the
    /// rejection without touching the live circle.
    func rejectRequest(_ requestId: UUID) {
        guard let ri = circleTaskRequests.firstIndex(where: { $0.id == requestId }) else { return }
        let request = circleTaskRequests[ri]
        guard request.status == .pending,
              let circle = circles.first(where: { $0.id == request.circleId }),
              canManageTasks(in: circle)
        else { return }
        circleTaskRequests[ri].status = .rejected
        circleTaskRequests[ri].reviewedById = currentUserId
        circleTaskRequests[ri].reviewedAt = Date()
        persistAll()
    }

    // MARK: - Circle mode switching + the group's story (CR2)

    /// Add an objective layer (a shared list or a shared number) to a
    /// circle, switching its mode while keeping the same group, identity,
    /// and history. Owner/admin only. Re-adding a previously set-aside
    /// layer resumes its dormant data exactly where it left off. Returns
    /// `true` when the change applied.
    @discardableResult
    func addCircleLayer(
        _ kind: CircleObjectiveKind,
        to circleId: UUID,
        unit: String? = nil,
        target: Double? = nil
    ) -> Bool {
        guard let circle = circle(by: circleId), !circle.objectives.contains(kind) else { return false }
        return setCircleObjectives(circle.objectives + [kind], in: circleId, unit: unit, target: target)
    }

    /// Set aside an objective layer — it goes dormant, never deleted.
    /// The shared list (and its completion history) or the shared number
    /// (and its running total) sleeps until the layer is re-added. Owner/
    /// admin only.
    @discardableResult
    func removeCircleLayer(_ kind: CircleObjectiveKind, from circleId: UUID) -> Bool {
        guard let circle = circle(by: circleId), circle.objectives.contains(kind) else { return false }
        return setCircleObjectives(circle.objectives.filter { $0 != kind }, in: circleId)
    }

    /// The heart of mode-switching: set a circle's active objective
    /// layers. Owner/admin only. Closes the current chapter and opens a
    /// new one so the switch is recorded in the group's story, and never
    /// destroys the data of a layer being set aside (suspend-not-delete).
    @discardableResult
    func setCircleObjectives(
        _ requested: [CircleObjectiveKind],
        in circleId: UUID,
        unit: String? = nil,
        target: Double? = nil
    ) -> Bool {
        guard let i = circles.firstIndex(where: { $0.id == circleId }) else { return false }
        guard canManageTasks(in: circles[i]) else { return false }

        let old = circles[i].objectives
        let new = Self.normalizeObjectives(requested)
        guard new != old else { return false }

        // Adding a shared-number layer: set/refresh its unit + target and
        // resume any dormant progress (never reset a running total).
        if new.contains(.sharedNumber) && !old.contains(.sharedNumber) {
            let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedUnit, !trimmedUnit.isEmpty {
                circles[i].collectiveUnit = trimmedUnit
            } else if (circles[i].collectiveUnit ?? "").isEmpty {
                circles[i].collectiveUnit = "total"
            }
            if let target, target > 0 {
                circles[i].collectiveTarget = target
            }
            // Resume dormant progress from any contributions already logged.
            let logged = circleContributions
                .filter { $0.circleId == circleId }
                .reduce(0) { $0 + $1.amount }
            circles[i].collectiveProgress = max(circles[i].collectiveProgress ?? 0, logged)
        }

        // Suspend-not-delete: a layer set aside keeps ALL of its data —
        // tasks + completions for a list, target + contributions for a
        // number — so re-adding it later resumes everything untouched.
        // We deliberately mutate nothing on removal.

        circles[i].objectives = new
        transitionChapter(at: i, from: old, to: new, actorName: "You")
        persistAll()
        return true
    }

    /// Close the open chapter (recording how it ended) and open a fresh
    /// one for the new mode, so the circle's lifetime story stays whole.
    private func transitionChapter(
        at i: Int,
        from old: [CircleObjectiveKind],
        to new: [CircleObjectiveKind],
        actorName: String?
    ) {
        let now = Date()
        if let ci = circles[i].chapters.lastIndex(where: { $0.endedAt == nil }) {
            circles[i].chapters[ci].endedAt = now
            circles[i].chapters[ci].outcome = Self.closingOutcome(
                objectives: old,
                target: circles[i].collectiveTarget,
                progress: circles[i].collectiveProgress
            )
        }
        let snap = Self.chapterSnapshot(
            objectives: new,
            tasks: circles[i].tasks,
            unit: circles[i].collectiveUnit,
            target: circles[i].collectiveTarget
        )
        circles[i].chapters.append(
            CircleChapter(
                objectives: new,
                title: snap.title,
                detail: snap.detail,
                startedAt: now,
                endedAt: nil,
                outcome: .ongoing,
                actorName: actorName
            )
        )
    }

    /// Stable, de-duplicated layer order — list before number — so the
    /// derived type and equality checks are deterministic.
    static func normalizeObjectives(_ objs: [CircleObjectiveKind]) -> [CircleObjectiveKind] {
        var result: [CircleObjectiveKind] = []
        if objs.contains(.sharedList) { result.append(.sharedList) }
        if objs.contains(.sharedNumber) { result.append(.sharedNumber) }
        return result
    }

    /// How a closing chapter reads in the lookback: a number that hit its
    /// target is `completed`; a presence stretch ending is `returned`;
    /// anything else was `setAside` (dormant, never gone).
    static func closingOutcome(
        objectives: [CircleObjectiveKind],
        target: Double?,
        progress: Double?
    ) -> CircleChapterOutcome {
        if objectives.isEmpty { return .returned }
        if objectives.contains(.sharedNumber), let target, target > 0, (progress ?? 0) >= target {
            return .completed
        }
        return .setAside
    }

    /// A warm label + supporting line for a chapter that runs with the
    /// given layers, using the circle's goal data for context. Pure so
    /// both seeding and live switching can share it.
    static func chapterSnapshot(
        objectives: [CircleObjectiveKind],
        tasks: [CircleTask],
        unit: String?,
        target: Double?
    ) -> (title: String, detail: String?) {
        switch CircleType(objectives: objectives) {
        case .witness:
            return ("Just present", "Everyone kept their own goals")
        case .parallel:
            let titles = tasks.map(\.title).filter { !$0.isEmpty }
            return ("Shared list", titles.isEmpty ? "A shared checklist" : titles.prefix(3).joined(separator: " · "))
        case .collective:
            if let target, target > 0, let unit, !unit.isEmpty {
                let t = target.rounded() == target ? String(Int(target)) : String(format: "%.1f", target)
                return ("Shared number", "\(t) \(unit)")
            }
            return ("Shared number", "One number, together")
        case .hybrid:
            return ("Two goals", "A shared list and a shared number")
        }
    }

    /// Ensure every circle carries at least its founding chapter so the
    /// group's story always has a timeline. Backfills circles persisted
    /// before chapters landed and any seeded circle without an explicit
    /// story; leaves circles that already have chapters untouched.
    static func withChapterTimelines(_ circles: [FFCircle]) -> [FFCircle] {
        circles.map { circle in
            guard circle.chapters.isEmpty else { return circle }
            var c = circle
            let snap = chapterSnapshot(
                objectives: c.objectives,
                tasks: c.tasks,
                unit: c.collectiveUnit,
                target: c.collectiveTarget
            )
            c.chapters = [
                CircleChapter(
                    objectives: c.objectives,
                    title: snap.title,
                    detail: snap.detail,
                    startedAt: c.createdAt,
                    endedAt: nil,
                    outcome: .ongoing,
                    actorName: nil
                )
            ]
            return c
        }
    }

    /// Story posts (proofs / moments) attached to a circle within a
    /// chapter's window — the proofs + milestones that lookback surfaces
    /// alongside each chapter.
    func storyPosts(forCircleId circleId: UUID, in chapter: CircleChapter) -> [StoryPost] {
        let end = chapter.endedAt ?? Date()
        return storyPosts.filter { post in
            post.circleId == circleId
                && post.createdAt >= chapter.startedAt
                && post.createdAt <= end
        }
    }

    // MARK: - Note actions

    /// Append a brand-new Note and persist. Caller is responsible for
    /// any side-effects (e.g. recording → file written) before calling.
    func addNote(_ note: Note) {
        notes.append(note)
        persistAll()
    }

    /// Replace an existing Note in place. If the id doesn't match, the
    /// call is silently dropped so accidental stale references don't
    /// corrupt the array.
    func updateNote(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx] = note
        persistAll()
    }

    /// Remove a Note. Also deletes the attached voice memo file on
    /// disk so the Documents directory doesn't accumulate orphans.
    func deleteNote(_ note: Note) {
        for memo in note.voiceMemos {
            if let url = memo.url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        notes.removeAll { $0.id == note.id }
        persistAll()
    }

    /// Flip a note's pinned state and persist immediately. Pinning is
    /// a one-tap action from the detail toolbar, so we don't gate it
    /// behind the form's dirty/save flow — it commits on tap.
    func togglePinned(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx].isPinned.toggle()
        persistAll()
    }

    // MARK: - Folder actions

    /// Add a folder and return the persisted value. Trims whitespace
    /// off the name so accidental padding doesn't break sort order.
    @discardableResult
    func addFolder(name: String, colorKey: FolderColor) -> NoteFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = NoteFolder(name: trimmed, colorKey: colorKey)
        folders.append(folder)
        persistAll()
        return folder
    }

    /// Rename a folder (trimmed). Silently drops if id doesn't match.
    func renameFolder(_ folder: NoteFolder, to newName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        persistAll()
    }

    /// Change a folder's tint to one of the eight palette options.
    func recolorFolder(_ folder: NoteFolder, to colorKey: FolderColor) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].colorKey = colorKey
        persistAll()
    }

    /// Delete a folder. When `deleteNotes` is `true`, every note in
    /// the folder is also removed (audio cleaned up). Otherwise the
    /// notes are kept but moved to "no folder".
    func deleteFolder(_ folder: NoteFolder, deleteNotes: Bool) {
        if deleteNotes {
            for note in notes where note.folderId == folder.id {
                for memo in note.voiceMemos {
                    if let url = memo.url {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            notes.removeAll { $0.folderId == folder.id }
        } else {
            for i in notes.indices where notes[i].folderId == folder.id {
                notes[i].folderId = nil
            }
        }
        folders.removeAll { $0.id == folder.id }
        persistAll()
    }

    /// Flip a To-do's completion state. When completing a pointed To-do
    /// we also record a LogEntry so the day's score moves. Uncompleting
    /// removes both the flag and the matching LogEntry.
    func toggleTodo(_ todo: Todo) {
        guard let idx = todos.firstIndex(where: { $0.id == todo.id }) else { return }

        if todos[idx].isCompleted {
            todos[idx].isCompleted = false
            todos[idx].completedAt = nil
            logEntries.removeAll { $0.todoId == todo.id }
        } else {
            todos[idx].isCompleted = true
            todos[idx].completedAt = Date()
            if let points = todo.pointValue {
                let entry = LogEntry(
                    date: Date(),
                    taskId: nil,
                    todoId: todo.id,
                    pointsEarned: points,
                    entryType: .completed
                )
                logEntries.append(entry)
            }
        }
        persistAll()
    }

    // MARK: - Day rollover

    /// Runs once per local day. Sweeps stale pins (`.today` schedules
    /// reset to `.none`, past-dated `.singleDate` pins likewise) and
    /// auto-records a skip-penalty LogEntry for any Must-Do that
    /// wasn't completed yesterday. Skipped on the very first launch
    /// so a fresh install doesn't penalise the user for a day the app
    /// didn't exist.
    func performDayRolloverIfNeeded() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let lastRollover = userDefaults.object(forKey: Keys.lastRollover) as? Date
        if let lastRollover, cal.isDate(lastRollover, inSameDayAs: today) {
            return // Already ran today
        }

        let isFirstRollover = (lastRollover == nil)

        // 1. Sweep stale pins. `.today` always clears; past-dated
        //    `.singleDate` pins are tidied to `.none` so they don't
        //    accumulate forever. Recurring schedules are left alone.
        for i in tasks.indices {
            switch tasks[i].pinSchedule {
            case .today:
                tasks[i].pinSchedule = .none
            case .singleDate(let date):
                if cal.startOfDay(for: date) < today {
                    tasks[i].pinSchedule = .none
                }
            case .none, .daily, .daysOfWeek:
                break
            }
        }

        // 2. Penalise yesterday's missed Must-Dos. Skipped on first
        //    launch — there's no "yesterday" to evaluate when the app
        //    didn't exist yet.
        if !isFirstRollover, let yesterday = cal.date(byAdding: .day, value: -1, to: today) {
            // Skip penalties apply to ANY task that opts into one (no
            // longer gated by the retired Must-Do tier).
            for task in tasks {
                guard let penalty = task.skipPenalty, penalty < 0 else { continue }

                let completedYesterday = logEntries.contains { entry in
                    entry.taskId == task.id
                        && cal.isDate(entry.date, inSameDayAs: yesterday)
                        && entry.entryType == .completed
                }
                let alreadyPenalised = logEntries.contains { entry in
                    entry.taskId == task.id
                        && cal.isDate(entry.date, inSameDayAs: yesterday)
                        && entry.entryType == .penalty
                }
                guard !completedYesterday, !alreadyPenalised else { continue }

                let entry = LogEntry(
                    date: yesterday,
                    taskId: task.id,
                    todoId: nil,
                    pointsEarned: penalty,
                    entryType: .penalty
                )
                logEntries.append(entry)
            }

            // Linked Cadence Must routines with an opt-in skip penalty
            // get the same missed-Must-Do treatment. Without a penalty
            // they're exempt (the link enriches, never pressures).
            for link in cadenceLinks where cadenceConnected
                && link.type == .launchRun
                && link.recurrence.matches(yesterday) {
                guard let penalty = link.skipPenalty, penalty < 0 else { continue }
                let earnedYesterday = logEntries.contains { entry in
                    entry.cadenceLinkId == link.id
                        && cal.isDate(entry.date, inSameDayAs: yesterday)
                        && entry.entryType == .completed
                }
                let alreadyPenalised = logEntries.contains { entry in
                    entry.cadenceLinkId == link.id
                        && cal.isDate(entry.date, inSameDayAs: yesterday)
                        && entry.entryType == .penalty
                }
                guard !earnedYesterday, !alreadyPenalised else { continue }
                logEntries.append(LogEntry(
                    date: yesterday,
                    taskId: nil,
                    todoId: nil,
                    cadenceLinkId: link.id,
                    pointsEarned: penalty,
                    entryType: .penalty
                ))
            }
        }

        userDefaults.set(today, forKey: Keys.lastRollover)
        persistAll()
    }

    /// Seven daily scores, oldest first, ending with today. Future days
    /// never appear — the array always ends on today's local day.
    var weekStripeData: [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var results: [Int] = []
        for offset in (0...6).reversed() {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else {
                results.append(0)
                continue
            }
            let dayScore = logEntries
                .filter { cal.isDate($0.date, inSameDayAs: day) }
                .map { $0.pointsEarned }
                .reduce(0, +)
            results.append(dayScore)
        }
        return results
    }
}

// MARK: - Seed data

extension Store {
    static func seedSeason() -> Season {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -22, to: Date()) ?? Date()
        let seasonId = UUID()
        return Season(
            id: seasonId,
            name: "Album Season",
            lengthDays: 60,
            startDate: startDate,
            vibe: .warmForest,
            dailyGoal: 50,
            weeklyGoal: 350,
            categories: [
                SeasonCategory(category: .creative, tier: .primary),
                SeasonCategory(category: .spiritual, tier: .primary),
                SeasonCategory(category: .fitness, tier: .support),
                SeasonCategory(category: .health, tier: .support),
                SeasonCategory(category: .work, tier: .quiet)
            ],
            milestones: [
                Milestone(seasonId: seasonId, weekNumber: 3, title: "Finish 3 demos", status: .inMotion, pointValue: 50),
                Milestone(seasonId: seasonId, weekNumber: 6, title: "Master the EP", status: .upcoming, pointValue: 80),
                Milestone(seasonId: seasonId, weekNumber: 9, title: "Release the single", status: .upcoming, pointValue: 120)
            ]
        )
    }

    /// A wider seed list than v1 — the expanded Season page in
    /// Prompt 2h needs enough Tasks across categories and tiers to
    /// demonstrate grouping. Several entries also exercise the new
    /// `.daily` and `.daysOfWeek` pin schedules.
    static func seedTasks() -> [FFTask] {
        [
            FFTask(
                title: "Lift — push day",
                category: .fitness,
                pointValue: 10,
                tier: .must,
                skipPenalty: -5,
                estimatedMinutes: 40,
                pinSchedule: .today
            ),
            FFTask(
                title: "Ship v2 onboarding to TestFlight",
                category: .work,
                pointValue: 15,
                tier: .should,
                estimatedMinutes: 90,
                pinSchedule: .today
            ),
            FFTask(
                title: "Morning prayer + reading",
                category: .spiritual,
                pointValue: 8,
                tier: .must,
                skipPenalty: -5,
                pinSchedule: .daily
            ),
            FFTask(
                title: "Capital One deep work block",
                category: .work,
                pointValue: 12,
                tier: .should,
                estimatedMinutes: 90,
                pinSchedule: .daysOfWeek([2, 3, 4, 5, 6])
            ),
            FFTask(
                title: "Wash face · brush teeth",
                category: .health,
                pointValue: 2,
                tier: .could,
                pinSchedule: .daily
            ),
            FFTask(
                title: "Northup verse work",
                category: .creative,
                pointValue: 7,
                tier: .should,
                pinSchedule: .today
            ),
            FFTask(
                title: "Evening reflection",
                category: .spiritual,
                pointValue: 5,
                tier: .could,
                estimatedMinutes: 15,
                pinSchedule: .today
            ),
            FFTask(
                title: "Demo recording session",
                category: .creative,
                pointValue: 12,
                tier: .should,
                estimatedMinutes: 45,
                pinSchedule: .today
            ),
            FFTask(
                title: "Lyrics journal entry",
                category: .creative,
                pointValue: 3,
                tier: .could,
                estimatedMinutes: 10,
                pinSchedule: .today
            ),
            // Tiered — sleep awards the highest level the logged hours reach.
            FFTask(
                title: "Sleep 7+ hours",
                category: .health,
                pointValue: 4,
                pinSchedule: .daily,
                scoring: ScoringConfig(
                    type: .tiered,
                    unit: "hours",
                    tiers: [
                        ScoreTier(threshold: 6, points: 2),
                        ScoreTier(threshold: 7, points: 4),
                        ScoreTier(threshold: 8, points: 6)
                    ]
                )
            ),
            // Quantity — base payout at a floor, plus more per block beyond.
            FFTask(
                title: "Pushups",
                category: .fitness,
                pointValue: 3,
                pinSchedule: .today,
                scoring: ScoringConfig(
                    type: .quantity,
                    unit: "reps",
                    baseThreshold: 100,
                    basePoints: 3,
                    unitSize: 50,
                    pointsPerUnit: 1
                )
            )
        ]
    }

    static func seedTodos() -> [Todo] {
        let calendar = Calendar.current
        let today = Date()
        return [
            Todo(
                title: "Call grandma",
                dueDate: calendar.date(byAdding: .day, value: -2, to: today),
                pointValue: 4
            ),
            Todo(
                title: "Doctor — annual physical",
                dueDate: calendar.date(byAdding: .day, value: 2, to: today),
                pointValue: 6
            ),
            Todo(
                title: "Email landlord about the radiator",
                dueDate: today,
                pointValue: 2
            ),
            Todo(
                title: "Replace bathroom lightbulb",
                dueDate: nil,
                pointValue: nil
            )
        ]
    }

    static func seedLogEntries() -> [LogEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return [
            // Today: 8 + 12 + 12 = 32 → matches the hardcoded Sun-zone score.
            LogEntry(date: today, pointsEarned: 8),
            LogEntry(date: today, pointsEarned: 12),
            LogEntry(date: today, pointsEarned: 12),
            // Yesterday
            LogEntry(
                date: cal.date(byAdding: .day, value: -1, to: today) ?? today,
                pointsEarned: 42
            ),
            // 2 days ago
            LogEntry(
                date: cal.date(byAdding: .day, value: -2, to: today) ?? today,
                pointsEarned: 58
            ),
            // 3 days ago
            LogEntry(
                date: cal.date(byAdding: .day, value: -3, to: today) ?? today,
                pointsEarned: 25
            )
        ]
    }

    /// The three folders the v1 design referenced (Songs, Prayer,
    /// Work). Their tints match the previously-hard-coded styling so
    /// the morning-pages screenshot still reads the same way after
    /// the model lift.
    static func seedFolders() -> [NoteFolder] {
        [
            NoteFolder(name: "Songs", colorKey: .purple),
            NoteFolder(name: "Prayer", colorKey: .green),
            NoteFolder(name: "Work", colorKey: .blue)
        ]
    }

    static func seedNotes() -> [Note] {
        let calendar = Calendar.current
        let now = Date()
        let morning = calendar.date(bySettingHour: 8, minute: 14, second: 0, of: now) ?? now
        return [
            Note(
                createdAt: morning,
                body: "Slept rough. Mind kept circling the v2 onboarding — the empty state copy still isn't right. Going to lift first to clear it, then sit with the screen. Don't open Slack until after.",
                label: "morning pages"
            )
        ]
    }
}

// MARK: - Social accessors
//
// Read-only helpers the homepage / future Circles surfaces use to
// slice the social arrays without leaking the underlying filtering
// logic. Every accessor reads observable state, so any view that
// touches them updates automatically as cheers / posts roll over.

extension Store {
    /// Cheers sent today, newest first. The homepage Season zone
    /// surfaces these; older cheers stay in the store but don't
    /// surface there. (`isActiveToday` follows the local calendar.)
    var activeCheersToday: [Cheer] {
        cheers
            .filter { $0.isActiveToday && $0.toUserId == currentUserId && $0.dismissedAt == nil }
            .sorted { $0.sentAt > $1.sentAt }
    }

    /// Swipe a received cheer off the homepage. The cheer stays in
    /// the underlying ledger (history is preserved), but it no
    /// longer surfaces in `activeCheersToday`.
    func dismissCheer(_ cheerId: UUID) {
        guard let idx = cheers.firstIndex(where: { $0.id == cheerId }),
              cheers[idx].dismissedAt == nil else { return }
        cheers[idx].dismissedAt = Date()
        if cheers[idx].readAt == nil {
            cheers[idx].readAt = Date()
        }
        persistAll()
    }

    /// Resolve the `Friend` who sent a given cheer, so the recipient
    /// can tap a received cheer and send one back. Returns nil if
    /// the friend has since been removed from the contacts list.
    func friend(forCheer cheer: Cheer) -> Friend? {
        friends.first { $0.id == cheer.fromFriendId }
    }

    // MARK: - C7b: cheers

    /// Append a cheer from the current user to a friend. Empty
    /// messages drop silently so the composer's Send button can be
    /// kept enabled-by-default without writing a ghost row.
    func sendCheer(to friend: Friend, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cheers.append(Cheer(
            fromFriendId: currentUserId,
            fromName: "You",
            fromInitials: "Y",
            fromColorHex: "2C2C2A",
            toUserId: friend.id,
            message: trimmed
        ))
        persistAll()
    }

    // MARK: - C8b: posting media

    /// Persist a captured photo (or video) as a `MediaAsset` + a
    /// `StoryPost`. Writes the image bytes into the app's Documents
    /// directory so the file id survives across launches; the
    /// `MediaAsset.localURL` carries that path forward for the
    /// renderers. The `circleId` / `attachedCircleTaskId` fields
    /// branch destinations: nil circleId → general friend post that
    /// expires in 24h; non-nil → a circle clip archived for the
    /// circle's life with an optional earned-task badge.
    @discardableResult
    func postMedia(
        imageData: Data?,
        type: MediaType,
        caption: String?,
        circleId: UUID?,
        attachedCircleTaskId: UUID?,
        durationSeconds: Double? = nil
    ) -> StoryPost {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionOrNil: String? = (trimmed?.isEmpty == false) ? trimmed : nil

        let asset = Self.writeMediaAsset(
            imageData: imageData,
            type: type,
            durationSeconds: durationSeconds
        )
        mediaAssets.append(asset)

        let post = StoryPost(
            authorId: currentUserId,
            createdAt: Date(),
            caption: captionOrNil,
            mediaId: asset.id,
            circleId: circleId,
            attachedCircleTaskId: attachedCircleTaskId
        )
        storyPosts.insert(post, at: 0)
        persistAll()
        return post
    }

    /// Writes the captured photo bytes into the app's Documents
    /// directory under a UUID-named `.jpg`, returning a fully-formed
    /// `MediaAsset` pointing at the new file. Falls back to a
    /// URL-less asset if either the bytes are missing or the disk
    /// write fails so the post still threads through the social
    /// surfaces — better an attribution-only post than a crash.
    private static func writeMediaAsset(
        imageData: Data?,
        type: MediaType,
        durationSeconds: Double?
    ) -> MediaAsset {
        guard let imageData,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return MediaAsset(
                type: type,
                localURL: nil,
                remoteURL: nil,
                thumbnailURL: nil,
                durationSeconds: durationSeconds,
                createdAt: Date()
            )
        }

        let dir = docs.appendingPathComponent("FrisFocusMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ext = (type == .photo) ? "jpg" : "mov"
        let url = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try imageData.write(to: url, options: .atomic)
            return MediaAsset(
                type: type,
                localURL: url,
                remoteURL: nil,
                thumbnailURL: nil,
                durationSeconds: durationSeconds,
                createdAt: Date()
            )
        } catch {
            return MediaAsset(
                type: type,
                localURL: nil,
                remoteURL: nil,
                thumbnailURL: nil,
                durationSeconds: durationSeconds,
                createdAt: Date()
            )
        }
    }

    // MARK: - C8c: direct (private) shares

    /// Send a captured photo/video privately to any combination of
    /// friends and circles in one action. The media is written **once**
    /// and every recipient gets a `DirectShare` pointing at that single
    /// asset — a personal copy per friend, plus one per circle (a circle
    /// fans out to its members). Picking several recipients is NOT a
    /// group thread. Returns the created shares; an empty/unresolved
    /// recipient list is a no-op.
    @discardableResult
    func sendDirect(
        imageData: Data?,
        type: MediaType,
        caption: String?,
        friendIds: [UUID],
        circleIds: [UUID],
        durationSeconds: Double? = nil
    ) -> [DirectShare] {
        let friendRecipients = friendIds.filter { friend(by: $0) != nil }
        let circleRecipients = circleIds.filter { circle(by: $0) != nil }
        guard !friendRecipients.isEmpty || !circleRecipients.isEmpty else { return [] }

        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionOrNil: String? = (trimmed?.isEmpty == false) ? trimmed : nil

        let asset = Self.writeMediaAsset(
            imageData: imageData,
            type: type,
            durationSeconds: durationSeconds
        )
        mediaAssets.append(asset)

        let now = Date()
        var created: [DirectShare] = []
        created.append(contentsOf: friendRecipients.map { friendId in
            DirectShare(
                authorId: currentUserId,
                recipientFriendId: friendId,
                circleId: nil,
                caption: captionOrNil,
                mediaId: asset.id,
                createdAt: now
            )
        })
        created.append(contentsOf: circleRecipients.map { circleId in
            DirectShare(
                authorId: currentUserId,
                recipientFriendId: nil,
                circleId: circleId,
                caption: captionOrNil,
                mediaId: asset.id,
                createdAt: now
            )
        })
        directShares.insert(contentsOf: created, at: 0)
        persistAll()
        return created
    }

    /// Send privately to one or more friends. Thin wrapper over
    /// `sendDirect` kept for existing call sites.
    @discardableResult
    func sendDirectToFriends(
        imageData: Data?,
        type: MediaType,
        caption: String?,
        friendIds: [UUID],
        durationSeconds: Double? = nil
    ) -> [DirectShare] {
        sendDirect(
            imageData: imageData,
            type: type,
            caption: caption,
            friendIds: friendIds,
            circleIds: [],
            durationSeconds: durationSeconds
        )
    }

    /// Send privately to everyone in a circle. Thin wrapper over
    /// `sendDirect`; returns the single created share.
    @discardableResult
    func sendDirectToCircle(
        imageData: Data?,
        type: MediaType,
        caption: String?,
        circleId: UUID,
        durationSeconds: Double? = nil
    ) -> DirectShare? {
        sendDirect(
            imageData: imageData,
            type: type,
            caption: caption,
            friendIds: [],
            circleIds: [circleId],
            durationSeconds: durationSeconds
        ).first
    }

    /// Every direct share involving the current user — outgoing (sent
    /// by me) and incoming (sent to me) — newest first. Drives the
    /// Direct surface.
    var myDirectShares: [DirectShare] {
        directShares
            .filter { $0.authorId == currentUserId || $0.recipientFriendId == currentUserId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Count of incoming shares the user hasn't opened yet. Drives the
    /// "new" dot on the Direct entry.
    var unreadDirectCount: Int {
        directShares.filter {
            $0.authorId != currentUserId
                && $0.recipientFriendId == currentUserId
                && $0.readAt == nil
        }.count
    }

    /// Stamp an incoming share as opened. Idempotent; outgoing shares
    /// are ignored.
    func markDirectShareRead(_ id: UUID) {
        guard let idx = directShares.firstIndex(where: { $0.id == id }),
              directShares[idx].authorId != currentUserId,
              directShares[idx].readAt == nil else { return }
        directShares[idx].readAt = Date()
        persistAll()
    }

    /// The media asset backing a direct share, if any.
    func mediaAsset(forDirectShare share: DirectShare) -> MediaAsset? {
        guard let id = share.mediaId else { return nil }
        return mediaAssets.first { $0.id == id }
    }

    /// Lookup a media asset by id.
    func media(by id: UUID) -> MediaAsset? {
        mediaAssets.first { $0.id == id }
    }

    /// The media behind a friend's most recent active story — fills the
    /// story-row ring with a real preview. Prefers the newest unwatched
    /// post so the thumbnail matches what tapping will play first.
    func storyThumbMedia(forFriendId friendId: UUID) -> MediaAsset? {
        let posts = activeFriendStories.filter { $0.authorId == friendId }
        let pick = posts.first { !viewedStoryPostIds.contains($0.id) } ?? posts.first
        guard let mediaId = pick?.mediaId else { return nil }
        return media(by: mediaId)
    }

    /// The media behind the user's own newest active story — fills the
    /// "Your story" bubble once something is posted. Skips caption-only
    /// posts so the bubble always previews the latest visual addition.
    var myStoryThumbMedia: MediaAsset? {
        guard let mediaId = activeMyStories.last(where: { $0.mediaId != nil })?.mediaId else { return nil }
        return media(by: mediaId)
    }

    // MARK: - Exact-points permission

    /// Ask a friend to share their exact point values. Point values are
    /// private calibration — they only ever surface behind this explicit
    /// ask. Full-tier friends (who already share their whole day) say
    /// yes shortly after; everyone else leaves the ask pending.
    func requestExactPoints(friendId: UUID) {
        guard let idx = friends.firstIndex(where: { $0.id == friendId }),
              friends[idx].pointsAccess == nil else { return }
        friends[idx].pointsAccess = .requested
        persistAll()

        if friends[idx].sharesWithMe.tier == .full {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                self?.grantExactPoints(friendId: friendId)
            }
        }
    }

    /// The friend said yes — their exact points are now visible to me.
    func grantExactPoints(friendId: UUID) {
        guard let idx = friends.firstIndex(where: { $0.id == friendId }),
              friends[idx].pointsAccess == .requested else { return }
        friends[idx].pointsAccess = .granted
        persistAll()
    }

    /// "To Maya" / "To Morning Run" / "From Aaron" — the counterpart
    /// label for a direct share, from the current user's point of view.
    func directShareCounterpartLabel(_ share: DirectShare) -> String {
        if share.authorId == currentUserId {
            if let circleId = share.circleId {
                return "To \(circle(by: circleId)?.name ?? "circle")"
            }
            if let rid = share.recipientFriendId {
                return "To \(friend(by: rid)?.displayName ?? "friend")"
            }
            return "Sent"
        }
        return "From \(friend(by: share.authorId)?.displayName ?? "friend")"
    }

    /// The Proofs inbox, regrouped by person: one entry per friend the
    /// user has traded 1:1 proofs/notes with, newest conversation
    /// first. Circle sends are intentionally excluded — this surface is
    /// person-to-person only; circle proofs live in the circle.
    var directConversations: [DirectConversation] {
        var latestByFriend: [UUID: DirectShare] = [:]
        for share in directShares where share.circleId == nil {
            let counterpartId: UUID?
            if share.authorId == currentUserId {
                counterpartId = share.recipientFriendId
            } else if share.recipientFriendId == currentUserId {
                counterpartId = share.authorId
            } else {
                counterpartId = nil
            }
            guard let fid = counterpartId else { continue }
            if let existing = latestByFriend[fid], existing.createdAt >= share.createdAt {
                continue
            }
            latestByFriend[fid] = share
        }
        return latestByFriend.compactMap { fid, latest -> DirectConversation? in
            guard let friend = friend(by: fid) else { return nil }
            return DirectConversation(
                friend: friend,
                latest: latest,
                unreadCount: unreadCount(fromFriendId: fid)
            )
        }
        .sorted { $0.latest.createdAt > $1.latest.createdAt }
    }

    /// Mark a received cheer as read. Cheers stay visible for the
    /// rest of the local day either way; the read stamp just lets
    /// future surfaces tell new from acknowledged.
    func markCheerRead(_ cheerId: UUID) {
        guard let idx = cheers.firstIndex(where: { $0.id == cheerId }),
              cheers[idx].readAt == nil else { return }
        cheers[idx].readAt = Date()
        persistAll()
    }

    /// Mark a story post as watched by the current user. Idempotent —
    /// re-watching the same post doesn't churn persistence. Drives
    /// the watched-vs-new state of the friends story avatars.
    func markStoryViewed(_ postId: UUID) {
        guard !viewedStoryPostIds.contains(postId) else { return }
        viewedStoryPostIds.insert(postId)
        persistAll()
    }

    /// True when the friend has at least one unexpired general story
    /// post that the current user has NOT yet viewed.
    func hasUnviewedStories(forFriendId friendId: UUID) -> Bool {
        activeFriendStories.contains { post in
            post.authorId == friendId && !viewedStoryPostIds.contains(post.id)
        }
    }

    /// True when the friend has at least one unexpired general story
    /// post (viewed or not).
    func hasAnyActiveStories(forFriendId friendId: UUID) -> Bool {
        activeFriendStories.contains { $0.authorId == friendId }
    }

    /// General (non-circle) story posts that haven't expired yet,
    /// newest first. Drives the friends stories row.
    var activeFriendStories: [StoryPost] {
        storyPosts
            .filter { $0.circleId == nil && !$0.isExpired() }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The current user's own unexpired general story posts, oldest
    /// first so they replay in the same chronological order as a
    /// friend's tape. Drives the "view your own stories" tap on the
    /// You avatar.
    var activeMyStories: [StoryPost] {
        storyPosts
            .filter { $0.authorId == currentUserId && $0.circleId == nil && !$0.isExpired() }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Convenience flag — true when the user has at least one
    /// unexpired general post to play back.
    var hasActiveMyStories: Bool {
        !activeMyStories.isEmpty
    }

    /// Permanently remove one of the user's own story posts. Strips
    /// associated likes, comments, and the backing media asset (file
    /// + ledger row) so deleting a post doesn't leave dangling state.
    func deleteMyStoryPost(_ postId: UUID) {
        guard let idx = storyPosts.firstIndex(where: { $0.id == postId }) else { return }
        let post = storyPosts[idx]
        guard post.authorId == currentUserId else { return }

        if let mediaId = post.mediaId,
           let mediaIdx = mediaAssets.firstIndex(where: { $0.id == mediaId }) {
            if let url = mediaAssets[mediaIdx].localURL {
                try? FileManager.default.removeItem(at: url)
            }
            mediaAssets.remove(at: mediaIdx)
        }

        likes.removeAll { $0.postId == postId }
        comments.removeAll { $0.postId == postId }
        storyPosts.remove(at: idx)
        persistAll()
    }

    // MARK: - Pacts

    /// Pacts the current user is part of, newest-active first. Active
    /// before pending; declined / completed sink to the bottom.
    var myPacts: [Pact] {
        pacts
            .filter { $0.proposerId == currentUserId || $0.partnerId == currentUserId }
            .sorted { lhs, rhs in
                func rank(_ s: PactStatus) -> Int {
                    switch s {
                    case .active: return 0
                    case .pending: return 1
                    case .completed: return 2
                    case .declined: return 3
                    }
                }
                if rank(lhs.status) != rank(rhs.status) {
                    return rank(lhs.status) < rank(rhs.status)
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// The other side of a pact for the current user. Returns nil when
    /// the partner friend record has since been removed.
    func partnerFriend(forPact pact: Pact) -> Friend? {
        let otherId = (pact.proposerId == currentUserId) ? pact.partnerId : pact.proposerId
        return friends.first { $0.id == otherId }
    }

    /// Lookup a pact by id.
    func pact(by id: UUID) -> Pact? { pacts.first { $0.id == id } }

    /// Distinct local days within the pact's window on which the user
    /// completed at least one pact task. "Days kept" reads symmetric
    /// for both people — no winner numbers.
    func pactDaysKept(pact: Pact, userId: UUID) -> Int {
        let cal = Calendar.current
        let days = pactCompletions
            .filter { $0.pactId == pact.id && $0.userId == userId }
            .map { cal.startOfDay(for: $0.date) }
        return Set(days).count
    }

    /// Days remaining in the pact's window, clamped at zero. Returns
    /// the full `durationDays` for a pending pact (no start yet).
    func pactDaysLeft(pact: Pact, from now: Date = Date()) -> Int {
        guard let end = pact.endDate else { return pact.durationDays }
        let cal = Calendar.current
        let comps = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: now),
            to: cal.startOfDay(for: end)
        )
        return max(0, comps.day ?? 0)
    }

    /// True when the current user already logged a completion for
    /// this pact task on today's local day.
    func hasUserCompletedPactTaskToday(pactId: UUID, taskId: UUID) -> Bool {
        let cal = Calendar.current
        let today = Date()
        return pactCompletions.contains { c in
            c.pactId == pactId
                && c.taskId == taskId
                && c.userId == currentUserId
                && cal.isDate(c.date, inSameDayAs: today)
        }
    }

    /// Toggle the current user's completion of a pact task for today.
    /// Mirrors the circle bridge: if the task is linked to a personal
    /// `FFTask`, the personal side also toggles — each ledger awards
    /// its own points independently.
    func togglePactTaskCompletion(pactId: UUID, task: PactTask) {
        let cal = Calendar.current
        let today = Date()
        guard let pact = pacts.first(where: { $0.id == pactId }),
              pact.status == .active else { return }

        let existing = pactCompletions.first { c in
            c.pactId == pactId
                && c.taskId == task.id
                && c.userId == currentUserId
                && cal.isDate(c.date, inSameDayAs: today)
        }

        let nowCompleted: Bool
        if let existing {
            pactCompletions.removeAll { $0.id == existing.id }
            nowCompleted = false
        } else {
            pactCompletions.append(
                PactCompletion(
                    pactId: pactId,
                    taskId: task.id,
                    userId: currentUserId,
                    date: today
                )
            )
            nowCompleted = true
        }

        if let linkedId = task.linkedPersonalTaskId {
            setPersonalTaskCompleted(linkedId, completed: nowCompleted, mirror: false)
        }

        persistAll()
    }

    /// Create a new pact, addressed to a partner, status `.pending`.
    /// `startDate` / `endDate` are stamped on acceptance, not here.
    @discardableResult
    func proposePact(
        title: String,
        partner: Friend,
        tasks: [PactTask],
        durationDays: Int
    ) -> Pact {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pact = Pact(
            title: trimmed.isEmpty ? "Untitled pact" : trimmed,
            proposerId: currentUserId,
            partnerId: partner.id,
            tasks: tasks,
            durationDays: max(1, durationDays)
        )
        pacts.append(pact)
        persistAll()
        return pact
    }

    /// Accept a pending pact. Stamps both window dates and flips to
    /// `.active`. No-op if the pact isn't pending.
    func acceptPact(_ pactId: UUID, at now: Date = Date()) {
        guard let idx = pacts.firstIndex(where: { $0.id == pactId }),
              pacts[idx].status == .pending else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: pacts[idx].durationDays, to: start) ?? start
        pacts[idx].startDate = start
        pacts[idx].endDate = end
        pacts[idx].status = .active
        persistAll()
    }

    /// Decline a pending pact. Terminal — the row stays so the user can
    /// see the history but it won't surface as active.
    func declinePact(_ pactId: UUID) {
        guard let idx = pacts.firstIndex(where: { $0.id == pactId }),
              pacts[idx].status == .pending else { return }
        pacts[idx].status = .declined
        persistAll()
    }

    /// End a pact early or after the window closes. Strips no
    /// completion history — ending is a state change, not a wipe.
    func endPact(_ pactId: UUID) {
        guard let idx = pacts.firstIndex(where: { $0.id == pactId }) else { return }
        pacts[idx].status = .completed
        persistAll()
    }

    /// Walk away from a pact entirely. Removes the row and any
    /// recorded completions so a left-behind pact doesn't keep
    /// counting from the list.
    func leavePact(_ pactId: UUID) {
        pacts.removeAll { $0.id == pactId }
        pactCompletions.removeAll { $0.pactId == pactId }
        persistAll()
    }

    /// Lookup helpers. Return nil when the id is unknown — callers
    /// should treat that as "deleted or never existed" rather than a
    /// crash, because seed and persisted data can drift across
    /// model-version bumps.
    func friend(by id: UUID) -> Friend? { friends.first { $0.id == id } }

    /// Replace what this friend is cleared to see about the current
    /// user. Persists immediately so toggle changes in the sharing
    /// settings panel survive the next launch without a save button.
    func updateFriendClearance(friendId: UUID, clearance: SharingSettings) {
        guard let idx = friends.firstIndex(where: { $0.id == friendId }) else { return }
        guard friends[idx].theirClearanceToMyData != clearance else { return }
        friends[idx].theirClearanceToMyData = clearance
        persistAll()
    }
    func circle(by id: UUID) -> FFCircle? { circles.first { $0.id == id } }

    /// Create a brand-new circle owned by the current user. The roster
    /// is the picked friends plus the user; parallel circles carry a
    /// shared task list, collective circles a target + unit (progress
    /// starts at zero). Persists immediately and returns the circle so
    /// the caller can route straight into its detail.
    @discardableResult
    func createCircle(
        name: String,
        type: CircleType,
        memberFriendIds: [UUID],
        timeframe: CircleTimeframe,
        taskTitles: [String] = [],
        collectiveUnit: String? = nil,
        collectiveTarget: Double? = nil
    ) -> FFCircle {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let memberIds = [currentUserId] + memberFriendIds.filter { $0 != currentUserId }
        let tasks: [CircleTask] = type == .parallel
            ? taskTitles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { CircleTask(title: $0, pointValue: nil, linkedPersonalTaskId: nil) }
            : []
        let unit = collectiveUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = Date()
        let resolvedUnit = type == .collective ? (unit?.isEmpty == false ? unit : nil) : nil
        let resolvedTarget = type == .collective ? collectiveTarget : nil
        // Open the founding chapter so the circle's story starts the day
        // it's born — every later mode switch adds to this timeline.
        let snap = Self.chapterSnapshot(
            objectives: type.objectives,
            tasks: tasks,
            unit: resolvedUnit,
            target: resolvedTarget
        )
        let opening = CircleChapter(
            objectives: type.objectives,
            title: snap.title,
            detail: snap.detail,
            startedAt: createdAt,
            endedAt: nil,
            outcome: .ongoing,
            actorName: nil
        )
        let circle = FFCircle(
            name: trimmedName.isEmpty ? "New circle" : trimmedName,
            type: type,
            timeframe: timeframe,
            memberIds: memberIds,
            tasks: tasks,
            collectiveUnit: resolvedUnit,
            collectiveTarget: resolvedTarget,
            collectiveProgress: type == .collective ? 0 : nil,
            createdAt: createdAt,
            ownerId: currentUserId,
            adminIds: [],
            membersCanProposeTasks: false,
            chapters: [opening]
        )
        circles.append(circle)
        persistAll()
        return circle
    }

    // MARK: - Relationship hub (C-Restructure)

    /// The witnessing texture of a friend's day. Deterministic — no
    /// backend — so it never reshuffles between renders.
    func friendDay(for friend: Friend) -> FriendDay { FriendDay.make(for: friend) }

    /// A calm 0...1 ring fraction for a friend's day, respecting their
    /// pairwise visibility tier. Full → today's task completion; Open →
    /// recent momentum (never task-specific); Quiet → 0, so the ring
    /// reads as a faint track only and reveals nothing they didn't share.
    func dayRingFraction(for friend: Friend) -> Double {
        let day = friendDay(for: friend)
        switch friend.sharesWithMe.tier {
        case .full: return day.completionFraction
        case .open: return day.momentum
        case .quiet: return 0
        }
    }

    /// My own today completion as a 0...1 fraction — today's score against
    /// the season's daily goal. Drives my presence ring in shared rooms.
    var myTodayFraction: Double {
        max(0, min(1, Double(todayScore) / Double(max(1, currentSeason.dailyGoal))))
    }

    /// Whole months since the connection began. Zero when unknown.
    func connectedMonths(_ friend: Friend) -> Int {
        guard let start = friend.connectedAt else { return 0 }
        let comps = Calendar.current.dateComponents([.month], from: start, to: Date())
        return max(0, comps.month ?? 0)
    }

    /// "connected 4 months" / "connected 1 year" — the warm tenure line
    /// under a friend's name on the hub.
    func connectedDescription(_ friend: Friend) -> String {
        let m = connectedMonths(friend)
        if m <= 0 { return "connected recently" }
        if m == 1 { return "connected 1 month" }
        if m < 12 { return "connected \(m) months" }
        let years = m / 12
        return years == 1 ? "connected 1 year" : "connected \(years) years"
    }

    /// Circles both the current user and this friend belong to.
    func sharedCircles(withFriendId friendId: UUID) -> [FFCircle] {
        circles.filter {
            $0.memberIds.contains(currentUserId) && $0.memberIds.contains(friendId)
        }
    }

    /// Pacts between the current user and this friend (any non-declined
    /// state). A pact is a circle of two — surfaced alongside circles.
    func sharedPacts(withFriendId friendId: UUID) -> [Pact] {
        pacts.filter { p in
            p.status != .declined &&
            ((p.proposerId == currentUserId && p.partnerId == friendId) ||
             (p.partnerId == currentUserId && p.proposerId == friendId))
        }
    }

    // MARK: - 1:1 proof / message thread

    /// Every proof + message exchanged 1:1 with this friend (both
    /// directions), oldest → newest so a thread reads top to bottom.
    /// Circle sends are excluded — this is the private thread.
    func thread(withFriendId friendId: UUID) -> [DirectShare] {
        directShares
            .filter { share in
                share.circleId == nil && (
                    (share.authorId == currentUserId && share.recipientFriendId == friendId) ||
                    (share.authorId == friendId && share.recipientFriendId == currentUserId)
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Count of unopened incoming shares from this friend.
    func unreadCount(fromFriendId friendId: UUID) -> Int {
        directShares.filter {
            $0.authorId == friendId
                && $0.recipientFriendId == currentUserId
                && $0.readAt == nil
        }.count
    }

    /// Most recent unopened incoming share from this friend, if any.
    /// Drives the activity-row "lit" affordance + preview line.
    func latestUnread(fromFriendId friendId: UUID) -> DirectShare? {
        directShares
            .filter { $0.authorId == friendId && $0.recipientFriendId == currentUserId && $0.readAt == nil }
            .max { $0.createdAt < $1.createdAt }
    }

    /// The newest share in the 1:1 thread, either direction.
    func latestShare(withFriendId friendId: UUID) -> DirectShare? {
        thread(withFriendId: friendId).last
    }

    /// Mark every incoming share from this friend as read. Idempotent.
    func markThreadRead(withFriendId friendId: UUID) {
        var changed = false
        for idx in directShares.indices
        where directShares[idx].authorId == friendId
            && directShares[idx].recipientFriendId == currentUserId
            && directShares[idx].readAt == nil {
            directShares[idx].readAt = Date()
            changed = true
        }
        if changed { persistAll() }
    }

    /// Send a text-only note (a calm "message") to a friend in their
    /// 1:1 thread. Empty strings drop silently.
    func sendNote(toFriendId friendId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, friend(by: friendId) != nil else { return }
        directShares.insert(
            DirectShare(
                authorId: currentUserId,
                recipientFriendId: friendId,
                circleId: nil,
                caption: trimmed,
                mediaId: nil,
                createdAt: Date()
            ),
            at: 0
        )
        persistAll()
    }

    // MARK: - Proof watching

    /// Incoming proofs from this friend the user hasn't watched yet,
    /// oldest → newest. Drives the chat pill's "tap to view" state and
    /// the play queue (watch several in a row).
    func unwatchedProofs(fromFriendId friendId: UUID) -> [DirectShare] {
        directShares
            .filter {
                $0.circleId == nil
                    && $0.isProof
                    && $0.authorId == friendId
                    && $0.recipientFriendId == currentUserId
                    && $0.viewedAt == nil
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The ordered run of proofs to play when the user taps `share` in
    /// the thread. Tapping an unwatched incoming proof rolls the whole
    /// run of that friend's unwatched proofs from the tapped one onward
    /// (watch several in a row); tapping your own or an already-watched
    /// proof just replays that single one.
    func proofPlayQueue(startingAt share: DirectShare) -> [DirectShare] {
        guard share.isProof else { return [] }
        let isIncomingUnwatched = share.authorId != currentUserId
            && share.recipientFriendId == currentUserId
            && share.viewedAt == nil
        guard isIncomingUnwatched else { return [share] }
        let queue = unwatchedProofs(fromFriendId: share.authorId)
        guard let idx = queue.firstIndex(where: { $0.id == share.id }) else { return [share] }
        return Array(queue[idx...])
    }

    /// Stamp a proof as watched. Also clears its incoming `readAt` so
    /// the conversation badge can never disagree with the watched
    /// state. Idempotent; safe to call on any share.
    func markProofViewed(_ id: UUID) {
        guard let idx = directShares.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        if directShares[idx].viewedAt == nil {
            directShares[idx].viewedAt = Date()
            changed = true
        }
        if directShares[idx].authorId != currentUserId && directShares[idx].readAt == nil {
            directShares[idx].readAt = Date()
            changed = true
        }
        if changed { persistAll() }
    }

    // MARK: - Own-story seen count

    /// A calm "seen by" count for one of the user's own posts — the
    /// length of the derived viewer list, so the number and the list
    /// of names can never disagree.
    func seenCount(forPost postId: UUID) -> Int {
        storyViewers(forPost: postId).count
    }

    /// The calm, read-only list of who's seen one of the user's own
    /// posts. No backend, so it's derived deterministically: everyone
    /// who reacted (liked or commented) is a viewer, then the list is
    /// floored to a gentle base so a fresh post still reads witnessed,
    /// filling with additional friends in a post-seeded order that
    /// never reshuffles between renders. `didReact` marks a soft heart
    /// beside anyone who liked the post.
    func storyViewers(forPost postId: UUID) -> [StoryViewer] {
        let likedIds = Set(likes.filter { $0.postId == postId }.map { $0.fromFriendId })
        let commentedIds = Set(comments.filter { $0.postId == postId }.map { $0.fromFriendId })
        let reactorIds = likedIds.union(commentedIds)

        // Reactors first, in stable `friends`-array order.
        var viewers: [StoryViewer] = friends
            .filter { reactorIds.contains($0.id) }
            .map { StoryViewer(friend: $0, didReact: likedIds.contains($0.id)) }

        // Floor so a fresh post still reads witnessed; matches the
        // previous seen-count base so the number never shrinks.
        let target = max(viewers.count, min(friends.count, 4))
        if viewers.count < target {
            let remaining = friends
                .filter { !reactorIds.contains($0.id) }
                .sorted { stableViewerKey($0.id, postId) < stableViewerKey($1.id, postId) }
            for friend in remaining {
                if viewers.count >= target { break }
                viewers.append(StoryViewer(friend: friend, didReact: false))
            }
        }
        return viewers
    }

    /// Stable per-(friend, post) ordering key — an FNV-1a hash over both
    /// UUIDs' bytes so the "seen by" fill is deterministic across
    /// launches (unlike `hashValue`, which is per-process randomized).
    private func stableViewerKey(_ friendId: UUID, _ postId: UUID) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ id: UUID) {
            let u = id.uuid
            let bytes = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                         u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
            for b in bytes {
                hash ^= UInt64(b)
                hash = hash &* 1_099_511_628_211
            }
        }
        mix(friendId)
        mix(postId)
        return hash
    }

    // MARK: - Connection texture

    /// Relationship texture for the "Since you connected" block. Real
    /// signal (proofs + cheers exchanged) floored by tenure so the
    /// block stays full even on a quiet day — calm, never a streak.
    func connectionTexture(for friend: Friend) -> ConnectionTexture {
        let realProofs = directShares.filter { s in
            s.circleId == nil && (
                (s.authorId == currentUserId && s.recipientFriendId == friend.id) ||
                (s.authorId == friend.id && s.recipientFriendId == currentUserId)
            )
        }.count
        let realCheers = cheers.filter { c in
            (c.fromFriendId == friend.id && c.toUserId == currentUserId) ||
            (c.fromFriendId == currentUserId && c.toUserId == friend.id)
        }.count

        let months = connectedMonths(friend)
        var seed = UInt64(abs(friend.id.uuidString.hashValue) % 9_999 + 1)
        func bump(_ u: Int) -> Int {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Int(seed % UInt64(max(1, u)))
        }
        let proofFloor = max(2, months * 2 + bump(5))
        let cheerFloor = max(3, months * 8 + bump(6))
        let milestones = 1 + bump(3)

        return ConnectionTexture(
            proofsTraded: max(realProofs, proofFloor),
            cheersExchanged: max(realCheers, cheerFloor),
            milestonesWitnessed: milestones,
            line: connectionLine(for: friend, milestones: milestones)
        )
    }

    /// Warm, honest one-liner for the connection block. Aaron is pinned
    /// to the reference; everyone else gets a calm generated line.
    private func connectionLine(for friend: Friend, milestones: Int) -> String {
        if friend.displayName == "Aaron" {
            return "You were there for his \u{201C}day 1 of Heal.\u{201D} He\u{2019}s cheered every milestone you\u{2019}ve hit."
        }
        let season = friend.currentSeasonName?.replacingOccurrences(of: " Season", with: "") ?? "this season"
        return "You\u{2019}ve witnessed \(milestones) of \(friend.displayName)\u{2019}s milestones, and shown up through \(season)."
    }

    func likes(for postId: UUID) -> [Like] { likes.filter { $0.postId == postId } }
    func comments(for postId: UUID) -> [Comment] {
        comments.filter { $0.postId == postId }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - C7a: likes & comments

    /// The friend's most recent unexpired general story post, if one
    /// exists. Used as the implicit target for the friend-detail
    /// gesture bar's Like + Comment buttons — there's no per-friend
    /// "current" surface elsewhere, so we lean on the freshest active
    /// post the friend has shared.
    func currentStoryPost(forFriendId friendId: UUID) -> StoryPost? {
        activeFriendStories.first { $0.authorId == friendId }
    }

    /// Whether the current user has already liked this post. Drives
    /// the heart fill state on every surface that renders a like
    /// affordance.
    func isPostLikedByMe(_ postId: UUID) -> Bool {
        likes.contains { $0.postId == postId && $0.fromFriendId == currentUserId }
    }

    /// Toggle the current user's like on a story post. Appends a
    /// `Like` if none exists, removes it if one does. Persists
    /// immediately so the heart state survives a relaunch.
    func toggleLike(postId: UUID) {
        if let idx = likes.firstIndex(where: { $0.postId == postId && $0.fromFriendId == currentUserId }) {
            likes.remove(at: idx)
        } else {
            likes.append(Like(
                postId: postId,
                fromFriendId: currentUserId,
                fromName: "You"
            ))
        }
        persistAll()
    }

    /// Append a comment on a story post from the current user. Empty
    /// strings are dropped silently so a stray Return key never
    /// writes a ghost row.
    func addComment(postId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        comments.append(Comment(
            postId: postId,
            fromFriendId: currentUserId,
            fromName: "You",
            fromInitials: "Y",
            text: trimmed
        ))
        persistAll()
    }

    /// Names-forward summary of who liked a post. Returns nil when
    /// the post has no likes so the caller can omit the row entirely
    /// rather than rendering empty chrome.
    ///
    /// The product rule is deliberate: no bare numeric counts
    /// anywhere. Many likers collapse to `… and N others` so the
    /// names lead and the number trails in lowercase.
    func likeSummary(postId: UUID) -> String? {
        let postLikes = likes.filter { $0.postId == postId }
        guard !postLikes.isEmpty else { return nil }

        let mine = postLikes.first { $0.fromFriendId == currentUserId }
        let others = postLikes.filter { $0.fromFriendId != currentUserId }
        let otherNames = others.map { $0.fromName }
        let youSuffix = mine != nil ? "you" : nil

        switch (otherNames.count, youSuffix) {
        case (0, .some):
            return "Liked by you"
        case (1, .some(let you)):
            return "Liked by \(otherNames[0]) and \(you)"
        case (1, .none):
            return "Liked by \(otherNames[0])"
        case (2, .none):
            return "Liked by \(otherNames[0]) and \(otherNames[1])"
        case (2, .some(let you)):
            return "Liked by \(otherNames[0]), \(otherNames[1]) and \(you)"
        default:
            // 3+ other names → lead with the first, collapse the rest.
            let leader = otherNames[0]
            let remaining = otherNames.count - 1 + (youSuffix != nil ? 1 : 0)
            let plural = remaining == 1 ? "other" : "others"
            return "Liked by \(leader) and \(remaining) \(plural)"
        }
    }
}

// MARK: - Social seeds
//
// Believable starting graph so the C2+ UI prompts have material to
// render the moment the app launches. Seeds run in dependency order
// from `init()` so circles can reference both friends and the user's
// stable id, and posts can reference their attached media.

extension Store {
    static func seedFriends() -> [Friend] {
        let cal = Calendar.current
        let now = Date()
        return [
            Friend(
                displayName: "Aaron",
                initials: "A",
                accentColorHex: "3B6D11",
                theirClearanceToMyData: .openByDefault,
                currentSeasonName: "Heal Season",
                currentSeasonDay: 12,
                todayScore: 38,
                hitGoalToday: false,
                lastSignalAt: cal.date(byAdding: .minute, value: -14, to: now),
                sharesWithMe: .full,
                connectedAt: cal.date(byAdding: .month, value: -4, to: now)
            ),
            Friend(
                displayName: "Madison",
                initials: "M",
                accentColorHex: "993556",
                theirClearanceToMyData: .goalOnly,
                currentSeasonName: "Reset Season",
                currentSeasonDay: 5,
                todayScore: nil,
                hitGoalToday: false,
                lastSignalAt: cal.date(byAdding: .hour, value: -2, to: now),
                sharesWithMe: .open,
                connectedAt: cal.date(byAdding: .month, value: -2, to: now)
            ),
            Friend(
                displayName: "Devin",
                initials: "D",
                accentColorHex: "185FA5",
                theirClearanceToMyData: .goalOnly,
                currentSeasonName: "Build Season",
                currentSeasonDay: 30,
                todayScore: nil,
                hitGoalToday: true,
                lastSignalAt: cal.date(byAdding: .hour, value: -5, to: now),
                sharesWithMe: .open,
                connectedAt: cal.date(byAdding: .month, value: -6, to: now)
            ),
            Friend(
                displayName: "Kennedy",
                initials: "K",
                accentColorHex: "7F77DD",
                theirClearanceToMyData: .openByDefault,
                currentSeasonName: "Quiet Season",
                currentSeasonDay: 8,
                todayScore: 8,
                hitGoalToday: false,
                lastSignalAt: cal.date(byAdding: .hour, value: -7, to: now),
                sharesWithMe: .full,
                connectedAt: cal.date(byAdding: .month, value: -3, to: now)
            ),
            Friend(
                displayName: "Naomi",
                initials: "N",
                accentColorHex: "888780",
                theirClearanceToMyData: .minimal,
                currentSeasonName: "Renewal Season",
                currentSeasonDay: 3,
                todayScore: nil,
                hitGoalToday: nil,
                lastSignalAt: cal.date(byAdding: .day, value: -4, to: now),
                sharesWithMe: .quiet,
                connectedAt: cal.date(byAdding: .month, value: -1, to: now)
            ),
            // --- Expanded roster (indices 5...9) so every social surface
            //     reads alive: more full-visibility days, more lit rows,
            //     more circles + pacts to be a member of. ---
            Friend(
                displayName: "Theo",
                initials: "T",
                accentColorHex: "1F7A6D",
                theirClearanceToMyData: .openByDefault,
                currentSeasonName: "Build Season",
                currentSeasonDay: 22,
                todayScore: 44,
                hitGoalToday: false,
                lastSignalAt: cal.date(byAdding: .minute, value: -20, to: now),
                sharesWithMe: .full,
                connectedAt: cal.date(byAdding: .month, value: -7, to: now)
            ),
            Friend(
                displayName: "Priya",
                initials: "P",
                accentColorHex: "C2641B",
                theirClearanceToMyData: .openByDefault,
                currentSeasonName: "Create Season",
                currentSeasonDay: 16,
                todayScore: 51,
                hitGoalToday: true,
                lastSignalAt: cal.date(byAdding: .minute, value: -35, to: now),
                sharesWithMe: .full,
                connectedAt: cal.date(byAdding: .month, value: -9, to: now)
            ),
            Friend(
                displayName: "Marcus",
                initials: "M",
                accentColorHex: "A23B2E",
                theirClearanceToMyData: .goalOnly,
                currentSeasonName: "Strength Season",
                currentSeasonDay: 47,
                todayScore: nil,
                hitGoalToday: true,
                lastSignalAt: cal.date(byAdding: .hour, value: -3, to: now),
                sharesWithMe: .open,
                connectedAt: cal.date(byAdding: .month, value: -14, to: now)
            ),
            Friend(
                displayName: "Sofia",
                initials: "S",
                accentColorHex: "8E6E83",
                theirClearanceToMyData: .minimal,
                currentSeasonName: "Reset Season",
                currentSeasonDay: 6,
                todayScore: nil,
                hitGoalToday: nil,
                lastSignalAt: cal.date(byAdding: .day, value: -2, to: now),
                sharesWithMe: .quiet,
                connectedAt: cal.date(byAdding: .month, value: -2, to: now)
            ),
            Friend(
                displayName: "Jonah",
                initials: "J",
                accentColorHex: "2E4A8C",
                theirClearanceToMyData: .openByDefault,
                currentSeasonName: "Focus Season",
                currentSeasonDay: 9,
                todayScore: 19,
                hitGoalToday: false,
                lastSignalAt: cal.date(byAdding: .minute, value: -50, to: now),
                sharesWithMe: .full,
                connectedAt: cal.date(byAdding: .month, value: -5, to: now)
            )
        ]
    }

    static func seedCircles(friends: [Friend], userId: UUID) -> [FFCircle] {
        guard friends.count >= 5 else { return [] }
        let cal = Calendar.current
        let now = Date()
        let aaron = friends[0].id
        let madison = friends[1].id
        let devin = friends[2].id
        let kennedy = friends[3].id
        let naomi = friends[4].id

        let run5kEnd = cal.date(byAdding: .day, value: 18, to: now) ?? now
        let run5kStart = cal.date(byAdding: .day, value: -12, to: now) ?? now
        let milesStart = cal.date(byAdding: .day, value: -45, to: now) ?? now
        let aaronName = friends[0].displayName

        let run5k = FFCircle(
            name: "Run a 5K",
            type: .parallel,
            timeframe: .timeBoxed(endDate: run5kEnd),
            memberIds: [userId, aaron, madison, devin],
            tasks: [
                CircleTask(title: "Run a mile", pointValue: nil, linkedPersonalTaskId: nil),
                CircleTask(title: "Sleep 6+ hours", pointValue: nil, linkedPersonalTaskId: nil),
                CircleTask(title: "Stretch 10 min", pointValue: nil, linkedPersonalTaskId: nil)
            ],
            collectiveUnit: nil,
            collectiveTarget: nil,
            collectiveProgress: nil,
            createdAt: run5kStart,
            ownerId: userId,
            adminIds: [],
            membersCanProposeTasks: false,
            // Story: two weeks just present together, then Aaron added the
            // shared list they're running now.
            chapters: [
                CircleChapter(
                    objectives: [],
                    title: "Just present",
                    detail: "Everyone kept their own goals",
                    startedAt: cal.date(byAdding: .day, value: -26, to: now) ?? now,
                    endedAt: run5kStart,
                    outcome: .returned,
                    actorName: nil
                ),
                CircleChapter(
                    objectives: [.sharedList],
                    title: "Shared list",
                    detail: "Run a mile · Sleep 6+ hours · Stretch 10 min",
                    startedAt: run5kStart,
                    endedAt: nil,
                    outcome: .ongoing,
                    actorName: aaronName
                )
            ]
        )

        let miles = FFCircle(
            name: "1000 Miles Together",
            type: .collective,
            timeframe: .ongoing,
            memberIds: [userId, aaron, madison, kennedy, naomi],
            tasks: [],
            collectiveUnit: "miles",
            collectiveTarget: 1000,
            collectiveProgress: 632,
            createdAt: milesStart,
            ownerId: userId,
            adminIds: [aaron],
            membersCanProposeTasks: false,
            chapters: [
                CircleChapter(
                    objectives: [],
                    title: "Just present",
                    detail: "Found our footing together",
                    startedAt: cal.date(byAdding: .day, value: -60, to: now) ?? now,
                    endedAt: milesStart,
                    outcome: .returned,
                    actorName: nil
                ),
                CircleChapter(
                    objectives: [.sharedNumber],
                    title: "Shared number",
                    detail: "1000 miles",
                    startedAt: milesStart,
                    endedAt: nil,
                    outcome: .ongoing,
                    actorName: nil
                )
            ]
        )

        // A presence-only Witness circle: no shared goal, just a calm room
        // these friends inhabit. Its story shows a finished shared list
        // they ran together before returning to simply being present.
        let eveningsStart = cal.date(byAdding: .day, value: -50, to: now) ?? now
        let eveningsSwitch = cal.date(byAdding: .day, value: -20, to: now) ?? now
        let evenings = FFCircle(
            name: "Evenings Together",
            type: .witness,
            timeframe: .ongoing,
            memberIds: [userId, aaron, naomi, kennedy],
            tasks: [],
            collectiveUnit: nil,
            collectiveTarget: nil,
            collectiveProgress: nil,
            createdAt: eveningsStart,
            ownerId: userId,
            adminIds: [],
            membersCanProposeTasks: false,
            chapters: [
                CircleChapter(
                    objectives: [.sharedList],
                    title: "Shared list",
                    detail: "A 30-day evening reset",
                    startedAt: eveningsStart,
                    endedAt: eveningsSwitch,
                    outcome: .completed,
                    actorName: nil
                ),
                CircleChapter(
                    objectives: [],
                    title: "Just present",
                    detail: "Everyone keeps their own goals now",
                    startedAt: eveningsSwitch,
                    endedAt: nil,
                    outcome: .ongoing,
                    actorName: aaronName
                )
            ]
        )

        var result = [run5k, miles, evenings]

        // Two more circles spanning the expanded roster so several
        // friend profiles surface a populated "Together" section.
        if friends.count >= 8 {
            let theo = friends[5].id
            let priya = friends[6].id
            let pagesStart = cal.date(byAdding: .day, value: -10, to: now) ?? now
            let pagesEnd = cal.date(byAdding: .day, value: 20, to: now) ?? now
            let morningPages = FFCircle(
                name: "Morning Pages",
                type: .parallel,
                timeframe: .timeBoxed(endDate: pagesEnd),
                memberIds: [userId, aaron, priya, theo],
                tasks: [
                    CircleTask(title: "Write 500 words", pointValue: nil, linkedPersonalTaskId: nil),
                    CircleTask(title: "No phone first hour", pointValue: nil, linkedPersonalTaskId: nil),
                    CircleTask(title: "Read 10 pages", pointValue: nil, linkedPersonalTaskId: nil)
                ],
                collectiveUnit: nil,
                collectiveTarget: nil,
                collectiveProgress: nil,
                createdAt: pagesStart,
                ownerId: userId,
                adminIds: [],
                membersCanProposeTasks: false
            )
            result.append(morningPages)
        }

        if friends.count >= 10 {
            let theo = friends[5].id
            let marcus = friends[7].id
            let jonah = friends[9].id
            let plungeStart = cal.date(byAdding: .day, value: -30, to: now) ?? now
            let coldPlunge = FFCircle(
                name: "Cold Plunge Club",
                type: .collective,
                timeframe: .ongoing,
                memberIds: [userId, marcus, jonah, theo, devin],
                tasks: [],
                collectiveUnit: "plunges",
                collectiveTarget: 100,
                collectiveProgress: 41,
                createdAt: plungeStart,
                ownerId: marcus,
                adminIds: [userId],
                membersCanProposeTasks: false
            )
            result.append(coldPlunge)
        }

        return result
    }

    /// Today's per-member completion for the parallel "Run a 5K"
    /// circle. Aaron 3/3, Madison 2/3, the user 1/3, Devin 0/3.
    static func seedCircleTaskCompletions(
        circles: [FFCircle],
        friends: [Friend],
        userId: UUID
    ) -> [CircleTaskCompletion] {
        guard let run5k = circles.first(where: { $0.name == "Run a 5K" }),
              run5k.tasks.count >= 3,
              friends.count >= 3
        else { return [] }

        let now = Date()
        let aaron = friends[0].id
        let madison = friends[1].id
        let runTask = run5k.tasks[0].id
        let sleepTask = run5k.tasks[1].id
        let stretchTask = run5k.tasks[2].id

        var rows: [CircleTaskCompletion] = [
            // Aaron — full sweep.
            CircleTaskCompletion(circleId: run5k.id, circleTaskId: runTask, memberId: aaron, date: now),
            CircleTaskCompletion(circleId: run5k.id, circleTaskId: sleepTask, memberId: aaron, date: now),
            CircleTaskCompletion(circleId: run5k.id, circleTaskId: stretchTask, memberId: aaron, date: now),
            // Madison — run + sleep.
            CircleTaskCompletion(circleId: run5k.id, circleTaskId: runTask, memberId: madison, date: now),
            CircleTaskCompletion(circleId: run5k.id, circleTaskId: sleepTask, memberId: madison, date: now),
            // User — just the mile so far.
            CircleTaskCompletion(circleId: run5k.id, circleTaskId: runTask, memberId: userId, date: now)
            // Devin — nothing today; surfaces as 0/3 in the UI.
        ]

        // Morning Pages (parallel) — give it today's texture too so the
        // second parallel card and its member-progress read alive.
        if let pages = circles.first(where: { $0.name == "Morning Pages" }),
           pages.tasks.count >= 3, friends.count >= 7 {
            let priya = friends[6].id
            let theo = friends[5].id
            let write = pages.tasks[0].id
            let phone = pages.tasks[1].id
            let read = pages.tasks[2].id
            rows += [
                // You — write + read.
                CircleTaskCompletion(circleId: pages.id, circleTaskId: write, memberId: userId, date: now),
                CircleTaskCompletion(circleId: pages.id, circleTaskId: read, memberId: userId, date: now),
                // Aaron — full sweep again.
                CircleTaskCompletion(circleId: pages.id, circleTaskId: write, memberId: aaron, date: now),
                CircleTaskCompletion(circleId: pages.id, circleTaskId: phone, memberId: aaron, date: now),
                CircleTaskCompletion(circleId: pages.id, circleTaskId: read, memberId: aaron, date: now),
                // Theo — write + phone.
                CircleTaskCompletion(circleId: pages.id, circleTaskId: write, memberId: theo, date: now),
                CircleTaskCompletion(circleId: pages.id, circleTaskId: phone, memberId: theo, date: now),
                // Priya — just the writing so far.
                CircleTaskCompletion(circleId: pages.id, circleTaskId: write, memberId: priya, date: now)
            ]
        }

        return rows
    }

    /// Per-member contributions toward the "1000 Miles Together"
    /// collective target. Sums to 632, matching the circle's seeded
    /// `collectiveProgress`.
    static func seedCircleContributions(
        circles: [FFCircle],
        friends: [Friend],
        userId: UUID
    ) -> [CircleContribution] {
        guard let miles = circles.first(where: { $0.name == "1000 Miles Together" }),
              friends.count >= 5
        else { return [] }

        let now = Date()
        let aaron = friends[0].id
        let madison = friends[1].id
        let kennedy = friends[3].id
        let naomi = friends[4].id

        var rows: [CircleContribution] = [
            CircleContribution(circleId: miles.id, memberId: aaron, amount: 198, date: now),
            CircleContribution(circleId: miles.id, memberId: userId, amount: 158, date: now),
            CircleContribution(circleId: miles.id, memberId: madison, amount: 124, date: now),
            CircleContribution(circleId: miles.id, memberId: kennedy, amount: 92, date: now),
            CircleContribution(circleId: miles.id, memberId: naomi, amount: 60, date: now)
            // Sum: 198 + 158 + 124 + 92 + 60 = 632.
        ]

        // Cold Plunge Club (collective) — contributions sum to the
        // circle's seeded progress (41) so the bar reads honestly.
        if let plunge = circles.first(where: { $0.name == "Cold Plunge Club" }),
           friends.count >= 10 {
            let devin = friends[2].id
            let theo = friends[5].id
            let marcus = friends[7].id
            let jonah = friends[9].id
            rows += [
                CircleContribution(circleId: plunge.id, memberId: marcus, amount: 15, date: now),
                CircleContribution(circleId: plunge.id, memberId: userId, amount: 9, date: now),
                CircleContribution(circleId: plunge.id, memberId: jonah, amount: 8, date: now),
                CircleContribution(circleId: plunge.id, memberId: theo, amount: 6, date: now),
                CircleContribution(circleId: plunge.id, memberId: devin, amount: 3, date: now)
                // Sum: 15 + 9 + 8 + 6 + 3 = 41.
            ]
        }

        return rows
    }

    /// Four facts spread across the social graph so the signal
    /// generator (C2) has variety to render — a threshold hit, a
    /// completed Must-Do, a returning category, and a volume high.
    static func seedSignalFacts(friends: [Friend]) -> [SignalFact] {
        guard friends.count >= 4 else { return [] }
        let cal = Calendar.current
        let now = Date()
        let aaron = friends[0]
        let madison = friends[1]
        let devin = friends[2]
        let kennedy = friends[3]

        var facts: [SignalFact] = [
            SignalFact(
                ownerId: aaron.id,
                kind: .threshold,
                date: now,
                createdAt: cal.date(byAdding: .minute, value: -14, to: now) ?? now,
                score: aaron.todayScore,
                goal: 50
            ),
            SignalFact(
                ownerId: madison.id,
                kind: .mustDo,
                date: now,
                createdAt: cal.date(byAdding: .hour, value: -2, to: now) ?? now,
                taskName: "Morning pages",
                category: "Spiritual"
            ),
            SignalFact(
                ownerId: devin.id,
                kind: .returning,
                date: now,
                createdAt: cal.date(byAdding: .hour, value: -5, to: now) ?? now,
                taskName: "Lift",
                category: "Fitness",
                daysSince: 8
            ),
            SignalFact(
                ownerId: kennedy.id,
                kind: .volumeHigh,
                date: now,
                createdAt: cal.date(byAdding: .hour, value: -7, to: now) ?? now,
                score: 47,
                goal: 35
            )
        ]

        // Expanded roster signals so the feed reads with more variety.
        if friends.count >= 10 {
            let theo = friends[5]
            let priya = friends[6]
            let jonah = friends[9]
            facts += [
                SignalFact(
                    ownerId: theo.id,
                    kind: .threshold,
                    date: now,
                    createdAt: cal.date(byAdding: .minute, value: -20, to: now) ?? now,
                    score: theo.todayScore,
                    goal: 40
                ),
                SignalFact(
                    ownerId: priya.id,
                    kind: .milestone,
                    date: now,
                    createdAt: cal.date(byAdding: .minute, value: -35, to: now) ?? now,
                    milestoneTitle: "Finish the zine",
                    milestoneDone: 7,
                    milestoneTotal: 10
                ),
                SignalFact(
                    ownerId: jonah.id,
                    kind: .returning,
                    date: now,
                    createdAt: cal.date(byAdding: .minute, value: -50, to: now) ?? now,
                    taskName: "Deep work",
                    category: "Work",
                    daysSince: 6
                )
            ]
        }

        return facts
    }

    /// One cheer landing today (shows in the homepage Season zone)
    /// plus one from yesterday (lives in the store but doesn't
    /// surface as active).
    static func seedCheers(friends: [Friend], userId: UUID) -> [Cheer] {
        guard friends.count >= 2 else { return [] }
        let cal = Calendar.current
        let now = Date()
        let aaron = friends[0]
        let madison = friends[1]

        var result: [Cheer] = [
            Cheer(
                fromFriendId: aaron.id,
                fromName: aaron.displayName,
                fromInitials: aaron.initials,
                fromColorHex: aaron.accentColorHex,
                toUserId: userId,
                message: "go get that EP done today 🔥",
                sentAt: cal.date(byAdding: .hour, value: -3, to: now) ?? now
            ),
            Cheer(
                fromFriendId: madison.id,
                fromName: madison.displayName,
                fromInitials: madison.initials,
                fromColorHex: madison.accentColorHex,
                toUserId: userId,
                message: "proud of you, keep going",
                sentAt: cal.date(byAdding: .hour, value: -1, to: now) ?? now
            )
        ]

        if friends.count >= 7 {
            let priya = friends[6]
            result.append(
                Cheer(
                    fromFriendId: priya.id,
                    fromName: priya.displayName,
                    fromInitials: priya.initials,
                    fromColorHex: priya.accentColorHex,
                    toUserId: userId,
                    message: "day 16 and still showing up ✨",
                    sentAt: cal.date(byAdding: .minute, value: -40, to: now) ?? now
                )
            )
        }

        return result
    }

    /// Two placeholder media records. Neither has a real local URL —
    /// the actual capture flow in a later prompt will write files
    /// and patch `localURL` accordingly. Seeded so the C1 story-post
    /// seed has something to reference for media-bearing posts.
    static func seedMediaAssets() -> [MediaAsset] {
        let now = Date()
        func photo() -> MediaAsset {
            MediaAsset(type: .photo, localURL: nil, remoteURL: nil, thumbnailURL: nil, durationSeconds: nil, createdAt: now)
        }
        func video() -> MediaAsset {
            MediaAsset(type: .video, localURL: nil, remoteURL: nil, thumbnailURL: nil, durationSeconds: 6.0, createdAt: now)
        }
        // A small pool so proofs + posts can each reference distinct
        // media. No real files — surfaces render placeholders.
        return [photo(), video(), photo(), photo(), video()]
    }

    /// Three posts: two unexpired general stories and one circle
    /// clip attached to the "Run a mile" task in the 5K circle.
    static func seedStoryPosts(
        friends: [Friend],
        circles: [FFCircle],
        mediaAssets: [MediaAsset]
    ) -> [StoryPost] {
        guard friends.count >= 2 else { return [] }
        let cal = Calendar.current
        let now = Date()
        let aaron = friends[0]
        let madison = friends[1]

        let photos = mediaAssets.filter { $0.type == .photo }
        let videos = mediaAssets.filter { $0.type == .video }
        func photoId(_ i: Int) -> UUID? { photos.indices.contains(i) ? photos[i].id : photos.first?.id }

        var posts: [StoryPost] = []

        // Aaron general post — caption + photo.
        posts.append(StoryPost(
            authorId: aaron.id,
            createdAt: cal.date(byAdding: .hour, value: -2, to: now) ?? now,
            caption: "first morning in a long while where everything pointed the same direction.",
            mediaId: photoId(0),
            circleId: nil,
            attachedCircleTaskId: nil
        ))

        // Madison general post — caption only.
        posts.append(StoryPost(
            authorId: madison.id,
            createdAt: cal.date(byAdding: .hour, value: -4, to: now) ?? now,
            caption: "slow morning, but the plan is set. small lift, then back to writing.",
            mediaId: nil,
            circleId: nil,
            attachedCircleTaskId: nil
        ))

        // Expanded roster — a few more fresh, unviewed general stories
        // so the rail lights up with gold rings on first launch.
        if friends.count >= 10 {
            let theo = friends[5]
            let priya = friends[6]
            let jonah = friends[9]
            posts.append(StoryPost(
                authorId: theo.id,
                createdAt: cal.date(byAdding: .minute, value: -25, to: now) ?? now,
                caption: "cold water, clear head. that's the whole trick.",
                mediaId: photoId(1),
                circleId: nil,
                attachedCircleTaskId: nil
            ))
            posts.append(StoryPost(
                authorId: priya.id,
                createdAt: cal.date(byAdding: .minute, value: -45, to: now) ?? now,
                caption: "7 of 10 pages of the zine done. it's becoming a real thing.",
                mediaId: photoId(2),
                circleId: nil,
                attachedCircleTaskId: nil
            ))
            posts.append(StoryPost(
                authorId: jonah.id,
                createdAt: cal.date(byAdding: .hour, value: -3, to: now) ?? now,
                caption: "slow day, but I opened the doc. that counts.",
                mediaId: nil,
                circleId: nil,
                attachedCircleTaskId: nil
            ))
        }

        // Aaron circle clip in the 5K circle, attached to the
        // "Run a mile" task as the earned badge.
        if let run5k = circles.first(where: { $0.name == "Run a 5K" }),
           let runTask = run5k.tasks.first,
           let videoMedia = videos.first {
            posts.append(StoryPost(
                authorId: aaron.id,
                createdAt: cal.date(byAdding: .hour, value: -1, to: now) ?? now,
                caption: "got the mile in.",
                mediaId: videoMedia.id,
                circleId: run5k.id,
                attachedCircleTaskId: runTask.id
            ))
        }

        // Theo circle clip in Morning Pages, attached to "Write 500 words".
        if friends.count >= 6,
           let pages = circles.first(where: { $0.name == "Morning Pages" }),
           let writeTask = pages.tasks.first {
            posts.append(StoryPost(
                authorId: friends[5].id,
                createdAt: cal.date(byAdding: .hour, value: -2, to: now) ?? now,
                caption: "500 words before sunrise.",
                mediaId: photoId(3),
                circleId: pages.id,
                attachedCircleTaskId: writeTask.id
            ))
        }

        return posts
    }

    /// Seeded 1:1 proofs/messages so the threads + activity-row message
    /// affordances read alive on first launch, matching the reference:
    ///   • Aaron — an unread *message* (lights his row "OPEN").
    ///   • Devin — an unread *proof* (lights his row "VIEW").
    ///   • Madison — an already-read proof (history, stays quiet).
    static func seedDirectShares(
        friends: [Friend],
        userId: UUID,
        mediaAssets: [MediaAsset]
    ) -> [DirectShare] {
        guard friends.count >= 3 else { return [] }
        let cal = Calendar.current
        let now = Date()
        let aaron = friends[0]
        let madison = friends[1]
        let devin = friends[2]
        let photos = mediaAssets.filter { $0.type == .photo }
        func photoId(_ i: Int) -> UUID? { photos.indices.contains(i) ? photos[i].id : photos.first?.id }

        var shares: [DirectShare] = [
            // Aaron — message, unread.
            DirectShare(
                authorId: aaron.id,
                recipientFriendId: userId,
                circleId: nil,
                caption: "look where the trail opened up this morning",
                mediaId: nil,
                createdAt: cal.date(byAdding: .minute, value: -8, to: now) ?? now
            ),
            // You → Aaron — an earlier reply so the thread reads two-sided.
            DirectShare(
                authorId: userId,
                recipientFriendId: aaron.id,
                circleId: nil,
                caption: "that's gorgeous. saving it for my run later",
                mediaId: nil,
                createdAt: cal.date(byAdding: .minute, value: -7, to: now) ?? now,
                readAt: cal.date(byAdding: .minute, value: -7, to: now) ?? now
            ),
            // Devin — proof (has media), unread.
            DirectShare(
                authorId: devin.id,
                recipientFriendId: userId,
                circleId: nil,
                caption: "made the morning ride \u{1F6B4}",
                mediaId: photoId(0),
                createdAt: cal.date(byAdding: .minute, value: -2, to: now) ?? now
            ),
            // Madison — proof, already read (keeps her row quiet).
            DirectShare(
                authorId: madison.id,
                recipientFriendId: userId,
                circleId: nil,
                caption: "proof i actually made the 6am class \u{1F4AA}",
                mediaId: nil,
                createdAt: cal.date(byAdding: .hour, value: -6, to: now) ?? now,
                readAt: cal.date(byAdding: .hour, value: -5, to: now) ?? now
            )
        ]

        // Expanded roster — more lit rows + a couple of richer threads.
        if friends.count >= 10 {
            let theo = friends[5]
            let priya = friends[6]
            let jonah = friends[9]
            shares += [
                // Theo — proof, unread (lights his row "VIEW").
                DirectShare(
                    authorId: theo.id,
                    recipientFriendId: userId,
                    circleId: nil,
                    caption: "day 9 of the plunge \u{1F976}",
                    mediaId: photoId(1),
                    createdAt: cal.date(byAdding: .minute, value: -4, to: now) ?? now
                ),
                // Priya — message, unread (lights her row "OPEN").
                DirectShare(
                    authorId: priya.id,
                    recipientFriendId: userId,
                    circleId: nil,
                    caption: "can you read the first page when you get a sec?",
                    mediaId: nil,
                    createdAt: cal.date(byAdding: .minute, value: -12, to: now) ?? now
                ),
                // Jonah — older proof, already read (stays quiet).
                DirectShare(
                    authorId: jonah.id,
                    recipientFriendId: userId,
                    circleId: nil,
                    caption: "finally back at the desk",
                    mediaId: photoId(2),
                    createdAt: cal.date(byAdding: .hour, value: -8, to: now) ?? now,
                    readAt: cal.date(byAdding: .hour, value: -7, to: now) ?? now
                ),
                // You → Priya — your reply, so her thread reads two-sided.
                DirectShare(
                    authorId: userId,
                    recipientFriendId: priya.id,
                    circleId: nil,
                    caption: "on it tonight \u{2728}",
                    mediaId: nil,
                    createdAt: cal.date(byAdding: .hour, value: -9, to: now) ?? now,
                    readAt: cal.date(byAdding: .hour, value: -9, to: now) ?? now
                )
            ]
        }

        return shares
    }

    /// One of the user's own stories so the posted state + viewer
    /// (seen-by, reactions, in-viewer "+ Add") are demoable on first
    /// launch. Caption-only — no file needed on disk.
    static func seedMyStoryPosts(userId: UUID) -> [StoryPost] {
        let cal = Calendar.current
        let now = Date()
        return [
            StoryPost(
                authorId: userId,
                createdAt: cal.date(byAdding: .hour, value: -2, to: now) ?? now,
                caption: "Made the 6am class \u{1F4AA}",
                mediaId: nil,
                circleId: nil,
                attachedCircleTaskId: nil
            )
        ]
    }

    /// Two likes on the user's own story so the viewer reads "\u{2661} 2".
    static func seedMyLikes(post: StoryPost, friends: [Friend]) -> [Like] {
        guard friends.count >= 3 else { return [] }
        let aaron = friends[0]
        let devin = friends[2]
        return [
            Like(postId: post.id, fromFriendId: aaron.id, fromName: aaron.displayName),
            Like(postId: post.id, fromFriendId: devin.id, fromName: devin.displayName)
        ]
    }

    /// A pair of likes on Aaron's general post so the feed reads
    /// alive on first launch.
    static func seedLikes(posts: [StoryPost], friends: [Friend]) -> [Like] {
        guard let firstPost = posts.first, friends.count >= 3 else { return [] }
        let madison = friends[1]
        let devin = friends[2]
        return [
            Like(
                postId: firstPost.id,
                fromFriendId: madison.id,
                fromName: madison.displayName
            ),
            Like(
                postId: firstPost.id,
                fromFriendId: devin.id,
                fromName: devin.displayName
            )
        ]
    }

    /// One accepted pact with Aaron — "Write every day" — so the
    /// detail surface has material to render on first launch. Started
    /// five days ago, fourteen-day window, so the eyebrow reads with
    /// real time pressure.
    static func seedPacts(friends: [Friend], userId: UUID) -> [Pact] {
        guard let aaron = friends.first else { return [] }
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .day, value: -5, to: cal.startOfDay(for: now)) ?? now
        let end = cal.date(byAdding: .day, value: 14, to: start) ?? now

        let writeTask = PactTask(
            name: "Write — 20 minutes",
            category: .creative,
            linkedPersonalTaskId: nil
        )

        var result: [Pact] = [
            Pact(
                title: "Write every day",
                proposerId: userId,
                partnerId: aaron.id,
                tasks: [writeTask],
                durationDays: 14,
                startDate: start,
                endDate: end,
                status: .active,
                createdAt: start
            )
        ]

        // A second active pact (with Jonah) and an incoming pending
        // pact (from Priya) so both the live and the "accept / decline"
        // states of a pact are demoable straight from a fresh install.
        if friends.count >= 10 {
            let priya = friends[6]
            let jonah = friends[9]
            let jStart = cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: now)) ?? now
            let jEnd = cal.date(byAdding: .day, value: 10, to: jStart) ?? now
            result.append(
                Pact(
                    title: "Cold shower streak",
                    proposerId: userId,
                    partnerId: jonah.id,
                    tasks: [PactTask(name: "Cold shower", category: .health, linkedPersonalTaskId: nil)],
                    durationDays: 10,
                    startDate: jStart,
                    endDate: jEnd,
                    status: .active,
                    createdAt: jStart
                )
            )
            result.append(
                Pact(
                    title: "Read before bed",
                    proposerId: priya.id,
                    partnerId: userId,
                    tasks: [PactTask(name: "Read 10 pages", category: .creative, linkedPersonalTaskId: nil)],
                    durationDays: 10,
                    startDate: nil,
                    endDate: nil,
                    status: .pending,
                    createdAt: cal.date(byAdding: .hour, value: -4, to: now) ?? now
                )
            )
        }

        return result
    }

    /// Seed prior-day completions so both progress bars read non-zero
    /// on the very first launch. "You" has four prior days kept;
    /// Aaron has five. Today is intentionally left open so the
    /// checkbox is something the user can tap immediately.
    static func seedPactCompletions(pacts: [Pact], userId: UUID) -> [PactCompletion] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        func day(_ offset: Int) -> Date {
            cal.date(byAdding: .day, value: -offset, to: today) ?? today
        }

        var rows: [PactCompletion] = []
        // Seed every *active* pact: the partner kept every prior day in
        // the window; you kept all but the most recent (a gentle gap),
        // leaving today open to tap. Pending pacts get nothing.
        for pact in pacts where pact.status == .active {
            guard let task = pact.tasks.first, let start = pact.startDate else { continue }
            let startDay = cal.startOfDay(for: start)
            let elapsed = max(0, cal.dateComponents([.day], from: startDay, to: today).day ?? 0)
            let priorDays = min(elapsed, pact.durationDays)
            guard priorDays >= 1 else { continue }
            let otherId = (pact.proposerId == userId) ? pact.partnerId : pact.proposerId
            for offset in 1...priorDays {
                rows.append(PactCompletion(pactId: pact.id, taskId: task.id, userId: otherId, date: day(offset)))
                if offset > 1 {
                    rows.append(PactCompletion(pactId: pact.id, taskId: task.id, userId: userId, date: day(offset)))
                }
            }
        }
        return rows
    }

    /// One short comment on the first post so threads have material.
    static func seedComments(posts: [StoryPost], friends: [Friend]) -> [Comment] {
        guard let firstPost = posts.first, friends.count >= 2 else { return [] }
        let madison = friends[1]
        return [
            Comment(
                postId: firstPost.id,
                fromFriendId: madison.id,
                fromName: madison.displayName,
                fromInitials: madison.initials,
                text: "felt this. so glad."
            )
        ]
    }
}
