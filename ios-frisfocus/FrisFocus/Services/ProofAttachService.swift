//
//  ProofAttachService.swift
//  FrisFocus
//
//  Writing composed proof cards into the rest of the app: a milestone's
//  journey timeline or a note's media. The composed CLEAN card (overlay,
//  captions, stickers baked in) is persisted to the Documents directory
//  through the same stores as plain media, flagged `isProof` so the UI
//  can give it the signature edge. Everything is local — the attachment
//  outlives the 24h story.
//

import Foundation

extension Store {
    // MARK: - Attaching

    /// Write a composed proof onto a milestone's journey timeline.
    /// Returns false when the milestone is gone or the write fails.
    @discardableResult
    func attachProof(_ media: ComposedProofMedia, toMilestone milestoneId: UUID) -> Bool {
        guard let idx = currentSeason.milestones.firstIndex(where: { $0.id == milestoneId }) else { return false }
        let attachment: MilestoneAttachment?
        switch media {
        case .photo(let data):
            attachment = MilestoneMediaStore.saveProofPhotoData(data)
        case .video(let data, let duration):
            attachment = MilestoneMediaStore.saveProofVideoData(data, duration: duration)
        }
        guard let attachment else { return false }
        currentSeason.milestones[idx].attachments.append(attachment)
        persistAll()
        return true
    }

    /// Write a composed proof into an existing note's media.
    /// Returns false when the note is gone or the write fails.
    @discardableResult
    func attachProof(_ media: ComposedProofMedia, toNote noteId: UUID) -> Bool {
        guard let note = notes.first(where: { $0.id == noteId }),
              let saved = saveProofNoteMedia(media)
        else { return false }
        var updated = note
        updated.photos.append(saved)
        updateNote(updated)
        return true
    }

    /// Persist a composed proof as note media WITHOUT attaching it to a
    /// stored note — the composer flow appends it to its in-progress
    /// draft instead.
    func saveProofNoteMedia(_ media: ComposedProofMedia) -> NotePhoto? {
        switch media {
        case .photo(let data):
            return NotePhotoStore.saveProofPhotoData(data)
        case .video(let data, let duration):
            return NotePhotoStore.saveProofVideoData(data, duration: duration)
        }
    }

    // MARK: - Picker data

    /// Milestones for the attach picker — in-motion first (week order),
    /// landed ones after, so the live journeys lead.
    var attachableMilestones: [Milestone] {
        let ordered = journeyMilestones
        return ordered.filter { !$0.isCompleted } + ordered.filter { $0.isCompleted }
    }

    /// Notes for the attach picker, newest first.
    var attachableNotes: [Note] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }
}
