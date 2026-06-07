//
//  BirdFlockView.swift
//  FrisFocus
//
//  Replaces the two solo drifters. A flock of five tiny V-silhouettes
//  travelling together in a loose V-formation, drifting across the
//  sky every ~36 seconds. Each bird fades in at the start of its
//  journey and out at the end so the loop is seamless.
//
//  The formation is anchored on a leader bird; the other four trail
//  behind in two diagonal lines. Bird positions and angles bob gently
//  on independent rhythms to keep the flock feeling alive.
//

import SwiftUI

/// V-shaped gull silhouette built from two quadratic curves.
private struct BirdShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        let dipY = midY + rect.height * 0.30
        let peakY = midY - rect.height * 0.42

        path.move(to: CGPoint(x: rect.minX, y: dipY))
        path.addQuadCurve(
            to: CGPoint(x: midX, y: peakY),
            control: CGPoint(x: rect.width * 0.25, y: midY - rect.height * 0.10)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: dipY),
            control: CGPoint(x: rect.width * 0.75, y: midY - rect.height * 0.10)
        )
        return path
    }
}

struct BirdFlockView: View {
    /// Color of the strokes. Cream on dark skies; the parent may pass
    /// the palette's halo or current text color.
    var tint: Color = Theme.textCream

    /// Vertical anchor for the flock as a fraction of the zone height.
    /// Default sits a bit above the horizon.
    var anchorY: CGFloat = 0.40

    /// How long one cross of the screen takes. 36 s for a calm pace.
    var cycleSeconds: Double = 36.0

    private struct Member {
        /// Offset from the leader bird, in points.
        let dx: CGFloat
        let dy: CGFloat
        /// Bird size.
        let size: CGSize
        /// Stroke width.
        let lineWidth: CGFloat
        /// Peak opacity (multiplied by appearance/fade).
        let opacity: Double
        /// Phase offset for the gentle vertical wobble.
        let wobbleOffset: Double
    }

    /// Five birds: a leader plus two trailing pairs. Wing-flap timing is
    /// staggered slightly so the flock doesn't feel mechanical.
    private let members: [Member] = [
        // Leader — front of the V
        Member(dx:   0, dy:   0,  size: CGSize(width: 11, height: 5), lineWidth: 0.95, opacity: 0.60, wobbleOffset: 0.00),
        // Right wing-back
        Member(dx: -16, dy:   6,  size: CGSize(width: 9,  height: 4), lineWidth: 0.85, opacity: 0.52, wobbleOffset: 0.50),
        // Left wing-back
        Member(dx: -16, dy:  -6,  size: CGSize(width: 9,  height: 4), lineWidth: 0.85, opacity: 0.52, wobbleOffset: 1.10),
        // Far right
        Member(dx: -30, dy:  12,  size: CGSize(width: 7,  height: 3), lineWidth: 0.75, opacity: 0.42, wobbleOffset: 1.70),
        // Far left
        Member(dx: -30, dy: -12,  size: CGSize(width: 7,  height: 3), lineWidth: 0.75, opacity: 0.42, wobbleOffset: 2.30)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let cycle = ((time / cycleSeconds))
                    .truncatingRemainder(dividingBy: 1.0)
                let appearance = fadeWindow(cycle: cycle)
                let margin: CGFloat = 80
                let totalDistance = proxy.size.width + margin * 2
                let leaderX = -margin + CGFloat(cycle) * totalDistance
                let leaderY = anchorY * proxy.size.height

                ZStack {
                    ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                        let bob = sin(time * 1.20 + member.wobbleOffset) * 1.3
                        BirdShape()
                            .stroke(
                                tint.opacity(member.opacity * appearance),
                                style: StrokeStyle(
                                    lineWidth: member.lineWidth,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .frame(width: member.size.width, height: member.size.height)
                            .position(
                                x: leaderX + member.dx,
                                y: leaderY + member.dy + bob
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Fade in over the first 12 % of the loop and out over the last 12 %.
    private func fadeWindow(cycle: Double) -> Double {
        let fade: Double = 0.12
        if cycle < fade { return cycle / fade }
        if cycle > 1.0 - fade { return (1.0 - cycle) / fade }
        return 1.0
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Theme.skyDeep, Theme.skyLow],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        BirdFlockView()
    }
}
