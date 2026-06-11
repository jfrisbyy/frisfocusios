//
//  SunStateMarkView.swift
//  FrisFocus
//
//  The signature share mark — a sun above a thin horizon hairline whose
//  every property is computed from ratio = points ÷ daily goal:
//
//   • Height — the sun's center rises with ratio; at ~0.25 it barely
//     crests the hairline (mostly clipped below), at 1.0 it floats clear.
//   • Vibrance — color temperature warms continuously along the home
//     landscape's own sun palette: dusk ember → full afternoon gold.
//   • Glow — the home sun's layered treatment at mark scale: a wide
//     atmospheric bleed, a soft halo, a warm body bloom, and a luminous
//     core with the subtle upper-left highlight.
//   • Rays — the ONLY discrete element. Five soft light streaks appear
//     exclusively at ratio ≥ 1.0, keeping 99% visually distinct from 100%.
//
//  `WeekSunsMarkView` is the weekly variant: seven small suns at their
//  day-ratios above ONE shared hairline — no stems, no day letters.
//

import SwiftUI

// MARK: - Single-day mark

struct SunStateMarkView: View {
    /// Raw ratio — may exceed 1.0; visuals clamp, rays key off ≥ 1.
    let ratio: Double
    var diameter: CGFloat = 40

    private var width: CGFloat { SunGlyphCore.frameWidth(diameter: diameter) }
    private var height: CGFloat { SunGlyphCore.frameHeight(diameter: diameter) }
    private var hairlineY: CGFloat { SunGlyphCore.hairlineY(diameter: diameter) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShareHairline()
                .frame(width: width, height: 1)
                .position(x: width / 2, y: hairlineY)

            SunGlyphCore(ratio: ratio, diameter: diameter)
                .position(x: width / 2, y: height / 2)
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel("Sun at \(Int((max(0, ratio) * 100).rounded())) percent of the daily goal")
    }
}

// MARK: - Weekly variant

struct WeekSunsMarkView: View {
    /// Seven day-ratios, oldest first, ending with today.
    let ratios: [Double]
    var width: CGFloat = 172
    var sunDiameter: CGFloat = 13

    private var height: CGFloat { SunGlyphCore.frameHeight(diameter: sunDiameter) }
    private var hairlineY: CGFloat { SunGlyphCore.hairlineY(diameter: sunDiameter) }

