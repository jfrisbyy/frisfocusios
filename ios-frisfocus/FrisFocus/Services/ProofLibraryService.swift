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
                print("[ProofLibrary] photo write failed: \(error)")
                return nil
            }
            item = ProofLibraryItem(kind: .photo, filename: filename, source: source)
        case .video(let data, let duration):
            let filename = "proof-lib-\(UUID().uuidString.lowercased()).mp4"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
            } catch {
                print("[ProofLibrary] video write failed: \(error)")
                return nil
            }
            item = ProofLibraryItem(kind: .video, filename: filename, duration: duration, source: source)
        }
        proofLibrary.append(item)
        persistAll()
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
    }

    /// Permanently remove an archived proof and its media file.
    func deleteProofLibraryItem(_ itemId: UUID) {
        guard let idx = proofLibrary.firstIndex(where: { $0.id == itemId }) else { return }
        if let url = proofLibrary[idx].url {
            try? FileManager.default.removeItem(at: url)
        }
        proofLibrary.remove(at: idx)
        persistAll()
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
