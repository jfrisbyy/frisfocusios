//
//  BringPeopleStep.swift
//  FrisFocus
//
//  Screen C of the account seam — "Bring your people." The account
//  exists now, so this is where invites live. Three quiet, optional
//  routes, stacked:
//
//    1. Share your link  — system share sheet with a warm prefilled note.
//                          The deep link installs + auto-friends on signup.
//    2. Find by username — inline search, one-tap add-request.
//    3. Connect contacts — strictly opt-in, one tap, plainly explained;
//                          never auto-prompted, never pre-toggled.
//
//  The witness model applies to growth: no counters, no invite-gating, no
//  rewards. "Later" is always present and costs nothing — skipping lands
//  straight on home, and the whole flow stays reachable from the People
//  page afterward.
//

import SwiftUI
import UIKit

struct BringPeopleStep: View {
    /// Land on the live home with the saved season.
    let onFinish: () -> Void

    @Environment(AuthManager.self) private var auth
    @Environment(ProfileStore.self) private var profileStore
    @Environment(FriendGraphService.self) private var graph
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contacts = ContactsMatchService()
    @State private var query: String = ""
    @State private var hasSearched: Bool = false
    @State private var addedIds: Set<String> = []
    @State private var invitedIds: Set<String> = []
    @State private var showContacts: Bool = false
    @State private var shown: Bool = false
    @FocusState private var searchFocused: Bool

    private var myId: String? { auth.user?.id }

    private var inviteURL: URL? { myId.flatMap { InviteLink.url(forUserId: $0) } }

    private var shareMessage: String {
        let link = inviteURL?.absoluteString ?? ""
        return "I'm keeping an honest record of my days on FrisFocus. Watch my sun rise — and let me watch yours: \(link)"
    }

