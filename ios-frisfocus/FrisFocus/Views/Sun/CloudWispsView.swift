//
//  CloudWispsView.swift
//  FrisFocus
//
//  Three or four thin, painterly horizontal wisps drifting across the
//  sky on a ~2 minute cycle. Each wisp fades in/out at its endpoints so
//  the loop is invisible. Tint comes from the SkyPalette so the wisps
//  read warm at dusk and cream-cool at midday.
//

import SwiftUI

struct CloudWispsView: View {
    /// Color of the wisps. Defaults to cream; the parent can pass the
    /// palette's halo for a warmer tinted look.
    var tint: Color = Theme.textCream

    private struct Wisp {
        let yRelative: CGFloat
        let widthPt: CGFloat
        let heightPt: CGFloat
        let opacity: Double
        let speed: Double
        let phase: Double
    }

    private let wisps: [Wisp] = [
        Wisp(yRelative: 0.18, widthPt: 210, heightPt: 3.5, opacity: 0.14, speed: 0.0085, phase: 0.00),
        Wisp(yRelative: 0.30, widthPt: 150, heightPt: 2.5, opacity: 0.10, speed: 0.0060, phase: 0.42),
        Wisp(yRelative: 0.43, widthPt: 260, heightPt: 4.0, opacity: 0.11, speed: 0.0050, phase: 0.70),
        Wisp(yRelative: 0.55, widthPt: 170, heightPt: 2.5, opacity: 0.09, speed: 0.0072, phase: 0.18)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(wisps.enumerated()), id: \.offset) { _, wisp in
                        let cycle = ((time * wisp.speed) + wisp.phase)
                            .truncatingRemainder(dividingBy: 1.0)
                        let totalDistance = proxy.size.width + wisp.widthPt * 2
                        let xPosition = -wisp.widthPt + cycle * totalDistance

                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.clear, location: 0.0),
                                        .init(color: tint.opacity(wisp.opacity * 0.55), location: 0.18),
                                        .init(color: tint.opacity(wisp.opacity), location: 0.50),
                                        .init(color: tint.opacity(wisp.opacity * 0.65), location: 0.82),
                                        .init(color: Color.clear, location: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: wisp.widthPt, height: wisp.heightPt)
                            .blur(radius: 2.5)
                            .position(
                                x: xPosition + wisp.widthPt / 2,
                                y: wisp.yRelative * proxy.size.height
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: SkyPalette.afternoon.skyStops,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        CloudWispsView(tint: SkyPalette.afternoon.halo)
    }
}
