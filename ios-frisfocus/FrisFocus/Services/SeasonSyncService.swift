//
//  SeasonSyncService.swift
//  FrisFocus
//
//  Private cloud sync for the season: the season itself (categories,
//  goals, milestones with steps + attachments), tasks, to-dos, the full
//  score history, boosters, habit trains, and avoidance — everything a
//  reinstall needs to restore the season instead of starting blank.
//
//  Document-style: each Store slice uploads as one JSON payload row in
//  `season_sync` keyed (user_id, slice_key), resolved latest-wins via
//  per-slice stamps. The Store stays the offline-first source of truth;
//  `flushPendingSaves` notifies this service whenever a season-scoped
//  slice is written, so every mutation path is covered by one hook.
//
//  Milestone journey media (photos / voice memos) uploads privately
//  into the `note-media` bucket under `<userId>/<filename>` — same
//  convention as the journal — and missing files download on pull.
//

import Foundation
import Supabase

// MARK: - Wire DTO

private nonisolated struct SeasonSyncRow: Codable, Sendable {
    let userId: String
    let sliceKey: String
    let payload: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case payload
        case userId = "user_id"
        case sliceKey = "slice_key"
        case updatedAt = "updated_at"
    }
}

/// One captured known-good state of a slice, kept on-device as a
/// last-resort fallback if both the live copy and the cloud are wiped.
private nonisolated struct SnapshotEntry: Codable, Sendable {
    let payload: String
    let stamp: Date
}

/// Minimal read shape for verifying the friend-visible season card
/// before we would overwrite it with an empty one.
private nonisolated struct ProfileCardRow: Decodable, Sendable {
    let seasonCard: String?
    enum CodingKeys: String, CodingKey { case seasonCard = "season_card" }
}

// MARK: - Service

@Observable
@MainActor
final class SeasonSyncService {
    private(set) var myUserId: String?

    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private var flushDebounce: Task<Void, Never>?
    @ObservationIgnored private var isFlushing = false
    /// Slices whose hooks should be ignored because we're writing
    /// remote data into the Store right now (prevents echo loops).
    @ObservationIgnored private var suppressedSlices: Set<String> = []

    /// Slices with local changes not yet pushed. Persisted so offline
    /// edits survive a relaunch.
    @ObservationIgnored private var pendingSlices: Set<String> = []
    /// Per-slice stamp of the latest local mutation (or the remote
    /// stamp last applied), driving latest-wins.
    @ObservationIgnored private var localStamps: [String: Date] = [:]
    /// Media filenames known to be safely in the bucket already.
    @ObservationIgnored private var uploadedMedia: Set<String> = []
    /// Filenames currently downloading, so refreshes don't double-fetch.
    @ObservationIgnored private var activeDownloads: Set<String> = []
    /// Rolling on-device snapshots of the last few known-good states per
    /// slice, kept separate from the live copy. If a local wipe leaves a
    /// slice empty and the cloud can't restore it, the newest snapshot
    /// is the final fallback before the account shows blank.
    @ObservationIgnored private var snapshots: [String: [SnapshotEntry]] = [:]
    /// Hard startup gate: no slice may upload until we have reached and
    /// finished restoring from the cloud backup at least once this
    /// launch. Prevents a fresh install / rebuild from ever writing an
    /// empty slate over real cloud content.
    @ObservationIgnored private var restoreConfirmed = false
    /// Slices the last cloud pull found to hold real (non-empty) content.
    /// Used as a live guard so an empty local slice can never be flushed
    /// over a cloud slice that still has data.
    @ObservationIgnored private var cloudNonEmptySlices: Set<String> = []

    private enum Keys {
        static let pendingSlices = "seasonSync.pendingSlices"
        static let localStamps = "seasonSync.localStamps"
        static let uploadedMedia = "seasonSync.uploadedMedia"
        static let snapshots = "seasonSync.snapshots"
        static func initialPush(_ userId: String) -> String { "seasonSync.initialPush.\(userId)" }
    }

    /// Max snapshots retained per slice.
    private static let maxSnapshotsPerSlice = 3

