//
//  SunRaysView.swift
//  FrisFocus
//
//  Soft crepuscular rays fanning out from the sun's centre. Five wide
//  wedges at very low opacity — they read as light, not lines. The wedge
//  set rotates extremely slowly (~80 s cycle) so the rays feel alive
//  without ever calling attention to themselves.
//
//  Drawn as `Path`s relative to the parent's frame; the parent positions
//  this view so its centre sits at the sun's current centre.
//

import SwiftUI

struct SunRaysView: View {
    /// 0...1, multiplied into the rays' opacity. Pull this from the sun's
    /// brightness so they fade at zero score.
    var brightness: Double = 1.0

    /// Tint of the rays. Defaults to cream, but the parent can pass a
    /// warmer tone (e.g. the palette's halo) to mood-match dusk.
    var tint: Color = Theme.textCream

    /// Maximum reach of each ray.
    var reach: CGFloat = 520

    private let rays: [Ray] = [
        // Angles in radians measured clockwise from straight up (-Y).
        Ray(angle: -1.18, halfWidth: 0.34, peakOpacity: 0.085),
        Ray(angle: -0.55, halfWidth: 0.30, peakOpacity: 0.060),
        Ray(angle:  0.18, halfWidth: 0.32, peakOpacity: 0.075),
        Ray(angle:  0.85, halfWidth: 0.28, peakOpacity: 0.055),
        Ray(angle:  1.52, halfWidth: 0.36, peakOpacity: 0.070)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            // Very slow rotation — ~80 s for a full sweep
            let drift = sin(time * 0.078) * 0.06

            ZStack {
                ForEach(Array(rays.enumerated()), id: \.offset) { _, ray in
                    rayShape(ray: ray, drift: drift)
                }
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func rayShape(ray: Ray, drift: Double) -> some View {
        WedgeShape(
            angle: ray.angle + drift,
            halfWidth: ray.halfWidth,
            length: reach
        )
        .fill(
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(ray.peakOpacity * brightness), location: 0.0),
                    .init(color: tint.opacity(ray.peakOpacity * 0.55 * brightness), location: 0.35),
                    .init(color: Color.clear, location: 1.0)
                ],
                startPoint: .center,
                endPoint: rayEndpoint(angle: ray.angle + drift)
            )
        )
        .blur(radius: 8)
    }

    /// Convert the ray's angle (clockwise from straight up) into a
    /// UnitPoint roughly pointing outward, for the linear gradient.
    private func rayEndpoint(angle: Double) -> UnitPoint {
        let dx = sin(angle)
        let dy = -cos(angle)
        // Map -1...1 to 0...1
        return UnitPoint(
            x: max(0.0, min(1.0, 0.5 + dx * 0.5)),
            y: max(0.0, min(1.0, 0.5 + dy * 0.5))
        )
    }
}

// MARK: - Models

private struct Ray {
    let angle: Double       // radians, clockwise from straight up
    let halfWidth: Double   // radians, half-spread of the wedge
    let peakOpacity: Double // at the wedge's centre
}

// MARK: - Wedge geometry

/// A triangular sliver from the centre outward to `length`, spread by
/// `halfWidth` radians on each side of `angle`. Angle 0 points straight
/// up; angles increase clockwise.
private struct WedgeShape: Shape {
    let angle: Double
    let halfWidth: Double
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let leftAngle = angle - halfWidth
        let rightAngle = angle + halfWidth

        let leftPoint = CGPoint(
            x: centre.x + CGFloat(sin(leftAngle)) * length,
            y: centre.y - CGFloat(cos(leftAngle)) * length
        )
        let rightPoint = CGPoint(
            x: centre.x + CGFloat(sin(rightAngle)) * length,
            y: centre.y - CGFloat(cos(rightAngle)) * length
        )

        var path = Path()
        path.move(to: centre)
        path.addLine(to: leftPoint)
        path.addLine(to: rightPoint)
        path.closeSubpath()
        return path
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

        SunRaysView()
            .frame(width: 700, height: 700)
    }
}
