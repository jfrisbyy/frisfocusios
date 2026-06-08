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
    @State private var service = FriendGraphService()
    @State private var email: String = ""
    @State private var hasSearched: Bool = false
    @FocusState private var emailFocused: Bool

    private var myId: String? { auth.user?.id }

    var body: some View {
        @Bindable var service = service

        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            content
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Something went wrong", isPresented: $service.showError) {
            Button("OK") { }
        } message: {
            Text(service.errorMessage ?? "Please try again.")
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
                    addSection
                    if !service.incoming.isEmpty { incomingSection }
                    if !service.outgoing.isEmpty { outgoingSection }
                    friendsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Add by email

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ADD A FRIEND", subtitle: "Find someone by the email they signed up with.")

            HStack(spacing: 10) {
                TextField("name@email.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }
                    .onChange(of: email) { _, _ in hasSearched = false }
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
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || service.isSearching)
            }

            ForEach(service.searchResults) { profile in
                personRow(profile) { searchResultTrailing(profile) }
            }

            if hasSearched, !service.isSearching, service.searchResults.isEmpty {
                Text("No one found with that email.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func searchResultTrailing(_ profile: RemoteProfile) -> some View {
        if service.friends.contains(where: { $0.id == profile.id }) {
            pill("Friends", filled: false).opacity(0.55)
        } else if service.outgoing.contains(where: { $0.profile.id == profile.id }) {
            pill("Pending", filled: false).opacity(0.55)
        } else {
            Button {
                guard let myId else { return }
                emailFocused = false
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
                ForEach(service.friends) { friend in
                    personRow(friend) {
                        Menu {
                            Button(role: .destructive) {
                                guard let myId else { return }
                                Task { await service.unfriend(friend, myUserId: myId) }
                            } label: {
                                Label("Remove friend", systemImage: "person.fill.xmark")
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
            Text("Add someone by email to start sharing circles, pacts, and stories.")
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
                if let email = profile.email, email != profile.displayName {
                    Text(email)
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
                AsyncImage(url: url) { image in
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
    }

    private func runSearch() async {
        guard let myId else { return }
        emailFocused = false
        hasSearched = true
        await service.search(email: email, myUserId: myId)
    }
}

#Preview {
    NavigationStack {
        FriendsView()
            .environment(AuthManager())
    }
}
