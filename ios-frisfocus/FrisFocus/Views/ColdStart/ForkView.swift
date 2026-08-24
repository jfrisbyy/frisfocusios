//
//  ForkView.swift
//  FrisFocus
//
//  THE FORK — one screen, two honest doors. Shown right after the
//  account beats on a first run, and forever after as the landing for
//  any authenticated person with no active season (sign-out/return,
//  a deleted season, a mistaken early sign-in). Both doors produce the
//  same real Season object; only the road differs.
//
//  "Build it in about a minute" → the quick tray-and-bands path.
//  "Talk it through"            → the deep season conversation
//                                 (honest ~10–15 min, resumable).
//

import SwiftUI

struct ForkView: View {
    /// Into the quick path (direction pick → boards → capstone → name).
    let onQuick: () -> Void
    /// Into the deep path (the season conversation).
    let onDeep: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    /// True when a half-finished conversation is waiting — the deep door
    /// becomes "pick this up whenever" instead of a cold start.
    private var hasSavedConversation: Bool {
        SeasonSetupResumeStore.hasSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 100, height: 100)
                Image(systemName: "sun.and.horizon.fill")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Theme.sunCore, Theme.sunWarm)
                    .symbolRenderingMode(.palette)
            }
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .padding(.bottom, 26)

            VStack(spacing: 12) {
                EyebrowText(text: "YOUR SEASON", opacity: 0.78, color: Theme.textCream)

                Text("How do you\nwant to start?")
                    .font(.serif(34, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Two doors, one season. You can always go deeper later.")
                    .font(.serifItalic(15.5, weight: .regular))
                    .foregroundStyle(Theme.textCream.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)

            Spacer(minLength: 26)

            VStack(spacing: 14) {
                doorCard(
                    icon: "square.grid.2x2",
                    title: "Build it in about a minute",
                    subtitle: "Pick your directions, drag what counts. The sun starts moving today.",
                    prominent: true,
                    action: onQuick
                )

                doorCard(
                    icon: "bubble.left.and.text.bubble.right",
                    title: hasSavedConversation ? "Pick the conversation back up" : "Talk it through",
                    subtitle: hasSavedConversation
                        ? "Your season chat is saved right where you left it."
                        : "A real conversation about your life. About 10–15 minutes — worth it.",
                    prominent: false,
                    action: onDeep
                )
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)

            Spacer(minLength: 26)
        }
        .padding(.horizontal, 26)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82)) {
                shown = true
            }
        }
    }

    /// One door. Equal class — the quick door is brighter, never bigger.
    private func doorCard(
        icon: String,
        title: String,
        subtitle: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(prominent ? Theme.textPrimary.opacity(0.1) : Color.white.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(prominent ? Theme.textPrimary : Theme.textCream)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.sans(16.5, weight: .semibold))
                        .foregroundStyle(prominent ? Theme.textPrimary : Theme.textCream)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.sans(12.5, weight: .regular))
                        .foregroundStyle(prominent ? Theme.textPrimary.opacity(0.7) : Theme.textCream.opacity(0.72))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(prominent ? Theme.textPrimary.opacity(0.8) : Theme.textCream.opacity(0.7))
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Theme.textCream) : AnyShapeStyle(Color.white.opacity(0.1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        prominent ? Color.clear : Theme.textCream.opacity(0.22),
                        lineWidth: 1
                    )
            )
            .shadow(color: prominent ? .black.opacity(0.22) : .clear, radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

#Preview {
    ZStack {
        DawnBackdrop(progress: 0.3).ignoresSafeArea()
        ForkView(onQuick: {}, onDeep: {})
    }
}
