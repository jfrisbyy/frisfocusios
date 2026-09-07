//
//  MediaContainer.swift
//  FrisFocus
//
//  What a blob of media bytes ACTUALLY is.
//
//  Every upload site used to derive its content type from the caller's
//  intent — "this is a video, so it's `video/mp4`" — which is only true
//  while transcoding succeeds. When `VideoTranscoder` bails (export
//  failure, or a clip already small enough that compression isn't a
//  win) the caller falls back to the raw `.mov` capture, and those
//  QuickTime bytes were then stored at an `.mp4` path under a
//  `video/mp4` content type. Storage, the CDN and every downstream
//  player were being told something false about the file.
//
//  So the bytes speak for themselves: sniff the container and let the
//  upload declare what it is really sending.
//

import Foundation

nonisolated enum MediaContainer: String, Sendable {
    case mp4
    case quickTime
    case jpeg
    case png

    var contentType: String {
        switch self {
        case .mp4: return "video/mp4"
        case .quickTime: return "video/quicktime"
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .quickTime: return "mov"
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }

    var isVideo: Bool { self == .mp4 || self == .quickTime }

    /// Identify the container from its magic bytes. Returns nil when the
    /// data is too short or matches nothing we know — callers keep their
    /// existing assumption in that case rather than guessing wrong.
    static func sniff(_ data: Data) -> MediaContainer? {
        // A 12-byte prefix covers every signature below; copying it out
        // avoids indexing a `Data` slice whose start index isn't 0 (a
        // sliced `Data` keeps the parent's indices, which is a classic
        // source of out-of-range crashes here).
        guard data.count >= 12 else { return nil }
        let b = [UInt8](data.prefix(12))

        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return .jpeg }
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return .png }

        let box = String(bytes: b[4..<8], encoding: .ascii)
        if box == "ftyp" {
            // ISO base media file. The major brand distinguishes a real
            // MP4 from the QuickTime flavour AVCaptureMovieFileOutput
            // writes, which also carries an `ftyp` box.
            let brand = String(bytes: b[8..<12], encoding: .ascii)
            return brand == "qt  " ? .quickTime : .mp4
        }
        // Classic QuickTime layouts that lead with a top-level atom
        // instead of a brand declaration.
        if let box, ["moov", "mdat", "free", "wide", "skip", "pnot"].contains(box) {
            return .quickTime
        }
        return nil
    }

    /// The container to declare for an outbound upload: what the bytes
    /// really are, falling back to `assumed` when they're unreadable.
    static func forUpload(_ data: Data, assuming assumed: MediaContainer) -> MediaContainer {
        guard let sniffed = sniff(data) else { return assumed }
        // Never let an image sniff redirect a video upload (or vice
        // versa) — a mismatch that wide means something upstream is
        // broken, and honouring it would only hide the real bug.
        guard sniffed.isVideo == assumed.isVideo else { return assumed }
        return sniffed
    }
}
