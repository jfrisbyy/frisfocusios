//
//  ShareCardRenderer.swift
//  FrisFocus
//
//  Flattens the share overlay into captured media — one renderer, a
//  destination parameter, two card subjects (the day card and the
//  milestone card via `ShareCardComposition`). Identical overlay
//  composition for in-app and external shares; the attribution line is
//  added only when the result leaves the app (external share or
//  camera-roll save).
//
//  Photos: normalized upright → center-cropped to the 9:16 story ratio
//  (preserving capture resolution) → the overlay is rendered at the
//  crop's pixel size with SwiftUI's ImageRenderer and drawn on top.
//
//  Videos: the overlay is rendered as TWO transparent frames with
//  identical layout — the chrome (text, chips, attribution, scrim) and
//  the mark alone (the sun, or the milestone flag). Core Image
//  composites both onto every frame via AVVideoComposition; the mark
//  layer glides up into its computed position over the clip's first
//  ~1.2 s (eased, fading in), giving recorded clips the signature
//  rise. Reduced-motion renders it static.
//
//  Everything composites locally — zero API calls anywhere.
//

import AVFoundation
import CoreImage
import SwiftUI
import UIKit

enum ShareCardRenderer {
    /// How long the mark's rise lasts at the start of a clip.
    private static let riseDuration: Double = 1.2

    // MARK: - Overlay rendering

    /// Renders the overlay at `pixelSize`, laying out at a phone-like
    /// logical width so typography matches what the viewfinder showed.
    @MainActor
    static func overlayImage(
        composition: ShareCardComposition,
        username: String,
        attributed: Bool,
        layer: ShareOverlayLayer,
        pixelSize: CGSize
    ) -> UIImage? {
        guard pixelSize.width > 1, pixelSize.height > 1 else { return nil }
        let logicalWidth: CGFloat = 390
        let logicalHeight = logicalWidth * pixelSize.height / pixelSize.width

        let content = ShareCompositionOverlayView(
            composition: composition,
            mode: .render(attributed: attributed),
            username: username,
            layer: layer,
            bottomPadding: 26
        )
        .frame(width: logicalWidth, height: logicalHeight)

        let renderer = ImageRenderer(content: content)
        renderer.scale = pixelSize.width / logicalWidth
        renderer.isOpaque = false
        return renderer.uiImage
    }

    // MARK: - Photo compositing

