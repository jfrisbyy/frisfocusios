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
import UIKit

/// The signature "new story" signal — a gently pulsing amber play
/// button carrying a "New story" label so a fresh, unwatched clip is
/// unmistakable. Tucks into a card corner or sits on a circle header.
struct NewStoryBadge: View {
    /// Drop the label and show just the pulsing play disc — for very
    /// tight corners where the pill would crowd the layout.
    var compact: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    private let amber = Color(red: 216.0 / 255, green: 125.0 / 255, blue: 68.0 / 255)

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 18, height: 18)
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.white)
                    .offset(x: 0.5)
            }

            if !compact {
                Text("New story")
                    .font(.sans(11, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, compact ? 5 : 10)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(amber))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: amber.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 11 : 5)
        .scaleEffect(pulse ? 1.06 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
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

    /// Tapping the badge launches the story directly, when provided.
    /// Otherwise the badge is purely decorative.
    var onTap: (() -> Void)? = nil

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
                    badge
                        .padding(10)
                }
            }
            .onAppear { startPulse() }
            .onChange(of: active) { _, isActive in
                if isActive { startPulse() }
            }
    }

    @ViewBuilder
    private var badge: some View {
        if let onTap {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            } label: {
                NewStoryBadge()
            }
            .buttonStyle(.plain)
        } else {
            NewStoryBadge()
                .allowsHitTesting(false)
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
    /// a gently pulsing amber edge glow + the corner play badge. Pass
    /// `onTap` to make the badge launch the story directly.
    func newStoryGlow(
        _ active: Bool,
        cornerRadius: CGFloat = Theme.cardCornerRadius,
        onTap: (() -> Void)? = nil
    ) -> some View {
        modifier(NewStoryGlowModifier(active: active, cornerRadius: cornerRadius, onTap: onTap))
    }
}

#Preview {
    NewStoryBadge()
        .padding()
        .background(Theme.paperCream)
}
