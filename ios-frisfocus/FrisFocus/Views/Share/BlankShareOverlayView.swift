//
//  BlankShareOverlayView.swift
//  FrisFocus
//
//  The "no overlay" page of the share camera. While composing and on
//  in-app sends it draws absolutely nothing — a clean viewfinder, a
//  clean card. Only when the result leaves the app (`.render(attributed:
//  true)`) does it add the mandatory identity line — orb glyph +
//  "@USERNAME · FRISFOCUS" — over a whisper of scrim for legibility.
//
//  `layer` mirrors the other overlays so the video compositor's two
//  transparent frames still align; this card has no rising mark, so the
//  `.sunOnly` frame renders empty.
//

import SwiftUI

struct BlankShareOverlayView: View {
    let mode: ShareOverlayMode
    let username: String
    var layer: ShareOverlayLayer = .all
    var bottomPadding: CGFloat = 20

    private var chromeVisible: Bool { layer != .sunOnly }

    /// The watermark exists ONLY on attributed renders — never while
    /// composing, never on clean in-app sends.
    private var attributionVisible: Bool {
        if case .render(true) = mode { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if attributionVisible {
                // The lightest possible scrim — just enough to keep the
                // identity line readable on bright footage.
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.black.opacity(0.10), location: 0.55),
                            .init(color: Color.black.opacity(0.28), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                }
                .opacity(chromeVisible ? 1 : 0)

                HStack(spacing: 7) {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: 0xFFE2A6), Color(hex: 0xF0A340)],
                                center: UnitPoint(x: 0.4, y: 0.35),
                                startRadius: 0,
                                endRadius: 6
                            )
                        )
                        .frame(width: 10, height: 10)
                        .shadow(color: Color(hex: 0xF0A340).opacity(0.7), radius: 3)

                    Text("@\(username.uppercased()) · FRISFOCUS")
                        .font(.sans(10.5, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.75))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .padding(.leading, 20)
                .padding(.bottom, bottomPadding)
                .opacity(chromeVisible ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }
}
