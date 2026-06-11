//
//  MilestoneMediaStore.swift
//  FrisFocus
//
//  Disk helper for milestone journey media. Photos live in the app's
//  Documents directory as `milestone-photo-<UUID>.jpg` — the model
//  stores just the filename (same convention as note media) so the
//  absolute path survives container moves, and the season sync layer
//  can upload/download by filename.
//

import Foundation
import UIKit

enum MilestoneMediaStore {
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Longest-edge cap applied before writing — keeps journey photos
    /// fast to load and cheap to sync.
    private static let maxDimension: CGFloat = 2048

    /// Persist a picked image as JPEG and return the attachment
    /// metadata. Returns nil if encoding or the write fails.
    static func savePhoto(_ image: UIImage) -> MilestoneAttachment? {
        let resized = downscaled(image)
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let filename = "milestone-photo-\(UUID().uuidString.lowercased()).jpg"
        let url = documentsDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return MilestoneAttachment(kind: .photo, filename: filename)
        } catch {
            print("[MilestoneMediaStore] write failed: \(error)")
            return nil
        }
    }

    /// Remove an attachment's file from disk. Safe to call when missing.
    static func delete(_ attachment: MilestoneAttachment) {
        guard let url = attachment.url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Load the UIImage for a photo attachment, or nil when the file
    /// is gone (e.g. still downloading from sync on a fresh install).
    static func image(for attachment: MilestoneAttachment) -> UIImage? {
        guard attachment.kind == .photo,
              let url = attachment.url,
              let data = try? Data(contentsOf: url) else { return nil }
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
