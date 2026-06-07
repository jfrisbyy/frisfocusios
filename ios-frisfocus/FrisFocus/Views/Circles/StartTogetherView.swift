//
//  StartTogetherView.swift
//  FrisFocus
//
//  The entry chooser surfaced from the Circles page's start/join row.
//  A pact is a circle of two, so the two ways to start something with
//  people live side by side here: make a 1:1 pact, or start a group
//  circle. Calm and warm — a quiet fork, never a funnel. The actual
//  flows (ProposePactView / CreateCircleView) are presented by the
//  caller once this sheet dismisses, so each opens full-screen.
//

import SwiftUI
import UIKit

struct StartTogetherView: View {
    let onMakePact: () -> Void
    let onStartCircle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("START SOMETHING TOGETHER")
                    .font(.sans(10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Text("Who's it with?")
                    .font(.serif(24, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.top, 10)

            VStack(spacing: 12) {
                optionCard(
                    tint: Theme.categorySpiritual,
                    icon: "person.2.fill",
                    eyebrow: "JUST THE TWO OF YOU",
                    title: "Make a pact",
                    blurb: "A two-person commitment. Same goal, same window — you both finish, or you push each other to it.",
                    action: { tap(onMakePact) }
                )
                optionCard(
                    tint: Theme.alertGreen,
                    icon: "person.3.fill",
                    eyebrow: "A SMALL GROUP",
                    title: "Start a circle",
                    blurb: "A shared goal with a few friends — run the same list, or build toward one number together.",
                    action: { tap(onStartCircle) }
                )
            }
            .padding(.horizontal, Theme.pageHorizontalPadding)
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warmWheat)
    }

    private func tap(_ action: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action()
    }

    private func optionCard(
        tint: Color,
        icon: String,
        eyebrow: String,
        title: String,
        blurb: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.sans(19, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.sans(9, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.serif(19, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(blurb)
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
                    .padding(.top, 18)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.2), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(blurb)
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            StartTogetherView(onMakePact: {}, onStartCircle: {})
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
}