    private var visibleResults: [RemoteProfile] {
        guard let myId else { return [] }
        return graph.searchResults.filter { profile in
            !moderation.isBlocked(profile.id) &&
            graph.relationship(to: profile.id, myUserId: myId) != .isMe
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    shareRoute
                    usernameRoute
                    contactsRoute
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .opacity(shown ? 1 : 0)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85)) {
                shown = true
            }
        }
        .sheet(isPresented: $showContacts) {
            ContactsInviteSheet(
                contacts: contacts,
                addedIds: $addedIds,
                invitedIds: $invitedIds,
                shareMessage: shareMessage
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            CompanionSlotsMark()
                .frame(height: 78)
                .padding(.bottom, 2)

            EyebrowText(text: "BRING YOUR PEOPLE", opacity: 0.5)

            Text("Bring your people.")
                .font(.serif(29, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)

            Text("They'll see the shape of your days — and you'll see theirs.")
                .font(.serifItalic(15, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)
        }
    }

    // MARK: Route 1 — Share link

    @ViewBuilder
    private var shareRoute: some View {
        routeCard(
            icon: "square.and.arrow.up",
            title: "Share your link",
            subtitle: "They install and land as your friend — one tap for them."
        ) {
            if let inviteURL {
                ShareLink(
                    item: inviteURL,
                    subject: Text("Watch my sun rise on FrisFocus"),
                    message: Text(shareMessage)
                ) {
                    routeActionLabel(title: "Share", filled: true)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                })
            }
        }
    }

    // MARK: Route 2 — Find by username

    private var usernameRoute: some View {
        VStack(alignment: .leading, spacing: 12) {
            routeHeader(
                icon: "at",
                title: "Find by username",
                subtitle: "Search someone you already know is here."
            )

            HStack(spacing: 10) {
                TextField("@username or name", text: $query)
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
                    .background(Theme.warmWheat)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    Task { await runSearch() }
                } label: {
                    Group {
                        if graph.isSearching {
                            ProgressView().tint(Theme.textCream)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(Theme.textPrimary)
                    .foregroundStyle(Theme.textCream)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || graph.isSearching)
            }

            ForEach(visibleResults) { profile in
                searchResultRow(profile)
            }

            if hasSearched, !graph.isSearching, visibleResults.isEmpty {
                Text("No one found. Try a different @username or name.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func searchResultRow(_ profile: RemoteProfile) -> some View {
        let relationship = myId.map { graph.relationship(to: profile.id, myUserId: $0) } ?? .none
        let added = addedIds.contains(profile.id) || relationship == .requestSent
        return HStack(spacing: 12) {
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
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailingControl(for: profile, relationship: relationship, added: added)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func trailingControl(for profile: RemoteProfile, relationship: FriendRelationship, added: Bool) -> some View {
        switch relationship {
        case .friends:
            pill(title: "Friends", filled: false, icon: "checkmark").opacity(0.55)
        case .isMe:
            EmptyView()
        case .requestReceived:
            Button {
                guard let myId, let request = graph.incoming.first(where: { $0.profile.id == profile.id }) else { return }
                Task { await graph.accept(request, myUserId: myId) }
            } label: {
                pill(title: "Accept", filled: true, icon: nil)
            }
            .buttonStyle(.plain)
        default:
            Button {
                guard let myId, !added else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                searchFocused = false
                addedIds.insert(profile.id)
                Task {
                    await graph.sendRequest(to: profile, myUserId: myId)
                }
            } label: {
                pill(title: added ? "Added" : "Add", filled: !added, icon: added ? "checkmark" : "plus")
            }
            .buttonStyle(.plain)
            .disabled(added)
        }
    }

    // MARK: Route 3 — Connect contacts

    @ViewBuilder
    private var contactsRoute: some View {
        routeCard(
            icon: "person.crop.circle.badge.plus",
            title: "Connect contacts",
            subtitle: "Find friends already here — contacts never leave your phone without asking."
        ) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    if let myId, !contacts.isAuthorized {
                        await contacts.connectAndMatch(myUserId: myId)
                    } else if let myId, !contacts.hasLoaded {
                        await contacts.match(myUserId: myId)
                    }
                    if contacts.isAuthorized { showContacts = true }
                }
            } label: {
                routeActionLabel(
                    title: contacts.isWorking ? "Checking…" : "Connect",
                    filled: true
                )
            }
            .buttonStyle(.plain)
            .disabled(contacts.isWorking)
        }
    }

    // MARK: Route scaffolding

    @ViewBuilder
    private func routeCard<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            routeIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sans(15.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.sans(12.5, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(16)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func routeHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            routeIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sans(15.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.sans(12.5, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func routeIcon(_ icon: String) -> some View {
        ZStack {
            Circle().fill(Theme.textPrimary.opacity(0.08))
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 44, height: 44)
    }

    private func routeActionLabel(title: String, filled: Bool) -> some View {
        Text(title)
            .font(.sans(14.5, weight: .semibold))
            .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(filled ? Theme.textPrimary : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.textPrimary.opacity(filled ? 0 : 0.25), lineWidth: 1))
    }

    private func pill(title: String, filled: Bool, icon: String?) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
            }
            Text(title).font(.sans(14, weight: .semibold))
        }
        .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(filled ? Theme.textPrimary : Color.clear)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.textPrimary.opacity(filled ? 0 : 0.25), lineWidth: 1))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onFinish()
            } label: {
                HStack(spacing: 10) {
                    Text("Start my season")
                        .font(.sans(17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.textCream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.textPrimary)
                )
            }
            .buttonStyle(.plain)

            Button {
                onFinish()
            } label: {
                Text("Later")
                    .font(.sans(14.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Search

    private func scheduleLiveSearch(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if query.trimmingCharacters(in: .whitespaces) == trimmed {
                await runSearch()
            }
        }
    }

    private func runSearch() async {
        guard let myId else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        hasSearched = true
        await graph.searchPeople(query: trimmed, myUserId: myId)
    }
}

// MARK: - Companion slots mark

/// The header visual: the user's own low sun with two empty companion
/// slots beside it, waiting to be filled.
private struct CompanionSlotsMark: View {
    var body: some View {
        HStack(spacing: 14) {
            emptySlot(size: 44)
            ownSun(size: 58)
            emptySlot(size: 44)
        }
    }

    private func ownSun(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Theme.sunOuter.opacity(0.35))
            Image(systemName: "sun.and.horizon.fill")
                .font(.system(size: size * 0.5, weight: .regular))
                .foregroundStyle(Theme.sunCore, Theme.sunWarm)
                .symbolRenderingMode(.palette)
        }
        .frame(width: size, height: size)
    }

    private func emptySlot(size: CGFloat) -> some View {
        Circle()
            .strokeBorder(
                Theme.textPrimary.opacity(0.18),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.28))
            )
    }
}

