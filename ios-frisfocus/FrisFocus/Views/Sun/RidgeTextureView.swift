//
//  RidgeTextureView.swift
//  FrisFocus
//
//  Two small overlays that sit on top of the existing ridge silhouettes
//  to give them a hand-drawn feel:
//
//   • A scatter of short vertical strokes across the near ridge that
//     read as a far-away tree line.
//   • A sparser row of taller strokes at the bottom edge that read as
//     blades of grass coming up from the foreground band.
//
//  Both render at low opacity so the ridges still read as a single
//  silhouette from a distance — the texture only emerges close-up.
//

import SwiftUI

struct RidgeTreeTextureView: View {
    /// Color of the strokes. Defaults to a slightly darker variant of
    /// the underlying ridge.
    var color: Color = Color.black

    /// Overall opacity multiplier — kept low so the texture whispers.
    var opacity: Double = 0.22

    /// Hand-placed tree strokes (xRelative, yRelative, height, alphaMul)
    private let trees: [Tree] = [
        Tree(x: 0.04, y: 0.42, h: 5.0, a: 0.85),
        Tree(x: 0.07, y: 0.36, h: 6.0, a: 1.00),
        Tree(x: 0.11, y: 0.44, h: 4.2, a: 0.70),
        Tree(x: 0.15, y: 0.38, h: 5.5, a: 0.95),
        Tree(x: 0.19, y: 0.46, h: 3.5, a: 0.65),
        Tree(x: 0.24, y: 0.40, h: 5.0, a: 0.90),
        Tree(x: 0.28, y: 0.32, h: 6.5, a: 1.00),
        Tree(x: 0.33, y: 0.44, h: 4.0, a: 0.75),
        Tree(x: 0.38, y: 0.36, h: 5.5, a: 0.85),
        Tree(x: 0.42, y: 0.42, h: 4.5, a: 0.80),
        Tree(x: 0.47, y: 0.34, h: 6.0, a: 0.95),
        Tree(x: 0.52, y: 0.44, h: 4.0, a: 0.70),
        Tree(x: 0.57, y: 0.36, h: 5.5, a: 0.90),
        Tree(x: 0.61, y: 0.42, h: 4.5, a: 0.78),
        Tree(x: 0.66, y: 0.32, h: 6.5, a: 1.00),
        Tree(x: 0.70, y: 0.40, h: 5.0, a: 0.85),
        Tree(x: 0.75, y: 0.46, h: 3.5, a: 0.62),
        Tree(x: 0.80, y: 0.38, h: 5.5, a: 0.90),
        Tree(x: 0.85, y: 0.42, h: 4.8, a: 0.82),
        Tree(x: 0.90, y: 0.34, h: 6.0, a: 0.95),
        Tree(x: 0.95, y: 0.44, h: 4.0, a: 0.72)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(trees.enumerated()), id: \.offset) { _, tree in
                    Capsule()
                        .fill(color.opacity(opacity * tree.a))
                        .frame(width: 1.1, height: tree.h)
                        .position(
                            x: tree.x * proxy.size.width,
                            y: tree.y * proxy.size.height
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct Tree {
        let x: Double
        let y: Double
        let h: CGFloat
        let a: Double
    }
}

/// Short vertical blades scattered across the very bottom of the
/// foreground band — reads as grass.
struct GrassBladeRowView: View {
    var color: Color = Color.black
    var opacity: Double = 0.30

    private let blades: [Blade] = [
        Blade(x: 0.03, h: 3.0, a: 0.7),
        Blade(x: 0.07, h: 4.5, a: 1.0),
        Blade(x: 0.10, h: 2.5, a: 0.6),
        Blade(x: 0.14, h: 3.8, a: 0.9),
        Blade(x: 0.18, h: 3.0, a: 0.7),
        Blade(x: 0.23, h: 4.0, a: 0.95),
        Blade(x: 0.27, h: 2.8, a: 0.65),
        Blade(x: 0.31, h: 3.6, a: 0.85),
        Blade(x: 0.36, h: 4.2, a: 0.95),
        Blade(x: 0.40, h: 2.8, a: 0.7),
        Blade(x: 0.45, h: 3.6, a: 0.85),
        Blade(x: 0.49, h: 4.5, a: 1.0),
        Blade(x: 0.54, h: 3.0, a: 0.75),
        Blade(x: 0.58, h: 3.8, a: 0.9),
        Blade(x: 0.63, h: 2.6, a: 0.6),
        Blade(x: 0.67, h: 4.0, a: 0.9),
        Blade(x: 0.71, h: 3.0, a: 0.7),
        Blade(x: 0.76, h: 3.8, a: 0.88),
        Blade(x: 0.80, h: 2.8, a: 0.65),
        Blade(x: 0.84, h: 4.2, a: 0.95),
        Blade(x: 0.89, h: 3.0, a: 0.72),
        Blade(x: 0.93, h: 3.8, a: 0.88),
        Blade(x: 0.97, h: 2.8, a: 0.66)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ForEach(Array(blades.enumerated()), id: \.offset) { _, blade in
                    Capsule()
                        .fill(color.opacity(opacity * blade.a))
                        .frame(width: 0.9, height: blade.h)
                        .position(
                            x: blade.x * proxy.size.width,
                            y: proxy.size.height - blade.h / 2.0
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct Blade {
        let x: Double
        let h: CGFloat
        let a: Double
    }
}

#Preview {
    VStack(spacing: 0) {
        Theme.ridgeNear.frame(height: 80)
            .overlay(RidgeTreeTextureView())
        Theme.foregroundBand.frame(height: 14)
            .overlay(GrassBladeRowView())
    }
}