    /// Slice key for a Store data key. Only season-scoped keys map.
    private static func slice(for key: Store.DataKey) -> String? {
        switch key {
        case .season: return "season"
        case .pastSeasons: return "pastSeasons"
        case .archivedSeasons: return "archivedSeasons"
        case .tasks: return "tasks"
        case .todos: return "todos"
        case .logEntries: return "logEntries"
        case .boosters: return "boosters"
        case .habitTrains: return "habitTrains"
        case .avoidanceItems: return "avoidanceItems"
        case .avoidanceOccurrences: return "avoidanceOccurrences"
        default: return nil
        }
    }

    private static let allSlices = [
        "season", "pastSeasons", "archivedSeasons", "tasks", "todos", "logEntries",
        "boosters", "habitTrains", "avoidanceItems", "avoidanceOccurrences"
    ]

    /// Slices whose content feeds the public season card on the
    /// profile row — flushing one republishes the card.
    private static let seasonCardSlices: Set<String> = ["season", "pastSeasons"]

    // MARK: Lifecycle

    /// Begin syncing for the signed-in user. Idempotent per user id.
    func start(myUserId: String, store: Store) async {
        if self.myUserId == myUserId, self.store === store { return }
        self.myUserId = myUserId
        self.store = store
        store.seasonSync = self
        loadState()

        let defaults = UserDefaults.standard
        let isFirstSync = !defaults.bool(forKey: Keys.initialPush(myUserId))

        // Startup guarantee: reach and finish restoring from the cloud
        // backup before we are ever allowed to upload. Retries on
        // failure so a network hiccup never makes us assume there's no
        // data and blank the account out.
        await restoreFromCloud()

        // Last-resort local fallback: if a slice is still empty after the
        // cloud restore (e.g. the backup was blanked by an older build),
        // rebuild it from the newest on-device snapshot and re-queue it.
        recoverEmptySlicesFromSnapshots()

        // Recover any season that was replaced before full archives
        // existed — reconstruct a restorable copy from on-device
        // snapshots so it can be reactivated like any other past season.
        recoverReplacedSeasonsIntoArchive()

        // First sync for this account on this install: queue only the
        // slices that actually have content so a real local season
        // migrates up. Empty slices are never queued — an empty starting
        // slate must never win over (or overwrite) the cloud backup we
        // just restored.
        if isFirstSync {
            let now = Date()
            for slice in Self.allSlices where !sliceIsEmpty(slice) {
                pendingSlices.insert(slice)
                if localStamps[slice] == nil { localStamps[slice] = now }
            }
            persistState()
            defaults.set(true, forKey: Keys.initialPush(myUserId))
        }

        await flushNow()
        // Make sure friends see the freshest season card even when no
        // slice needed flushing this launch.
        await pushSeasonCard()
    }

    /// Stop syncing on sign-out. The local season stays put — it
    /// existed before sign-in and remains personal to this device.
    func stop() {
        flushDebounce?.cancel()
        flushDebounce = nil
        myUserId = nil
    }

    // MARK: Up-sync hook (called by Store.flushPendingSaves)

    /// A season-scoped slice was just written locally. Stamp it, queue
    /// it, and schedule a debounced push. Ignored while remote data is
    /// being applied so pulls never echo back up.
    func sliceChanged(_ key: Store.DataKey) {
        guard let slice = Self.slice(for: key) else { return }
        guard !suppressedSlices.contains(slice) else { return }
        localStamps[slice] = Date()
        pendingSlices.insert(slice)
        persistState()
        scheduleFlush()
    }

    // MARK: Pull + merge

    /// Reach the cloud backup and finish restoring before any upload is
    /// allowed this launch. Retries a few times on failure; once a pull
    /// succeeds the upload gate opens.
    private func restoreFromCloud() async {
        for attempt in 0..<5 {
            if await pullRemote() { return }
            try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        }
        print("[SeasonSync] restore could not reach cloud after retries; uploads stay gated")
    }

    /// Whether a slice currently holds no real user data locally. Used
    /// so a phantom empty slice can never be queued or uploaded.
    private func sliceIsEmpty(_ slice: String) -> Bool {
        guard let store else { return true }
        switch slice {
        case "season":
            let s = store.currentSeason
            return s.categories.isEmpty && s.milestones.isEmpty
        case "pastSeasons": return store.pastSeasons.isEmpty
        case "archivedSeasons": return store.archivedSeasons.isEmpty
        case "tasks": return store.tasks.isEmpty
        case "todos": return store.todos.isEmpty
        case "logEntries": return store.logEntries.isEmpty
        case "boosters": return store.boosters.isEmpty
        case "habitTrains": return store.habitTrains.isEmpty
        case "avoidanceItems": return store.avoidanceItems.isEmpty
        case "avoidanceOccurrences": return store.avoidanceOccurrences.isEmpty
        default: return true
        }
    }

