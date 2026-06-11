//
//  SkeletonComponents.swift
//  FrisFocus
//
//  Shared shimmer skeletons for loading states. Instead of a bare
//  spinner, list surfaces render placeholder rows in the exact shape
//  of their real content with a soft moving sheen — the page feels
//  one beat away from ready instead of empty.
//

import SwiftUI

// MARK: - Shimmer

/// A soft highlight that sweeps across the content on a loop. Applied
/// to skeleton shapes; respects Reduce Motion (the sheen just holds
/// still as a subtle gradient).
struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.2

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.45),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: geo.size.width * phase)
                    .allowsHitTesting(false)
                }
                .clipped()
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

extension View {
    /// Adds the looping skeleton sheen.
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Primitive blocks

/// A rounded placeholder bar — the basic unit skeleton rows compose.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.textPrimary.opacity(0.08))
            .frame(width: width, height: height)
    }
}

/// A circular placeholder — avatars.
struct SkeletonCircle: View {
    var size: CGFloat = 52

    var body: some View {
        Circle()
            .fill(Theme.textPrimary.opacity(0.08))
            .frame(width: size, height: size)
    }
}

// MARK: - Conversation row skeleton

/// Mirrors `ProofConversationRow`'s layout: avatar, name line + time,
/// preview line — all shimmering inside the same white card.
struct SkeletonConversationRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonCircle(size: 52)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SkeletonBlock(width: 120, height: 13)
                    Spacer()
                    SkeletonBlock(width: 34, height: 10)
                }
                SkeletonBlock(width: 190, height: 11)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
        )
        .shimmering()
        .accessibilityHidden(true)
    }
}

/// A friend-picker style skeleton row (smaller avatar, single line).
struct SkeletonPersonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonCircle(size: 46)
            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(width: 130, height: 13)
                SkeletonBlock(width: 90, height: 10)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
        )
        .shimmering()
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Theme.warmWheat.ignoresSafeArea()
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                SkeletonConversationRow()
                    .opacity(1.0 - Double(index) * 0.15)
            }
            SkeletonPersonRow()
        }
        .padding(.horizontal, 20)
    }
}
