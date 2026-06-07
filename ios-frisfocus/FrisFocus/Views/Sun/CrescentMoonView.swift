//
//  CrescentMoonView.swift
//  FrisFocus
//
//  A small, ghostly crescent for editorial balance opposite the sun.
//  Drawn with a clipped/masked circle so the unlit side composites
//  cleanly against the sky gradient.
//

import SwiftUI

struct CrescentMoonView: View {
    var diameter: CGFloat = 22

    var body: some View {
        ZStack {
            // Soft outer glow — barely there
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.textCream.opacity(0.10),
                            Theme.textCream.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: diameter * 0.4,
                        endRadius: diameter * 1.4
                    )
                )
                .frame(width: diameter * 2.2, height: diameter * 2.2)

            // The crescent itself — two circles, second one cut out via mask
            Circle()
                .fill(Theme.textCream.opacity(0.22))
                .frame(width: diameter, height: diameter)
                .mask {
                    ZStack {
                        Circle()
                            .frame(width: diameter, height: diameter)
                        Circle()
                            .frame(width: diameter * 0.88, height: diameter * 0.88)
                            .offset(x: diameter * 0.30, y: -diameter * 0.06)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .blur(radius: 0.35)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Theme.skyDeep, Theme.skyMid],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        CrescentMoonView()
    }
}
