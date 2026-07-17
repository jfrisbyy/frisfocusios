//
//  SeasonInvitationCard.swift
//  FrisFocus
//
//  The home invitation card — a quiet, pull-not-push nudge toward the
//  deeper season conversation. Shown only when local logic has something
//  specific to say (see `Store.seasonInvitation`). Tapping opens the
//  conversation warm-started with the full season context; "Not now"
//  quiets this observation for good (a different one may return later).
//

import SwiftUI

struct SeasonInvitationCard: View {
    let invitation: SeasonInvitation
    let onTap: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.sunWarm.opacity(0.22))
                        .frame(width: 40, height: 40)
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Theme.sunCore, Theme.sunWarm)
                        .symbolRenderingMode(.palette)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(invitation.headline)
                        .font(.serif(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Text(invitation.cta)
                                .font(.sans(12.5, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textCream)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.textPrimary))

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onDismiss()
                        } label: {
                            Text("Not now")
                                .font(.sans(12.5, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.paperCream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.sunWarm.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pageHorizontalPadding)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -8)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) {
                shown = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(invitation.headline). \(invitation.cta).")
        .accessibilityHint("Double tap to talk it through, or use Not now to dismiss.")
    }
}