    /// Fetch the remote season and apply any slice whose remote stamp
    /// is newer than the local one. Local slices with newer stamps stay
    /// queued for the next flush. Returns whether the cloud was reached
    /// (so the caller can open the upload gate / retry).
    @discardableResult
    func pullRemote() async -> Bool {
        guard let myUserId, let store else { return false }
        do {
            let rows: [SeasonSyncRow] = try await supabase
                .from("season_sync")
                .select()
                .eq("user_id", value: myUserId)
                .execute()
                .value

            print("[SeasonSync] pull for user=\(myUserId): \(rows.count) row(s)")
            var appliedSeason = false
            cloudNonEmptySlices = []
            for row in rows {
                let remoteStamp = SyncDates.parse(row.updatedAt)
                let localStamp = localStamps[row.sliceKey] ?? .distantPast
                let remoteEmpty = remotePayloadIsEmpty(slice: row.sliceKey, payload: row.payload)
                let localEmpty = sliceIsEmpty(row.sliceKey)
                if !remoteEmpty { cloudNonEmptySlices.insert(row.sliceKey) }
                print("[SeasonSync] slice=\(row.sliceKey) bytes=\(row.payload.utf8.count) remoteEmpty=\(remoteEmpty) localEmpty=\(localEmpty) remoteStamp=\(row.updatedAt) localStamp=\(localStamp)")

                // Empty never wins: apply the cloud copy when it is newer
                // by stamp, OR whenever the local slice is empty and the
                // cloud still holds real content — so a stale local stamp
                // (left by an earlier build that marked empty data as
                // "changed now") can never block restoring real data.
                let shouldApply = (remoteStamp > localStamp) || (localEmpty && !remoteEmpty)
                guard shouldApply else { continue }

                suppressedSlices.insert(row.sliceKey)
                let applied = apply(slice: row.sliceKey, payload: row.payload)
                // Flush synchronously inside the suppression window so
                // the resulting write never re-queues this slice.
                store.flushPendingSaves()
                suppressedSlices.remove(row.sliceKey)

                if applied {
                    // Keep the stamp monotonic: never move it backwards
                    // when we restored purely because local was empty.
                    localStamps[row.sliceKey] = max(remoteStamp, localStamp)
                    pendingSlices.remove(row.sliceKey)
                    captureSnapshot(slice: row.sliceKey, payload: row.payload, stamp: remoteStamp)
                    if row.sliceKey == "season" { appliedSeason = true }
                    print("[SeasonSync] applied slice=\(row.sliceKey)")
                }
            }
            persistState()

            // Media already in the bucket needs no re-upload; fetch
            // anything this device doesn't have yet.
            for (filename, _) in milestoneMediaFilenames() {
                uploadedMedia.insert(filename)
            }
            if appliedSeason {
                downloadMissingMedia()
                store.refreshMilestoneNudges()
            }
            // Cloud reached and applied — the upload gate may open.
            restoreConfirmed = true
            return true
        } catch {
            print("[SeasonSync] pull failed: \(error)")
            return false
        }
    }

    /// Whether a decoded remote payload holds no real user data — the
    /// mirror of `sliceIsEmpty` but for an inbound cloud row. A payload
    /// that fails to decode is treated as empty so it never blocks a
    /// real local copy.
    private func remotePayloadIsEmpty(slice: String, payload: String) -> Bool {
        guard let data = payload.data(using: .utf8) else { return true }
        let d = JSONDecoder()
        switch slice {
        case "season":
            guard let v = try? d.decode(Season.self, from: data) else { return true }
            return v.categories.isEmpty && v.milestones.isEmpty
        case "pastSeasons": return (try? d.decode([PastSeasonSummary].self, from: data))?.isEmpty ?? true
        case "archivedSeasons": return (try? d.decode([SeasonArchive].self, from: data))?.isEmpty ?? true
        case "tasks": return (try? d.decode([FFTask].self, from: data))?.isEmpty ?? true
        case "todos": return (try? d.decode([Todo].self, from: data))?.isEmpty ?? true
        case "logEntries": return (try? d.decode([LogEntry].self, from: data))?.isEmpty ?? true
        case "boosters": return (try? d.decode([WeeklyBooster].self, from: data))?.isEmpty ?? true
        case "habitTrains": return (try? d.decode([HabitTrain].self, from: data))?.isEmpty ?? true
        case "avoidanceItems": return (try? d.decode([AvoidanceItem].self, from: data))?.isEmpty ?? true
        case "avoidanceOccurrences": return (try? d.decode([AvoidanceOccurrence].self, from: data))?.isEmpty ?? true
        default: return true
        }
    }

