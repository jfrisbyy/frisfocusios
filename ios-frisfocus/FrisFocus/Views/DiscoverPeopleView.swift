//
//  DiscoverPeopleView.swift
//  FrisFocus
//
//  The full "Discover people" screen, pushed from the Friends page's
//  See all link. Every person on the app you're not connected to,
//  friends-of-friends first (by mutual count) then newest members,
//  with the same one-tap Add → Pending rows and profile previews as
//  the inline section. Pull to refresh re-ranks the list.
//

import SwiftUI

struct DiscoverPeopleView: View {
    /// Shared with the Friends page so Add/Pending state stays in sync
    /// across both surfaces.
    let graph: FriendGraphService
    let discover: DiscoverService

    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync

    @State private var preview: DiscoverSuggestion?

    private var myId: String? { auth.user?.id }

    /// Blocked accounts are hidden; rows you've just added stay visible
    /// as Pending until the next refresh re-ranks the list.
    private var visibleSuggestions: [DiscoverSuggestion] {
        guard let myId else { return [] }
        return discover.suggestions.filter { suggestion in
            guard !moderation.isBlocked(suggestion.profile.id) else { return false }
            switch graph.relationship(to: suggestion.profile.id, myUserId: myId) {
            case .none, .requestSent: return true
            case .friends, .requestReceived, .isMe: return false
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            content
        }
        .navigationTitle("Discover people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable { await reloadAll() }
        .task {
            if !discover.hasLoaded { await reloadAll() }
        }
        .sheet(item: $preview) { suggestion in
            DiscoverProfileSheet(suggestion: suggestion, graph: graph)
        }
    }

    @ViewBuilder
    private var content: some View {
        if discover.isLoading && visibleSuggestions.isEmpty {
            ProgressView()
                .tint(Theme.textPrimary)
        } else if visibleSuggestions.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("People on FrisFocus you're not connected with yet — friends of friends first.")
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 4)

                    ForEach(visibleSuggestions) { suggestion in
                        row(for: suggestion)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 44)
            }
        }
    }

    private func row(for suggestion: DiscoverSuggestion) -> some View {
        DiscoverPersonRow(
            suggestion: suggestion,
            relationship: myId.map { graph.relationship(to: suggestion.profile.id, myUserId: $0) } ?? .none,
            onOpen: { preview = suggestion },
            onAdd: {
                guard let myId else { return }
                Task {
                    await graph.sendRequest(to: suggestion.profile, myUserId: myId)
                    socialSync.pokeEngine(trigger: "friend")
                }
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "binoculars")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No one new right now")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("You're connected with everyone we can suggest. Invite friends with your link, or check back soon.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
    }

    private func reloadAll() async {
        guard let myId else { return }
        await graph.load(myUserId: myId)
        await discover.refresh(myUserId: myId, graph: graph)
    }
}
