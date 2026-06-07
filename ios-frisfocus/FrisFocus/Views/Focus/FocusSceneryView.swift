//
//  FocusSceneryView.swift
//  FrisFocus
//
//  Atmosphere behind the focus tree — warm cream sky with a soft upper
//  sun glow, layered distant hill silhouettes, a slow-drifting cloud
//  layer, an occasional bird, and the warm ground band the tree sits
//  on. Everything moves on a "minutes, not seconds" cadence so the
//  scene rewards a glance but punishes a stare.
//

import SwiftUI

struct FocusSceneryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Sky: warm cream → slightly warmer ground band.
                LinearGradient(
                    colors: [
                        Color(hex: 0xFDF6E5),
                        Color(hex: 0xFAF2E0),
                        Color(hex: 0xF6EAC9),
                        Color(hex: 0xEFDFB1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Upper sun glow.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: 0xFFE9B7).opacity(0.85),
                                Color(hex: 0xFAC775).opacity(0.32),
                                Color(hex: 0xFAC775).opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: size.width * 0.55
                        )
                    )
                    .frame(width: size.width * 1.05, height: size.height * 0.55)
                    .position(x: size.width * 0.62, y: size.height * 0.16)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)

                // Distant hills (back layer — palest, set higher).
                HillSilhouette(
                    color: Color(hex: 0xC8B989).opacity(0.55),
                    baseline: 0.66,
                    peakHeight: 0.10,
                    peakOffsets: [0.10, 0.32, 0.55, 0.78, 0.94]
                )

                // Mid hills.
                HillSilhouette(
                    color: Color(hex: 0xA8965F).opacity(0.55),
                    baseline: 0.74,
                    peakHeight: 0.09,
                    peakOffsets: [0.05, 0.22, 0.42, 0.66, 0.86]
                )

                // Near hills — warmer green-brown.
                HillSilhouette(
                    color: Color(hex: 0x7E8A48).opacity(0.55),
                    baseline: 0.82,
                    peakHeight: 0.07,
                    peakOffsets: [0.15, 0.38, 0.58, 0.82]
                )

                // Slow drifting clouds.
                FocusCloudsView(reduceMotion: reduceMotion)
                    .frame(height: size.height * 0.35)
                    .position(x: size.width / 2, y: size.height * 0.18)
                    .allowsHitTesting(false)

                // Occasional bird.
                FocusBirdView(reduceMotion: reduceMotion)
                    .allowsHitTesting(false)

                // Warm ground band.
                LinearGradient(
                    colors: [
                        Color(hex: 0xE6D2A0).opacity(0.0),
                        Color(hex: 0xE6D2A0).opacity(0.65),
                        Color(hex: 0xD4B97A)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size.height * 0.18)
                .position(x: size.width / 2, y: size.height * 0.92)

                // Faint horizon line.
                Rectangle()
                    .fill(Color(hex: 0x8E7B60).opacity(0.18))
                    .frame(height: 0.5)
                    .position(x: size.width / 2, y: size.height * 0.835)

                // A few barely-visible grass tufts at the base.
                grassTufts(in: size)
            }
        }
    }

    @ViewBuilder
    private func grassTufts(in size: CGSize) -> some View {
        ForEach(0..<14, id: \.self) { i in
            let unit = Double(i) / 14.0
            let jitter = sin(Double(i) * 1.7) * 0.04
            let x = (unit + jitter) * size.width
            let h = 4 + CGFloat(abs(sin(Double(i) * 2.3))) * 4
            Path { p in
                p.move(to: CGPoint(x: x, y: size.height * 0.88))
                p.addQuadCurve(
                    to: CGPoint(x: x + 2, y: size.height * 0.88 - h),
                    control: CGPoint(x: x + 1, y: size.height * 0.88 - h * 0.4)
                )
            }
            .stroke(Color(hex: 0x6D7E32).opacity(0.45), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }
    }
}

// MARK: - Hill silhouette

/// A soft hill silhouette built from quadratic curves between peaks.
/// Layered by `FocusSceneryView` for atmospheric depth.
struct HillSilhouette: View {
    let color: Color
    /// 0...1 vertical baseline where the hill bottom sits.
    let baseline: CGFloat
    /// 0...1 vertical amplitude of the tallest peak.
    let peakHeight: CGFloat
    /// Horizontal peak positions (0...1).
    let peakOffsets: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Path { p in
                let baseY = baseline * size.height
                p.move(to: CGPoint(x: -10, y: baseY))
                // Walk through peaks with smooth quad curves.
                var prev = CGPoint(x: -10, y: baseY)
                for (i, offsetUnit) in peakOffsets.enumerated() {
                    let peakX = offsetUnit * size.width
                    let amplitude = peakHeight * (0.7 + 0.3 * CGFloat(sin(Double(i) * 1.3)))
                    let peakY = baseY - amplitude * size.height
                    let control = CGPoint(x: (prev.x + peakX) / 2, y: peakY + 8)
                    p.addQuadCurve(to: CGPoint(x: peakX, y: peakY), control: control)
                    // Drop back toward baseline between peaks.
                    let nextOffset = i + 1 < peakOffsets.count ? peakOffsets[i + 1] : 1.1
                    let troughX = (peakX + nextOffset * size.width) / 2
                    let troughY = baseY - peakHeight * 0.25 * size.height
                    p.addQuadCurve(
                        to: CGPoint(x: troughX, y: troughY),
                        control: CGPoint(x: (peakX + troughX) / 2, y: peakY + 4)
                    )
                    prev = CGPoint(x: troughX, y: troughY)
                }
                p.addLine(to: CGPoint(x: size.width + 10, y: baseY))
                p.addLine(to: CGPoint(x: size.width + 10, y: size.height + 10))
                p.addLine(to: CGPoint(x: -10, y: size.height + 10))
                p.closeSubpath()
            }
            .fill(color)
        }
    }
}
