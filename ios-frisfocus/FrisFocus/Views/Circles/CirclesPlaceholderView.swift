//
//  CirclesPlaceholderView.swift
//  FrisFocus
//
//  The "no longer available" page for a Circles route whose target has
//  gone: a friend who was removed, a circle that was deleted or left, a
//  pact that ended — reached from a stale notification, a deep link, or
//  a tap that raced a sync. `CirclesView.destination(for:)` falls back
//  to this whenever a route's id no longer resolves, so navigation
//  always lands somewhere that says what happened instead of on a blank
//  screen.
//
//  It began as a stub for destinations that had not been built yet;
//  every one of those now exists, and this is what is left of it. The
//  look matches the moonlit Circles room so the seam doesn't break
//  visually. Each route passes an eyebrow, a title and a one-line
//  explanation.
//

import SwiftUI

struct CirclesPlaceholderView: View {
    let title: String
    let subtitle: String
    let eyebrow: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x1A1830),
                    Color(hex: 0x2A2438),
                    Color(hex: 0x5A4868)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(eyebrow)
                    .font(.sans(10, weight: .medium))
                    .tracking(2.4)
                    .foregroundStyle(Theme.textCream.opacity(0.7))

                Text(title)
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.serifItalic(15, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .navigationBarBackButtonHidden(false)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        CirclesPlaceholderView(
            title: "Circle",
            subtitle: "This circle is no longer available.",
            eyebrow: "CIRCLE"
        )
    }
}
