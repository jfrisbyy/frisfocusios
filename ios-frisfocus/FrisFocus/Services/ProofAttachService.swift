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

    // MARK: - Task / To-do proof pins

    /// Pin a composed proof to a repeatable Task for the given day.
    /// The card lands beside that task's entry in the day breakdown.
    @discardableResult
    func attachProof(_ media: ComposedProofMedia, toTaskId taskId: UUID, on day: Date = Date()) -> Bool {
        guard let saved = Self.writeProofPinFile(media) else { return false }
        proofPins.append(ProofPin(
            date: Calendar.current.startOfDay(for: day),
            taskId: taskId,
            todoId: nil,
            filename: saved.filename,
            kind: saved.kind,
            duration: saved.duration
        ))
        persistAll()
        return true
    }

    /// Pin a composed proof to a one-time To-do for the given day.
    @discardableResult
    func attachProof(_ media: ComposedProofMedia, toTodoId todoId: UUID, on day: Date = Date()) -> Bool {
        guard let saved = Self.writeProofPinFile(media) else { return false }
        proofPins.append(ProofPin(
            date: Calendar.current.startOfDay(for: day),
            taskId: nil,
            todoId: todoId,
            filename: saved.filename,
            kind: saved.kind,
            duration: saved.duration
        ))
        persistAll()
        return true
    }

    /// Every proof pinned to the given task on the given local day.
    func proofPins(forTaskId taskId: UUID, on day: Date) -> [ProofPin] {
        let cal = Calendar.current
        return proofPins
            .filter { $0.taskId == taskId && cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Every proof pinned to the given to-do on the given local day.
    func proofPins(forTodoId todoId: UUID, on day: Date) -> [ProofPin] {
        let cal = Calendar.current
        return proofPins
            .filter { $0.todoId == todoId && cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Write the composed card's bytes into Documents and return the
    /// pin metadata. Returns nil when the write fails (caller pins
    /// nothing — never a broken thumbnail).
    private static func writeProofPinFile(
        _ media: ComposedProofMedia
    ) -> (filename: String, kind: NoteMediaKind, duration: TimeInterval?)? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        switch media {
        case .photo(let data):
            let filename = "proof-pin-\(UUID().uuidString.lowercased()).jpg"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
                return (filename, .photo, nil)
            } catch {
                print("[ProofPin] photo write failed: \(error)")
                return nil
            }
        case .video(let data, let duration):
            let filename = "proof-pin-\(UUID().uuidString.lowercased()).mp4"
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
                return (filename, .video, duration)
            } catch {
                print("[ProofPin] video write failed: \(error)")
                return nil
            }
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