    /// Decode one slice payload into the Store. Returns whether the
    /// payload decoded cleanly (a corrupt payload never nukes local data).
    private func apply(slice: String, payload: String) -> Bool {
        guard let store, let data = payload.data(using: .utf8) else { return false }
        let decoder = JSONDecoder()
        switch slice {
        case "season":
            guard let value = try? decoder.decode(Season.self, from: data) else { return false }
            store.currentSeason = value
        case "pastSeasons":
            guard let value = try? decoder.decode([PastSeasonSummary].self, from: data) else { return false }
            store.pastSeasons = value
        case "archivedSeasons":
            guard let value = try? decoder.decode([SeasonArchive].self, from: data) else { return false }
            store.archivedSeasons = value
        case "tasks":
            guard let value = try? decoder.decode([FFTask].self, from: data) else { return false }
            store.tasks = value
        case "todos":
            guard let value = try? decoder.decode([Todo].self, from: data) else { return false }
            store.todos = value
        case "logEntries":
            guard let value = try? decoder.decode([LogEntry].self, from: data) else { return false }
            store.logEntries = value
        case "boosters":
            guard let value = try? decoder.decode([WeeklyBooster].self, from: data) else { return false }
            store.boosters = value
        case "habitTrains":
            guard let value = try? decoder.decode([HabitTrain].self, from: data) else { return false }
            store.habitTrains = value
        case "avoidanceItems":
            guard let value = try? decoder.decode([AvoidanceItem].self, from: data) else { return false }
            store.avoidanceItems = value
        case "avoidanceOccurrences":
            guard let value = try? decoder.decode([AvoidanceOccurrence].self, from: data) else { return false }
            store.avoidanceOccurrences = value
        default:
            return false
        }
        return true
    }

    /// Encode one slice's current local value as a JSON payload.
    private func payload(for slice: String) -> String? {
        guard let store else { return nil }
        let encoder = JSONEncoder()
        func encode<T: Encodable>(_ value: T) -> String? {
            guard let data = try? encoder.encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        switch slice {
        case "season": return encode(store.currentSeason)
        case "pastSeasons": return encode(store.pastSeasons)
        case "archivedSeasons": return encode(store.archivedSeasons)
        case "tasks": return encode(store.tasks)
        case "todos": return encode(store.todos)
        case "logEntries": return encode(store.logEntries)
        case "boosters": return encode(store.boosters)
        case "habitTrains": return encode(store.habitTrains)
        case "avoidanceItems": return encode(store.avoidanceItems)
        case "avoidanceOccurrences": return encode(store.avoidanceOccurrences)
        default: return nil
        }
    }

    // MARK: Flush

    /// Debounced flush — bursts of edits coalesce into one round-trip.
    private func scheduleFlush() {
        flushDebounce?.cancel()
        flushDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.flushNow()
        }
    }

