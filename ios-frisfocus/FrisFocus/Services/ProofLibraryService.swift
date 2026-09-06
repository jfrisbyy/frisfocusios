//
//  ProofLibraryService.swift
//  FrisFocus
//
//  Writing composed proof cards into the permanent on-device library.
//  Every posted story / circle clip and every "Just save" lands here
//  with its own copy of the bytes, so the archive outlives story
//  expiry, post deletion, and pin removal. Private sends to friends
//  are never recorded.
//

import Foundation

extension Store {
    /// All archived proofs, newest first. Drives the Proof Library grid.
    var proofLibraryNewestFirst: [ProofLibraryItem] {
        proofLibrary.sorted { $0.createdAt > $1.createdAt }
    }

    /// Archive a composed proof from raw bytes (the posting paths hold
    /// `Data`). Returns the new item's id, or nil when the write fails.
    @discardableResult
    func recordProofToLibrary(
        imageData: Data?,
        type: MediaType,
        duration: Double?,
        source: ProofLibrarySource
    ) -> UUID? {
        guard let imageData else { return nil }
        let media: ComposedProofMedia = type == .video
            ? .video(imageData, duration: duration ?? 0)
            : .photo(imageData)
        return recordProofToLibrary(media, source: source)
    }

    /// Archive a composed proof. Writes the library's own copy of the
    /// bytes into Documents; a failed write records nothing so the grid
    /// never shows a broken tile.
    @discardableResult
    func recordProofToLibrary(_ media: ComposedProofMedia, source: ProofLibrarySource) -> UUID? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let item: ProofLibraryItem
        switch media {
        case .photo(let data):
            let filename = "proof-lib-\(UUID().uuidString.lowercased()).jpg"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
            } catch {
                Log.proofLibrary.error("photo write failed: \(error)")
                return nil
            }
            item = ProofLibraryItem(kind: .photo, filename: filename, source: source)
        case .video(let data, let duration):
            let filename = "proof-lib-\(UUID().uuidString.lowercased()).mp4"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
            } catch {
                Log.proofLibrary.error("video write failed: \(error)")
                return nil
            }
            item = ProofLibraryItem(kind: .video, filename: filename, duration: duration, source: source)
        }
        proofLibrary.append(item)
        // Archive entries write through immediately — a proof save must
        // never be lost to the debounce window if the app exits.
        persistAll()
        flushPendingSaves()
        return item.id
    }

    /// Note where an archived proof was pinned (task / to-do / note /
    /// milestone titles) so the viewer can say "pinned to …".
    func appendProofLibraryLabels(_ itemId: UUID?, labels: [String]) {
        guard let itemId,
              let idx = proofLibrary.firstIndex(where: { $0.id == itemId }),
              !labels.isEmpty else { return }
        for label in labels where !proofLibrary[idx].pinnedLabels.contains(label) {
            proofLibrary[idx].pinnedLabels.append(label)
        }
        persistAll()
        flushPendingSaves()
    }

    /// Permanently remove an archived proof and its media file.
    func deleteProofLibraryItem(_ itemId: UUID) {
        guard let idx = proofLibrary.firstIndex(where: { $0.id == itemId }) else { return }
        if let url = proofLibrary[idx].url {
            try? FileManager.default.removeItem(at: url)
        }
        proofLibrary.remove(at: idx)
        persistAll()
        flushPendingSaves()
    }

    // MARK: - One-time back-fill

    private static let backfillFlagKey = "proofLibrary.backfilled.v1"

    /// Import every proof that existed BEFORE the library shipped —
    /// task/to-do pins, note and milestone proof media, and the user's
    /// own posted story clips — so the archive isn't empty for early
    /// savers. Runs exactly once; each import copies the bytes into the
    /// library's own file so later pin/post deletion never breaks it.
    /// Identical bytes reached from several pins collapse into one
    /// entry with merged labels.
    func backfillProofLibraryIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.backfillFlagKey) else { return }
        defaults.set(true, forKey: Self.backfillFlagKey)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var imported: [ProofLibraryItem] = []
        var indexByByteCountAndHash: [String: Int] = [:]

        func importProof(
            at url: URL?,
            kind: NoteMediaKind,
            duration: TimeInterval?,
            source: ProofLibrarySource,
            createdAt: Date,
            labels: [String]
        ) {
            guard let url, let data = try? Data(contentsOf: url), !data.isEmpty else { return }
            let dedupeKey = "\(data.count)-\(data.hashValue)"
            if let existingIdx = indexByByteCountAndHash[dedupeKey] {
                for label in labels where !imported[existingIdx].pinnedLabels.contains(label) {
                    imported[existingIdx].pinnedLabels.append(label)
                }
                if source == .posted { imported[existingIdx].source = .posted }
                return
            }
            let ext = kind == .video ? "mp4" : "jpg"
            let filename = "proof-lib-\(UUID().uuidString.lowercased()).\(ext)"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
            } catch {
                Log.proofLibrary.error("backfill write failed: \(error)")
                return
            }
            var item = ProofLibraryItem(kind: kind, filename: filename, duration: duration, source: source)
            item.createdAt = createdAt
            item.pinnedLabels = labels
            indexByByteCountAndHash[dedupeKey] = imported.count
            imported.append(item)
        }

        // 1. Task / to-do pins.
        for pin in proofPins {
            var labels: [String] = []
            if let taskId = pin.taskId, let title = tasks.first(where: { $0.id == taskId })?.title {
                labels.append(title)
            }
            if let todoId = pin.todoId, let title = todos.first(where: { $0.id == todoId })?.title {
                labels.append(title)
            }
            importProof(
                at: pin.url, kind: pin.kind, duration: pin.duration,
                source: .saved, createdAt: pin.createdAt, labels: labels
            )
        }

        // 2. Proofs attached to notes.
        for note in notes {
            for photo in note.photos where photo.isProof {
                importProof(
                    at: photo.url, kind: photo.kind, duration: photo.duration,
                    source: .saved, createdAt: photo.createdAt, labels: ["a note"]
                )
            }
        }

        // 3. Proofs on milestone journeys (voice memos aren't proofs).
        for milestone in currentSeason.milestones {
            for attachment in milestone.attachments where attachment.isProof && attachment.kind != .voiceMemo {
                importProof(
                    at: attachment.url,
                    kind: attachment.kind == .video ? .video : .photo,
                    duration: attachment.duration,
                    source: .saved,
                    createdAt: attachment.createdAt,
                    labels: [milestone.title]
                )
            }
        }

        // 4. The user's own posted story / circle clips. Private sends
        // live in `directShares`, never here — so they stay excluded.
        for post in storyPosts where post.authorId == currentUserId {
            guard let mediaId = post.mediaId, let asset = media(by: mediaId) else { continue }
            var labels: [String] = []
            if let circleId = post.circleId, let name = circle(by: circleId)?.name {
                labels.append(name)
            }
            importProof(
                at: asset.resolvedLocalURL,
                kind: asset.type == .video ? .video : .photo,
                duration: asset.durationSeconds,
                source: .posted,
                createdAt: post.createdAt,
                labels: labels
            )
        }

        guard !imported.isEmpty else { return }
        proofLibrary.append(contentsOf: imported)
        persistAll()
        flushPendingSaves()
        Log.proofLibrary.debug("back-filled \(imported.count) existing proofs")
    }

    /// A friendly title for an attach target — used to label library
    /// entries with where they were pinned.
    func proofTargetLabel(_ target: ProofAttachTarget) -> String? {
        switch target {
        case .task(let id): return tasks.first { $0.id == id }?.title
        case .todo(let id): return todos.first { $0.id == id }?.title
        case .milestone(let id): return currentSeason.milestones.first { $0.id == id }?.title
        case .note: return "a note"
        case .cameraRoll: return nil
        }
    }
}
