//
//  PeopleCardStep.swift
//  FrisFocus
//
//  Screen A of the account seam — the people card that leads the seam,
//  shown before sign-in. Your own low sun sits at the horizon; two or
//  three warm companion suns rise beside it, a quiet picture of friends
//  witnessing each other's seasons.
//
//  The copy holds three honest promises and must always keep all three:
//    1. you choose your people,
//    2. your numbers are private by default,
//    3. nothing is ever public.
//
//  No growth pressure, no counters — a warm invitation with an equally
//  warm way to pass. "Bring your people" continues into sign-in;
//  "Not now" skips straight past invites toward home.
//

import SwiftUI

struct PeopleCardStep: View {
    /// Continue into sign-in (the season attaches on the next step).
    let onContinue: () -> Void
    /// Pass on people entirely — still signs in, just skips the invite beat.
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false
    @State private var companionsIn: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            CompanionSunsMark(companionsIn: companionsIn, reduceMotion: reduceMotion)
                .frame(height: 132)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.9)
                .padding(.bottom, 30)

            VStack(spacing: 16) {
                EyebrowText(text: "YOUR PEOPLE", opacity: 0.8, color: Theme.textCream)

                Text("Bring your people,\nor don't.")
                    .font(.serif(33, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                bodyCopy
                    .padding(.horizontal, 6)

                promises
                    .padding(.top, 4)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)

            Spacer(minLength: 28)

            VStack(spacing: 14) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onContinue()
                } label: {
                    HStack(spacing: 10) {
                        Text("Bring your people")
                            .font(.sans(17, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.textCream)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSkip()
                } label: {
                    Text("Not now")
                        .font(.sans(14.5, weight: .medium))
                        .foregroundStyle(Theme.textCream.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82)) {
                shown = true
            }
            if reduceMotion {
                companionsIn = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.35)) {
                    companionsIn = true
                }
            }
        }
    }

    private var bodyCopy: some View {
        Text("Friends you choose see the shape of your days — the sun, the showing up, the proof. Your numbers stay yours unless you decide to share them. Nothing is ever public.")
            .font(.serifItalic(15.5, weight: .regular))
            .foregroundStyle(Theme.textCream.opacity(0.88))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var promises: some View {
        VStack(alignment: .leading, spacing: 9) {
            promiseRow("You choose who's in.")
            promiseRow("Your numbers are private by default.")
            promiseRow("Nothing is ever public.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.textCream.opacity(0.16), lineWidth: 1)
        )
    }

    private func promiseRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.sunCore, Theme.textCream.opacity(0.9))
                .symbolRenderingMode(.palette)
            Text(text)
                .font(.sans(13.5, weight: .medium))
                .foregroundStyle(Theme.textCream.opacity(0.92))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Companion suns mark

/// The user's own low sun with two warm companion suns rising in beside
/// it. `companionsIn` fades and lifts the companions after the user's own
/// sun has settled — reduced-motion shows them already present.
private struct CompanionSunsMark: View {
    var companionsIn: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            // Own sun — centered, the anchor.
            sun(size: 62, opacity: 1)
                .zIndex(2)

            // Companions rising in beside it.
            sun(size: 46, opacity: 0.82)
                .offset(x: -58, y: companionsIn ? 10 : 34)
                .opacity(companionsIn ? 0.82 : 0)
                .zIndex(1)

            sun(size: 42, opacity: 0.72)
                .offset(x: 58, y: companionsIn ? 14 : 38)
                .opacity(companionsIn ? 0.72 : 0)
                .zIndex(1)
        }
    }

    private func sun(size: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: size * 1.7, height: size * 1.7)
            Image(systemName: "sun.and.horizon.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Theme.sunCore, Theme.sunWarm)
                .symbolRenderingMode(.palette)
                .opacity(opacity)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(hex: 0x241B3A), Color(hex: 0x8E5A4E)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        PeopleCardStep(onContinue: {}, onSkip: {})
    }
}
