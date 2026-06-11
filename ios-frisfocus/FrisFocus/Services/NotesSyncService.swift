//
//  NotesSyncService.swift
//  FrisFocus
//
//  Private cloud sync for the journal: notes, folders, tags, voice
//  memos, and photos. Unlike the social mirror, this data belongs to
//  exactly one person — rows live in `notes` / `note_folders` under
//  RLS that only the owner passes, and media uploads into the private
//  `note-media` bucket under `<userId>/<filename>`.
//
//  Offline-first: the local Store stays the source of truth. Every
//  mutation enqueues work (upsert / delete / media upload) into
//  UserDefaults-persisted queues, so edits made offline flush on the
//  next launch or foreground. Conflicts resolve latest-wins via the
//  `updatedAt` stamp; the first sync after sign-in pushes every
//  existing local note up so nothing is ever lost.
//

import Foundation
import Supabase

// MARK: - Wire DTOs

/// JSONB shape for one voice memo on a remote note row.
private nonisolated struct RemoteNoteMemo: Codable, Sendable {
    let id: String
    let filename: String
    let duration: Double
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, filename, duration
        case createdAt = "created_at"
    }
}

/// JSONB shape for one photo / video on a remote note row. The media
/// fields are optional so rows written before videos and proofs
/// existed still decode.
private nonisolated struct RemoteNotePhoto: Codable, Sendable {
    let id: String
    let filename: String
    let createdAt: String
    let kind: String?
    let duration: Double?
    let isProof: Bool?

    enum CodingKeys: String, CodingKey {
        case id, filename, kind, duration
        case createdAt = "created_at"
        case isProof = "is_proof"
    }
}

private nonisolated struct NoteRow: Codable, Sendable {
    let id: UUID
    let userId: String
    let body: String?
    let label: String?
    let folderId: UUID?
    let isPinned: Bool
    let tags: [String]
    let voiceMemos: [RemoteNoteMemo]
    let photos: [RemoteNotePhoto]
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, body, label, tags, photos
        case userId = "user_id"
        case folderId = "folder_id"
        case isPinned = "is_pinned"
        case voiceMemos = "voice_memos"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct FolderRow: Codable, Sendable {
    let id: UUID
    let userId: String
    let name: String
    let colorKey: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case userId = "user_id"
        case colorKey = "color_key"
        case updatedAt = "updated_at"
    }
}

// MARK: - Service

@Observable
@MainActor
final class NotesSyncService {
    private(set) var myUserId: String?

    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private var flushDebounce: Task<Void, Never>?
    @ObservationIgnored private var isFlushing = false

    // Persisted offline queues
    @ObservationIgnored private var pendingNoteIds: Set<UUID> = []
    @ObservationIgnored private var pendingNoteDeletes: [UUID: [String]] = [:]
    @ObservationIgnored private var pendingFolderIds: Set<UUID> = []
    @ObservationIgnored private var pendingFolderDeletes: Set<UUID> = []
    /// Media filenames known to be safely in the bucket already.
    @ObservationIgnored private var uploadedMedia: Set<String> = []
    /// Filenames currently downloading, so refreshes don't double-fetch.
    @ObservationIgnored private var activeDownloads: Set<String> = []

    private enum Keys {
        static let pendingNotes = "notesSync.pendingNotes"
        static let pendingNoteDeletes = "notesSync.pendingNoteDeletes"
        static let pendingFolders = "notesSync.pendingFolders"
        static let pendingFolderDeletes = "notesSync.pendingFolderDeletes"
        static let uploadedMedia = "notesSync.uploadedMedia"
        static func initialPush(_ userId: String) -> String { "notesSync.initialPush.\(userId)" }
    }

    // MARK: Lifecycle

    /// Begin syncing for the signed-in user. Idempotent per user id.
    func start(myUserId: String, store: Store) async {
        if self.myUserId == myUserId, self.store === store { return }
        self.myUserId = myUserId
        self.store = store
        store.notesSync = self
        loadQueues()

        // First sync for this account on this install: queue every
        // local note + folder so existing journal history migrates up.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Keys.initialPush(myUserId)) {
            pendingFolderIds.formUnion(store.folders.map(\.id))
            pendingNoteIds.formUnion(store.notes.map(\.id))
            persistQueues()
            defaults.set(true, forKey: Keys.initialPush(myUserId))
        }

