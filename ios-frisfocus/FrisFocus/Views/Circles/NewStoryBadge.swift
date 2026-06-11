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
    var diameter: CGFloat = 13
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
                    Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 1.6)
                )
                .shadow(color: amber.opacity(0.85), radius: 6)
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

/// A pulsing amber glow ring hugging a card's rounded edge plus the
/// signature dot in the top-trailing corner. Applied to every circle
/// preview card so a fresh, unwatched story visibly radiates instead
/// of relying on a small corner dot alone.
struct NewStoryGlowModifier: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = Theme.cardCornerRadius

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    private let amber = Color(red: 216.0 / 255, green: 125.0 / 255, blue: 68.0 / 255)

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(amber.opacity(pulse ? 0.95 : 0.55), lineWidth: 1.6)
                        .shadow(color: amber.opacity(pulse ? 0.75 : 0.35), radius: pulse ? 10 : 5)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if active {
                    NewStoryBadge()
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { startPulse() }
            .onChange(of: active) { _, isActive in
                if isActive { startPulse() }
            }
    }

    private func startPulse() {
        guard active, !reduceMotion else { return }
        pulse = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

extension View {
    /// Marks a circle preview card as carrying a fresh, unwatched story:
    /// a gently pulsing amber edge glow + the corner dot.
    func newStoryGlow(_ active: Bool, cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        modifier(NewStoryGlowModifier(active: active, cornerRadius: cornerRadius))
    }
}

#Preview {
    NewStoryBadge()
        .padding()
        .background(Theme.paperCream)
}
