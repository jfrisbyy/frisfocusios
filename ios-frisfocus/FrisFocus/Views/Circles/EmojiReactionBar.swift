//
//  EmojiReactionBar.swift
//  FrisFocus
//
//  One-tap emoji reactions for the proof player. Far lower friction
//  than a typed reply: tap a glyph, it bursts into a little firework
//  of itself, and the reaction lands in the 1:1 thread instantly
//  (optimistically) as an emoji note.
//
//  The burst is purely decorative — particles fly up from the tapped
//  button with random drift, spin, and fade, then clean themselves up.
//

import SwiftUI
import UIKit

// MARK: - Reaction bar

/// A floating capsule of quick reactions shown over an incoming proof.
struct ProofReactionBar: View {
    let onReact: (String) -> Void

    private let emojis = ["❤️", "🔥", "👏", "😂", "💪"]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(emojis, id: \.self) { emoji in
                EmojiBurstButton(emoji: emoji) {
                    onReact(emoji)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.38)))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick reactions")
    }
}

// MARK: - Burst button

/// One emoji button that pops and emits a particle burst when tapped.
struct EmojiBurstButton: View {
    let emoji: String
    let action: () -> Void

    @State private var particles: [EmojiParticle] = []
    @State private var bumped: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            bump()
            burst()
            action()
        } label: {
            Text(emoji)
                .font(.system(size: 26))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(bumped ? 1.3 : 1)
        .overlay {
            ZStack {
                ForEach(particles) { particle in
                    EmojiParticleView(emoji: emoji, particle: particle)
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel("React with \(emoji)")
    }

    private func bump() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { bumped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { bumped = false }
        }
    }

    private func burst() {
        let fresh = (0..<8).map { _ in EmojiParticle() }
        particles.append(contentsOf: fresh)
        let ids = Set(fresh.map(\.id))
        // Sweep this burst's particles once their animations finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            particles.removeAll { ids.contains($0.id) }
        }
    }
}

// MARK: - Particles

/// One particle's randomized flight plan, fixed at creation so the
/// animation runs on stable values.
struct EmojiParticle: Identifiable {
    let id = UUID()
    let dx: CGFloat = .random(in: -70...70)
    let dy: CGFloat = .random(in: -200 ... -90)
    let spin: Double = .random(in: -42...42)
    let scale: CGFloat = .random(in: 0.7...1.5)
    let duration: Double = .random(in: 0.65...1.1)
}

private struct EmojiParticleView: View {
    let emoji: String
    let particle: EmojiParticle

    @State private var flown: Bool = false

    var body: some View {
        Text(emoji)
            .font(.system(size: 21))
            .scaleEffect(flown ? particle.scale : 0.4)
            .rotationEffect(.degrees(flown ? particle.spin : 0))
            .offset(x: flown ? particle.dx : 0, y: flown ? particle.dy : -6)
            .opacity(flown ? 0 : 0.95)
            .onAppear {
                withAnimation(.easeOut(duration: particle.duration)) { flown = true }
            }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ProofReactionBar { _ in }
    }
}
