//
//  MediaAsset+Resolve.swift
//  FrisFocus
//
//  Container-safe file resolution for saved media. `localURL` /
//  `thumbnailURL` are persisted as absolute paths, but the app's
//  sandbox container moves on every install/update — freezing those
//  paths silently breaks every saved preview. These helpers re-anchor
//  a stored URL by its file name inside the *current* container's
//  media directory, so renderers keep finding the bytes across
//  updates and reinstalls.
//

import Foundation

extension MediaAsset {
    /// The app's media directory in the *current* container. All
    /// captured photos/videos (and their poster frames) live here.
    static var mediaDirectory: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("FrisFocusMedia", isDirectory: true)
    }

    /// The on-disk media file, re-anchored to the current container if
    /// the stored absolute path went stale. `nil` when no file exists.
    var resolvedLocalURL: URL? {
        Self.resolveFile(localURL)
    }

    /// The on-disk thumbnail/poster file, re-anchored like
    /// `resolvedLocalURL`. `nil` when no file exists.
    var resolvedThumbnailURL: URL? {
        Self.resolveFile(thumbnailURL)
    }

    /// Resolve a stored file URL by checking the exact path first,
    /// then falling back to the same file name inside the current
    /// media directory. Non-file URLs pass through untouched.
    private static func resolveFile(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard url.isFileURL else { return url }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return url }
        guard let dir = mediaDirectory else { return nil }
        let candidate = dir.appendingPathComponent(url.lastPathComponent)
        return fm.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
