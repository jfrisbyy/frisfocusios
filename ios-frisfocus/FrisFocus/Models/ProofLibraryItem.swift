//
//  ProofLibraryItem.swift
//  FrisFocus
//
//  A permanent archive entry for a composed proof card. Every proof a
//  person makes lands here — posted to a story, dropped in a circle,
//  sent privately to a friend, or simply kept — because the thing that
//  makes an archive worth having is not having to decide, at the moment
//  of capture, whether this one will matter later.
//
//  Proofs RECEIVED from friends are never archived here: the library is
//  what you made, not what you were sent.
//
//  The media bytes live in the Documents directory under `filename` as
//  the item's own copy, so deleting a post, a pin, or a message never
//  breaks the library.
//

import Foundation

/// How a proof entered the library — posted publicly (story or circle
/// clip) or kept on-device via "Just save" / pinning.
enum ProofLibrarySource: String, Codable, Sendable {
    case posted
    case saved
}

/// Where a proof went beyond the library itself. Empty means it was
/// only ever kept — which is the clear distinction the library needs to
/// be able to draw: "just for me" versus "this one went out".
enum ProofShareDestination: String, Codable, Sendable, CaseIterable, Identifiable {
    case story
    case circle
    case friend

    var id: String { rawValue }

    var label: String {
        switch self {
        case .story: return "Story"
        case .circle: return "Circle"
        case .friend: return "Sent"
        }
    }

    var symbolName: String {
        switch self {
        case .story: return "sun.max.fill"
        case .circle: return "person.3.fill"
        case .friend: return "paperplane.fill"
        }
    }
}

/// What a proof is tied to. Real ids, not display names: the library
/// linked proofs to their task by TITLE, which made "show me every
/// proof for this milestone" unanswerable and orphaned a task's proofs
/// the moment it was renamed.
struct ProofLibraryLinks: Equatable, Sendable {
    var taskId: UUID?
    var todoId: UUID?
    var milestoneId: UUID?
    var noteId: UUID?

    var isEmpty: Bool {
        taskId == nil && todoId == nil && milestoneId == nil && noteId == nil
    }
}

struct ProofLibraryItem: Codable, Identifiable, Equatable {
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
    /// save time. Kept for display and for entries created before the
    /// id columns existed; `links` is what filtering uses.
    var pinnedLabels: [String] = []

    /// The caption composed with the proof, if any.
    var caption: String? = nil

    // Real links — see `ProofLibraryLinks`.
    var taskId: UUID? = nil
    var todoId: UUID? = nil
    var milestoneId: UUID? = nil
    var noteId: UUID? = nil

    /// Where this proof was sent. Empty = kept only.
    var sharedTo: [ProofShareDestination] = []

    // MARK: Account sync
    //
    // The library is local-first: the bytes are written to Documents
    // immediately and the upload happens later, on Wi-Fi. These record
    // how far that has got.

    /// Storage object path once the media has been uploaded.
    var mediaPath: String? = nil
    /// When the row + media reached the server. Nil = still local-only.
    var uploadedAt: Date? = nil

    var links: ProofLibraryLinks {
        ProofLibraryLinks(taskId: taskId, todoId: todoId, milestoneId: milestoneId, noteId: noteId)
    }

    /// True when this proof only ever existed for its author.
    var isPrivateToMe: Bool { sharedTo.isEmpty }

    var url: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(filename)
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: NoteMediaKind = .photo,
        filename: String,
        duration: TimeInterval? = nil,
        source: ProofLibrarySource = .saved,
        pinnedLabels: [String] = [],
        caption: String? = nil,
        links: ProofLibraryLinks = ProofLibraryLinks(),
        sharedTo: [ProofShareDestination] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.filename = filename
        self.duration = duration
        self.source = source
        self.pinnedLabels = pinnedLabels
        self.caption = caption
        self.taskId = links.taskId
        self.todoId = links.todoId
        self.milestoneId = links.milestoneId
        self.noteId = links.noteId
        self.sharedTo = sharedTo
    }

    // MARK: Codable
    //
    // Written by hand rather than synthesized. Synthesized `Decodable`
    // does NOT fall back to a property's default value when the key is
    // absent — it throws — so every field added after the first release
    // would fail to decode every archive entry already on disk. The
    // Store salvages per-element, which here would mean silently losing
    // the entire library the first time it launched a newer build.

    enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, filename, duration, source, pinnedLabels
        case caption, taskId, todoId, milestoneId, noteId, sharedTo
        case mediaPath, uploadedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `filename` is the one field an entry cannot be without: no
        // filename means no bytes, and the tile would render as a hole.
        filename = try c.decode(String.self, forKey: .filename)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        // Enums decode through their raw strings so a value written by a
        // NEWER build — a destination or media kind this build has never
        // heard of — degrades to the default instead of throwing. A
        // throw here would cost the whole entry, since the Store
        // salvages per element and this IS the element.
        let rawKind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        kind = rawKind.flatMap(NoteMediaKind.init(rawValue:)) ?? .photo
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        let rawSource = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
        source = rawSource.flatMap(ProofLibrarySource.init(rawValue:)) ?? .saved
        pinnedLabels = try c.decodeIfPresent([String].self, forKey: .pinnedLabels) ?? []
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        taskId = try c.decodeIfPresent(UUID.self, forKey: .taskId)
        todoId = try c.decodeIfPresent(UUID.self, forKey: .todoId)
        milestoneId = try c.decodeIfPresent(UUID.self, forKey: .milestoneId)
        noteId = try c.decodeIfPresent(UUID.self, forKey: .noteId)
        let rawShared = (try? c.decodeIfPresent([String].self, forKey: .sharedTo)) ?? nil
        sharedTo = (rawShared ?? []).compactMap(ProofShareDestination.init(rawValue:))
        mediaPath = try c.decodeIfPresent(String.self, forKey: .mediaPath)
        uploadedAt = try c.decodeIfPresent(Date.self, forKey: .uploadedAt)
    }
}
