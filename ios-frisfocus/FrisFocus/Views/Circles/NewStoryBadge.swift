//
//  NewStoryBadge.swift
//  FrisFocus
//
//  A small glowing dot that marks a circle as having a fresh, unwatched
//  story today. Used on circle list cards and on a circle's own page
//  header so there's an at-a-glance signal that something new is waiting
//  to be played. Gently pulses to draw the eye without shouting.
//

import SwiftUI

/// The signature "new story" dot — an amber core with a soft pulsing
/// halo. Sized to tuck into a card corner or sit beside a title.
struct NewStoryBadge: View {
    var diameter: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    private let amber = Color(red: 216.0 / 255, green: 125.0 / 255, blue: 68.0 / 255)

    var body: some View {
        ZStack {
            Circle()
                .fill(amber.opacity(0.30))
                .frame(width: diameter * 2.0, height: diameter * 2.0)
                .scaleEffect(pulse ? 1.0 : 0.7)
                .opacity(pulse ? 0.0 : 0.85)

            Circle()
                .fill(amber)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                )
                .shadow(color: amber.opacity(0.6), radius: 4)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityLabel("New story to watch")
    }
}

#Preview {
    NewStoryBadge()
        .padding()
        .background(Theme.paperCream)
}
