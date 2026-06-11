//
//  VideoThumbnailService.swift
//  FrisFocus
//
//  Tiny shared helper that extracts a poster frame from a local video
//  file — used by journey rows and note grids to show video proofs as
//  thumbnails with a play badge. Frames are generated off the main
//  actor and cached in memory by filename.
//

import AVFoundation
import Foundation
import UIKit

enum VideoThumbnailService {
    private static let cache = NSCache<NSString, UIImage>()

    /// A poster frame for the video at `url`, capped to `maxDimension`
    /// on its longest side. Returns nil when the file is missing or
    /// undecodable (callers show their quiet placeholder).
    static func thumbnail(for url: URL, maxDimension: CGFloat = 480) async -> UIImage? {
        let key = "\(url.lastPathComponent)-\(Int(maxDimension))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        do {
            let (cgImage, _) = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600))
            let image = UIImage(cgImage: cgImage)
            cache.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }
}
