//
//  BlockedAccountsView.swift
//  FrisFocus
//
//  The two lists of people the user has turned down, each with a
//  one-tap undo. Reached from the account hub.
//
//  Blocked and muted sit on one page because they are the same
//  instinct at two strengths, and seeing them together makes the
//  difference legible: a block is a wall, a mute is a volume dial.
//  Unblocking lets the two find and message each other again (they
//  won't be re-friended automatically); unmuting simply lets their
//  moments back into the feed.
//

import SwiftUI
import UIKit

struct BlockedAccountsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation

    @State private var blocked: [RemoteProfile] = []
    @State private var muted: [RemoteProfile] = []
    @State private var isLoading: Bool = true

    private var myId: String? { auth.user?.id }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            content
        }
        .navigationTitle("Blocked and muted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().tint(Theme.textPrimary)
        } else if blocked.isEmpty && muted.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 26) {
                    if !blocked.isEmpty { section(.blocked) }
                    if !muted.isEmpty { section(.muted) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
        }
    }

    /// The two lists this page holds. Same rows either way — only the
    /// wording and the undo differ.
    private enum ListKind {
        case blocked
        case muted

        var title: String {
            switch self {
            case .blocked: return "Blocked"
            case .muted: return "Muted"
            }
        }

        var note: String {
            switch self {
            case .blocked:
                return "Blocked people can't message you, send you requests, or find you. You won't see them either."
            case .muted:
                return "Muted people stay friends and stay reachable. Their moments just don't come to you, and their notifications stay quiet. They are never told."
            }
        }

        var actionTitle: String {
            switch self {
            case .blocked: return "Unblock"
            case .muted: return "Unmute"
            }
        }
    }

    private func profiles(for kind: ListKind) -> [RemoteProfile] {
        switch kind {
        case .blocked: return blocked
        case .muted: return muted
        }
    }

    private func undo(_ profile: RemoteProfile, kind: ListKind) async {
        guard let myId else { return }
        switch kind {
        case .blocked:
            await moderation.unblock(profile.id, myUserId: myId)
            blocked.removeAll { $0.id == profile.id }
        case .muted:
            await moderation.unmute(profile.id, myUserId: myId)
            muted.removeAll { $0.id == profile.id }
        }
    }

    private func section(_ kind: ListKind) -> some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.serif(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(kind.note)
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)

            ForEach(profiles(for: kind)) { profile in
                row(profile, kind: kind)
            }
        }
    }

    private func row(_ profile: RemoteProfile, kind: ListKind) -> some View {
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
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await undo(profile, kind: kind) }
            } label: {
                Text(kind.actionTitle)
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
            Text("No one blocked or muted")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("People you block or mute will show up here.")
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
        muted = await moderation.loadMutedProfiles()
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
