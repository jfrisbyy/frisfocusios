//
//  ProofLibraryItem.swift
//  FrisFocus
//
//  A permanent, on-device archive entry for a composed proof card the
//  user either posted (story / circle clip — kept even after the 24h
//  story expires) or saved through "Just save". Proofs sent privately
//  to friends are deliberately never archived here. The media bytes
//  live in the Documents directory under `filename` as the item's own
//  copy, so deleting a post or pin never breaks the library.
//

import Foundation

/// How a proof entered the library — posted publicly (story or circle
/// clip) or kept on-device via "Just save" / pinning.
enum ProofLibrarySource: String, Codable {
    case posted
    case saved
}

struct ProofLibraryItem: Codable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// Photo or video clip.
    var kind: NoteMediaKind = .photo
    /// File name of the library's own copy inside Documents.
    var filename: String
    /// Clip length; nil for photos.
    var duration: TimeInterval? = nil
    var source: ProofLibrarySource = .saved
    /// Human-readable names of everything this proof was pinned to at
    /// save time (task / to-do / milestone / note titles).
    var pinnedLabels: [String] = []

    var url: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(filename)
    }
}
