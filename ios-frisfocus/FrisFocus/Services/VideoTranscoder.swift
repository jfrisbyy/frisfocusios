//
//  VideoTranscoder.swift
//  FrisFocus
//
//  Snapchat-style outbound video compression. Every recorded clip is
//  re-encoded to capped-quality H.264 in an .mp4 container before it
//  ever touches the network — a raw 30s `.mov` capture (tens of MB)
//  drops to a few MB, and the bytes finally match the `video/mp4`
//  content type the upload declares.
//
//  The 1280×720 preset is the deliberate ceiling: full-screen-sharp on
//  a phone, light on cellular. Failure is always survivable — callers
//  fall back to the original clip so a send never dies in transcode.
//

import AVFoundation
import Foundation

nonisolated enum VideoTranscoder {
    /// Hard ceiling for a single proof upload, applied *after*
    /// compression. A clip that still exceeds this is refused with a
    /// friendly message rather than silently burning someone's data plan.
    static let maxUploadBytes: Int = 60 * 1024 * 1024

    /// Re-encode the clip at `sourceURL` to capped-quality H.264 .mp4,
    /// optimized for network streaming. Returns the new temporary file
    /// URL, or nil when the export fails (caller falls back to the
    /// original recording).
    static func compressForUpload(sourceURL: URL) async -> URL? {
        let asset = AVURLAsset(url: sourceURL)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1280x720
        ) else {
            return nil
        }
        session.shouldOptimizeForNetworkUse = true

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff-upload-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            Log.videoTranscoder.error("Export failed: \(error)")
            return nil
        }

        // Sanity check: only hand back the compressed file when it's a
        // real win (or at least not larger than the original).
        let originalSize = fileSize(at: sourceURL)
        let compressedSize = fileSize(at: outputURL)
        if compressedSize > 0, originalSize > 0, compressedSize > originalSize {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return outputURL
    }

    private static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