    /// Flattens the overlay onto a captured photo. Returns the final
    /// 9:16 story-ratio image at full capture resolution. `editLayer`
    /// supplies the user's edits (captions, task stickers, drawing)
    /// rendered at the crop's pixel size — drawn between the photo and
    /// the day-overlay chrome so attribution is never obscured.
    /// `zoom` / `zoomOffset` (card points) / `zoomCanvas` (the card's
    /// point size) bake the preview's pinch framing into the photo.
    @MainActor
    static func compositePhoto(
        _ photo: UIImage,
        composition: ShareCardComposition,
        username: String,
        attributed: Bool,
        zoom: CGFloat = 1.0,
        zoomOffset: CGSize = .zero,
        zoomCanvas: CGSize = .zero,
        editLayer: ((CGSize) -> UIImage?)? = nil
    ) -> UIImage? {
        guard let base = normalizedStoryCrop(photo) else { return nil }
        let overlay = overlayImage(
            composition: composition,
            username: username,
            attributed: attributed,
            layer: .all,
            pixelSize: base.size
        )
        let edits = editLayer?(base.size)
        let isZoomed = zoom > 1.001
        guard overlay != nil || edits != nil || isZoomed else { return base }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: base.size)
            if isZoomed {
                // The crop shares the card's 9:16 aspect, so the
                // points→pixels mapping is a single uniform ratio.
                let pixelsPerPoint = zoomCanvas.width > 1 ? base.size.width / zoomCanvas.width : 0
                let drawSize = CGSize(width: base.size.width * zoom, height: base.size.height * zoom)
                let origin = CGPoint(
                    x: rect.midX - drawSize.width / 2 + zoomOffset.width * pixelsPerPoint,
                    y: rect.midY - drawSize.height / 2 + zoomOffset.height * pixelsPerPoint
                )
                base.draw(in: CGRect(origin: origin, size: drawSize))
            } else {
                base.draw(in: rect)
            }
            edits?.draw(in: rect)
            overlay?.draw(in: rect)
        }
    }

    /// Draws the photo upright at pixel scale and center-crops it to
    /// 9:16, keeping the maximum possible resolution.
    private static func normalizedStoryCrop(_ image: UIImage) -> UIImage? {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        guard pixelSize.width > 1, pixelSize.height > 1 else { return nil }

        let targetAspect: CGFloat = 9.0 / 16.0
        let currentAspect = pixelSize.width / pixelSize.height

        var cropSize = pixelSize
        if currentAspect > targetAspect {
            cropSize.width = (pixelSize.height * targetAspect).rounded(.down)
        } else {
            cropSize.height = (pixelSize.width / targetAspect).rounded(.down)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: cropSize, format: format)
        return renderer.image { _ in
            // Drawing the UIImage honors its orientation, normalizing
            // the pixels upright; offsetting centers the crop.
            let origin = CGPoint(
                x: -((pixelSize.width - cropSize.width) / 2),
                y: -((pixelSize.height - cropSize.height) / 2)
            )
            image.draw(in: CGRect(origin: origin, size: pixelSize))
        }
    }

    // MARK: - Video compositing

    /// Immutable hand-off to the background Core Image frame handler.
    private final class ShareVideoPayload: @unchecked Sendable {
        nonisolated let edits: CIImage?
        nonisolated let chrome: CIImage?
        nonisolated let sun: CIImage?
        nonisolated let risePixels: CGFloat
        nonisolated let duration: Double
        nonisolated let animated: Bool
        nonisolated let zoom: CGFloat
        nonisolated let zoomOffset: CGSize
        nonisolated let zoomCanvas: CGSize

        nonisolated init(
            edits: CIImage?,
            chrome: CIImage?,
            sun: CIImage?,
            risePixels: CGFloat,
            duration: Double,
            animated: Bool,
            zoom: CGFloat,
            zoomOffset: CGSize,
            zoomCanvas: CGSize
        ) {
            self.edits = edits
            self.chrome = chrome
            self.sun = sun
            self.risePixels = risePixels
            self.duration = duration
            self.animated = animated
            self.zoom = zoom
            self.zoomOffset = zoomOffset
            self.zoomCanvas = zoomCanvas
        }
    }

    /// Burns the overlay into a recorded clip, animating the mark's
    /// rise (sun or milestone flag) over the first ~1.2 s of playback
    /// (static when `animated` is false — reduced motion). Returns a
    /// fresh temporary `.mov`.
    @MainActor
    static func compositeVideo(
        at sourceURL: URL,
        composition: ShareCardComposition,
        username: String,
        attributed: Bool,
        animated: Bool,
        zoom: CGFloat = 1.0,
        zoomOffset: CGSize = .zero,
        zoomCanvas: CGSize = .zero,
        editLayer: ((CGSize) -> UIImage?)? = nil
    ) async -> URL? {
        guard
            let renderSize = await uprightSize(forVideoAt: sourceURL),
            renderSize.width > 1, renderSize.height > 1
        else {
            return nil
        }

        let chromeImage = overlayImage(
            composition: composition,
            username: username,
            attributed: attributed,
            layer: .chrome,
            pixelSize: renderSize
        )
        let sunImage = overlayImage(
            composition: composition,
            username: username,
            attributed: attributed,
            layer: .sunOnly,
            pixelSize: renderSize
        )

        let chromeCI = chromeImage?.cgImage.map { CIImage(cgImage: $0) }
        let sunCI = sunImage?.cgImage.map { CIImage(cgImage: $0) }
        let editsCI = editLayer?(renderSize)?.cgImage.map { CIImage(cgImage: $0) }
        guard chromeCI != nil || sunCI != nil || editsCI != nil || zoom > 1.001 else { return nil }

        let payload = ShareVideoPayload(
            edits: editsCI,
            chrome: chromeCI,
            sun: sunCI,
            risePixels: renderSize.width * 0.16,
            duration: riseDuration,
            animated: animated,
            zoom: zoom,
            zoomOffset: zoomOffset,
            zoomCanvas: zoomCanvas
        )
        return await burn(sourceURL: sourceURL, payload: payload)
    }

    /// Builds the Core Image composition and re-encodes off the main
    /// actor. Audio passes through untouched.
    nonisolated private static func burn(sourceURL: URL, payload: ShareVideoPayload) async -> URL? {
        let asset = AVURLAsset(url: sourceURL)

        let videoComposition: AVVideoComposition
        do {
            videoComposition = try await AVVideoComposition.videoComposition(with: asset) { request in
                let extent = request.sourceImage.extent
                var output = request.sourceImage

                // The preview's pinch framing reshapes the footage first,
                // so every layer above composites onto the zoomed frame.
                if payload.zoom > 1.001 {
                    output = VideoOverlayExporter.zoomedFrame(
                        output,
                        extent: extent,
                        zoom: payload.zoom,
                        offset: payload.zoomOffset,
                        canvas: payload.zoomCanvas
                    )
                }

                // The user's edit layer (captions / stickers / drawing)
                // sits directly on the footage, beneath the chrome.
                if let edits = payload.edits, edits.extent.width > 0, edits.extent.height > 0 {
                    let scale = CGAffineTransform(
                        scaleX: extent.width / edits.extent.width,
                        y: extent.height / edits.extent.height
                    )
                    output = edits.transformed(by: scale).composited(over: output)
                }

                if let chrome = payload.chrome, chrome.extent.width > 0, chrome.extent.height > 0 {
                    let scale = CGAffineTransform(
                        scaleX: extent.width / chrome.extent.width,
                        y: extent.height / chrome.extent.height
                    )
                    output = chrome.transformed(by: scale).composited(over: output)
                }

                if let sun = payload.sun, sun.extent.width > 0, sun.extent.height > 0 {
                    let time = request.compositionTime.seconds
                    let raw = payload.animated
                        ? min(1.0, max(0.0, time / payload.duration))
                        : 1.0
                    // Ease-out cubic — the glide decelerates into place.
                    let progress = 1.0 - pow(1.0 - raw, 3)
                    // Core Image's y-axis points up: a negative offset
                    // places the sun visually lower at the start.
                    let dy = -(1.0 - CGFloat(progress)) * payload.risePixels
                    let alpha = min(1.0, raw * 2.4)

                    let scale = CGAffineTransform(
                        scaleX: extent.width / sun.extent.width,
                        y: extent.height / sun.extent.height
                    )
                    var sunFrame = sun
                        .transformed(by: scale)
                        .transformed(by: CGAffineTransform(translationX: 0, y: dy))
                    sunFrame = applyAlpha(alpha, to: sunFrame)
                    output = sunFrame.cropped(to: extent).composited(over: output)
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
            .appendingPathComponent("frisfocus-share-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        do {
            try await session.export(to: outputURL, as: .mov)
            return outputURL
        } catch {
            return nil
        }
    }

    /// Multiplies the image's alpha channel — the sun's fade-in.
    nonisolated private static func applyAlpha(_ alpha: Double, to image: CIImage) -> CIImage {
        guard alpha < 0.999 else { return image }
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha)), forKey: "inputAVector")
        return filter.outputImage ?? image
    }

    /// The clip's display size after its preferred transform, so the
    /// overlay matches the upright frames the handler receives.
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
