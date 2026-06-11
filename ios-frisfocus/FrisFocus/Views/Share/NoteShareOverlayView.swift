//
//  NoteShareOverlayView.swift
//  FrisFocus
//
//  The journal capture's minimal overlay — rendered live on the
//  viewfinder AND composited into the export by ShareCardRenderer.
//  Deliberately the quietest card in the family: a soft scrim, the
//  date in the journal's serif voice, and a small season wordmark.
//  No disclosure layers — the capture itself is the point.
//
//  `layer` mirrors the other overlays so the video compositor's two
//  transparent frames still align; this card has no rising mark, so
//  the `.sunOnly` frame simply renders empty.
//

import SwiftUI

struct NoteShareOverlayView: View {
    let context: ShareNoteContext
    let mode: ShareOverlayMode
    let username: String
    var layer: ShareOverlayLayer = .all
    var bottomPadding: CGFloat = 20

    private var chromeVisible: Bool { layer != .sunOnly }

    private var attributionVisible: Bool {
        switch mode {
        case .composing: return true
        case .render(let attributed): return attributed
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Soft bottom scrim under the text for legibility — the
            // lightest in the family; there's barely any chrome.
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.14), location: 0.55),
                        .init(color: Color.black.opacity(0.36), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(false)

            cluster
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    private var cluster: some View {
        VStack(alignment: .leading, spacing: 7) {
            // The date — the journal's voice.
            Text(context.dateText)
                .font(.sans(11, weight: .semibold))
                .tracking(2.6)
                .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .opacity(chromeVisible ? 1 : 0)

            // The season wordmark, small and serif-italic.
            Text(context.seasonName)
                .font(.serifItalic(15, weight: .medium))
                .foregroundStyle(Color(hex: 0xFFF6E6).opacity(0.72))
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                .lineLimit(2)
                .opacity(chromeVisible ? 1 : 0)

            // Attribution — identity, never a toggle.
            if attributionVisible {
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
                .padding(.top, 2)
                .opacity(chromeVisible ? 1 : 0)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.bottom, bottomPadding)
    }
}

#Preview {
    ZStack {
        Color(hex: 0x2B2218).ignoresSafeArea()
        NoteShareOverlayView(
            context: ShareNoteContext(date: Date(), seasonName: "Keeping Up, Not Drowning"),
            mode: .composing,
            username: "jordan"
        )
    }
}
