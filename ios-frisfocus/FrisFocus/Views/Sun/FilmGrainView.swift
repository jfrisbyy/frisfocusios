//
//  FilmGrainView.swift
//  FrisFocus
//
//  A very subtle noise pattern layered over the whole Sun zone to give
//  the painting a printed-paper feel. Drawn with `Canvas` using a
//  seeded PRNG so the grain stays put across renders instead of
//  flickering.
//
//  Strength is kept low (~25 %) per the locked design — the grain
//  should add texture, not visible noise.
//

import SwiftUI

struct FilmGrainView: View {
    /// Overall strength of the grain, 0...1. The locked design sits at
    /// ~0.25 — anything above 0.4 starts to look like static.
    var strength: Double = 0.25

    /// Density of grain dots per 1000 pt² of canvas. Higher = busier.
    var density: Double = 0.9

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let count = max(0, Int(density * (size.width * size.height) / 1000.0))
            // Seeded PRNG so the grain is stable across re-renders.
            var rng = SeededRandom(seed: 1_337)

            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let dotSize = CGFloat(0.5 + rng.next() * 0.9)
                // Mostly dark dots with the occasional bright fleck —
                // gives the texture a printed grain look.
                let isLight = rng.next() < 0.30
                let baseAlpha = (isLight ? 0.45 : 0.55) * strength
                let alpha = baseAlpha * (0.55 + rng.next() * 0.45)
                let color: Color = isLight
                    ? .white.opacity(alpha)
                    : .black.opacity(alpha)

                let rect = CGRect(
                    x: x - dotSize / 2,
                    y: y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

/// Tiny linear-congruential PRNG. Stable across runs given the same
/// seed — no Foundation randomness, no Sendable headaches.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zeros state
        self.state = seed == 0 ? 1 : seed
    }

    /// Returns a Double in 0..<1.
    mutating func next() -> Double {
        state &*= 6_364_136_223_846_793_005
        state &+= 1_442_695_040_888_963_407
        // Use the top 53 bits for a Double in 0..<1
        let bits = state >> 11
        return Double(bits) / Double(1 << 53)
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

        FilmGrainView(strength: 0.4)
    }
}
