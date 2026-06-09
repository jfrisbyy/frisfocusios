//
//  AddFriendLinkView.swift
//  FrisFocus
//
//  The landing a shared invite link (or scanned code) opens to: the
//  inviter's profile and a single clear Add control. Loads the target
//  profile and the viewer's current relationship to them, so the button
//  reads correctly — Add, Request sent, Accept, or Already friends.
//

import SwiftUI
import UIKit

struct AddFriendLinkView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let userId: String

    @State private var service = FriendGraphService()
    @State private var profile: RemoteProfile?
    @State private var didLoad: Bool = false
    @State private var isLoadingProfile: Bool = true

    private var myId: String? { auth.user?.id }

    private var relationship: FriendRelationship {
        guard let myId else { return .none }
        return service.relationship(to: userId, myUserId: myId)
    }

    var body: some View {
        @Bindable var service = service

        ZStack {
            Theme.warmWheat.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                content
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task { await load() }
        .alert("Something went wrong", isPresented: $service.showError) {
            Button("OK") { }
        } message: {
            Text(service.errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Text("FRIEND INVITE")
                .font(.sans(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.textPrimary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, 18)
    }

    @ViewBuilder
    private var content: some View {
        if myId == nil {
            signedOut
        } else if isLoadingProfile {
            ProgressView().tint(Theme.textPrimary)
        } else if let profile {
            VStack(spacing: 16) {
                RemoteAvatarView(profile: profile, size: 96)

                VStack(spacing: 4) {
                    Text(profile.displayName)
                        .font(.serif(24, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    if let handle = profile.handle {
                        Text(handle)
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                actionButton(for: profile)
                    .padding(.top, 4)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("We couldn't find that person")
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("This invite link may be old or invalid.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func actionButton(for profile: RemoteProfile) -> some View {
        switch relationship {
        case .isMe:
            statusPill(text: "This is you", systemImage: "person.fill")
        case .friends:
            statusPill(text: "Already friends", systemImage: "checkmark.seal.fill", tint: Theme.alertGreen)
        case .requestSent:
            statusPill(text: "Request sent", systemImage: "clock.fill")
        case .requestReceived:
            primaryButton(title: "Accept request", systemImage: "checkmark") {
                guard let myId,
                      let request = service.incoming.first(where: { $0.profile.id == profile.id }) else { return }
                Task { await service.accept(request, myUserId: myId) }
            }
        case .none:
            primaryButton(title: "Add friend", systemImage: "person.badge.plus") {
                guard let myId else { return }
                Task { await service.sendRequest(to: profile, myUserId: myId) }
            }
        }
    }

    private func primaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                Text(title).font(.sans(16, weight: .semibold))
            }
            .foregroundStyle(Theme.textCream)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func statusPill(text: String, systemImage: String, tint: Color = Theme.textSecondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
            Text(text).font(.sans(16, weight: .semibold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.textPrimary.opacity(0.1), lineWidth: 1)
        )
    }

    private var signedOut: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Sign in to add friends")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Open your profile to sign in, then tap the invite link again.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Load

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        if let myId { await service.load(myUserId: myId) }
        profile = await service.fetchProfile(id: userId)
        isLoadingProfile = false
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            AddFriendLinkView(userId: "usr_preview")
                .environment(AuthManager())
        }
}