    /// Push every queued slice now. Failed slices stay queued so the
    /// next launch / foreground retries them — offline edits survive.
    func flushNow() async {
        guard let myUserId, store != nil, !isFlushing else { return }
        // Hard gate: never upload until the cloud restore is confirmed,
        // so a fresh install / rebuild can't clobber the backup.
        guard restoreConfirmed else {
            print("[SeasonSync] flush skipped — cloud restore not yet confirmed")
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        let touchesSeasonCard = !pendingSlices.isDisjoint(with: Self.seasonCardSlices)

        for slice in pendingSlices {
            // Content-aware guard: never upload an empty slice over a
            // cloud slice that still holds real content. This covers both
            // the phantom-empty reinstall case (no local mutation) and a
            // stale-stamp case where an empty slice looks "changed".
            if sliceIsEmpty(slice), localStamps[slice] == nil || cloudNonEmptySlices.contains(slice) {
                print("[SeasonSync] flush skip empty slice=\(slice) (cloud has content or never edited)")
                pendingSlices.remove(slice)
                continue
            }
            // The season slice carries the milestone media references —
            // make sure the files are up before the row points at them.
            if slice == "season" {
                guard await uploadMilestoneMedia(userId: myUserId) else { continue }
            }
            guard let payload = payload(for: slice) else {
                pendingSlices.remove(slice)
                continue
            }
            do {
                let stamp = localStamps[slice] ?? Date()
                try await supabase.from("season_sync").upsert(SeasonSyncRow(
                    userId: myUserId,
                    sliceKey: slice,
                    payload: payload,
                    updatedAt: SyncDates.iso(stamp)
                ), onConflict: "user_id,slice_key").execute()
                pendingSlices.remove(slice)
                captureSnapshot(slice: slice, payload: payload, stamp: stamp)
            } catch {
                print("[SeasonSync] upsert failed for \(slice): \(error)")
            }
        }

        persistState()

        if touchesSeasonCard {
            await pushSeasonCard()
        }
    }

    // MARK: Season card (public, friend-readable)

    private nonisolated struct SeasonCardUpdate: Encodable, Sendable {
        let seasonCard: String?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case seasonCard = "season_card"
            case updatedAt = "updated_at"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let seasonCard { try c.encode(seasonCard, forKey: .seasonCard) } else { try c.encodeNil(forKey: .seasonCard) }
            try c.encode(updatedAt, forKey: .updatedAt)
        }
    }

    /// Publish the friend-readable season card (cover, accent,
    /// intention, season info, past chapters) onto the user's own
    /// profile row, where every profile surface reads it. Best-effort
    /// — the next flush retries naturally.
    func pushSeasonCard() async {
        guard let myUserId, let store else { return }
        // Content-aware guard: never publish an empty card over a
        // friend-visible one that still has content. Only overwrite with
        // an empty card once we've confirmed the cloud card is also empty.
        if store.mySeasonCard.isEmpty {
            let remote = await fetchRemoteSeasonCard()
            if !remote.reached || (remote.card?.isEmpty == false) {
                print("[SeasonSync] skip publishing empty season card over non-empty/unverified cloud card")
                return
            }
        }
        do {
            try await supabase
                .from("profiles")
                .update(SeasonCardUpdate(
                    seasonCard: store.mySeasonCard.encodedJSON(),
                    updatedAt: SyncDates.iso(Date())
                ))
                .eq("id", value: myUserId)
                .execute()
        } catch {
            print("[SeasonSync] season card push failed: \(error)")
        }
    }

    /// Read the friend-visible season card currently stored on the
    /// profile row. `reached` is false when the read failed, so callers
    /// can stay conservative and refuse to overwrite with an empty card.
    private func fetchRemoteSeasonCard() async -> (reached: Bool, card: SeasonCard?) {
        guard let myUserId else { return (false, nil) }
        do {
            let rows: [ProfileCardRow] = try await supabase
                .from("profiles")
                .select("season_card")
                .eq("id", value: myUserId)
                .limit(1)
                .execute()
                .value
            return (true, SeasonCard.decode(fromJSON: rows.first?.seasonCard))
        } catch {
            print("[SeasonSync] could not verify remote season card: \(error)")
            return (false, nil)
        }
    }

    // MARK: Snapshots (on-device fallback)

    /// Record a known-good, non-empty slice state. De-duplicates the
    /// newest identical payload and keeps only the most recent few.
    private func captureSnapshot(slice: String, payload: String, stamp: Date) {
        guard !sliceIsEmpty(slice) else { return }
        var entries = snapshots[slice] ?? []
        if entries.last?.payload == payload { return }
        entries.append(SnapshotEntry(payload: payload, stamp: stamp))
        if entries.count > Self.maxSnapshotsPerSlice {
            entries.removeFirst(entries.count - Self.maxSnapshotsPerSlice)
        }
        snapshots[slice] = entries
        persistState()
    }

