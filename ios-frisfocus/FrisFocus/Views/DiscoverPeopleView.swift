//
//  DiscoverPeopleView.swift
//  FrisFocus
//
//  The full Discover screen, pushed from the Friends page. Top to
//  bottom: a live as-you-type search bar, the Find-friends-from-contacts
//  entry, the Near-you opt-in card (or its section once on), friends of
//  friends ranked by mutual count, then the newest members. Sections
//  with nothing to show simply don't appear. Pull to refresh re-ranks
//  everything at once.
//

import SwiftUI
import UIKit
import CoreLocation

struct DiscoverPeopleView: View {
    /// Shared with the Friends page so Add/Pending state stays in sync
    /// across both surfaces.
    let graph: FriendGraphService
    let discover: DiscoverService

    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(ProfileStore.self) private var profileStore

    @State private var preview: DiscoverSuggestion?
    @State private var query: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var location = LocationService()
    @State private var nearYouBusy: Bool = false
    @State private var nearYouHint: String?
    @FocusState private var searchFocused: Bool

    private var myId: String? { auth.user?.id }

    /// Search mode kicks in at two useful characters.
    private var isSearchActive: Bool {
        query.trimmingCharacters(in: .whitespaces).count >= 2
    }

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

    private var mutualTier: [DiscoverSuggestion] {
        visibleSuggestions.filter { $0.mutualCount > 0 }
    }

    /// Newest members, minus anyone already shown in Near you.
    private var newestTier: [DiscoverSuggestion] {
        let nearbyIds = Set(visibleNearby.map(\.id))
        return visibleSuggestions.filter { $0.mutualCount == 0 && !nearbyIds.contains($0.id) }
    }

    private var visibleNearby: [DiscoverSuggestion] {
        guard let myId else { return [] }
        return discover.nearby.filter { suggestion in
            guard !moderation.isBlocked(suggestion.profile.id) else { return false }
            switch graph.relationship(to: suggestion.profile.id, myUserId: myId) {
            case .none, .requestSent: return true
            case .friends, .requestReceived, .isMe: return false
            }
        }
    }

