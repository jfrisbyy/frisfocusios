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

    private enum Keys {
        static let pendingSlices = "seasonSync.pendingSlices"
        static let localStamps = "seasonSync.localStamps"
        static let uploadedMedia = "seasonSync.uploadedMedia"
        static func initialPush(_ userId: String) -> String { "seasonSync.initialPush.\(userId)" }
    }

    /// Slice key for a Store data key. Only season-scoped keys map.
    private static func slice(for key: Store.DataKey) -> String? {
        switch key {
        case .season: return "season"
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
        "season", "tasks", "todos", "logEntries",
        "boosters", "habitTrains", "avoidanceItems", "avoidanceOccurrences"
    ]

    // MARK: Lifecycle

    /// Begin syncing for the signed-in user. Idempotent per user id.
    func start(myUserId: String, store: Store) async {
        if self.myUserId == myUserId, self.store === store { return }
        self.myUserId = myUserId
        self.store = store
        store.seasonSync = self
        loadState()

        // First sync for this account on this install: queue every
        // slice so the existing local season migrates up (or, if the
        // account already has a newer season, the pull below wins).
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Keys.initialPush(myUserId)) {
            let now = Date()
            for slice in Self.allSlices {
                pendingSlices.insert(slice)
                if localStamps[slice] == nil { localStamps[slice] = now }
            }
            persistState()
            defaults.set(true, forKey: Keys.initialPush(myUserId))
        }

        await pullRemote()
        await flushNow()
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

    /// Fetch the remote season and apply any slice whose remote stamp
    /// is newer than the local one. Local slices with newer stamps stay
    /// queued for the next flush.
    func pullRemote() async {
        guard let myUserId, let store else { return }
        do {
            let rows: [SeasonSyncRow] = try await supabase
                .from("season_sync")
                .select()
                .eq("user_id", value: myUserId)
                .execute()
                .value

            var appliedSeason = false
            for row in rows {
                let remoteStamp = SyncDates.parse(row.updatedAt)
                let localStamp = localStamps[row.sliceKey] ?? .distantPast
                guard remoteStamp > localStamp else { continue }

                suppressedSlices.insert(row.sliceKey)
                let applied = apply(slice: row.sliceKey, payload: row.payload)
                // Flush synchronously inside the suppression window so
                // the resulting write never re-queues this slice.
                store.flushPendingSaves()
                suppressedSlices.remove(row.sliceKey)

                if applied {
                    localStamps[row.sliceKey] = remoteStamp
                    pendingSlices.remove(row.sliceKey)
                    if row.sliceKey == "season" { appliedSeason = true }
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
        } catch {
            print("[SeasonSync] pull failed: \(error)")
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
        isFlushing = true
        defer { isFlushing = false }

        for slice in pendingSlices {
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
                try await supabase.from("season_sync").upsert(SeasonSyncRow(
                    userId: myUserId,
                    sliceKey: slice,
                    payload: payload,
                    updatedAt: SyncDates.iso(localStamps[slice] ?? Date())
                ), onConflict: "user_id,slice_key").execute()
                pendingSlices.remove(slice)
            } catch {
                print("[SeasonSync] upsert failed for \(slice): \(error)")
            }
        }

        persistState()
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
                (attachment.filename, attachment.kind == .photo ? "image/jpeg" : "audio/mp4")
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
    }

    private func persistState() {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(Array(pendingSlices)), forKey: Keys.pendingSlices)
        defaults.set(try? encoder.encode(localStamps), forKey: Keys.localStamps)
        defaults.set(try? encoder.encode(Array(uploadedMedia)), forKey: Keys.uploadedMedia)
    }
}