    /// For any slice still empty after the cloud restore, rebuild it from
    /// the newest on-device snapshot and re-queue it for upload. This is
    /// the final fallback against a local wipe that also lost the cloud
    /// copy. Uploads stay gated on `restoreConfirmed`, so a recovered
    /// slice only re-publishes once the cloud state is known.
    private func recoverEmptySlicesFromSnapshots() {
        guard let store else { return }
        var recoveredAny = false
        for slice in Self.allSlices where sliceIsEmpty(slice) {
            guard let newest = snapshots[slice]?.max(by: { $0.stamp < $1.stamp }) else { continue }
            suppressedSlices.insert(slice)
            let applied = apply(slice: slice, payload: newest.payload)
            store.flushPendingSaves()
            suppressedSlices.remove(slice)
            if applied, !sliceIsEmpty(slice) {
                localStamps[slice] = newest.stamp
                pendingSlices.insert(slice)
                recoveredAny = true
                print("[SeasonSync] recovered \(slice) from on-device snapshot")
            }
        }
        if recoveredAny {
            persistState()
            store.refreshMilestoneNudges()
        }
    }

    // MARK: Replaced-season recovery

    /// Decode the newest snapshot of a slice into a typed value, or nil
    /// when no snapshot exists / it can't be decoded.
    private func decodeNewestSnapshot<T: Decodable>(_ slice: String, as type: T.Type) -> T? {
        guard let newest = snapshots[slice]?.max(by: { $0.stamp < $1.stamp }),
              let data = newest.payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Reconstruct restorable archives for seasons that were replaced
    /// before full archives existed. Walks the on-device "season" slice
    /// snapshots (each a full past Season JSON); for any real season that
    /// isn't the live one and has no archive yet, it rebuilds a
    /// `SeasonArchive` — attaching the best-effort sibling graph from the
    /// newest task/to-do/booster/train/avoidance snapshots — and adds a
    /// friend-visible chapter so the season reappears and can be reopened.
    private func recoverReplacedSeasonsIntoArchive() {
        guard let store else { return }
        guard let seasonSnaps = snapshots["season"], !seasonSnaps.isEmpty else { return }
        let decoder = JSONDecoder()

        var knownIds = Set(store.archivedSeasons.map(\.id))
        knownIds.insert(store.currentSeason.id)

        // Sibling graph, best-effort — the newest known-good copy of each.
        let recoveredTasks = decodeNewestSnapshot("tasks", as: [FFTask].self) ?? []
        let recoveredTodos = decodeNewestSnapshot("todos", as: [Todo].self) ?? []
        let recoveredBoosters = decodeNewestSnapshot("boosters", as: [WeeklyBooster].self) ?? []
        let recoveredTrains = decodeNewestSnapshot("habitTrains", as: [HabitTrain].self) ?? []
        let recoveredAvoidance = decodeNewestSnapshot("avoidanceItems", as: [AvoidanceItem].self) ?? []

        var recoveredAny = false
        // Newest snapshots first so the freshest copy of a season wins.
        for snap in seasonSnaps.sorted(by: { $0.stamp > $1.stamp }) {
            guard let data = snap.payload.data(using: .utf8),
                  let season = try? decoder.decode(Season.self, from: data) else { continue }
            guard !knownIds.contains(season.id) else { continue }
            // Skip empty shells — only real seasons are worth recovering.
            guard !(season.categories.isEmpty && season.milestones.isEmpty) else { continue }

            // Attach sibling graph only when it plausibly belongs to this
            // season (its tasks reference the season's categories); a
            // mismatched newest snapshot would otherwise graft the wrong
            // tasks on. When unsure, recover the season with an empty
            // board — its categories, milestones, and cover still return.
            let seasonCats = Set(season.categories.map(\.category))
            let tasksFit = !recoveredTasks.isEmpty && recoveredTasks.allSatisfy { seasonCats.contains($0.category) }
            let archive = SeasonArchive(
                id: season.id,
                season: season,
                tasks: tasksFit ? recoveredTasks : [],
                todos: tasksFit ? recoveredTodos : [],
                boosters: tasksFit ? recoveredBoosters : [],
                habitTrains: tasksFit ? recoveredTrains : [],
                avoidanceItems: tasksFit ? recoveredAvoidance : [],
                archivedAt: snap.stamp
            )
            store.archivedSeasons.insert(archive, at: 0)
            knownIds.insert(season.id)
            if !store.pastSeasons.contains(where: { $0.id == season.id }) {
                store.pastSeasons.insert(archive.summary(endedAt: snap.stamp), at: 0)
            }
            recoveredAny = true
            print("[SeasonSync] recovered replaced season \(season.name) into archive (tasksFit=\(tasksFit))")
        }

        if recoveredAny {
            store.flushPendingSaves()
        }
    }

    // MARK: Media

    private nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Every journey media filename referenced by the current season.
    private func milestoneMediaFilenames() -> [(filename: String, contentType: String)] {
        guard let store else { return [] }
        return store.currentSeason.milestones.flatMap { milestone in
            milestone.attachments.map { attachment in
                let contentType: String
                switch attachment.kind {
                case .photo: contentType = "image/jpeg"
                case .voiceMemo: contentType = "audio/mp4"
                case .video: contentType = "video/mp4"
                }
                return (attachment.filename, contentType)
            }
        }
    }

    /// Upload any not-yet-synced milestone media. Returns false when an
    /// upload failed (the season slice stays queued and retries later).
    private func uploadMilestoneMedia(userId: String) async -> Bool {
        for (filename, contentType) in milestoneMediaFilenames() where !uploadedMedia.contains(filename) {
            let local = Self.documentsDirectory.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: local) else {
                // File missing locally (e.g. cleaned up) — skip rather
                // than blocking the whole season from syncing forever.
                uploadedMedia.insert(filename)
                continue
            }
            do {
                try await StorageUploadClient.upload(
                    data: data,
                    bucket: "note-media",
                    path: "\(userId)/\(filename)",
                    contentType: contentType,
                    onProgress: { _ in }
                )
                uploadedMedia.insert(filename)
            } catch StorageUploadError.badResponse(let status) where status == 409 {
                // Already in the bucket from a previous attempt.
                uploadedMedia.insert(filename)
            } catch {
                print("[SeasonSync] media upload failed for \(filename): \(error)")
                return false
            }
        }
        return true
    }

