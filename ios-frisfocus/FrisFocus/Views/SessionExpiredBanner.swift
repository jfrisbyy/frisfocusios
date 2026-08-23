//
//  SessionExpiredBanner.swift
//  FrisFocus
//
//  The visible answer to a silent sign-out. When the auth server
//  rejects a stored refresh token the app used to quietly sign the
//  person out — home looked empty and cloud data seemed "gone". This
//  banner names what happened and offers the way back in, right there.
//
//  Renders itself only while `auth.sessionExpired` holds and no user is
//  signed in; signing back in (or dismissing) clears it.
//

import SwiftUI
import UIKit

struct SessionExpiredBanner: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        if auth.sessionExpired && auth.user == nil {
            card
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.sunOuter)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text("You've been signed out")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                    Text("Your days are safe on this phone. Sign back in so they keep syncing and friends stay in reach.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textCream.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        auth.sessionExpired = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textCream.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            HStack(spacing: 8) {
                signInButton(title: "Sign in with Apple", icon: "apple.logo", provider: "apple")
                signInButton(title: "Google", icon: "globe", provider: "google")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.sunWarm.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    private func signInButton(title: String, icon: String, provider: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await auth.signIn(provider: provider) }
        } label: {
            HStack(spacing: 6) {
                if auth.isSigningIn {
                    ProgressView()
                        .tint(Theme.textPrimary)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.sans(12, weight: .semibold))
                    Text(title)
                        .font(.sans(12.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(Theme.textCream))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn)
        .accessibilityLabel(title)
    }
}

#Preview {
    ZStack {
        Theme.warmWheat.ignoresSafeArea()
        SessionExpiredBanner()
            .environment(AuthManager())
    }
}
