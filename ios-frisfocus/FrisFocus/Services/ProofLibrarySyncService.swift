//
//  ProofLibrarySyncService.swift
//  FrisFocus
//
//  The proof library follows the account.
//
//  An archive that only exists on one phone is not an archive — it is a
//  folder waiting to be lost to a cracked screen. But proofs are the
//  heaviest thing this app stores, so the sync is deliberately split in
//  two and the halves travel at different speeds:
//
//  • THE ROW goes up on any connection. It is a few hundred bytes and
//    it carries everything that makes the archive an archive — when the
//    proof was captured, what it was of, where it went. That survives a
//    reinstall even if the bytes never made it.
//  • THE MEDIA waits for an unmetered connection. Nobody wants their
//    quarter of proofs pushed over a hotspot on a train.
//
//  So a row can exist with a null `media_path` for a while, and it gets
//  patched once the file lands. That order matters: the reverse would
//  leave uploaded bytes nothing points at, which is how storage buckets
//  quietly fill with garbage nobody can attribute or delete.
//
//  Local-first throughout. The device's copy is the truth; the server is
//  a backup that catches up.
//

import Foundation
import Network
import Supabase

// MARK: - Wire row

private nonisolated struct RemoteProofRow: Codable, Sendable {
    let id: UUID
    let userId: String
    let capturedAt: String
    let kind: String
    let mediaPath: String?
    let duration: Double?
    let caption: String?
    let taskId: UUID?
    let todoId: UUID?
    let milestoneId: UUID?
    let noteId: UUID?
    let sharedTo: [String]

    enum CodingKeys: String, CodingKey {
        case id, kind, duration, caption
        case userId = "user_id"
        case capturedAt = "captured_at"
        case mediaPath = "media_path"
        case taskId = "task_id"
        case todoId = "todo_id"
        case milestoneId = "milestone_id"
        case noteId = "note_id"
        case sharedTo = "shared_to"
    }
}

/// The patch that fills in `media_path` once the bytes actually land.
private nonisolated struct RemoteProofMediaPatch: Encodable, Sendable {
    let mediaPath: String

    enum CodingKeys: String, CodingKey {
        case mediaPath = "media_path"
    }
}

// MARK: - Service

@Observable
@MainActor
final class ProofLibrarySyncService {
    private(set) var myUserId: String?

    /// Bumped every time archive bytes land on disk. The grid keys its
    /// thumbnails on this, so a proof restored from the account paints
    /// the moment its media arrives instead of sitting on a placeholder
    /// glyph until the next launch.
    private(set) var mediaRevision: Int = 0
    /// True while a user-initiated fetch is bringing missing archive
    /// media down. Drives the library's "still coming down" state.
    var isFetchingMedia: Bool { !activeDownloads.isEmpty }
    private(set) var failedDownloads: Set<UUID> = []
    private(set) var downloadRevisions: [UUID: Int] = [:]
    private(set) var restoreError: String?
    private(set) var isRestoring: Bool = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleID: UUID = UUID()
    /// Archived proofs whose bytes are not on this device yet.
    private(set) var missingMediaCount: Int = 0

    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private var flushDebounce: Task<Void, Never>?
    @ObservationIgnored private var isFlushing = false

    /// Item ids whose row still needs to reach the server.
    @ObservationIgnored private var pendingRows: Set<UUID> = []
    /// Item ids whose media still needs uploading. Separate from
    /// `pendingRows` because they clear on different connections.
    @ObservationIgnored private var pendingMedia: Set<UUID> = []
    /// Filenames being fetched right now, so a second refresh doesn't
    /// download the same clip twice.
    private(set) var activeDownloads: Set<String> = []
    /// Media the server has refused permanently — too large, or a
    /// bucket rejection. Retrying cannot make a file smaller, and a
    /// queue that never drains blocks everything behind it.
    @ObservationIgnored private var refusedMedia: Set<UUID> = []

    /// Whether the current connection is cheap enough for media.
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var unmetered = false

    private enum Keys {
        static let pendingRows = "proofLibrarySync.pendingRows"
        static let pendingMedia = "proofLibrarySync.pendingMedia"
        static let refusedMedia = "proofLibrarySync.refusedMedia"
        static func initialPush(_ userId: String) -> String { "proofLibrarySync.initialPush.\(userId)" }
    }

    // MARK: Lifecycle

