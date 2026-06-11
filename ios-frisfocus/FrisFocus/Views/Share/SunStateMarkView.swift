//
//  SunStateMarkView.swift
//  FrisFocus
//
//  The signature share mark — a sun above a thin horizon hairline whose
//  every property is computed from ratio = points ÷ daily goal:
//
//   • Height — the sun's center rises with ratio; at ~0.25 it barely
//     crests the hairline (mostly clipped below), at 1.0 it floats clear.
//   • Vibrance — color temperature warms continuously: dim cool-amber
//     (ember) → warming amber → bright gold → near-white core at full.
//   • Halo + glow — radius and opacity scale continuously with ratio.
//   • Rays — the ONLY discrete element. Five delicate rays appear
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

    // Vibrance — continuous warm-up with ratio.
    private var coreColor: Color {
        Color.lerpHSL(Color(hex: 0xD89A4E), Color(hex: 0xFFF3D9), t: clamped)
    }
    private var bodyColor: Color {
        Color.lerpHSL(Color(hex: 0xA86A28), Color(hex: 0xFFC668), t: clamped)
    }
    private var edgeColor: Color {
        Color.lerpHSL(Color(hex: 0x7E5520), Color(hex: 0xF0A340), t: clamped)
    }
    private var glowColor: Color {
        Color.lerpHSL(Color(hex: 0xC98A35), Color(hex: 0xFFD98A), t: clamped)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Halo + outer glow — unclipped light, continuous with ratio.
            // Reference: ~16px @ .18 at 0.25 → ~44px @ .55 at 1.0.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: glowColor.opacity(0.06 + 0.49 * clamped), location: 0.0),
                            .init(color: glowColor.opacity(0.03 + 0.20 * clamped), location: 0.55),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * (0.65 + 0.55 * clamped)
                    )
                )
                .frame(
                    width: diameter * (1.35 + 1.0 * clamped),
                    height: diameter * (1.35 + 1.0 * clamped)
                )
                .blur(radius: diameter * 0.08)
                .position(sunCenter)

            // The disc — clipped at the hairline so it crests the horizon.
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: coreColor, location: 0.0),
                            .init(color: bodyColor, location: 0.55),
                            .init(color: edgeColor, location: 1.0)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.38),
                        startRadius: 0,
                        endRadius: diameter * 0.62
                    )
                )
                .frame(width: diameter, height: diameter)
                .opacity(0.72 + 0.28 * clamped)
                .position(sunCenter)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: frameSize.width, height: hairlineY)
                }

            // Rays — discrete, ONLY at goal-hit. Never below.
            if isFull {
                ForEach([-64.0, -32.0, 0.0, 32.0, 64.0], id: \.self) { angle in
                    Capsule()
                        .fill(Color(hex: 0xFFE2A6).opacity(0.92))
                        .frame(width: diameter * 0.045 + 1.2, height: diameter * 0.24)
                        .offset(y: -diameter * 0.82)
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
