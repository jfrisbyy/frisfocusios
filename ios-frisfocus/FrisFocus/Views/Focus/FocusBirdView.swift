//
//  FocusBirdView.swift
//  FrisFocus
//
//  An occasional bird (a simple double-curve silhouette) crosses the
//  frame on a long, irregular interval — rare enough you don't wait
//  for it. The path arcs gently, and the wings stroke at a calm
//  cadence. Reduced-motion hides the bird entirely (it's the only
//  scene element with a real arrival, so keep the static scene clean).
//

import SwiftUI

struct FocusBirdView: View {
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    // A cycle of ~180s where the bird is on-screen
                    // briefly (~14s) inside each cycle, then gone for
                    // the rest of the period.
                    let cyclePeriod: Double = 180
                    let cycleOffset = 23.0
                    let phase = ((t + cycleOffset).truncatingRemainder(dividingBy: cyclePeriod)) / cyclePeriod
                    // On-screen when phase is between 0 and ~0.08.
                    let visibleSpan = 0.085
                    if phase < visibleSpan {
                        let p = phase / visibleSpan  // 0...1 across this transit
                        let xUnit = -0.1 + p * 1.2
                        // Subtle arc: parabolic dip then rise.
                        let yUnit = 0.18 + 0.05 * sin(p * .pi)
                        let wingPhase = sin(t * 4.6)
                        FocusBirdShape(wingPhase: wingPhase)
                            .stroke(
                                Color(hex: 0x4A4137).opacity(0.7),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 26, height: 14)
                            .position(
                                x: geo.size.width * CGFloat(xUnit),
                                y: geo.size.height * CGFloat(yUnit)
                            )
                            .opacity(birdOpacity(p: p))
                    }
                }
            }
        }
    }

    private func birdOpacity(p: Double) -> Double {
        // Soft fade-in / fade-out at the edges so the bird doesn't
        // pop in at the frame boundary.
        if p < 0.08 { return p / 0.08 }
        if p > 0.92 { return (1 - p) / 0.08 }
        return 1
    }
}

/// Two-curve gull silhouette. `wingPhase` ∈ -1...1 drives wing stroke
/// position (down-stroke to up-stroke).
struct FocusBirdShape: Shape {
    var wingPhase: Double

    var animatableData: Double {
        get { wingPhase }
        set { wingPhase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let midY = rect.midY
        let lift = CGFloat(wingPhase) * h * 0.35

        // Left wing.
        p.move(to: CGPoint(x: 0, y: midY))
        p.addQuadCurve(
            to: CGPoint(x: w / 2, y: midY + h * 0.05),
            control: CGPoint(x: w * 0.25, y: midY - h * 0.4 + lift)
        )
        // Right wing.
        p.addQuadCurve(
            to: CGPoint(x: w, y: midY),
            control: CGPoint(x: w * 0.75, y: midY - h * 0.4 + lift)
        )
        return p
    }
}
