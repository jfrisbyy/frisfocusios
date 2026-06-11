//
//  FocusCloudsView.swift
//  FrisFocus
//
//  Slow-drifting cloud layer. Three soft clouds drift horizontally on
//  very long, staggered periods (full traverse takes minutes, not
//  seconds) so the eye registers presence without being drawn to track
//  motion. Respects `prefers-reduced-motion` → renders a static
//  positioning of the same clouds.
//

import SwiftUI

struct FocusCloudsView: View {
    let reduceMotion: Bool

    // Each cloud: (relative y in 0...1, scale 0...1, period seconds,
    // phase offset 0...1, opacity).
    private let clouds: [(y: CGFloat, scale: CGFloat, period: Double, phase: Double, opacity: Double)] = [
        (0.20, 1.00, 360, 0.10, 0.55),
        (0.45, 0.78, 480, 0.55, 0.42),
        (0.70, 1.20, 600, 0.80, 0.32),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if reduceMotion {
                ZStack {
                    ForEach(0..<clouds.count, id: \.self) { i in
                        let cloud = clouds[i]
                        CloudShape()
                            .fill(Color.white.opacity(cloud.opacity))
                            .frame(width: size.width * 0.38 * cloud.scale, height: size.height * 0.30 * cloud.scale)
                            .position(
                                x: size.width * CGFloat(cloud.phase),
                                y: size.height * cloud.y
                            )
                    }
                }
            } else {
                // Clouds move ~1.6 pt/s — a 2 fps tick is indistinguishable
                // from 20 fps and cuts CPU by 10×.
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<clouds.count, id: \.self) { i in
                            let cloud = clouds[i]
                            // Periodic wrap from -0.2 → 1.2 along the
                            // width so clouds drift in from the left
                            // and exit to the right.
                            let cyclePos = (t / cloud.period + cloud.phase)
                                .truncatingRemainder(dividingBy: 1.0)
                            let xUnit = -0.2 + cyclePos * 1.4
                            CloudShape()
                                .fill(Color.white.opacity(cloud.opacity))
                                .frame(
                                    width: size.width * 0.38 * cloud.scale,
                                    height: size.height * 0.30 * cloud.scale
                                )
                                .blur(radius: 1.4)
                                .position(
                                    x: size.width * CGFloat(xUnit),
                                    y: size.height * cloud.y
                                )
                        }
                    }
                    .animation(.linear(duration: 0.5), value: t)
                }
            }
        }
    }
}

/// Soft puffy cloud shape — three overlapping ellipses fused so the
/// silhouette reads as cloud rather than a sausage.
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Big middle puff.
        p.addEllipse(in: CGRect(x: w * 0.20, y: h * 0.15, width: w * 0.60, height: h * 0.75))
        // Left puff.
        p.addEllipse(in: CGRect(x: 0, y: h * 0.35, width: w * 0.45, height: h * 0.55))
        // Right puff.
        p.addEllipse(in: CGRect(x: w * 0.55, y: h * 0.32, width: w * 0.45, height: h * 0.58))
        // Top dome.
        p.addEllipse(in: CGRect(x: w * 0.30, y: 0, width: w * 0.45, height: h * 0.55))
        // Bottom flat smear for a gentle base.
        p.addEllipse(in: CGRect(x: w * 0.12, y: h * 0.55, width: w * 0.78, height: h * 0.35))
        return p
    }
}
