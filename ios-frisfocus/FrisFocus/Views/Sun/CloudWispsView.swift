//
//  CloudWispsView.swift
//  FrisFocus
//
//  Three or four thin, painterly horizontal wisps drifting across the
//  sky on a ~2 minute cycle. Each wisp's gradient fades at its tips so
//  the loop is invisible. Tint comes from the SkyPalette so the wisps
//  read warm at dusk and cream-cool at midday.
//
//  Perf: each wisp drifts via a repeat-forever linear position
//  animation (GPU-composited). No TimelineView — the blurred capsule
//  is rasterized once, not 30× per second.
//

import SwiftUI

struct CloudWispsView: View {
    /// Color of the wisps. Defaults to cream; the parent can pass the
    /// palette's halo for a warmer tinted look.
    var tint: Color = Theme.textCream

    fileprivate struct Wisp {
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
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(wisps.enumerated()), id: \.offset) { _, wisp in
                    WispView(wisp: wisp, tint: tint, containerSize: proxy.size)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One drifting wisp. Travels off-screen-left → off-screen-right on a
/// repeat-forever linear animation; a short stagger delay keeps the
/// wisps from marching in lockstep.
private struct WispView: View {
    let wisp: CloudWispsView.Wisp
    let tint: Color
    let containerSize: CGSize

    @State private var isDrifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let startX = -wisp.widthPt / 2
        let endX = containerSize.width + wisp.widthPt * 1.5
        let y = wisp.yRelative * containerSize.height
        let staticX = containerSize.width * CGFloat(0.15 + wisp.phase * 0.7)

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
                x: reduceMotion ? staticX : (isDrifting ? endX : startX),
                y: y
            )
            .onAppear {
                guard !reduceMotion else { return }
                let duration = 1.0 / max(0.0001, wisp.speed)
                withAnimation(
                    .linear(duration: duration)
                        .repeatForever(autoreverses: false)
                        .delay(wisp.phase * 18.0)
                ) {
                    isDrifting = true
                }
            }
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
