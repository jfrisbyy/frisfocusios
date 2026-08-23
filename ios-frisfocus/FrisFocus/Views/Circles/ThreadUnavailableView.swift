//
//  ThreadUnavailableView.swift
//  FrisFocus
//
//  Shown in place of a 1:1 thread when the real, synced conversation
//  can't open — either the user is signed out, or the friend's cloud
//  profile hasn't resolved yet. Messages in FrisFocus are ONLY ever the
//  Supabase-backed kind; there is no local-only composer fallback, so
//  nothing a person writes can silently go nowhere.
//

import SwiftUI
import UIKit

struct ThreadUnavailableView: View {
    /// The person the user tried to message, for warm copy.
    let friendName: String

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private var isSignedOut: Bool { auth.user == nil }

    var body: some View {
        @Bindable var auth = auth
        return ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: isSignedOut ? "person.crop.circle.badge.exclamationmark" : "bubble.left.and.bubble.right")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.textTertiary)

                Text(isSignedOut ? "Sign in to message \(friendName)" : "Connecting to \(friendName)…")
                    .font(.serif(21, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(isSignedOut
                     ? "Notes and proofs travel between real accounts, so they always arrive. Sign back in and this thread opens right up."
                     : "Their profile is still syncing. Give it a moment and try again.")
                    .font(.sans(13.5, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                if isSignedOut {
                    VStack(spacing: 10) {
                        signInButton(label: "Sign in with Apple", icon: "apple.logo", provider: "apple", filled: true)
                        signInButton(label: "Sign in with Google", icon: "globe", provider: "google", filled: false)
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 44)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.textCream)
                            .padding(.horizontal, 26)
                            .frame(height: 44)
                            .background(Theme.textPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .padding(28)
        }
        .alert("Sign in failed", isPresented: $auth.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(auth.errorMessage)
        }
    }

    @ViewBuilder
    private func signInButton(label: String, icon: String, provider: String, filled: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await auth.signIn(provider: provider) }
        } label: {
            HStack(spacing: 8) {
                if auth.isSigningIn {
                    ProgressView()
                        .tint(filled ? Theme.textCream : Theme.textPrimary)
                } else {
                    Image(systemName: icon)
                        .font(.sans(14, weight: .semibold))
                    Text(label)
                        .font(.sans(14.5, weight: .semibold))
                }
            }
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Group {
                    if filled {
                        Capsule().fill(Theme.textPrimary)
                    } else {
                        Capsule().strokeBorder(Theme.textPrimary.opacity(0.3), lineWidth: 1.2)
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn)
    }
}

#Preview {
    ThreadUnavailableView(friendName: "Maya")
        .environment(AuthManager())
}
