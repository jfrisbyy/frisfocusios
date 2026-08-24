//
//  EmojiReactionBar.swift
//  FrisFocus
//
//  One-tap reactions for the proof player — five tinted line-icon
//  glyphs (heart, flame, applause, sun, thumbs-up), matching the app's
//  single icon language. Far lower friction than a typed reply: tap a
//  glyph, it bursts into a little firework of itself, and the reaction
//  lands in the 1:1 thread instantly (optimistically).
//
//  Wire format: each reaction still travels as its classic character
//  (the thread table stores plain text), but every surface RENDERS the
//  glyph — so old reactions and new ones read identically.
//
//  The burst is purely decorative — particles fly up from the tapped
//  button with random drift, spin, and fade, then clean themselves up.
//

import SwiftUI
import UIKit

// MARK: - Reaction catalog

/// One quick reaction: its wire text (stored as the message body), the
/// line-icon it renders as, and its tint.
struct ProofReaction: Identifiable, Equatable {
    let id: String
    let symbol: String
    let tint: Color
    let label: String

    /// The five offered in the player bar.
    static let bar: [ProofReaction] = [
        ProofReaction(id: "\u{2764}\u{FE0F}", symbol: "heart.fill", tint: Color(hex: 0xED93B1), label: "Heart"),
        ProofReaction(id: "\u{1F525}", symbol: "flame.fill", tint: Color(hex: 0xE8853D), label: "Flame"),
        ProofReaction(id: "\u{1F44F}", symbol: "hands.clap.fill", tint: Color(hex: 0xD8B44A), label: "Applause"),
        ProofReaction(id: "\u{2600}\u{FE0F}", symbol: "sun.max.fill", tint: Color(hex: 0xE0A334), label: "Sun"),
        ProofReaction(id: "\u{1F44D}", symbol: "hand.thumbsup.fill", tint: Color(hex: 0x8FB339), label: "Thumbs up"),
    ]

    /// Legacy reactions from earlier builds, still rendered as glyphs.
    private static let legacy: [ProofReaction] = [
        ProofReaction(id: "\u{1F602}", symbol: "face.smiling", tint: Color(hex: 0xD8B44A), label: "Laugh"),
        ProofReaction(id: "\u{1F4AA}", symbol: "dumbbell.fill", tint: Color(hex: 0x8FB339), label: "Strong"),
    ]

    /// Resolve a message body to a known reaction, if it is exactly one.
    static func match(_ body: String?) -> ProofReaction? {
        guard let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return (bar + legacy).first { $0.id == trimmed }
    }
}

// MARK: - Reaction bar

/// A floating capsule of quick reactions shown over an incoming proof.
struct ProofReactionBar: View {
    let onReact: (String) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(ProofReaction.bar) { reaction in
                ReactionBurstButton(reaction: reaction) {
                    onReact(reaction.id)
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

/// One reaction glyph that pops and emits a particle burst when tapped.
struct ReactionBurstButton: View {
    let reaction: ProofReaction
    let action: () -> Void

    @State private var particles: [ReactionParticle] = []
    @State private var bumped: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            bump()
            burst()
            action()
        } label: {
            Image(systemName: reaction.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(reaction.tint)
                .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(bumped ? 1.3 : 1)
        .overlay {
            ZStack {
                ForEach(particles) { particle in
                    ReactionParticleView(reaction: reaction, particle: particle)
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel("React with \(reaction.label)")
    }

    private func bump() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { bumped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { bumped = false }
        }
    }

    private func burst() {
        let fresh = (0..<8).map { _ in ReactionParticle() }
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
struct ReactionParticle: Identifiable {
    let id = UUID()
    let dx: CGFloat = .random(in: -70...70)
    let dy: CGFloat = .random(in: -200 ... -90)
    let spin: Double = .random(in: -42...42)
    let scale: CGFloat = .random(in: 0.7...1.5)
    let duration: Double = .random(in: 0.65...1.1)
}

private struct ReactionParticleView: View {
    let reaction: ProofReaction
    let particle: ReactionParticle

    @State private var flown: Bool = false

    var body: some View {
        Image(systemName: reaction.symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(reaction.tint)
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
