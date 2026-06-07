//
//  DistantMountainsView.swift
//  FrisFocus
//
//  A row of jagged, distant peaks set behind the rolling ridges to give
//  the landscape an extra depth pass. Renders against the sky color, so
//  it lives just above the ridge seam in z-order. The peak color comes
//  from the current SkyPalette (`mountainShadow`).
//

import SwiftUI

struct DistantMountainsView: View {
    /// Color of the silhouette — usually `palette.mountainShadow`.
    let color: Color

    /// Height of the peaks band. Defaults to a short strip just tall
    /// enough to read as "ridge behind a ridge".
    var height: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            Path { path in
                // Start off-screen left at the baseline
                path.move(to: CGPoint(x: 0, y: h))

                // A hand-tuned sawtooth of peaks of varying heights — gives
                // it an editorial, drawn-by-hand jaggedness instead of a
                // mechanical zigzag.
                let peaks: [(x: CGFloat, dip: CGFloat, peak: CGFloat)] = [
                    (0.00, 0.55, 0.22),
                    (0.08, 0.65, 0.10),
                    (0.16, 0.70, 0.30),
                    (0.24, 0.60, 0.16),
                    (0.33, 0.74, 0.06),
                    (0.42, 0.55, 0.28),
                    (0.50, 0.68, 0.14),
                    (0.58, 0.40, 0.34),
                    (0.66, 0.62, 0.18),
                    (0.74, 0.48, 0.08),
                    (0.82, 0.66, 0.24),
                    (0.90, 0.55, 0.12),
                    (1.00, 0.62, 0.20)
                ]

                for peak in peaks {
                    let xPos = peak.x * w
                    path.addLine(to: CGPoint(x: xPos, y: h * peak.dip))
                    path.addLine(to: CGPoint(x: xPos + w * 0.04, y: h * peak.peak))
                }

                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
            }
            .fill(color)
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

#Preview {
    VStack(spacing: 0) {
        Theme.skyLow.frame(height: 60)
        DistantMountainsView(color: SkyPalette.afternoon.mountainShadow)
        Theme.ridgeFar.frame(height: 80)
    }
}
