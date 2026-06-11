//
//  SetupOrbArc.swift
//  FrisFocus
//
//  The setup flow's signature motif: a thin horizon arc with a glowing
//  orb riding it. The orb climbs as the conversation progresses, the arc
//  fills behind it (violet → amber), and each recognized focus area
//  drops a colored tick at the spot it appeared. Also home to the dawn
//  gradient used across the flow's hero screens.
//
//  Motion: the orb glides on progress changes and softly pulses while
//  the AI is thinking. Reduced-motion users get position jumps and no
//  pulse — same information, no glide.
//

import SwiftUI

// MARK: - Dawn gradient

/// Background washes for the setup flow's hero screens.
enum SetupSky {
    /// Deep violet → dusk → amber → cream. `lift` 0…1 raises the warm
    /// band (0 = orb low / early, 1 = orb high / nearly risen).
    static func dawn(lift: Double) -> LinearGradient {
        let clamped = max(0, min(1, lift))
        return LinearGradient(
            stops: [
                .init(color: Color(hex: 0x4A3C66), location: 0),
                .init(color: Color(hex: 0x6B5378), location: 0.30 - 0.10 * clamped),
                .init(color: Color(hex: 0xC98A4B), location: 0.62 - 0.14 * clamped),
                .init(color: Color(hex: 0xEFC988), location: 0.82 - 0.10 * clamped),
                .init(color: Theme.paperCream, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The risen sky for the closing screen — soft blue into gold.
    static var risen: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x9DB8D8), location: 0),
                .init(color: Color(hex: 0xC3CFD9), location: 0.34),
                .init(color: Color(hex: 0xEDD9A8), location: 0.68),
                .init(color: Color(hex: 0xF2C36B), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Hero sun

/// The large glowing sun used on the begin / naming / begins heroes.
struct SetupHeroSun: View {
    var diameter: CGFloat = 96
    var haloOpacity: Double = 0.35

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.sunWarm.opacity(haloOpacity), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter
                    )
                )
                .frame(width: diameter * 2.1, height: diameter * 2.1)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.sunCore, Theme.sunWarm, Theme.sunOuter],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 2,
                        endRadius: diameter * 0.62
                    )
                )
                .frame(width: diameter, height: diameter)
        }
    }
}

// MARK: - Arc geometry

/// A shallow rise arc. `t` 0…1 maps left foot → crest-right; the sweep
/// runs 200° → 340° (peaking at 270°, straight up in SwiftUI's flipped
/// coordinate space).
private enum ArcMath {
    static let startDegrees: Double = 202
    static let sweepDegrees: Double = 136

    static func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height + radius(in: size) - size.height * 0.92)
    }

    static func radius(in size: CGSize) -> CGFloat {
        size.width * 0.72
    }

    static func point(at t: Double, in size: CGSize) -> CGPoint {
        let clamped = max(0, min(1, t))
        let angle = Angle.degrees(startDegrees + sweepDegrees * clamped).radians
        let c = center(in: size)
        let r = radius(in: size)
        return CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
    }
}

private struct ArcShape: Shape {
    /// Portion of the sweep to draw, 0…1.
    var upTo: Double

    var animatableData: Double {
        get { upTo }
        set { upTo = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = max(0.001, min(1, upTo))
        path.addArc(
            center: ArcMath.center(in: rect.size),
            radius: ArcMath.radius(in: rect.size),
            startAngle: .degrees(ArcMath.startDegrees),
            endAngle: .degrees(ArcMath.startDegrees + ArcMath.sweepDegrees * clamped),
            clockwise: false
        )
        return path
    }
}

// MARK: - Orb arc

struct SetupOrbArc: View {
    /// Orb position along the arc, 0…1 (1 = crest).
    let progress: Double
    /// Recognized focus areas — each drops a tick at its arc position.
    let threads: [SetupThread]
    /// Soft glow-pulse while the AI is composing.
    var isThinking: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let orbPoint = ArcMath.point(at: progress, in: size)

            ZStack {
                // Track — the whole horizon, faint.
                ArcShape(upTo: 1)
                    .stroke(Theme.textPrimary.opacity(0.14), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

                // Fill behind the orb — violet → amber.
                ArcShape(upTo: progress)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: 0x7F77DD), Color(hex: 0xC98A4B), Theme.sunOuter],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )

                // Thread ticks, planted where each area was recognized.
                ForEach(threads) { thread in
                    let p = ArcMath.point(at: thread.arcPosition, in: size)
                    Circle()
                        .fill(Color(hex: thread.colorHex))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Theme.paperCream.opacity(0.8), lineWidth: 1))
                        .position(p)
                        .transition(.scale.combined(with: .opacity))
                }

                // The orb.
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.sunWarm.opacity(0.55), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 60, height: 60)
                        .scaleEffect(pulse && !reduceMotion ? 1.22 : 1)
                        .opacity(pulse && !reduceMotion ? 0.9 : 0.65)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.sunCore, Theme.sunWarm, Theme.sunOuter],
                                center: .init(x: 0.4, y: 0.35),
                                startRadius: 1,
                                endRadius: 13
                            )
                        )
                        .frame(width: 22, height: 22)
                }
                .position(orbPoint)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: progress)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: threads)
        }
        .onChange(of: isThinking) { _, thinking in
            guard !reduceMotion else { return }
            if thinking {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    pulse = false
                }
            }
        }
    }
}

// MARK: - Compact orb (long-reply slim bar)

/// The miniature orb used when the conversation compacts into its
/// scrollable long-reply state.
struct SetupMiniOrb: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Theme.sunCore, Theme.sunWarm, Theme.sunOuter],
                    center: .init(x: 0.4, y: 0.35),
                    startRadius: 1,
                    endRadius: 9
                )
            )
            .frame(width: 16, height: 16)
            .shadow(color: Theme.sunWarm.opacity(0.6), radius: 5)
    }
}
