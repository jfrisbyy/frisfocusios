//
//  ProfileHeaderCropView.swift
//  FrisFocus
//
//  The header framing screen. After picking a photo for the profile
//  header background, the image sits inside a banner-shaped frame that
//  matches the real profile hero; pinch to zoom, drag to reposition,
//  then confirm. The visible framing is baked into a fixed-size image
//  before upload, so what you frame is exactly what friends see and
//  nothing shifts at render time.
//

import SwiftUI
import UIKit

struct ProfileHeaderCropView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Width-to-height ratio of the profile hero band. Shared by the
    /// Edit-profile preview so the crop is true WYSIWYG.
    static let aspect: CGFloat = 1.24

    /// Baked output width in pixels (height follows from `aspect`).
    private static let outputWidth: CGFloat = 1320

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let frame = frameSize(in: geo.size)

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 12)

                cropFrame(frame)
                    .frame(maxWidth: .infinity)

                Text("Pinch to zoom · drag to reposition")
                    .font(.sans(12, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 18)

                Spacer(minLength: 12)

                confirmButton(frame)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Frame your header")
                .font(.serif(17, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            // Mirror the cancel width so the title stays centered.
            Text("Cancel")
                .font(.sans(15, weight: .regular))
                .hidden()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func cropFrame(_ frame: CGSize) -> some View {
        let drag = DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    zoom: zoom,
                    frame: frame
                )
            }
            .onEnded { _ in committedOffset = offset }

        let magnify = MagnifyGesture()
            .onChanged { value in
                zoom = min(5, max(1, committedZoom * value.magnification))
                offset = clamped(offset, zoom: zoom, frame: frame)
            }
            .onEnded { _ in
                committedZoom = zoom
                withAnimation(.spring(duration: 0.3)) {
                    offset = clamped(offset, zoom: zoom, frame: frame)
                }
                committedOffset = offset
            }

        let scale = baseScale(frame: frame) * zoom

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .offset(offset)
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .gesture(drag.simultaneously(with: magnify))
    }

    private func confirmButton(_ frame: CGSize) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onConfirm(bake(frame: frame))
            dismiss()
        } label: {
            Text("Use this framing")
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Geometry

    private func frameSize(in container: CGSize) -> CGSize {
        let width = max(10, min(container.width - 32, (container.height - 220) * Self.aspect))
        return CGSize(width: width, height: width / Self.aspect)
    }

    /// Scale at which the image exactly covers the crop frame.
    private func baseScale(frame: CGSize) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        return max(frame.width / image.size.width, frame.height / image.size.height)
    }

    /// Keep the image covering the frame — no empty edges, ever.
    private func clamped(_ proposed: CGSize, zoom: CGFloat, frame: CGSize) -> CGSize {
        let scale = baseScale(frame: frame) * zoom
        let maxX = max(0, (image.size.width * scale - frame.width) / 2)
        let maxY = max(0, (image.size.height * scale - frame.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    /// Render exactly what's visible in the frame to a fixed-size
    /// banner image, ready for upload.
    private func bake(frame: CGSize) -> UIImage {
        let outW = Self.outputWidth
        let outH = (outW / Self.aspect).rounded()
        let k = outW / frame.width
        let scale = baseScale(frame: frame) * zoom * k
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: outW / 2 + offset.width * k - drawSize.width / 2,
            y: outH / 2 + offset.height * k - drawSize.height / 2
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

#Preview {
    ProfileHeaderCropView(
        image: UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        },
        onConfirm: { _ in }
    )
}