    private var visibleSearchResults: [RemoteProfile] {
        discover.searchResults.filter { !moderation.isBlocked($0.id) }
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
            await profileStore.load(myUserId: myId ?? "")
            if let myId {
                await discover.refreshNearby(myUserId: myId, graph: graph, areaKey: profileStore.myProfile?.areaKey)
            }
        }
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
        .sheet(item: $preview) { suggestion in
            DiscoverProfileSheet(suggestion: suggestion, graph: graph)
        }
    }

    @ViewBuilder
    private var content: some View {
        if discover.isLoading && visibleSuggestions.isEmpty && !isSearchActive {
            // Shape-true skeletons instead of a bare spinner — the list
            // arrives into the same silhouette it loaded behind.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<6, id: \.self) { index in
                        SkeletonPersonRow()
                            .opacity(1.0 - Double(index) * 0.12)
                    }
                }
                .padding(.horizontal, Theme.pageHorizontalPadding)
                .padding(.top, 18)
            }
            .scrollDisabled(true)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    searchBar

                    if isSearchActive {
                        searchSection
                    } else {
                        contactsEntry
                        nearYouSection
                        if !mutualTier.isEmpty { suggestionSection(
                            title: "FRIENDS OF FRIENDS",
                            subtitle: "People your friends already know.",
                            suggestions: mutualTier
                        ) }
                        if !newestTier.isEmpty { suggestionSection(
                            title: "NEW TO FRISFOCUS",
                            subtitle: "The newest people on the app.",
                            suggestions: newestTier
                        ) }
                        if mutualTier.isEmpty && newestTier.isEmpty && visibleNearby.isEmpty {
                            emptyState
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            TextField("Search by @username, name, or email", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .font(.sans(15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)

            if discover.isSearching {
                ProgressView().controlSize(.small).tint(Theme.textTertiary)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.textPrimary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var searchSection: some View {
        if visibleSearchResults.isEmpty {
            if !discover.isSearching {
                Text("No one found. Try a different @username, name, or email.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleSearchResults) { profile in
                    row(for: DiscoverSuggestion(profile: profile, mutualCount: 0))
                }
            }
        }
    }

    /// Debounced as-you-type search — a brief pause so it never feels
    /// jumpy, then one query for the latest text.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            discover.searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let myId else { return }
            await discover.search(query: trimmed, myUserId: myId)
        }
    }

    // MARK: - Contacts entry

    private var contactsEntry: some View {
        NavigationLink {
            ContactsMatchView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.textPrimary)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find friends from contacts")
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("See who you know is already here")
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
        .buttonStyle(.plain)
    }

    // MARK: - Near you

    @ViewBuilder
    private var nearYouSection: some View {
        if profileStore.nearYouEnabled {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader(
                        "NEAR YOU",
                        subtitle: profileStore.myProfile?.areaName.map { "Near \($0)" } ?? "People roughly in your area."
                    )
                    Spacer()
                    Button {
                        guard let myId else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            await profileStore.setNearYou(areaKey: nil, areaName: nil, myUserId: myId)
                            await discover.refreshNearby(myUserId: myId, graph: graph, areaKey: nil)
                        }
                    } label: {
                        Text("Turn off")
                            .font(.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Turn off Near you")
                }

                if visibleNearby.isEmpty {
                    Text("No one nearby has turned this on yet — you'll appear to each other as people opt in.")
                        .font(.sans(13, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(visibleNearby) { suggestion in
                        row(for: suggestion)
                    }
                }
            }
        } else {
            nearYouOptInCard
        }
    }

    private var nearYouOptInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("People near you")
                    .font(.serif(18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Find opted-in people roughly in your area. Your profile only carries a coarse, city-level area — never your exact position. Turn it off anytime.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)

            if let nearYouHint {
                Text(nearYouHint)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.alertRed)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                turnOnNearYou()
            } label: {
                Group {
                    if nearYouBusy {
                        ProgressView().tint(Theme.textCream)
                    } else {
                        Text("Turn on Near you")
                            .font(.sans(15, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(nearYouBusy)
            .padding(.top, 2)
        }
        .padding(16)
        .background(Theme.paperCream.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.textPrimary.opacity(0.08), lineWidth: 1)
        )
    }

    /// Request a coarse fix (same one the sky uses), derive the area,
    /// and load the Near-you section.
    private func turnOnNearYou() {
        guard let myId else { return }
        nearYouHint = nil
        nearYouBusy = true
        location.requestPermissionIfNeeded()
        Task {
            // Wait up to ~6 seconds for a coarse fix.
            var waited = 0
            while location.coordinate == nil && waited < 24 {
                if location.authorizationStatus == .denied || location.authorizationStatus == .restricted { break }
                try? await Task.sleep(for: .milliseconds(250))
                waited += 1
            }
            if let coordinate = location.coordinate {
                let ok = await profileStore.enableNearYou(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    myUserId: myId
                )
                if ok {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    await discover.refreshNearby(myUserId: myId, graph: graph, areaKey: profileStore.myProfile?.areaKey)
                }
            } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                nearYouHint = "Location is off for FrisFocus. Allow it in Settings to use Near you."
            } else {
                nearYouHint = "Couldn't get your location just now. Try again in a moment."
            }
            nearYouBusy = false
        }
    }

    // MARK: - Suggestion sections

    private func suggestionSection(
        title: String,
        subtitle: String?,
        suggestions: [DiscoverSuggestion]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title, subtitle: subtitle)
            ForEach(suggestions) { suggestion in
                row(for: suggestion)
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
                }
            }
        )
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.sans(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            if let subtitle {
                Text(subtitle)
                    .font(.sans(12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
    }

    private func reloadAll() async {
        guard let myId else { return }
        await graph.load(myUserId: myId)
        await discover.refresh(myUserId: myId, graph: graph)
        await profileStore.load(myUserId: myId, force: true)
        await discover.refreshNearby(myUserId: myId, graph: graph, areaKey: profileStore.myProfile?.areaKey)
    }
}
