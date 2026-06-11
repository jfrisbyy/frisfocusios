//
//  ShareCardRenderer.swift
//  FrisFocus
//
//  Flattens the share overlay into captured media — one renderer, a
//  destination parameter. Identical overlay composition for in-app and
//  external shares; the attribution line is added only when the result
//  leaves the app (external share or camera-roll save).
//
//  Photos: normalized upright → center-cropped to the 9:16 story ratio
//  (preserving capture resolution) → the overlay is rendered at the
//  crop's pixel size with SwiftUI's ImageRenderer and drawn on top.
//
//  Videos: the overlay is rendered as TWO transparent frames with
//  identical layout — the chrome (text, chips, attribution, scrim) and
//  the sun mark alone. Core Image composites both onto every frame via
//  AVVideoComposition; the sun layer glides up into its computed
//  position over the clip's first ~1.2 s (eased, fading in), giving
//  recorded clips the signature rise. Reduced-motion renders it static.
//
//  Everything composites locally — zero API calls anywhere.
//

import AVFoundation
import CoreImage
import SwiftUI
import UIKit

enum ShareCardRenderer {
    /// How long the sun's rise lasts at the start of a clip.
    private static let riseDuration: Double = 1.2

    // MARK: - Overlay rendering

    /// Renders the overlay at `pixelSize`, laying out at a phone-like
    /// logical width so typography matches what the viewfinder showed.
    @MainActor
    static func overlayImage(
        context: ShareDayContext,
        options: ShareOverlayOptions,
        username: String,
        attributed: Bool,
        layer: ShareOverlayLayer,
        pixelSize: CGSize
    ) -> UIImage? {
        guard pixelSize.width > 1, pixelSize.height > 1 else { return nil }
        let logicalWidth: CGFloat = 390
        let logicalHeight = logicalWidth * pixelSize.height / pixelSize.width

        let content = ShareOverlayView(
            context: context,
            options: options,
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
    @MainActor
    static func compositePhoto(
        _ photo: UIImage,
        context: ShareDayContext,
        options: ShareOverlayOptions,
        username: String,
        attributed: Bool,
        editLayer: ((CGSize) -> UIImage?)? = nil
    ) -> UIImage? {
        guard let base = normalizedStoryCrop(photo) else { return nil }
        let overlay = overlayImage(
            context: context,
            options: options,
            username: username,
            attributed: attributed,
            layer: .all,
            pixelSize: base.size
        )
        let edits = editLayer?(base.size)
        guard overlay != nil || edits != nil else { return base }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: base.size)
            base.draw(in: rect)
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

        nonisolated init(edits: CIImage?, chrome: CIImage?, sun: CIImage?, risePixels: CGFloat, duration: Double, animated: Bool) {
            self.edits = edits
            self.chrome = chrome
            self.sun = sun
            self.risePixels = risePixels
            self.duration = duration
            self.animated = animated
        }
    }

    /// Burns the overlay into a recorded clip, animating the sun's rise
    /// over the first ~1.2 s of playback (static when `animated` is
    /// false — reduced motion). Returns a fresh temporary `.mov`.
    @MainActor
    static func compositeVideo(
        at sourceURL: URL,
        context: ShareDayContext,
        options: ShareOverlayOptions,
        username: String,
        attributed: Bool,
        animated: Bool,
        editLayer: ((CGSize) -> UIImage?)? = nil
    ) async -> URL? {
        guard
            let renderSize = await uprightSize(forVideoAt: sourceURL),
            renderSize.width > 1, renderSize.height > 1
        else {
            return nil
        }

        let chromeImage = overlayImage(
            context: context,
            options: options,
            username: username,
            attributed: attributed,
            layer: .chrome,
            pixelSize: renderSize
        )
        let sunImage = overlayImage(
            context: context,
            options: options,
            username: username,
            attributed: attributed,
            layer: .sunOnly,
            pixelSize: renderSize
        )

        let chromeCI = chromeImage?.cgImage.map { CIImage(cgImage: $0) }
        let sunCI = sunImage?.cgImage.map { CIImage(cgImage: $0) }
        let editsCI = editLayer?(renderSize)?.cgImage.map { CIImage(cgImage: $0) }
        guard chromeCI != nil || sunCI != nil || editsCI != nil else { return nil }

        let payload = ShareVideoPayload(
            edits: editsCI,
            chrome: chromeCI,
            sun: sunCI,
            risePixels: renderSize.width * 0.16,
            duration: riseDuration,
            animated: animated
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
