//
//  CaptureDraftStore.swift
//  FrisFocus
//
//  Persists a single capture-editor draft to disk so closing the editor
//  never destroys work. Saving writes the media (photo JPEG or the
//  recorded video file), the chosen filter, every caption block, every
//  task sticker, and the freehand drawing; the camera then offers a
//  "Draft" chip that restores the whole composition exactly as it was.
//
//  One draft at a time (Snapchat-style "keep your latest"): saving a
//  new draft replaces the previous one; posting or discarding a
//  restored draft clears it.
//

import PencilKit
import SwiftUI
import UIKit

// MARK: - Restored editor state

/// Everything the editor needs to pick a draft back up: the media as a
/// fresh `CaptureResult` plus the full overlay/filter state.
struct CaptureEditorDraft {
    let result: CaptureResult
    let filter: CaptureFilter
    let captions: [CaptionBlock]
    let stickers: [TaskStickerBlock]
    let drawing: PKDrawing
}

// MARK: - Codable wire shapes

private nonisolated struct DraftColor: Codable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double
}

private nonisolated struct DraftCaption: Codable {
    let text: String
    let x: Double
    let y: Double
    let style: String
    let scale: Double
    let rotationDegrees: Double
    let color: DraftColor?
}

private nonisolated struct DraftSticker: Codable {
    let title: String
    let isChecked: Bool
    let isTask: Bool
    let isMust: Bool
    let x: Double
    let y: Double
    let scale: Double
    let rotationDegrees: Double
}

private nonisolated struct DraftManifest: Codable {
    let isVideo: Bool
    let videoDuration: Double?
    let filter: String
    let captions: [DraftCaption]
    let stickers: [DraftSticker]
    let savedAt: Date
}

// MARK: - Store

@MainActor
enum CaptureDraftStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CaptureDraft", isDirectory: true)
    }

    private static var manifestURL: URL { directory.appendingPathComponent("draft.json") }
    private static var photoURL: URL { directory.appendingPathComponent("media.jpg") }
    private static var videoURL: URL { directory.appendingPathComponent("media.mov") }
    private static var thumbURL: URL { directory.appendingPathComponent("thumb.jpg") }

    /// True when a resumable draft exists on disk.
    static var hasDraft: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    /// A small thumbnail of the drafted media for the camera's chip.
    static func thumbnail() -> UIImage? {
        let source = FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : photoURL
        guard let image = UIImage(contentsOfFile: source.path) else { return nil }
        return image.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? image
    }

    // MARK: Save

    /// Persist the current editor session as the (single) draft.
    ///
    /// Returns whether the draft actually landed on disk. This used to
    /// return Void and swallow every error, while the caller played a
    /// success haptic and closed the editor — so a copy that failed
    /// (no space, protected data unavailable) threw the person's work
    /// away and told them it was saved.
    @discardableResult
    static func save(
        result: CaptureResult,
        filter: CaptureFilter,
        captions: [CaptionBlock],
        stickers: [TaskStickerBlock],
        drawing: PKDrawing
    ) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var isVideo = false
            var videoDuration: Double? = nil

            switch result {
            case .photo(let image):
                try? FileManager.default.removeItem(at: videoURL)
                try? FileManager.default.removeItem(at: thumbURL)
                guard let data = image.jpegData(compressionQuality: 0.92) else {
                    Log.captureDraft.error("Save failed: photo would not encode")
                    return false
                }
                try data.write(to: photoURL, options: .atomic)

            case .video(let url, let thumb, let duration):
                isVideo = true
                videoDuration = duration
                try? FileManager.default.removeItem(at: photoURL)
                // A re-saved restored draft already lives at the target
                // path — copying a file onto itself would throw.
                if url.standardizedFileURL != videoURL.standardizedFileURL {
                    try? FileManager.default.removeItem(at: videoURL)
                    try FileManager.default.copyItem(at: url, to: videoURL)
                }
                if let thumbData = thumb?.jpegData(compressionQuality: 0.8) {
                    try? thumbData.write(to: thumbURL, options: .atomic)
                }
            }

            let manifest = DraftManifest(
                isVideo: isVideo,
                videoDuration: videoDuration,
                filter: filter.rawValue,
                captions: captions.map(encode(_:)),
                stickers: stickers.map(encode(_:)),
                savedAt: Date()
            )
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL, options: .atomic)

            let drawingData = drawing.dataRepresentation()
            try drawingData.write(to: directory.appendingPathComponent("drawing.data"), options: .atomic)
            return true
        } catch {
            Log.captureDraft.error("Save failed: \(error)")
            return false
        }
    }

    // MARK: Load

    /// Rebuild the full editor state from disk, or nil when no draft
    /// exists (or the media has gone missing).
    static func load() -> CaptureEditorDraft? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(DraftManifest.self, from: data) else { return nil }

        let result: CaptureResult
        if manifest.isVideo {
            guard FileManager.default.fileExists(atPath: videoURL.path) else { return nil }
            let thumb = UIImage(contentsOfFile: thumbURL.path)
            result = .video(url: videoURL, thumbnail: thumb, duration: manifest.videoDuration ?? 0)
        } else {
            guard let image = UIImage(contentsOfFile: photoURL.path) else { return nil }
            result = .photo(image)
        }

        var drawing = PKDrawing()
        if let drawingData = try? Data(contentsOf: directory.appendingPathComponent("drawing.data")),
           let restored = try? PKDrawing(data: drawingData) {
            drawing = restored
        }

        return CaptureEditorDraft(
            result: result,
            filter: CaptureFilter(rawValue: manifest.filter) ?? .original,
            captions: manifest.captions.map(decode(_:)),
            stickers: manifest.stickers.map(decode(_:)),
            drawing: drawing
        )
    }

    /// Remove the draft entirely (after posting or an explicit discard).
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Mapping

    private static func encode(_ block: CaptionBlock) -> DraftCaption {
        DraftCaption(
            text: block.text,
            x: block.position.x,
            y: block.position.y,
            style: block.style.rawValue,
            scale: block.scale,
            rotationDegrees: block.rotation.degrees,
            color: block.color.map(encode(_:))
        )
    }

    private static func decode(_ draft: DraftCaption) -> CaptionBlock {
        CaptionBlock(
            text: draft.text,
            position: CGPoint(x: draft.x, y: draft.y),
            style: CaptionStyle(rawValue: draft.style) ?? .classic,
            scale: draft.scale,
            rotation: .degrees(draft.rotationDegrees),
            color: draft.color.map { Color(red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a) }
        )
    }

    private static func encode(_ block: TaskStickerBlock) -> DraftSticker {
        DraftSticker(
            title: block.title,
            isChecked: block.isChecked,
            isTask: block.isTask,
            isMust: block.isMust,
            x: block.position.x,
            y: block.position.y,
            scale: block.scale,
            rotationDegrees: block.rotation.degrees
        )
    }

    private static func decode(_ draft: DraftSticker) -> TaskStickerBlock {
        TaskStickerBlock(
            title: draft.title,
            isChecked: draft.isChecked,
            isTask: draft.isTask,
            isMust: draft.isMust,
            position: CGPoint(x: draft.x, y: draft.y),
            scale: draft.scale,
            rotation: .degrees(draft.rotationDegrees)
        )
    }

    private static func encode(_ color: Color) -> DraftColor {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return DraftColor(r: r, g: g, b: b, a: a)
    }
}