    var body: some View {
        let days = Array(ratios.prefix(7))
        ZStack(alignment: .topLeading) {
            ShareHairline()
                .frame(width: width, height: 1)
                .position(x: width / 2, y: hairlineY)

            ForEach(Array(days.enumerated()), id: \.offset) { index, dayRatio in
                SunGlyphCore(ratio: dayRatio, diameter: sunDiameter)
                    .position(
                        x: width * (CGFloat(index) + 0.5) / CGFloat(max(1, days.count)),
                        y: height / 2
                    )
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel("Seven suns showing this week's days")
    }
}

// MARK: - Glyph core (glow + clipped disc + rays)

/// The sun alone — glow unclipped, disc clipped below an internal
/// hairline so it rises from behind the horizon. The parent draws the
/// visible hairline at `hairlineY` and positions this glyph centered,
/// so disc clipping and the drawn line coincide exactly.
struct SunGlyphCore: View {
    let ratio: Double
    let diameter: CGFloat

    static func frameWidth(diameter: CGFloat) -> CGFloat { diameter * 1.7 }
    static func frameHeight(diameter: CGFloat) -> CGFloat { diameter * 2.0 }
    static func hairlineY(diameter: CGFloat) -> CGFloat { frameHeight(diameter: diameter) * 0.85 }

    private var clamped: Double { min(max(ratio, 0), 1) }
    private var isFull: Bool { ratio >= 1.0 }
    private var frameSize: CGSize {
        CGSize(width: Self.frameWidth(diameter: diameter), height: Self.frameHeight(diameter: diameter))
    }
    private var hairlineY: CGFloat { Self.hairlineY(diameter: diameter) }

    /// The sun's center relative to the hairline. At 0 it hides almost
    /// entirely below; at 0.25 it barely crests; at 1.0 it floats clear.
    private var sunCenter: CGPoint {
        CGPoint(
            x: frameSize.width / 2,
            y: hairlineY + diameter * (0.45 - 1.2 * clamped)
        )
    }

    // Vibrance — the home landscape's own sun palette, warming from the
    // dusk ember keyframe to the full afternoon keyframe with ratio.
    private var coreColor: Color {
        Color.lerpHSL(SkyPalette.dusk.sunCore, SkyPalette.afternoon.sunCore, t: clamped)
    }
    private var warmColor: Color {
        Color.lerpHSL(SkyPalette.dusk.sunWarm, SkyPalette.afternoon.sunWarm, t: clamped)
    }
    private var outerColor: Color {
        Color.lerpHSL(SkyPalette.dusk.sunOuter, SkyPalette.afternoon.sunOuter, t: clamped)
    }
    private var haloColor: Color {
        Color.lerpHSL(SkyPalette.dusk.halo, SkyPalette.afternoon.halo, t: clamped)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Atmospheric bleed — widest, softest light tying the sun
            //    to the horizon. Unclipped; fades in with ratio.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: haloColor.opacity(0.15 * clamped), location: 0.0),
                            .init(color: outerColor.opacity(0.07 * clamped), location: 0.45),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 1.15
                    )
                )
                .frame(width: diameter * 2.3, height: diameter * 2.3)
                .blur(radius: diameter * 0.06)
                .position(sunCenter)

            // 2. Soft halo — unclipped light, radius grows with ratio.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: haloColor.opacity(0.10 + 0.42 * clamped), location: 0.0),
                            .init(color: outerColor.opacity(0.05 + 0.21 * clamped), location: 0.55),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * (0.6 + 0.35 * clamped)
                    )
                )
                .frame(
                    width: diameter * (1.2 + 0.7 * clamped),
                    height: diameter * (1.2 + 0.7 * clamped)
                )
                .blur(radius: diameter * 0.05)
                .position(sunCenter)

            // 3–5. The sun body — warm bloom, luminous core, and highlight
            //    — clipped at the hairline so it crests the horizon.
            ZStack(alignment: .topLeading) {
                // Warm body bloom around the core.
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: warmColor.opacity(0.9), location: 0.0),
                                .init(color: outerColor.opacity(0.5), location: 0.7),
                                .init(color: .clear, location: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter * 0.72
                        )
                    )
                    .frame(width: diameter * 1.44, height: diameter * 1.44)
                    .opacity(0.2 + 0.8 * clamped)
                    .position(sunCenter)

                // Luminous core — always present, muted when dim.
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: coreColor, location: 0.0),
                                .init(color: warmColor, location: 0.55),
                                .init(color: outerColor, location: 1.0)
                            ],
                            center: UnitPoint(x: 0.45, y: 0.42),
                            startRadius: 0,
                            endRadius: diameter * 0.6
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .opacity(0.62 + 0.38 * clamped)
                    .position(sunCenter)

                // Upper-left highlight — a soft white kiss, glow-tied.
                Circle()
                    .fill(Color.white.opacity(0.26 * clamped))
                    .frame(width: diameter * 0.3, height: diameter * 0.3)
                    .blur(radius: diameter * 0.05)
                    .position(
                        x: sunCenter.x - diameter * 0.115,
                        y: sunCenter.y - diameter * 0.085
                    )
            }
            .frame(width: frameSize.width, height: frameSize.height)
            .mask(alignment: .topLeading) {
                Rectangle()
                    .frame(width: frameSize.width, height: hairlineY)
            }

            // Rays — discrete, ONLY at goal-hit. Soft light streaks that
            // fade outward, never hard capsule sticks.
            if isFull {
                ForEach([-64.0, -32.0, 0.0, 32.0, 64.0], id: \.self) { angle in
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: haloColor.opacity(0.8), location: 0.0),
                                    .init(color: haloColor.opacity(0.25), location: 0.55),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: diameter * 0.06 + 1.0, height: diameter * 0.38)
                        .blur(radius: diameter * 0.022)
                        .offset(y: -diameter * 0.84)
                        .rotationEffect(.degrees(angle))
                        .position(sunCenter)
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .animation(.easeOut(duration: 0.4), value: clamped)
    }
}

// MARK: - Hairline

/// The thin horizon line — cream, fading at both ends.
private struct ShareHairline: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Color(hex: 0xFFEFD4).opacity(0.6), location: 0.12),
                .init(color: Color(hex: 0xFFEFD4).opacity(0.6), location: 0.88),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

#Preview("Spectrum") {
    ZStack {
        Color(hex: 0x241B0C).ignoresSafeArea()
        VStack(spacing: 30) {
            HStack(spacing: 12) {
                SunStateMarkView(ratio: 0.25)
                SunStateMarkView(ratio: 0.5)
                SunStateMarkView(ratio: 0.8)
                SunStateMarkView(ratio: 1.0)
            }
            WeekSunsMarkView(ratios: [0.4, 0.9, 1.0, 0.6, 0.2, 0.75, 1.1])
        }
    }
}
