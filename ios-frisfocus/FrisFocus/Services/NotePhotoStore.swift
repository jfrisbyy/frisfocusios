//
//  NotePhotoStore.swift
//  FrisFocus
//
//  Disk helper for photos attached to Notes. Photos live in the app's
//  Documents directory as `note-photo-<UUID>.jpg` — the Note model
//  stores just the filename (like voice memos) so the absolute path
//  survives container moves between installs.
//

import Foundation
import UIKit

enum NotePhotoStore {
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Longest-edge cap applied before writing — keeps note photos
    /// fast to load, cheap to sync, and well under storage limits.
    private static let maxDimension: CGFloat = 2048

    /// Persist a picked image as JPEG and return the `NotePhoto`
    /// metadata to attach to the note. Returns nil if encoding or the
    /// write fails (caller shows nothing — never a broken thumbnail).
    static func save(_ image: UIImage) -> NotePhoto? {
        let resized = downscaled(image)
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let filename = "note-photo-\(UUID().uuidString.lowercased()).jpg"
        let url = documentsDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return NotePhoto(filename: filename)
        } catch {
            print("[NotePhotoStore] write failed: \(error)")
            return nil
        }
    }

    /// Remove a photo's file from disk. Safe to call when missing.
    static func delete(_ photo: NotePhoto) {
        guard let url = photo.url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Load the UIImage for a photo, or nil when the file is gone
    /// (e.g. still downloading from sync on a fresh install).
    static func image(for photo: NotePhoto) -> UIImage? {
        guard let url = photo.url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
