//
//  MilestoneFlagMarkView.swift
//  FrisFocus
//
//  The milestone card's signature glyph — a flag planted above the
//  same thin horizon hairline the sun mark uses, so milestone shares
//  read instantly different yet unmistakably family. In motion it's a
//  quiet ember flag; once landed it turns checkered with a warm gold
//  glow, mirroring the sun's goal-hit vibrance.
//
//  Frame proportions match `SunStateMarkView` (driven by `diameter`)
//  so the video compositor's rise animation lands identically.
//

import SwiftUI

struct MilestoneFlagMarkView: View {
    let isLanded: Bool
    var diameter: CGFloat = 38

    private var width: CGFloat { diameter * 1.7 }
    private var height: CGFloat { diameter * 2.0 }
    private var hairlineY: CGFloat { height * 0.85 }

    private var flagColor: Color {
        isLanded ? Color(hex: 0xFFD98A) : Color(hex: 0xE8A85C)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The shared horizon hairline — cream, fading at both ends.
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
            .frame(width: width, height: 1)
            .position(x: width / 2, y: hairlineY)

            // Landed glow — the sun's warm halo treatment at mark scale.
            if isLanded {
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color(hex: 0xFFC668).opacity(0.45), location: 0.0),
                                .init(color: Color(hex: 0xF0A340).opacity(0.18), location: 0.55),
                                .init(color: .clear, location: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter * 0.85
                        )
                    )
                    .frame(width: diameter * 1.7, height: diameter * 1.7)
                    .blur(radius: diameter * 0.05)
                    .position(x: width / 2, y: hairlineY - diameter * 0.55)
            }

            // The flag itself, planted just above the horizon.
            Image(systemName: isLanded ? "flag.checkered" : "flag.fill")
                .font(.system(size: diameter * 0.62, weight: .medium))
                .foregroundStyle(flagColor)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                .shadow(
                    color: isLanded ? Color(hex: 0xF0A340).opacity(0.6) : .clear,
                    radius: 6
                )
                .position(x: width / 2, y: hairlineY - diameter * 0.55)
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel(isLanded ? "Milestone landed flag" : "Milestone flag")
    }
}

#Preview("Flag marks") {
    ZStack {
        Color(hex: 0x241B0C).ignoresSafeArea()
        HStack(spacing: 24) {
            MilestoneFlagMarkView(isLanded: false)
            MilestoneFlagMarkView(isLanded: true)
        }
    }
}