// MARK: - Contacts invite sheet

/// Presents contact matches (already on FrisFocus → add) and invite
/// candidates (text them the warm link) once contacts are authorized.
private struct ContactsInviteSheet: View {
    let contacts: ContactsMatchService
    @Binding var addedIds: Set<String>
    @Binding var invitedIds: Set<String>
    let shareMessage: String

    @Environment(AuthManager.self) private var auth
    @Environment(FriendGraphService.self) private var graph
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(\.dismiss) private var dismiss

    private var myId: String? { auth.user?.id }

    private var visibleMatches: [RemoteProfile] {
        guard let myId else { return [] }
        return contacts.matched.filter { profile in
            !moderation.isBlocked(profile.id) &&
            graph.relationship(to: profile.id, myUserId: myId) != .isMe
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleMatches.isEmpty && contacts.inviteCandidates.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if !visibleMatches.isEmpty {
                                sectionHeader("ALREADY ON FRISFOCUS", subtitle: "From your contacts — add to keep up.")
                                ForEach(visibleMatches) { matchRow($0) }
                            }
                            if !contacts.inviteCandidates.isEmpty {
                                sectionHeader("INVITE TO JOIN", subtitle: "Send them your link.")
                                    .padding(.top, visibleMatches.isEmpty ? 0 : 14)
                                ForEach(contacts.inviteCandidates) { inviteRow($0) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
                }
            }
            .background(Theme.warmWheat.ignoresSafeArea())
            .navigationTitle("From your contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No matches yet")
                .font(.serif(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("None of your contacts are here yet — invite them with your link anytime.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func matchRow(_ profile: RemoteProfile) -> some View {
        let added = addedIds.contains(profile.id)
        return HStack(spacing: 12) {
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
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                guard let myId, !added else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                addedIds.insert(profile.id)
                Task {
                    await graph.sendRequest(to: profile, myUserId: myId)
                }
            } label: {
                pill(title: added ? "Added" : "Add", filled: !added, icon: added ? "checkmark" : "plus")
            }
            .buttonStyle(.plain)
            .disabled(added)
        }
        .padding(12)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func inviteRow(_ candidate: ContactCandidate) -> some View {
        let invited = invitedIds.contains(candidate.id)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.textPrimary.opacity(0.08))
                Text(candidate.initials)
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.65))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.sans(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let phone = candidate.primaryPhone {
                    Text(phone)
                        .font(.sans(12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                invitedIds.insert(candidate.id)
                sendInvite(to: candidate)
            } label: {
                pill(title: invited ? "Invited" : "Invite", filled: false, icon: invited ? "checkmark" : nil)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .padding(.bottom, 2)
    }

    private func pill(title: String, filled: Bool, icon: String?) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
            }
            Text(title).font(.sans(14, weight: .semibold))
        }
        .foregroundStyle(filled ? Theme.textCream : Theme.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(filled ? Theme.textPrimary : Color.clear)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.textPrimary.opacity(filled ? 0 : 0.25), lineWidth: 1))
    }

    private func sendInvite(to candidate: ContactCandidate) {
        guard let phone = candidate.primaryPhone else { return }
        let number = phone.filter { $0.isNumber || $0 == "+" }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let body = shareMessage.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "sms:\(number)&body=\(body)") else { return }
        UIApplication.shared.open(url)
    }
}
