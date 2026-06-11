//
//  VideoOverlayExporter.swift
//  FrisFocus
//
//  Burns the capture editor's overlay layer — the filter tint plus the
//  rendered captions / task stickers / freehand drawing — into a recorded
//  clip so recipients see exactly what the user composed, matching how
//  photos are already flattened before sending.
//
//  Pipeline:
//   1. Work out the video's *upright* pixel size (natural size with the
//      track's preferred transform applied).
//   2. On the main actor, ask the caller to render the overlay at that size
//      via SwiftUI's `ImageRenderer` (passed in as a closure).
//   3. Off the main actor, composite that overlay onto every frame with Core
//      Image through `AVVideoComposition(applyingCIFiltersWithHandler:)` and
//      re-encode with `AVAssetExportSession`. Audio passes through untouched.
//
//  The Core Image overlay is composited without a vertical flip: a
//  `CIImage(cgImage:)` is visually upright and `request.sourceImage` shares
//  the same convention, so matching extents line up directly (the proven
//  CIFilter watermarking approach).
//
//  On the cloud simulator there's no camera, so video capture — and therefore
//  this path — only runs on real hardware. Any failure returns `nil` and the
//  caller falls back to sending the raw recording.
//

import AVFoundation
import CoreImage
import UIKit

enum VideoOverlayExporter {
    /// Immutable, thread-safe hand-off to the background Core Image frame
    /// handler. `CIImage` / `CIColor` are value-immutable, so sharing them
    /// across the export queue is safe — hence the `@unchecked Sendable`.
    private final class OverlayPayload: @unchecked Sendable {
        nonisolated let overlay: CIImage?
        nonisolated let tint: CIColor?
        nonisolated let zoom: CGFloat
        nonisolated let zoomOffset: CGSize
        nonisolated let zoomCanvas: CGSize
        nonisolated init(overlay: CIImage?, tint: CIColor?, zoom: CGFloat, zoomOffset: CGSize, zoomCanvas: CGSize) {
            self.overlay = overlay
            self.tint = tint
            self.zoom = zoom
            self.zoomOffset = zoomOffset
            self.zoomCanvas = zoomCanvas
        }
    }

    /// Burns `tint` and the image produced by `overlay` into the clip at
    /// `sourceURL`, returning a fresh temporary file URL on success or `nil`
    /// when there's nothing to burn / rendering fails.
    ///
    /// - Parameters:
    ///   - sourceURL: the recorded `.mov` on disk.
    ///   - tint: optional full-frame colour wash matching the editor filter.
    ///   - zoom: the editor's pinch zoom (1 = untouched). Burned into every
    ///     frame so the export matches the on-screen framing.
    ///   - zoomOffset: the pan in canvas points (UIKit y-down).
    ///   - zoomCanvas: the editor canvas size in points — maps the pan into
    ///     video pixels via the aspect-fill preview relationship.
    ///   - overlay: builds the transparent overlay image for a given upright
    ///     pixel size. Invoked once, on the main actor, before encoding.
    @MainActor
    static func export(
        sourceURL: URL,
        tint: UIColor?,
        zoom: CGFloat = 1.0,
        zoomOffset: CGSize = .zero,
        zoomCanvas: CGSize = .zero,
        overlay: @MainActor (CGSize) -> UIImage?
    ) async -> URL? {
        guard
            let renderSize = await uprightSize(forVideoAt: sourceURL),
            renderSize.width > 1, renderSize.height > 1
        else {
            return nil
        }

        // Render the overlay on the main actor (ImageRenderer is main-actor).
        let overlayCI: CIImage?
        if let image = overlay(renderSize), let cg = image.cgImage {
            overlayCI = CIImage(cgImage: cg)
        } else {
            overlayCI = nil
        }
        let tintCI = tint.map { CIColor(color: $0) }

        // Nothing to composite → let the caller send the original clip.
        guard overlayCI != nil || tintCI != nil || zoom > 1.001 else { return nil }

        let payload = OverlayPayload(
            overlay: overlayCI,
            tint: tintCI,
            zoom: zoom,
            zoomOffset: zoomOffset,
            zoomCanvas: zoomCanvas
        )
        return await burn(sourceURL: sourceURL, payload: payload)
    }

    // MARK: - Zoom transform

    /// Scales `frame` about its center by `zoom` and pans it by `offset`
    /// (canvas points, UIKit y-down), mapped into video pixels via the
    /// aspect-fill relationship between the canvas and the frame. The
    /// result is edge-clamped and re-cropped so it always covers the
    /// extent. Shared with `ShareCardRenderer`.
    nonisolated static func zoomedFrame(
        _ frame: CIImage,
        extent: CGRect,
        zoom: CGFloat,
        offset: CGSize,
        canvas: CGSize
    ) -> CIImage {
        guard zoom > 1.001 else { return frame }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if canvas.width > 1, canvas.height > 1 {
            // Points → pixels via the aspect-filled preview: the video is
            // scaled so it covers the canvas, so one canvas point spans
            // `extent.width / displayedWidth` pixels.
            let videoAspect = extent.width / max(extent.height, 1)
            let displayedWidth = max(canvas.width, canvas.height * videoAspect)
            let pixelsPerPoint = extent.width / max(displayedWidth, 1)
            dx = offset.width * pixelsPerPoint
            dy = -offset.height * pixelsPerPoint // Core Image's y-axis points up
        }
        let transform = CGAffineTransform(translationX: extent.midX + dx, y: extent.midY + dy)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        return frame
            .transformed(by: transform)
            .clampedToExtent()
            .cropped(to: extent)
    }

    // MARK: - Background encode

    /// Builds the Core Image video composition and re-encodes the clip. Runs
    /// off the main actor so the export session is never main-actor isolated
    /// (which would otherwise trip "sending across isolation" diagnostics).
    nonisolated private static func burn(sourceURL: URL, payload: OverlayPayload) async -> URL? {
        let asset = AVURLAsset(url: sourceURL)

        let videoComposition: AVVideoComposition
        do {
            videoComposition = try await AVVideoComposition.videoComposition(with: asset) { request in
                let extent = request.sourceImage.extent
                var output = request.sourceImage

                if payload.zoom > 1.001 {
                    output = zoomedFrame(
                        output,
                        extent: extent,
                        zoom: payload.zoom,
                        offset: payload.zoomOffset,
                        canvas: payload.zoomCanvas
                    )
                }

                if let tint = payload.tint {
                    output = CIImage(color: tint).cropped(to: extent).composited(over: output)
                }

                if let overlay = payload.overlay, overlay.extent.width > 0, overlay.extent.height > 0 {
                    let scale = CGAffineTransform(
                        scaleX: extent.width / overlay.extent.width,
                        y: extent.height / overlay.extent.height
                    )
                    output = overlay.transformed(by: scale).composited(over: output)
                }

                request.finish(with: output, context: nil)
            }
        } catch {
            return nil
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        session.videoComposition = videoComposition

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        do {
            try await session.export(to: outputURL, as: .mov)
            return outputURL
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    /// The video's display size after applying its preferred transform, so
    /// the overlay is rendered to match the upright frames the CIFilter
    /// handler receives.
    nonisolated private static func uprightSize(forVideoAt url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        guard
            let naturalSize = try? await track.load(.naturalSize),
            let transform = try? await track.load(.preferredTransform)
        else {
            return nil
        }
        let transformed = naturalSize.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}
