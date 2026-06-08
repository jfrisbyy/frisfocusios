//
//  ProfileSheetView.swift
//  FrisFocus
//
//  The "You" experience — the account hub shown when the user taps the
//  top-right avatar on the homepage. Signed out, it offers Google / Apple
//  sign-in (via Rork Auth). Signed in, it shows the account and a sign-out
//  control. Profile, settings, season management, and history hang off
//  this screen as follow-ups.
//

import SwiftUI
import AuthenticationServices

struct ProfileSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth

    /// Presents the real Proofs inbox over the hub (a self-contained
    /// surface with its own header), reached from the "Proofs" row.
    @State private var showProofs: Bool = false

    var body: some View {
        @Bindable var auth = auth

        NavigationStack {
            ZStack {
                Theme.warmWheat.ignoresSafeArea()

                Group {
                    if auth.isLoading {
                        ProgressView()
                            .tint(Theme.textPrimary)
                    } else if let user = auth.user {
                        signedIn(user)
                    } else {
                        signedOut
                    }
                }
                .padding(.horizontal, 28)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .toolbarBackground(Theme.warmWheat, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Sign in failed", isPresented: $auth.showError) {
                Button("OK") { }
            } message: {
                Text(auth.errorMessage)
            }
            .sheet(isPresented: $showProofs) {
                ProofsInboxView()
                    .environment(auth)
            }
        }
    }

    // MARK: - Signed out

    private var signedOut: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 12)

            emblem(systemName: "sun.max.fill")

            VStack(spacing: 10) {
                EyebrowText(text: "Your account")

                Text("Sign in to FrisFocus")
                    .font(.serif(27, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Keep your circles, pacts, and stories in sync across every device you carry through the day.")
                    .font(.sans(14, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
            }
            .padding(.top, 22)

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { _ in
                    Task { await auth.signIn(provider: "apple") }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(auth.isSigningIn)

                googleButton
            }
            .padding(.top, 32)
            .overlay(alignment: .top) {
                if auth.isSigningIn {
                    ProgressView()
                        .tint(Theme.textPrimary)
                        .padding(.top, -28)
                }
            }

            Text("We only use your name and email to set up your account.")
                .font(.sans(11, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
                .padding(.horizontal, 16)

            Spacer()
        }
    }

    private var googleButton: some View {
        Button {
            Task { await auth.signIn(provider: "google") }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .semibold))
                Text("Continue with Google")
                    .font(.sans(17, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.textPrimary.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn)
    }

    // MARK: - Signed in

    private func signedIn(_ user: AuthManager.User) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)

            avatar(for: user)

            VStack(spacing: 5) {
                Text(user.name ?? "You")
                    .font(.serif(26, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.sans(14, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 16)

            syncedBadge
                .padding(.top, 18)

            VStack(spacing: 10) {
                NavigationLink {
                    FriendsView()
                } label: {
                    hubRow(
                        icon: "person.2.fill",
                        title: "Friends",
                        subtitle: "Add real friends and accept requests"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SharedCirclesListView()
                } label: {
                    hubRow(
                        icon: "circle.hexagongrid.fill",
                        title: "Circles",
                        subtitle: "Shared goals you run with friends"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showProofs = true
                } label: {
                    hubRow(
                        icon: "paperplane.fill",
                        title: "Proofs",
                        subtitle: "Private notes and proofs with friends"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 24)

            Text("Settings, season management, and history will live here.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 18)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                Task { await auth.signOut() }
            } label: {
                Text("Sign out")
                    .font(.sans(16, weight: .medium))
                    .foregroundStyle(Theme.alertRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.alertRed.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
    }

    private var syncedBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.alertGreen)
            Text("Synced to your account")
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.alertGreen.opacity(0.1))
        .clipShape(Capsule())
    }

    private func hubRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.textPrimary.opacity(0.06))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sans(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Pieces

    private func emblem(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Theme.textPrimary)
                .frame(width: 76, height: 76)
                .overlay(
                    Circle().stroke(Theme.sunWarm, lineWidth: 2)
                )
            Image(systemName: systemName)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.sunWarm)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private func avatar(for user: AuthManager.User) -> some View {
        ZStack {
            if let url = user.photoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialDisc(for: user)
                }
            } else {
                initialDisc(for: user)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 2))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private func initialDisc(for user: AuthManager.User) -> some View {
        ZStack {
            Theme.textPrimary
            Text(user.initials.isEmpty ? "?" : user.initials)
                .font(.serif(30, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }
}

#Preview {
    Color.gray.opacity(0.3)
        .sheet(isPresented: .constant(true)) {
            ProfileSheetView()
                .environment(AuthManager())
        }
}
