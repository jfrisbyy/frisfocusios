//
//  FriendsView.swift
//  FrisFocus
//
//  The real, multiplayer friend graph — the account hub's doorway into
//  finding people by email, accepting incoming requests, and seeing who
//  you're actually connected to. Everything here is backed by Supabase
//  (`FriendGraphService`), so it syncs across every device you sign into.
//
//  This screen is deliberately separate from the seeded Circles people:
//  it's the first real-account surface, and the shared circles / pacts /
//  stories will graduate onto this graph in later phases.
//

import SwiftUI

struct FriendsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync
    /// The app-wide friend graph — shared with the banners and avatar
    /// dot, so accepting here clears the alerts everywhere instantly.
    @Environment(FriendGraphService.self) private var service
    @Environment(WalkthroughManager.self) private var walkthrough
    @State private var discover = DiscoverService()
    /// The People-privacy concept lesson, fired once on first visit.
    @State private var lesson: WalkthroughLesson?
    @State private var query: String = ""
    @State private var hasSearched: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var reportTarget: ReportTarget?
    @State private var discoverPreview: DiscoverSuggestion?
    @FocusState private var searchFocused: Bool

    private var myId: String? { auth.user?.id }

    /// True once the graph has answered with zero friends — Discover
    /// jumps to the top so the first thing a new user sees is people to
    /// add, not an empty "Your friends" box.
    private var hasNoFriends: Bool {
        !service.isLoading && service.friends.isEmpty
    }

    var body: some View {
        @Bindable var service = service
        @Bindable var moderation = moderation

        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            content
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                WalkthroughHelpButton { lesson = .peoplePrivacy }
            }
        }
        .walkthroughLessonSheet($lesson) { walkthrough.markSeen($0) }
        .onAppear {
            // The privacy model, exactly when it becomes relevant.
            if auth.user != nil, walkthrough.shouldFire(.peoplePrivacy) {
                lesson = .peoplePrivacy
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Something went wrong", isPresented: $service.showError) {
            Button("OK") { }
        } message: {
            Text(service.errorMessage ?? "Please try again.")
        }
        .alert("Something went wrong", isPresented: $moderation.showError) {
            Button("OK") { }
        } message: {
            Text(moderation.errorMessage ?? "Please try again.")
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(
                reportedUserId: target.reportedUserId,
                messageId: target.messageId,
                subjectName: target.subjectName
            )
            .environment(auth)
            .environment(moderation)
        }
        .sheet(item: $discoverPreview) { suggestion in
            DiscoverProfileSheet(suggestion: suggestion, graph: service)
                .environment(auth)
                .environment(socialSync)
        }
    }

    @ViewBuilder
    private var content: some View {
        if auth.user == nil {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("Sign in to add friends")
                    .font(.serif(19, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(40)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    inviteRow
                    if hasNoFriends, !discoverSuggestions.isEmpty { discoverSection }
                    addSection
                    if !service.incoming.isEmpty { incomingSection }
                    if !service.outgoing.isEmpty { outgoingSection }
                    if !hasNoFriends, !discoverSuggestions.isEmpty { discoverSection }
                    friendsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Invite

    private var inviteRow: some View {
        NavigationLink {
            InviteFriendsView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.textPrimary)
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textCream)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite friends")
                        .font(.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Share your link or QR code")
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

    // MARK: - Add by username, name, or email

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ADD A FRIEND", subtitle: "Find people by @username, name, or email.")

            HStack(spacing: 10) {
                TextField("@username, name, or email", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                    .onChange(of: query) { _, newValue in scheduleLiveSearch(newValue) }
                    .font(.sans(15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await runSearch() }
                } label: {
                    Group {
                        if service.isSearching {
                            ProgressView().tint(Theme.textCream)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(Theme.textPrimary)
                    .foregroundStyle(Theme.textCream)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || service.isSearching)
            }

            ForEach(service.searchResults.filter { !moderation.isBlocked($0.id) }) { profile in
                personRow(profile) { searchResultTrailing(profile) }
            }

            if hasSearched, !service.isSearching, service.searchResults.isEmpty {
                Text("No one found. Try a different @username, name, or email.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func searchResultTrailing(_ profile: RemoteProfile) -> some View {
        switch myId.map({ service.relationship(to: profile.id, myUserId: $0) }) ?? .none {
        case .friends:
            pill("Friends", filled: false).opacity(0.55)
        case .requestSent:
            pill("Pending", filled: false).opacity(0.55)
        case .requestReceived:
            Button {
                guard let myId, let request = service.incoming.first(where: { $0.profile.id == profile.id }) else { return }
                Task { await service.accept(request, myUserId: myId) }
            } label: {
                pill("Accept", filled: true)
            }
            .buttonStyle(.plain)
        case .isMe:
            EmptyView()
        case .none:
            Button {
                guard let myId else { return }
                searchFocused = false
                Task { await service.sendRequest(to: profile, myUserId: myId) }
            } label: {
                pill("Add", filled: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Incoming requests

    private var incomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("REQUESTS", subtitle: nil)
            ForEach(service.incoming) { request in
                personRow(request.profile) {
                    HStack(spacing: 8) {
                        Button {
                            guard let myId else { return }
                            Task { await service.decline(request, myUserId: myId) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(Theme.textPrimary.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            guard let myId else { return }
                            Task { await service.accept(request, myUserId: myId) }
                        } label: {
                            pill("Accept", filled: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Outgoing (pending sent)

    private var outgoingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SENT", subtitle: nil)
            ForEach(service.outgoing) { request in
                personRow(request.profile) {
                    pill("Pending", filled: false).opacity(0.55)
                }
            }
        }
    }

    // MARK: - Discover people

    /// Suggestions still worth showing: blocked accounts are hidden, and
    /// anyone who became a friend (or sent us a request) while on screen
    /// drops out — freshly added people stay visible as Pending.
    private var discoverSuggestions: [DiscoverSuggestion] {
        guard let myId else { return [] }
        return discover.suggestions.filter { suggestion in
            guard !moderation.isBlocked(suggestion.profile.id) else { return false }
            switch service.relationship(to: suggestion.profile.id, myUserId: myId) {
            case .none, .requestSent: return true
            case .friends, .requestReceived, .isMe: return false
            }
        }
    }

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("DISCOVER PEOPLE", subtitle: "People on FrisFocus you may know.")
                Spacer()
                NavigationLink {
                    DiscoverPeopleView(graph: service, discover: discover)
                } label: {
                    HStack(spacing: 3) {
                        Text("See all")
                            .font(.sans(13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all suggestions")
            }

            ForEach(discoverSuggestions.prefix(6)) { suggestion in
                DiscoverPersonRow(
                    suggestion: suggestion,
                    relationship: myId.map { service.relationship(to: suggestion.profile.id, myUserId: $0) } ?? .none,
                    onOpen: { discoverPreview = suggestion },
                    onAdd: {
                        guard let myId else { return }
                        Task {
                            await service.sendRequest(to: suggestion.profile, myUserId: myId)
                        }
                    },
                    prominent: hasNoFriends
                )
            }
        }
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("YOUR FRIENDS", subtitle: nil)

            if service.isLoading && service.friends.isEmpty {
                ProgressView()
                    .tint(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else if service.friends.isEmpty {
                emptyFriends
            } else {
                ForEach(service.friends.filter { !moderation.isBlocked($0.id) }) { friend in
                    personRow(friend) {
                        Menu {
                            Button {
                                reportTarget = ReportTarget(reportedUserId: friend.id, messageId: nil, subjectName: friend.displayName)
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                guard let myId else { return }
                                Task { await service.unfriend(friend, myUserId: myId) }
                            } label: {
                                Label("Remove friend", systemImage: "person.fill.xmark")
                            }
                            Button(role: .destructive) {
                                guard let myId else { return }
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                Task { await moderation.block(friend.id, myUserId: myId) }
                            } label: {
                                Label("Block", systemImage: "hand.raised")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 34, height: 34)
                        }
                    }
                }
            }
        }
    }

    private var emptyFriends: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No friends yet")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Pick someone from Discover people above, or search by @username, name, or email to start sharing circles, pacts, and stories.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
        .background(Theme.paperCream.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Reusable pieces

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

    private func personRow<Trailing: View>(
        _ profile: RemoteProfile,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            avatar(profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let secondary = profile.handle ?? profile.email, secondary != profile.displayName {
                    Text(secondary)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func avatar(_ profile: RemoteProfile) -> some View {
        ZStack {
            if let url = profile.photoURL {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsDisc(profile)
                }
            } else {
                initialsDisc(profile)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func initialsDisc(_ profile: RemoteProfile) -> some View {
        ZStack {
            Theme.textPrimary
            Text(profile.initials)
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.textCream)
        }
    }

    private func pill(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.sans(13, weight: .semibold))
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(filled ? Theme.textPrimary : Theme.paperCream)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.textPrimary.opacity(filled ? 0 : 0.15), lineWidth: 1)
            )
    }

    // MARK: - Actions

    private func reload() async {
        guard let myId else { return }
        await service.load(myUserId: myId)
        service.startRealtime(myUserId: myId)
        // The user is looking at the request list now — clear the
        // unseen dot on the home avatar and quick-card tile.
        service.markRequestsSeen()
        await discover.refresh(myUserId: myId, graph: service)
    }

    private func runSearch() async {
        guard let myId else { return }
        searchFocused = false
        hasSearched = true
        await service.searchPeople(query: query, myUserId: myId)
    }

    /// Live as-you-type search: a short debounce, then the same query
    /// the magnifier runs — without stealing keyboard focus.
    private func scheduleLiveSearch(_ text: String) {
        hasSearched = false
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            service.searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let myId else { return }
            await service.searchPeople(query: trimmed, myUserId: myId)
            if !Task.isCancelled { hasSearched = true }
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView()
            .environment(AuthManager())
    }
}
