//
//  BlockedAccountsView.swift
//  FrisFocus
//
//  The list of people the user has blocked, with a one-tap Unblock.
//  Reached from the account hub. Unblocking lets the two find and
//  message each other again (they won't be re-friended automatically).
//

import SwiftUI
import UIKit

struct BlockedAccountsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation

    @State private var blocked: [RemoteProfile] = []
    @State private var isLoading: Bool = true

    private var myId: String? { auth.user?.id }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            content
        }
        .navigationTitle("Blocked")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().tint(Theme.textPrimary)
        } else if blocked.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    Text("Blocked people can't message you, send you requests, or find you. You won't see them either.")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    ForEach(blocked) { profile in
                        row(profile)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
        }
    }

    private func row(_ profile: RemoteProfile) -> some View {
        HStack(spacing: 12) {
            RemoteAvatarView(profile: profile, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let handle = profile.handle {
                    Text(handle)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                guard let myId else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    await moderation.unblock(profile.id, myUserId: myId)
                    blocked.removeAll { $0.id == profile.id }
                }
            } label: {
                Text("Unblock")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.textPrimary.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.paperCream.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.raised")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No one blocked")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("People you block will show up here.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func reload() async {
        guard let myId else { isLoading = false; return }
        await moderation.loadBlocks(myUserId: myId)
        blocked = await moderation.loadBlockedProfiles()
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        BlockedAccountsView()
            .environment(AuthManager())
            .environment(ModerationService())
    }
}
