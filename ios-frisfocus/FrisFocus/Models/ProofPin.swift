//
//  ProofPin.swift
//  FrisFocus
//
//  A composed proof card pinned to a specific Task or To-do for a
//  specific day. The media file (the clean card — overlay, captions,
//  stickers baked in) lives on disk in the Documents directory under
//  `filename`; the pin records which item it documents and the local
//  day it belongs to, so the stats day breakdown can surface the proof
//  right beside the entry it backs.
//

import Foundation

struct ProofPin: Codable, Identifiable {
    var id: UUID = UUID()
    /// The local day this proof documents (start-of-day comparisons).
    var date: Date
    /// Exactly one of `taskId` / `todoId` is set.
    var taskId: UUID?
    var todoId: UUID?
    var filename: String
    /// Photo or video clip. Defaults so early payloads decode.
    var kind: NoteMediaKind = .photo
    /// Clip length; nil for photos.
    var duration: TimeInterval? = nil
    var createdAt: Date = Date()

    var url: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(filename)
    }
}
