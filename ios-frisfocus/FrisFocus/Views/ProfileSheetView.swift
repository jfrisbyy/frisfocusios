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
    @Environment(ProfileStore.self) private var profileStore
    @Environment(Store.self) private var store
    @Environment(CadenceLinkService.self) private var cadence

    /// Presents the real Proofs inbox over the hub (a self-contained
    /// surface with its own header), reached from the "Proofs" row.
    @State private var showProofs: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false

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
            .alert("Delete your account?", isPresented: $showDeleteConfirm) {
                Button("Delete account", role: .destructive) {
                    Task {
                        isDeleting = true
                        let ok = await auth.deleteAccount()
                        isDeleting = false
                        if ok { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently erases your profile, proofs, messages, circles, and friends. This can't be undone.")
            }
            .sheet(isPresented: $showProofs) {
                ProofsInboxView()
                    .environment(auth)
            }
            .task {
                if let myId = auth.user?.id {
                    await profileStore.load(myUserId: myId)
                    await cadence.refresh(myUserId: myId)
                }
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
        let profile = profileStore.myProfile
        let displayName = profile?.name ?? user.name ?? "You"
        let handle = profile?.handle

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                identityHeader(user: user, displayName: displayName, handle: handle)
                    .padding(.top, 10)

                if cadence.isEligible && !store.cadenceConnected && !store.cadenceInviteDismissed {
                    cadenceInviteBanner
                        .padding(.top, 18)
                }

                hubList
                    .padding(.top, 22)

                quietFooter
                    .padding(.top, 28)
                    .padding(.bottom, 28)
            }
        }
    }

    /// Compact identity header: avatar beside name + handle, with the
    /// synced state folded in as a quiet line instead of a big badge.
    private func identityHeader(user: AuthManager.User, displayName: String, handle: String?) -> some View {
        HStack(spacing: 14) {
            avatar(for: user)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.serif(23, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if let handle {
                    Text(handle)
                        .font(.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else if !user.email.isEmpty {
                    Text(user.email)
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.alertGreen)
                    Text("Synced to your account")
                        .font(.sans(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// All hub destinations as one grouped, denser list — a single card
    /// with hairline separators instead of a stack of floating boxes.
    private var hubList: some View {
        VStack(spacing: 0) {
            NavigationLink {
                EditProfileView()
            } label: {
                hubRow(
                    icon: "person.crop.circle",
                    title: "Edit profile",
                    subtitle: "Name, photo, and @username"
                )
            }
            .buttonStyle(.plain)

            hubDivider

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

            hubDivider

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

            if cadence.isEligible {
                hubDivider

                NavigationLink {
                    CadenceConnectView()
                } label: {
                    hubRow(
                        icon: "moon.stars.fill",
                        title: "Cadence",
                        subtitle: store.cadenceConnected
                            ? "Linked routines & sleep outcomes"
                            : "Connect your routines & sleep"
                    )
                }
                .buttonStyle(.plain)
            }

            hubDivider

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

            hubDivider

            NavigationLink {
                BlockedAccountsView()
            } label: {
                hubRow(
                    icon: "hand.raised.fill",
                    title: "Blocked",
                    subtitle: "People you've blocked"
                )
            }
            .buttonStyle(.plain)
        }
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.textPrimary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var hubDivider: some View {
        Rectangle()
            .fill(Theme.textPrimary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 64)
    }

    /// Sign out / delete as quiet text actions — present, never loud.
    private var quietFooter: some View {
        VStack(spacing: 14) {
            Button {
                Task { await auth.signOut() }
            } label: {
                Text("Sign out")
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.alertRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                showDeleteConfirm = true
            } label: {
                Group {
                    if isDeleting {
                        ProgressView().tint(Theme.alertRed)
                    } else {
                        Text("Delete account")
                            .font(.sans(13, weight: .regular))
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
    }

    private var cadenceInviteBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cadenceLavender)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cadence detected")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Link your routines to earn points automatically.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { store.dismissCadenceInvite() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            NavigationLink {
                CadenceConnectView()
            } label: {
                Text("Connect Cadence")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.cadenceLavender)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.cadenceLavenderWash)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cadenceLavender.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func hubRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Theme.textPrimary.opacity(0.06))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
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
        let url = profileStore.myProfile?.photoURL ?? user.photoURL
        ZStack {
            if let url {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialDisc(for: user)
                }
            } else {
                initialDisc(for: user)
            }
        }
        .frame(width: 66, height: 66)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.sunWarm, lineWidth: 2))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
    }

    private func initialDisc(for user: AuthManager.User) -> some View {
        let initials = profileStore.myProfile?.initials ?? user.initials
        return ZStack {
            Theme.textPrimary
            Text(initials.isEmpty ? "?" : initials)
                .font(.serif(24, weight: .medium))
                .foregroundStyle(Theme.textCream)
        }
    }
}

#Preview {
    Color.gray.opacity(0.3)
        .sheet(isPresented: .constant(true)) {
            ProfileSheetView()
                .environment(AuthManager())
                .environment(Store())
                .environment(CadenceLinkService())
        }
}
