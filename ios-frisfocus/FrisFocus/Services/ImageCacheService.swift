//
//  ImageCacheService.swift
//  FrisFocus
//
//  The shared image cache behind every avatar and remote photo. Bare
//  `AsyncImage` re-downloads on every appearance and forgets everything
//  on relaunch; this two-tier cache (NSCache in memory, files on disk
//  under Caches/) downloads an image once and then serves it instantly
//  everywhere — including offline and across launches.
//
//  `CachedImage` is the drop-in SwiftUI replacement: the same
//  content/placeholder shape as `AsyncImage`, but a memory hit renders
//  synchronously on the first frame (no placeholder flash at all).
//
//  Keys are a SHA-256 of the URL string, so arbitrary remote URLs map
//  to safe, stable filenames. Disk lives in Caches — the system may
//  reclaim it under pressure, which is exactly right for re-fetchable
//  media.
//

import CryptoKit
import SwiftUI
import UIKit

// MARK: - Cache

nonisolated enum ImageCache {
    /// In-memory tier. NSCache is thread-safe and auto-evicts under
    /// memory pressure; UIImage is immutable/Sendable.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    private static var diskDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func diskURL(for url: URL) -> URL {
        diskDirectory.appendingPathComponent(cacheKey(for: url)).appendingPathExtension("img")
    }

    /// Memory-tier lookup — synchronous, safe to call during view body
    /// so a cached avatar renders on its very first frame.
    static func cached(for url: URL) -> UIImage? {
        memory.object(forKey: cacheKey(for: url) as NSString)
    }

    /// Full lookup: memory → disk → network (stored on success).
    static func image(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)
        if let hit = memory.object(forKey: key as NSString) {
            return hit
        }

        let fileURL = diskURL(for: url)
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let img = UIImage(data: data) else { return nil }
            memory.setObject(img, forKey: key as NSString)
            try? data.write(to: fileURL, options: .atomic)
            return img
        } catch {
            return nil
        }
    }

    /// Warm the cache for a URL without needing the image back —
    /// used by prefetchers so the next open is instant.
    static func prefetch(_ url: URL) async {
        _ = await image(for: url)
    }
}

// MARK: - Drop-in view

/// `AsyncImage`, but cached. Same call shape:
///
///     CachedImage(url: url) { image in
///         image.resizable().scaledToFill()
///     } placeholder: {
///         initials
///     }
///
/// A memory-cached image renders synchronously — no placeholder flash.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loaded: UIImage?
    /// True when the last fetch came back empty — the placeholder gains
    /// a quiet retry glyph so "failed" never masquerades as "loading".
    @State private var failed = false
    @State private var attempt = 0

    private var resolved: UIImage? {
        if let loaded { return loaded }
        guard let url else { return nil }
        return ImageCache.cached(for: url)
    }

    var body: some View {
        ZStack {
            if let image = resolved {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .overlay {
                        if failed {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.35), radius: 2)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .task(id: "\(url?.absoluteString ?? "")#\(attempt)") {
            guard let url, resolved == nil else { return }
            let image = await ImageCache.image(for: url)
            loaded = image
            failed = (image == nil)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                // A tap on a failed image re-attempts — simultaneous, so
                // the row's own tap still fires; a no-op unless failed.
                if failed {
                    failed = false
                    attempt += 1
                }
            }
        )
    }
}
