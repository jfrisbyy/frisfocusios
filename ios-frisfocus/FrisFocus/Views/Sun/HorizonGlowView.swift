//
//  HorizonGlowView.swift
//  FrisFocus
//
//  Warm glow at the bottom of the Sun zone — like first light catching
//  the treeline. Wide radial bloom from bottom-center plus a thin warm
//  band along the very bottom edge. Colors come from the SkyPalette so
//  the glow shifts: cool peach at dawn, full warm at midday, deep
//  amber at dusk.
//

import SwiftUI

struct HorizonGlowView: View {
    let palette: SkyPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Wide radial bloom from the bottom-centre
                RadialGradient(
                    stops: [
                        .init(color: palette.halo.opacity(0.32), location: 0.0),
                        .init(color: palette.sunOuter.opacity(0.18), location: 0.40),
                        .init(color: palette.sunOuter.opacity(0.08), location: 0.72),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    center: UnitPoint(x: 0.5, y: 1.0),
                    startRadius: 0,
                    endRadius: max(proxy.size.width * 0.85, 260)
                )
                .blendMode(.plusLighter)

                // Thin warm band at the very bottom edge
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.0),
                        .init(color: palette.halo.opacity(0.10), location: 0.6),
                        .init(color: palette.halo.opacity(0.16), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 48)
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
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

        HorizonGlowView(palette: .afternoon)
    }
}
