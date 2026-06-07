//
//  SunView.swift
//  FrisFocus
//
//  The sun itself — atmospheric bleed, halo, warm body, luminous core,
//  and the upper-left highlight. No longer carries the score number.
//  All warm colors come from the supplied SkyPalette so the sun shifts
//  along with the sky.
//
//  Visual response to score (linear):
//    • progress = score / goal, clamped 0–1.
//    • scale = 0.35 + progress × 0.65. At 0 pts the sun is a small
//      distant disc (~35 % of full); at goal it's full size.
//    • The warm body is always visible — even at 0 pts a quiet, muted
//      sun reads on the horizon.
//    • The halo, atmospheric bleed, crepuscular rays and bloom all
//      fade in with `progress`. At 0 pts there are no rays and no halo;
//      they ramp linearly as the user earns points and reach full
//      strength at goal.
//    • whiteMix = max(0, score/goal − 1). Past goal, mixes the core
//      toward white for a slightly hotter look.
//  Changes ease over 600 ms.
//
//  The view is sized at 600 × 600 to give the rays + bleed room to
//  spill outward. The parent positions it via `.position()`.
//

import SwiftUI

struct SunView: View {
    let score: Int
    let goal: Int
    let palette: SkyPalette

    /// Frame size for the sun + rays + bleed container. The visible sun
    /// body only fills the center; the surrounding rays use the rest.
    private let frameSize: CGFloat = 600

    /// Linear 0–1 progress toward today's goal.
    private var progress: Double {
        let raw = Double(score) / max(1.0, Double(goal))
        return max(0.0, min(1.0, raw))
    }

    /// Drives the glow layers (halo, bleed, rays, bloom). 0 at no
    /// points so the sun sits as a quiet disc on the horizon; 1 at
    /// goal so the full luminous treatment is in effect.
    private var glow: Double { progress }

    /// The warm body keeps a muted floor so the sun is always visible.
    private var bodyOpacity: Double { 0.42 + progress * 0.58 }

    private var scale: CGFloat {
        CGFloat(0.35 + progress * 0.65)
    }

    private var whiteMix: Double {
        let raw = Double(score) / max(1.0, Double(goal))
        return max(0.0, min(1.0, raw - 1.0))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            // ~6 s full breath cycle for the halo
            let breath01 = (sin(time * 1.047) + 1.0) / 2.0
            let haloBreath = 1.0 + breath01 * 0.035
            let coreColor = Color.lerpHSL(palette.sunCore, .white, t: whiteMix)

            ZStack {
                // 1. Atmospheric bleed — widest, softest, sits behind
                //    everything to tie the sun to the horizon glow.
                //    Fades in entirely with score.
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: palette.halo.opacity(0.18 * glow), location: 0.00),
                                .init(color: palette.sunOuter.opacity(0.10 * glow), location: 0.40),
                                .init(color: palette.sunOuter.opacity(0.04 * glow), location: 0.70),
                                .init(color: Color.clear, location: 1.00)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .blur(radius: 16)
                    .blendMode(.plusLighter)
                    .opacity(glow)

                // 2. Crepuscular rays — only appear as the user earns
                //    points; hidden entirely at 0.
                SunRaysView(brightness: glow, tint: palette.halo)
                    .opacity(glow)

                // 3. Outer halo — breathing, scaled to glow.
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: palette.halo.opacity(0.65 * glow), location: 0.00),
                                .init(color: palette.sunOuter.opacity(0.32 * glow), location: 0.55),
                                .init(color: Color.clear, location: 1.00)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 130
                        )
                    )
                    .frame(width: 260 * scale, height: 260 * scale)
                    .scaleEffect(haloBreath)
                    .blur(radius: 5)
                    .opacity(glow)

                // 4. Warm body bloom — solid colour around the core.
                //    Fades in with score so the sun doesn't bloom until
                //    the user starts earning points.
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: palette.sunWarm.opacity(0.95), location: 0.0),
                                .init(color: palette.sunOuter.opacity(0.55), location: 0.7),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180 * scale, height: 180 * scale)
                    .opacity(glow)

                // 5. Inner luminous core — always present (muted at 0,
                //    luminous at goal) so the sun reads as a disc on
                //    the horizon even when the user has no points.
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: coreColor, location: 0.0),
                                .init(color: palette.sunWarm, location: 0.55),
                                .init(color: palette.sunOuter, location: 1.0)
                            ],
                            center: UnitPoint(x: 0.45, y: 0.42),
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 122 * scale, height: 122 * scale)
                    .shadow(color: palette.sunOuter.opacity(0.45 * glow), radius: 20, x: 0, y: 0)
                    .opacity(bodyOpacity)

                // 6. Upper-left highlight — a soft white kiss, tied to
                //    glow so it only catches once the sun is luminous.
                Circle()
                    .fill(Color.white.opacity(0.28 * glow))
                    .frame(width: 36 * scale, height: 36 * scale)
                    .blur(radius: 6)
                    .offset(x: -14 * scale, y: -10 * scale)
            }
            .frame(width: frameSize, height: frameSize)
            .animation(.easeOut(duration: 0.6), value: progress)
            .animation(.easeOut(duration: 0.6), value: scale)
        }
        .frame(width: frameSize, height: frameSize)
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

        SunView(score: 32, goal: 50, palette: .afternoon)
    }
}
