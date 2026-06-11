//
//  StarFieldView.swift
//  FrisFocus
//
//  A small scatter of stars in the upper sky. Thinned to 7 specks per
//  the locked design — enough to add atmosphere without competing with
//  the new score headline. The brightest two twinkle very slowly.
//
//  Perf: stars are static views; the two twinklers animate opacity with
//  a repeat-forever ease, which Core Animation composites on the GPU.
//  No TimelineView — zero per-frame CPU work.
//

import SwiftUI

struct StarFieldView: View {
    fileprivate struct Star: Hashable {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let baseOpacity: Double
        let twinklePhase: Double
        let twinkleSpeed: Double
        let twinkles: Bool
    }

    /// Hand-tuned, deterministic — 7 specks clustered in the upper 45 %
    /// of the zone so they don't compete with the headline.
    private let stars: [Star] = [
        Star(x: 0.11, y: 0.06, size: 2.2, baseOpacity: 0.80, twinklePhase: 0.0, twinkleSpeed: 0.85, twinkles: true),
        Star(x: 0.84, y: 0.04, size: 2.0, baseOpacity: 0.72, twinklePhase: 1.7, twinkleSpeed: 0.70, twinkles: true),
        Star(x: 0.22, y: 0.16, size: 1.4, baseOpacity: 0.50, twinklePhase: 0.5, twinkleSpeed: 0.50, twinkles: false),
        Star(x: 0.68, y: 0.20, size: 1.4, baseOpacity: 0.46, twinklePhase: 2.4, twinkleSpeed: 0.50, twinkles: false),
        Star(x: 0.42, y: 0.30, size: 1.2, baseOpacity: 0.36, twinklePhase: 3.1, twinkleSpeed: 0.62, twinkles: false),
        Star(x: 0.92, y: 0.34, size: 1.1, baseOpacity: 0.30, twinklePhase: 3.5, twinkleSpeed: 0.48, twinkles: false),
        Star(x: 0.06, y: 0.40, size: 1.1, baseOpacity: 0.32, twinklePhase: 4.0, twinkleSpeed: 0.45, twinkles: false)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(stars, id: \.self) { star in
                    StarDot(star: star)
                        .position(
                            x: star.x * proxy.size.width,
                            y: star.y * proxy.size.height
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A single star. Twinklers animate opacity on a repeat-forever ease —
/// GPU-composited, no per-frame body evaluation.
private struct StarDot: View {
    let star: StarFieldView.Star

    @State private var isBright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let twinkleRange = 0.22
        let opacity: Double = {
            guard star.twinkles, !reduceMotion else { return star.baseOpacity }
            return isBright
                ? min(1.0, star.baseOpacity + twinkleRange)
                : max(0.0, star.baseOpacity - twinkleRange)
        }()

        Circle()
            .fill(Theme.textCream)
            .frame(width: star.size, height: star.size)
            .blur(radius: star.size > 1.8 ? 0.4 : 0)
            .opacity(opacity)
            .onAppear {
                guard star.twinkles, !reduceMotion else { return }
                // Half-period of the old sine twinkle: π / speed.
                let halfPeriod = Double.pi / max(0.1, star.twinkleSpeed)
                withAnimation(
                    .easeInOut(duration: halfPeriod)
                        .repeatForever(autoreverses: true)
                        .delay(star.twinklePhase)
                ) {
                    isBright = true
                }
            }
    }
}

#Preview {
    ZStack {
        Theme.skyDeep.ignoresSafeArea()
        StarFieldView()
    }
}
