//
//  RidgeSeamView.swift
//  FrisFocus
//
//  The visual seam between the Sun zone (deep sky) and the Work zone
//  (warm wheat). Now built up from five layers:
//
//   1. A base strip in the sky's lowest stop
//   2. Distant jagged mountain silhouettes (palette.mountainShadow)
//   3. Three rolling ridges in the palette's ridge tones
//   4. A subtle tree-stroke texture across the near ridge
//   5. A foreground band fading into warm wheat, dusted with grass
//
//  Ridge / mountain colours are pulled from the current SunSky in the
//  environment so the seam shifts with the time of day.
//

import SwiftUI

struct RidgeSeamView: View {
    @Environment(\.sunSky) private var sky

    var body: some View {
        let palette = sky.palette

        ZStack(alignment: .bottom) {
            // 1. Base — continues the lowest sky stop
            palette.skyStops.last ?? Theme.skyLow

            // 2. Distant mountain silhouettes — sit just behind the far ridge
            VStack(spacing: 0) {
                Spacer()
                DistantMountainsView(color: palette.mountainShadow, height: 28)
                    .padding(.bottom, 40)
            }

            // 3. Three rolling ridges
            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                ZStack {
                    farRidge(w: w, h: h)
                        .fill(palette.ridgeFar.opacity(0.95))

                    midRidge(w: w, h: h)
                        .fill(palette.ridgeMid)

                    nearRidge(w: w, h: h)
                        .fill(palette.ridgeNear)
                }
            }

            // 4. Tree texture across the near ridge area
            VStack(spacing: 0) {
                Spacer()
                RidgeTreeTextureView(color: .black, opacity: 0.22)
                    .frame(height: 38)
                    .padding(.bottom, 14)
            }
            .allowsHitTesting(false)

            // 5. Foreground band + grass strokes
            LinearGradient(
                colors: [palette.foregroundBand, Theme.warmWheat],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
            .overlay(
                GrassBladeRowView(color: .black, opacity: 0.30)
            )
        }
        .frame(height: 90)
    }

    // MARK: - Ridge paths

    private func farRidge(w: CGFloat, h: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: h * 0.55))
            path.addCurve(
                to: CGPoint(x: w * 0.45, y: h * 0.40),
                control1: CGPoint(x: w * 0.15, y: h * 0.42),
                control2: CGPoint(x: w * 0.28, y: h * 0.36)
            )
            path.addCurve(
                to: CGPoint(x: w, y: h * 0.52),
                control1: CGPoint(x: w * 0.65, y: h * 0.46),
                control2: CGPoint(x: w * 0.85, y: h * 0.58)
            )
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }
    }

    private func midRidge(w: CGFloat, h: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: h * 0.72))
            path.addCurve(
                to: CGPoint(x: w * 0.30, y: h * 0.58),
                control1: CGPoint(x: w * 0.08, y: h * 0.70),
                control2: CGPoint(x: w * 0.18, y: h * 0.55)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.72, y: h * 0.68),
                control1: CGPoint(x: w * 0.45, y: h * 0.62),
                control2: CGPoint(x: w * 0.58, y: h * 0.74)
            )
            path.addCurve(
                to: CGPoint(x: w, y: h * 0.62),
                control1: CGPoint(x: w * 0.85, y: h * 0.64),
                control2: CGPoint(x: w * 0.93, y: h * 0.60)
            )
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }
    }

    private func nearRidge(w: CGFloat, h: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: h * 0.86))
            path.addCurve(
                to: CGPoint(x: w * 0.40, y: h * 0.74),
                control1: CGPoint(x: w * 0.12, y: h * 0.82),
                control2: CGPoint(x: w * 0.25, y: h * 0.72)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.82, y: h * 0.82),
                control1: CGPoint(x: w * 0.55, y: h * 0.76),
                control2: CGPoint(x: w * 0.70, y: h * 0.88)
            )
            path.addCurve(
                to: CGPoint(x: w, y: h * 0.78),
                control1: CGPoint(x: w * 0.90, y: h * 0.80),
                control2: CGPoint(x: w * 0.96, y: h * 0.78)
            )
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        Theme.skyLow.frame(height: 80)
        RidgeSeamView()
        Theme.warmWheat.frame(height: 80)
    }
    .environment(\.sunSky, .make(now: .now, coordinate: nil))
}
