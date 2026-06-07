//
//  CirclesPlaceholderView.swift
//  FrisFocus
//
//  A tiny stub used by C3d to terminate navigation routes that point at
//  destinations not yet built (friend detail in C6, friend story in C9,
//  circle detail in C4, circle group story in C9, the circle creation
//  flow in a later prompt). The look matches the moonlit Circles room
//  so the seams don't break visually when a tap lands here today.
//
//  Each route passes a title + a short subtitle so the placeholder
//  reads as informative rather than empty. Once the real destinations
//  land, the calls in `CirclesView` get pointed at them and this file
//  can be deleted in one pass.
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
            title: "Aaron",
            subtitle: "Friend detail lands in C6.",
            eyebrow: "COMING SOON"
        )
    }
}