        await pullRemote()
        await flushNow()
    }

    /// Stop syncing on sign-out. Local journal data stays put — notes
    /// existed before sign-in and remain personal to this device.
    func stop() {
        flushDebounce?.cancel()
        flushDebounce = nil
        myUserId = nil
    }

    // MARK: Up-sync hooks (called by Store mutations)

    nonisolated func noteSaved(_ note: Note) {
        let id = note.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingNoteIds.insert(id)
            self.pendingNoteDeletes.removeValue(forKey: id)
            self.persistQueues()
            self.scheduleFlush()
        }
    }

    nonisolated func noteDeleted(id: UUID, mediaFilenames: [String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingNoteIds.remove(id)
            self.pendingNoteDeletes[id] = mediaFilenames
            self.persistQueues()
            self.scheduleFlush()
        }
    }

    nonisolated func folderSaved(_ folder: NoteFolder) {
        let id = folder.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingFolderIds.insert(id)
            self.pendingFolderDeletes.remove(id)
            self.persistQueues()
            self.scheduleFlush()
        }
    }

    nonisolated func folderDeleted(id: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingFolderIds.remove(id)
            self.pendingFolderDeletes.insert(id)
            self.persistQueues()
            self.scheduleFlush()
        }
    }

    // MARK: Pull + merge

    /// Fetch the remote journal and merge latest-wins into the Store.
    /// Remote rows pending a local delete are skipped; local rows with
    /// newer stamps stay queued for the next flush.
    func pullRemote() async {
        guard let myUserId, let store else { return }
        do {
            let folderRows: [FolderRow] = try await supabase
                .from("note_folders")
                .select()
                .eq("user_id", value: myUserId)
                .execute()
                .value
            let noteRows: [NoteRow] = try await supabase
                .from("notes")
                .select()
                .eq("user_id", value: myUserId)
                .execute()
                .value

            var changed = false

            for row in folderRows {
                if pendingFolderDeletes.contains(row.id) { continue }
                let remoteStamp = SyncDates.parse(row.updatedAt)
                let remote = NoteFolder(
                    id: row.id,
                    name: row.name,
                    colorKey: FolderColor(rawValue: row.colorKey) ?? .purple,
                    updatedAt: remoteStamp
                )
                if let idx = store.folders.firstIndex(where: { $0.id == row.id }) {
                    if remoteStamp > store.folders[idx].updatedAt, !pendingFolderIds.contains(row.id) {
                        store.folders[idx] = remote
                        changed = true
                    }
                } else {
                    store.folders.append(remote)
                    changed = true
                }
            }

            for row in noteRows {
                if pendingNoteDeletes[row.id] != nil { continue }
                let remote = localNote(from: row)
                if let idx = store.notes.firstIndex(where: { $0.id == row.id }) {
                    if remote.updatedAt > store.notes[idx].updatedAt, !pendingNoteIds.contains(row.id) {
                        store.notes[idx] = remote
                        changed = true
                    }
                } else {
                    store.notes.append(remote)
                    changed = true
                }
                // Media already in the bucket needs no re-upload.
                for memo in remote.voiceMemos { uploadedMedia.insert(memo.filename) }
                for photo in remote.photos { uploadedMedia.insert(photo.filename) }
                downloadMissingMedia(for: remote)
            }

            persistQueues()
            if changed { store.persistAll() }
        } catch {
            print("[NotesSync] pull failed: \(error)")
        }
    }

    private func localNote(from row: NoteRow) -> Note {
        var note = Note(
            id: row.id,
            createdAt: SyncDates.parse(row.createdAt),
            body: row.body,
            voiceMemos: row.voiceMemos.map {
                NoteVoiceMemo(
                    id: UUID(uuidString: $0.id) ?? UUID(),
                    filename: $0.filename,
                    duration: $0.duration,
                    createdAt: SyncDates.parse($0.createdAt)
                )
            },
            photos: row.photos.map {
                NotePhoto(
                    id: UUID(uuidString: $0.id) ?? UUID(),
                    filename: $0.filename,
                    createdAt: SyncDates.parse($0.createdAt),
                    kind: NoteMediaKind(rawValue: $0.kind ?? "photo") ?? .photo,
                    duration: $0.duration,
                    isProof: $0.isProof ?? false
                )
            },
            tags: row.tags,
            folderId: row.folderId,
            label: row.label,
            isPinned: row.isPinned
        )
        note.updatedAt = SyncDates.parse(row.updatedAt)
        return note
    }

    // MARK: Media download

    private nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Fetch any voice memo / photo files this device doesn't have yet
    /// (fresh installs, second devices). Fire-and-forget per file.
    private func downloadMissingMedia(for note: Note) {
        var filenames: [String] = []
        filenames.append(contentsOf: note.voiceMemos.map(\.filename))
        filenames.append(contentsOf: note.photos.map(\.filename))
        guard let myUserId else { return }

        for filename in filenames {
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
                    print("[NotesSync] media download failed for \(filename): \(error)")
                }
            }
        }
    }

    // MARK: Flush

    /// Debounced flush — bursts of edits coalesce into one round-trip.
    private func scheduleFlush() {
        flushDebounce?.cancel()
        flushDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.flushNow()
        }
    }

    /// Push every queued change now. Failed items stay queued so the
    /// next launch / foreground retries them — offline edits survive.
    func flushNow() async {
        guard let myUserId, let store, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Folders first so notes never reference a missing folder row.
        for id in pendingFolderIds {
            guard let folder = store.folders.first(where: { $0.id == id }) else {
                pendingFolderIds.remove(id)
                continue
            }
            do {
                try await supabase.from("note_folders").upsert(FolderRow(
                    id: folder.id,
                    userId: myUserId,
                    name: folder.name,
                    colorKey: folder.colorKey.rawValue,
                    updatedAt: SyncDates.iso(folder.updatedAt)
                ), onConflict: "id").execute()
                pendingFolderIds.remove(id)
            } catch {
                print("[NotesSync] folder upsert failed: \(error)")
            }
        }

        for id in pendingNoteIds {
            guard let note = store.notes.first(where: { $0.id == id }) else {
                pendingNoteIds.remove(id)
                continue
            }
            guard await uploadMedia(for: note, userId: myUserId) else { continue }
            do {
                try await supabase.from("notes").upsert(NoteRow(
                    id: note.id,
                    userId: myUserId,
                    body: note.body,
                    label: note.label,
                    folderId: note.folderId,
                    isPinned: note.isPinned,
                    tags: note.tags,
                    voiceMemos: note.voiceMemos.map {
                        RemoteNoteMemo(
                            id: $0.id.uuidString,
                            filename: $0.filename,
                            duration: $0.duration,
                            createdAt: SyncDates.iso($0.createdAt)
                        )
                    },
                    photos: note.photos.map {
                        RemoteNotePhoto(
                            id: $0.id.uuidString,
                            filename: $0.filename,
                            createdAt: SyncDates.iso($0.createdAt),
                            kind: $0.kind.rawValue,
                            duration: $0.duration,
                            isProof: $0.isProof
                        )
                    },
                    createdAt: SyncDates.iso(note.createdAt),
                    updatedAt: SyncDates.iso(note.updatedAt)
                ), onConflict: "id").execute()
                pendingNoteIds.remove(id)
            } catch {
                print("[NotesSync] note upsert failed: \(error)")
            }
        }

        for (id, mediaFilenames) in pendingNoteDeletes {
            do {
                try await supabase.from("notes")
                    .delete()
                    .eq("id", value: id.uuidString)
                    .execute()
                if !mediaFilenames.isEmpty {
                    let paths = mediaFilenames.map { "\(myUserId)/\($0)" }
                    _ = try? await supabase.storage.from("note-media").remove(paths: paths)
                    for filename in mediaFilenames { uploadedMedia.remove(filename) }
                }
                pendingNoteDeletes.removeValue(forKey: id)
            } catch {
                print("[NotesSync] note delete failed: \(error)")
            }
        }

        for id in pendingFolderDeletes {
            do {
                try await supabase.from("note_folders")
                    .delete()
                    .eq("id", value: id.uuidString)
                    .execute()
                pendingFolderDeletes.remove(id)
            } catch {
                print("[NotesSync] folder delete failed: \(error)")
            }
        }

        persistQueues()
    }

    /// Upload any not-yet-synced media for a note. Returns false when
    /// an upload failed (the note stays queued and retries later).
    private func uploadMedia(for note: Note, userId: String) async -> Bool {
        var pairs: [(filename: String, contentType: String)] = []
        for memo in note.voiceMemos {
            pairs.append((memo.filename, "audio/mp4"))
        }
        for photo in note.photos {
            pairs.append((photo.filename, photo.kind == .video ? "video/mp4" : "image/jpeg"))
        }

        for (filename, contentType) in pairs where !uploadedMedia.contains(filename) {
            let local = Self.documentsDirectory.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: local) else {
                // File missing locally (e.g. cleaned up) — skip rather
                // than blocking the note's text from syncing forever.
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
                print("[NotesSync] media upload failed for \(filename): \(error)")
                return false
            }
        }
        return true
    }

    // MARK: Queue persistence

    private func loadQueues() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Keys.pendingNotes),
           let ids = try? decoder.decode([UUID].self, from: data) {
            pendingNoteIds = Set(ids)
        }
        if let data = defaults.data(forKey: Keys.pendingNoteDeletes),
           let map = try? decoder.decode([UUID: [String]].self, from: data) {
            pendingNoteDeletes = map
        }
        if let data = defaults.data(forKey: Keys.pendingFolders),
           let ids = try? decoder.decode([UUID].self, from: data) {
            pendingFolderIds = Set(ids)
        }
        if let data = defaults.data(forKey: Keys.pendingFolderDeletes),
           let ids = try? decoder.decode([UUID].self, from: data) {
            pendingFolderDeletes = Set(ids)
        }
        if let data = defaults.data(forKey: Keys.uploadedMedia),
           let names = try? decoder.decode([String].self, from: data) {
            uploadedMedia = Set(names)
        }
    }

    private func persistQueues() {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(Array(pendingNoteIds)), forKey: Keys.pendingNotes)
        defaults.set(try? encoder.encode(pendingNoteDeletes), forKey: Keys.pendingNoteDeletes)
        defaults.set(try? encoder.encode(Array(pendingFolderIds)), forKey: Keys.pendingFolders)
        defaults.set(try? encoder.encode(Array(pendingFolderDeletes)), forKey: Keys.pendingFolderDeletes)
        defaults.set(try? encoder.encode(Array(uploadedMedia)), forKey: Keys.uploadedMedia)
    }
}
