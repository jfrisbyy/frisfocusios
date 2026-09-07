//
//  ProofLibraryService.swift
//  FrisFocus
//
//  Writing composed proof cards into the permanent on-device library.
//  EVERY proof a person makes lands here with its own copy of the
//  bytes — posted to a story, dropped in a circle, sent privately to a
//  friend, or just kept — so the archive outlives story expiry, post
//  deletion, and pin removal, and nobody has to decide at the moment of
//  capture whether this one will matter later. `sharedTo` records where
//  it went, which is what lets the library tell "just for me" apart
//  from "this went out".
//
//  Proofs RECEIVED from friends are still never recorded: the library
//  is what you made, not what you were sent.
//

import Foundation

/// Everything known about a proof at the moment it is archived, beyond
/// the bytes themselves. Passed as one value because these travel
/// together and every one of them is optional — a proof captured from
/// nowhere in particular is still a proof worth keeping.
struct ProofLibraryContext {
    var caption: String? = nil
    var links: ProofLibraryLinks = ProofLibraryLinks()
    /// Where the proof went. Empty means it was only kept.
    var sharedTo: [ProofShareDestination] = []
    /// Human-readable names for the links, for display.
    var labels: [String] = []

    static let none = ProofLibraryContext()
}

extension Store {
    /// All archived proofs, newest first. Drives the Proof Library grid.
    var proofLibraryNewestFirst: [ProofLibraryItem] {
        proofLibrary.sorted { $0.createdAt > $1.createdAt }
    }

    /// Every archived proof tied to one task / to-do / milestone / note,
    /// newest first. Drives the proof strip on the thing itself.
    func proofLibraryItems(for links: ProofLibraryLinks) -> [ProofLibraryItem] {
        guard !links.isEmpty else { return [] }
        return proofLibraryNewestFirst.filter { item in
            (links.taskId != nil && item.taskId == links.taskId)
                || (links.todoId != nil && item.todoId == links.todoId)
                || (links.milestoneId != nil && item.milestoneId == links.milestoneId)
                || (links.noteId != nil && item.noteId == links.noteId)
        }
    }

    /// Archive a composed proof from raw bytes (the posting paths hold
    /// `Data`). Returns the new item's id, or nil when the write fails.
    @discardableResult
    func recordProofToLibrary(
        imageData: Data?,
        type: MediaType,
        duration: Double?,
        source: ProofLibrarySource,
        context: ProofLibraryContext = .none
    ) -> UUID? {
        guard let imageData else { return nil }
        let media: ComposedProofMedia = type == .video
            ? .video(imageData, duration: duration ?? 0)
            : .photo(imageData)
        return recordProofToLibrary(media, source: source, context: context)
    }

    /// Archive a composed proof. Writes the library's own copy of the
    /// bytes into Documents; a failed write records nothing so the grid
    /// never shows a broken tile.
    @discardableResult
    func recordProofToLibrary(
        _ media: ComposedProofMedia,
        source: ProofLibrarySource,
        context: ProofLibraryContext = .none
    ) -> UUID? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let item: ProofLibraryItem
        switch media {
        case .photo(let data):
            guard !data.isEmpty else {
                Log.proofLibrary.error("refusing to archive an empty photo")
                return nil
            }
            let filename = "proof-lib-\(UUID().uuidString.lowercased()).jpg"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
            } catch {
                Log.proofLibrary.error("photo write failed: \(error)")
                return nil
            }
            item = ProofLibraryItem(
                kind: .photo,
                filename: filename,
                source: source,
                pinnedLabels: context.labels,
                caption: context.caption,
                links: context.links,
                sharedTo: context.sharedTo
            )
        case .video(let data, let duration):
            guard !data.isEmpty else {
                Log.proofLibrary.error("refusing to archive an empty clip")
                return nil
            }
            // The extension has to match what the bytes actually are, or
            // AVPlayer refuses the file and the tile plays nothing.
            let container = MediaContainer.forUpload(data, assuming: .mp4)
            let filename = "proof-lib-\(UUID().uuidString.lowercased()).\(container.fileExtension)"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
            } catch {
                Log.proofLibrary.error("video write failed: \(error)")
                return nil
            }
            item = ProofLibraryItem(
                kind: .video,
                filename: filename,
                duration: duration,
                source: source,
                pinnedLabels: context.labels,
                caption: context.caption,
                links: context.links,
                sharedTo: context.sharedTo
            )
        }
        proofLibrary.append(item)
        // Archive entries write through immediately — a proof save must
        // never be lost to the debounce window if the app exits.
        persistAll()
        flushPendingSaves()
        proofLibrarySync?.proofRecorded(item.id)
        return item.id
    }

    /// The media for an archived proof has reached the account.
    func markProofLibraryUploaded(_ itemId: UUID, mediaPath: String) {
        guard let idx = proofLibrary.firstIndex(where: { $0.id == itemId }) else { return }
        proofLibrary[idx].mediaPath = mediaPath
        proofLibrary[idx].uploadedAt = Date()
        persistAll()
    }

    /// Attach a link to an already-archived proof — the attach flow
    /// picks its destination AFTER the proof is saved, so the ids arrive
    /// later than the bytes do.
    func linkProofLibraryItem(_ itemId: UUID?, to target: ProofAttachTarget) {
        guard let itemId, let idx = proofLibrary.firstIndex(where: { $0.id == itemId }) else { return }
        switch target {
        case .task(let id): proofLibrary[idx].taskId = id
        case .todo(let id): proofLibrary[idx].todoId = id
        case .milestone(let id): proofLibrary[idx].milestoneId = id
        case .note(let id): proofLibrary[idx].noteId = id
        case .cameraRoll: return
        }
        if let label = proofTargetLabel(target), !proofLibrary[idx].pinnedLabels.contains(label) {
            proofLibrary[idx].pinnedLabels.append(label)
        }
        persistAll()
        flushPendingSaves()
        proofLibrarySync?.proofUpdated(itemId)
    }

    /// Record that an archived proof also went somewhere.
    func markProofLibraryShared(_ itemId: UUID?, to destinations: [ProofShareDestination]) {
        guard let itemId, let idx = proofLibrary.firstIndex(where: { $0.id == itemId }),
              !destinations.isEmpty else { return }
        for destination in destinations where !proofLibrary[idx].sharedTo.contains(destination) {
            proofLibrary[idx].sharedTo.append(destination)
        }
        persistAll()
        flushPendingSaves()
        proofLibrarySync?.proofUpdated(itemId)
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
        // Take the remote copy with it. A reinstall that resurrected a
        // proof the person deliberately removed would be worse than not
        // syncing at all.
        proofLibrarySync?.proofDeleted(itemId, mediaPath: proofLibrary[idx].mediaPath)
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
