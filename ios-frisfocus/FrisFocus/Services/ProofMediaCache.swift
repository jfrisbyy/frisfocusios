//
//  ProofMediaCache.swift
//  FrisFocus
//
//  A disk cache for private proof media, keyed by the *storage path*
//  (which is stable forever) rather than the signed URL (which changes
//  on every signature). This is what lets a proof open instantly: once
//  its bytes are on disk — from a previous view or a quiet prefetch —
//  the player reads the local file and never shows a network spinner.
//
//  Files live under Caches/ProofMedia so the system can reclaim them
//  under pressure; everything here is re-fetchable from storage.
//

import CryptoKit
import Foundation

nonisolated enum ProofMediaCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProofMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(forMediaPath path: String, kind: ProofMediaKind) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        let ext = kind == .video ? "mp4" : "jpg"
        return directory.appendingPathComponent(name).appendingPathExtension(ext)
    }

    /// The local file for this proof if its bytes are already cached,
    /// else nil. A hit means the player can open with zero network.
    static func cachedFileURL(forMediaPath path: String, kind: ProofMediaKind) -> URL? {
        let url = fileURL(forMediaPath: path, kind: kind)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Store freshly downloaded proof bytes; returns the local file URL.
    @discardableResult
    static func store(_ data: Data, forMediaPath path: String, kind: ProofMediaKind) -> URL? {
        let url = fileURL(forMediaPath: path, kind: kind)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.proofMediaCache.error("Write failed for \(path): \(error)")
            return nil
        }
    }

    /// Download a proof's bytes from its signed URL into the cache.
    /// No-op when already cached. Returns the local file URL.
    @discardableResult
    static func download(from signedURL: URL, forMediaPath path: String, kind: ProofMediaKind) async -> URL? {
        if let hit = cachedFileURL(forMediaPath: path, kind: kind) { return hit }
        do {
            let (data, _) = try await URLSession.shared.data(from: signedURL)
            return store(data, forMediaPath: path, kind: kind)
        } catch {
            Log.proofMediaCache.error("Download failed for \(path): \(error)")
            return nil
        }
    }
}