    /// Begin syncing for the signed-in user. Idempotent per user id.
    func start(myUserId: String, store: Store) async {
        if self.myUserId == myUserId, self.store === store { return }
        stop()
        self.myUserId = myUserId
        self.store = store
        store.proofLibrarySync = self
        loadQueues()
        beginWatchingConnection()

        // Pull before push. A fresh install has an empty library, and
        // uploading that emptiness first would be indistinguishable
        // from having deleted everything.
        let lifecycle = lifecycleID
        await refresh()
        guard lifecycle == lifecycleID, !Task.isCancelled else { return }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Keys.initialPush(myUserId)) {
            // First run for this account on this install: everything
            // already on the device is queued so an archive built
            // before sign-in still reaches the account.
            pendingRows.formUnion(store.proofLibrary.map(\.id))
            pendingMedia.formUnion(store.proofLibrary.filter { $0.mediaPath == nil }.map(\.id))
            persistQueues()
            defaults.set(true, forKey: Keys.initialPush(myUserId))
        }

        await flushNow()
    }

    /// Stop syncing on sign-out. The local archive stays put — it
    /// existed before sign-in and belongs to this device.
    func stop() {
        flushDebounce?.cancel()
        flushDebounce = nil
        lifecycleID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        activeDownloads.removeAll()
        failedDownloads.removeAll()
        downloadRevisions.removeAll()
        isRestoring = false
        restoreError = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        unmetered = false
        myUserId = nil
    }

    private func beginWatchingConnection() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        let lifecycle = lifecycleID
        monitor.pathUpdateHandler = { [weak self] path in
            let cheap = path.status == .satisfied && !path.isExpensive && !path.isConstrained
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleID == lifecycle else { return }
                let wasMetered = !self.unmetered
                self.unmetered = cheap
                // Landing on Wi-Fi is the moment the media queue can
                // finally drain, so take it rather than waiting for the
                // next app launch.
                if cheap, wasMetered {
                    self.scheduleFlush()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "frisfocus.prooflibrary.path"))
    }

    // MARK: Up-sync hooks

    /// A proof was archived. The row queues immediately; the media
    /// queues too but waits for a connection worth spending.
    nonisolated func proofRecorded(_ itemId: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingRows.insert(itemId)
            self.pendingMedia.insert(itemId)
            self.persistQueues()
            self.scheduleFlush()
        }
    }

    /// A proof's links or destinations changed after it was archived —
    /// the attach flow picks its target after the bytes are written.
    nonisolated func proofUpdated(_ itemId: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingRows.insert(itemId)
            self.persistQueues()
            self.scheduleFlush()
        }
    }

    /// A proof was removed locally. Delete the row and its media so a
    /// reinstall doesn't resurrect something the person threw away.
    nonisolated func proofDeleted(_ itemId: UUID, mediaPath: String?) {
        Task { @MainActor [weak self] in
            guard let self, let myUserId = self.myUserId else { return }
            self.pendingRows.remove(itemId)
            self.pendingMedia.remove(itemId)
            self.refusedMedia.remove(itemId)
            self.persistQueues()
            do {
                // `supabase` is the file-scope client every sync service
                // uses; it is not a member of self.
                try await supabase.from("proof_library")
                    .delete()
                    .eq("id", value: itemId.uuidString)
                    .eq("user_id", value: myUserId)
                    .execute()
                if let mediaPath {
                    _ = try? await supabase.storage.from("proof-library").remove(paths: [mediaPath])
                }
            } catch {
                Log.proofLibrary.error("delete failed for \(itemId): \(error)")
            }
        }
    }

    // MARK: Flush

    private func scheduleFlush() {
        flushDebounce?.cancel()
        flushDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.flushNow()
        }
    }

    func flushNow() async {
        guard !isFlushing, myUserId != nil, let store else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Rows first, on any connection.
        for id in pendingRows {
            guard let item = store.proofLibrary.first(where: { $0.id == id }) else {
                pendingRows.remove(id)
                continue
            }
            if await upsertRow(item) { pendingRows.remove(id) }
        }
        persistQueues()

        guard unmetered else { return }

        for id in pendingMedia where !refusedMedia.contains(id) && !pendingRows.contains(id) {
            guard let item = store.proofLibrary.first(where: { $0.id == id }) else {
                pendingMedia.remove(id)
                continue
            }
            if await uploadMedia(for: item) { pendingMedia.remove(id) }
        }
        persistQueues()
        await fetchMissingMedia()
    }

    /// Bring down the bytes for any archived proof whose local file is
    /// missing — a fresh install, a second device, or a row that
    /// restored before its media did.
    ///
    /// `force` is what opening the library passes. The background sweep
    /// stays Wi-Fi-only (nobody wants their archive pushed over a
    /// hotspot), but that gate used to apply to DOWNLOADS too — so on
    /// cellular every restored proof rendered as an empty tile and the
    /// library looked broken rather than patient. Asking to look at your
    /// own archive is an explicit request for those bytes.
    /// Refresh metadata before bytes: known rows can gain a cloud path later.
    func refresh(forceMedia: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            if forceMedia { await fetchMissingMedia(force: true) }
            return
        }
        guard myUserId != nil else { return }
        let lifecycle = lifecycleID
        let task = Task {
            await self.restoreFromCloud()
            guard !Task.isCancelled, self.lifecycleID == lifecycle else { return }
            await self.fetchMissingMedia(force: forceMedia)
        }
        refreshTask = task
        await task.value
        if lifecycleID == lifecycle { refreshTask = nil }
    }

    func fetchMissingMedia(force: Bool = false) async {
        if let downloadTask {
            await downloadTask.value
            return
        }
        guard myUserId != nil, force || unmetered else { return }
        let lifecycle = lifecycleID
        // Owned by the service, not a thumbnail/viewer task that changes
        // identity when bytes arrive.
        let task = Task { await self.downloadMissingMedia(force: force, lifecycle: lifecycle) }
        downloadTask = task
        await task.value
        if lifecycleID == lifecycle { downloadTask = nil }
    }

    private func downloadMissingMedia(force: Bool, lifecycle: UUID) async {
        guard force || unmetered else {
            refreshMissingCount()
            return
        }
        guard let store else { return }
        let outstanding = store.proofLibrary.filter { item in
            guard item.mediaPath != nil, let localURL = item.url else { return false }
            return !FileManager.default.fileExists(atPath: localURL.path)
        }
        missingMediaCount = outstanding.count
        guard !outstanding.isEmpty else { return }

        defer {
            if lifecycleID == lifecycle { refreshMissingCount() }
        }

        for item in outstanding {
            guard lifecycleID == lifecycle, !Task.isCancelled else { return }
            guard let mediaPath = item.mediaPath,
                  let localURL = item.url,
                  !activeDownloads.contains(item.filename) else { continue }
            activeDownloads.insert(item.filename)
            failedDownloads.remove(item.id)
            do {
                let data = try await supabase.storage.from("proof-library").download(path: mediaPath)
                guard lifecycleID == lifecycle, !Task.isCancelled else { return }
                guard !data.isEmpty else { throw URLError(.zeroByteResource) }
                try await Task.detached(priority: .utility) {
                    try data.write(to: localURL, options: .atomic)
                }.value
                guard lifecycleID == lifecycle, !Task.isCancelled else { return }
                mediaRevision &+= 1
                downloadRevisions[item.id, default: 0] &+= 1
            } catch {
                guard lifecycleID == lifecycle, !Task.isCancelled else { return }
                failedDownloads.insert(item.id)
                Log.proofLibrary.error("archive download failed (\((error as NSError).domain), code=\((error as NSError).code))")
            }
            activeDownloads.remove(item.filename)
        }
    }

    private func refreshMissingCount() {
        guard let store else { return }
        missingMediaCount = store.proofLibrary.reduce(into: 0) { total, item in
            guard item.mediaPath != nil, let localURL = item.url else { return }
            if !FileManager.default.fileExists(atPath: localURL.path) { total += 1 }
        }
    }

    private func upsertRow(_ item: ProofLibraryItem) async -> Bool {
        guard let myUserId else { return false }
        let row = RemoteProofRow(
            id: item.id,
            userId: myUserId,
            capturedAt: SyncDates.iso(item.createdAt),
            kind: item.kind == .video ? "video" : "photo",
            mediaPath: item.mediaPath,
            duration: item.duration,
            caption: item.caption,
            taskId: item.taskId,
            todoId: item.todoId,
            milestoneId: item.milestoneId,
            noteId: item.noteId,
            sharedTo: item.sharedTo.map(\.rawValue)
        )
        do {
            try await supabase.from("proof_library").upsert(row, onConflict: "id").execute()
            return true
        } catch {
            Log.proofLibrary.error("row upsert failed for \(item.id): \(error)")
            return false
        }
    }

    private func uploadMedia(for item: ProofLibraryItem) async -> Bool {
        guard let myUserId, item.mediaPath == nil else { return true }
        guard let url = item.url,
              let data = await Task.detached(priority: .utility, operation: {
                  try? Data(contentsOf: url)
              }).value, !data.isEmpty else {
            // The local file is gone. Nothing to upload and nothing to
            // retry — the row keeps the record of what was there.
            return true
        }
        guard data.count <= VideoTranscoder.maxUploadBytes else {
            Log.proofLibrary.error("archive media too large to upload: \(item.filename)")
            refusedMedia.insert(item.id)
            return true
        }
        let container = MediaContainer.forUpload(data, assuming: item.kind == .video ? .mp4 : .jpeg)
        let path = "\(myUserId)/\(item.id.uuidString.lowercased()).\(container.fileExtension)"
        do {
            try await StorageUploadClient.upload(
                data: data,
                bucket: "proof-library",
                path: path,
                contentType: container.contentType,
                onProgress: { _ in }
            )
        } catch StorageUploadError.badResponse(let status) where status == 409 {
            // Already there from an interrupted attempt.
        } catch StorageUploadError.badResponse(let status) where status == 413 {
            Log.proofLibrary.error("archive media refused as too large: \(item.filename)")
            refusedMedia.insert(item.id)
            return true
        } catch {
            Log.proofLibrary.error("media upload failed for \(item.filename): \(error)")
            return false
        }

        // Patch the row only now. Doing it the other way round would
        // point a row at bytes that might never arrive.
        do {
            try await supabase.from("proof_library")
                .update(RemoteProofMediaPatch(mediaPath: path))
                .eq("id", value: item.id.uuidString)
                .eq("user_id", value: myUserId)
                .execute()
        } catch {
            Log.proofLibrary.error("media path patch failed for \(item.id): \(error)")
            return false
        }
        store?.markProofLibraryUploaded(item.id, mediaPath: path)
        return true
    }

    // MARK: Down-sync

    /// Merge media availability even for known IDs, without overwriting
    /// local captions, links, or pending edits.
    private func restoreFromCloud() async {
        guard let myUserId, let store else { return }
        let lifecycle = lifecycleID
        isRestoring = true
        restoreError = nil
        defer { if lifecycleID == lifecycle { isRestoring = false } }
        do {
            let rows: [RemoteProofRow] = try await supabase
                .from("proof_library")
                .select()
                .eq("user_id", value: myUserId)
                .order("captured_at", ascending: false)
                .limit(2000)
                .execute()
                .value

            guard lifecycleID == lifecycle, !Task.isCancelled else { return }
            let known = Dictionary(store.proofLibrary.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            var restored: [ProofLibraryItem] = []
            var merged = false
            for row in rows {
                if let index = known[row.id] {
                    if let path = row.mediaPath, store.proofLibrary[index].mediaPath != path {
                        store.proofLibrary[index].mediaPath = path
                        store.proofLibrary[index].uploadedAt = Date()
                        merged = true
                    }
                    continue
                }
                let ext = (row.mediaPath as NSString?)?.pathExtension
                let suffix = (ext?.isEmpty == false) ? ext! : (row.kind == "video" ? "mp4" : "jpg")
                var item = ProofLibraryItem(
                    id: row.id,
                    createdAt: SyncDates.parse(row.capturedAt),
                    kind: row.kind == "video" ? .video : .photo,
                    filename: "proof-lib-\(row.id.uuidString.lowercased()).\(suffix)",
                    duration: row.duration,
                    source: row.sharedTo.isEmpty ? .saved : .posted,
                    caption: row.caption,
                    links: ProofLibraryLinks(
                        taskId: row.taskId,
                        todoId: row.todoId,
                        milestoneId: row.milestoneId,
                        noteId: row.noteId
                    ),
                    sharedTo: row.sharedTo.compactMap(ProofShareDestination.init(rawValue:))
                )
                item.mediaPath = row.mediaPath
                item.uploadedAt = row.mediaPath == nil ? nil : Date()
                restored.append(item)
            }
            guard merged || !restored.isEmpty else {
                refreshMissingCount()
                return
            }
            store.proofLibrary.append(contentsOf: restored)
            store.persistAll()
            refreshMissingCount()
            Log.proofLibrary.debug("restored \(restored.count) archived proofs from the account")
        } catch {
            guard lifecycleID == lifecycle, !Task.isCancelled else { return }
            restoreError = "Couldn't refresh your archive. Check your connection and try again."
            Log.proofLibrary.error("archive refresh failed (\((error as NSError).domain), code=\((error as NSError).code))")
        }
    }

    // MARK: Queue persistence

    private func loadQueues() {
        let defaults = UserDefaults.standard
        pendingRows = Self.readIds(defaults, Keys.pendingRows)
        pendingMedia = Self.readIds(defaults, Keys.pendingMedia)
        refusedMedia = Self.readIds(defaults, Keys.refusedMedia)
    }

    private func persistQueues() {
        let defaults = UserDefaults.standard
        defaults.set(pendingRows.map(\.uuidString), forKey: Keys.pendingRows)
        defaults.set(pendingMedia.map(\.uuidString), forKey: Keys.pendingMedia)
        defaults.set(refusedMedia.map(\.uuidString), forKey: Keys.refusedMedia)
    }

    private static func readIds(_ defaults: UserDefaults, _ key: String) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }
}