    /// Fetch any journey files this device doesn't have yet (fresh
    /// installs, second devices). Fire-and-forget per file.
    private func downloadMissingMedia() {
        guard let myUserId else { return }
        for (filename, _) in milestoneMediaFilenames() {
            let local = Self.documentsDirectory.appendingPathComponent(filename)
            guard !FileManager.default.fileExists(atPath: local.path),
                  !activeDownloads.contains(filename) else { continue }
            activeDownloads.insert(filename)
            Task { [weak self] in
                defer { Task { @MainActor [weak self] in self?.activeDownloads.remove(filename) } }
                do {
                    let signed = try await supabase.storage
                        .from("note-media")
                        .createSignedURL(path: "\(myUserId)/\(filename)", expiresIn: 3600)
                    let (data, response) = try await URLSession.shared.data(from: signed)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
                    try data.write(to: local, options: .atomic)
                } catch {
                    print("[SeasonSync] media download failed for \(filename): \(error)")
                }
            }
        }
    }

    // MARK: State persistence

    private func loadState() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Keys.pendingSlices),
           let slices = try? decoder.decode([String].self, from: data) {
            pendingSlices = Set(slices)
        }
        if let data = defaults.data(forKey: Keys.localStamps),
           let stamps = try? decoder.decode([String: Date].self, from: data) {
            localStamps = stamps
        }
        if let data = defaults.data(forKey: Keys.uploadedMedia),
           let names = try? decoder.decode([String].self, from: data) {
            uploadedMedia = Set(names)
        }
        if let data = defaults.data(forKey: Keys.snapshots),
           let snaps = try? decoder.decode([String: [SnapshotEntry]].self, from: data) {
            snapshots = snaps
        }
    }

    private func persistState() {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(Array(pendingSlices)), forKey: Keys.pendingSlices)
        defaults.set(try? encoder.encode(localStamps), forKey: Keys.localStamps)
        defaults.set(try? encoder.encode(Array(uploadedMedia)), forKey: Keys.uploadedMedia)
        defaults.set(try? encoder.encode(snapshots), forKey: Keys.snapshots)
    }
}
