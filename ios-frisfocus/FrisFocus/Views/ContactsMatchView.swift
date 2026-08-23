//
//  ContactsMatchView.swift
//  FrisFocus
//
//  Find friends from the address book: permission explainer, the
//  "On FrisFocus" matches with one-tap Add, and an Invite list that
//  opens a pre-filled text with the user's invite link. Contacts are
//  matched in the moment and never stored server-side.
//

import SwiftUI
import UIKit

struct ContactsMatchView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FriendGraphService.self) private var graph
    @Environment(ModerationService.self) private var moderation
    @Environment(SocialSyncService.self) private var socialSync
    @Environment(ProfileStore.self) private var profileStore

    @State private var service = ContactsMatchService()
    @State private var preview: DiscoverSuggestion?

    private var myId: String? { auth.user?.id }

    private var inviteMessage: String {
        let handle = profileStore.myProfile?.handle
        let link = myId.flatMap { InviteLink.webURL(forUserId: $0)?.absoluteString } ?? ""
        if let handle {
            return "I'm on FrisFocus as \(handle) — add me and let's keep each other going. \(link)"
        }
        return "I'm on FrisFocus — add me and let's keep each other going. \(link)"
    }

    private var visibleMatches: [RemoteProfile] {
        guard let myId else { return [] }
        return service.matched.filter { profile in
            guard !moderation.isBlocked(profile.id) else { return false }
            return graph.relationship(to: profile.id, myUserId: myId) != .isMe
        }
    }

    var body: some View {
        ZStack {
            Theme.warmWheat.ignoresSafeArea()
            content
        }
        .navigationTitle("Friends from contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.warmWheat, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if service.isAuthorized, !service.hasLoaded, let myId {
                await service.match(myUserId: myId)
            }
        }
        .refreshable {
            if service.isAuthorized, let myId {
                await service.match(myUserId: myId)
            }
        }
        .sheet(item: $preview) { suggestion in
            DiscoverProfileSheet(suggestion: suggestion, graph: graph)
                .environment(auth)
                .environment(socialSync)
        }
    }

    @ViewBuilder
    private var content: some View {
        if service.isDenied {
            deniedState
        } else if !service.isAuthorized {
            askState
        } else if service.isWorking && !service.hasLoaded {
            VStack(spacing: 10) {
                ProgressView().tint(Theme.textPrimary)
                Text("Checking your contacts…")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            resultsList
        }
    }

    // MARK: - Permission states

    private var askState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.paperCream)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 76, height: 76)

            Text("Find friends you already know")
                .font(.serif(21, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("FrisFocus checks your contacts' emails and phone numbers for people already here. Matching happens in the moment — your contacts are never stored on our servers.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard let myId else { return }
                Task { await service.connectAndMatch(myUserId: myId) }
            } label: {
                Text("Connect contacts")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.textCream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Contacts access is off")
                .font(.serif(19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Allow contacts access in Settings to find friends you already know. Everything else keeps working without it.")
                .font(.sans(13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(Theme.paperCream)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.textPrimary.opacity(0.14), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if visibleMatches.isEmpty && service.inviteCandidates.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("No matches yet")
                    .font(.serif(18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("None of your contacts are on FrisFocus yet — share your invite link to bring them in.")
                    .font(.sans(13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 36)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !visibleMatches.isEmpty {
                        sectionHeader("ON FRISFOCUS", subtitle: "From your contacts — already here.")
                        ForEach(matchSuggestions) { suggestion in
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
                    }

                    if !service.inviteCandidates.isEmpty {
                        sectionHeader("INVITE", subtitle: "Text them your link.")
                            .padding(.top, visibleMatches.isEmpty ? 0 : 14)
                        ForEach(service.inviteCandidates) { candidate in
                            inviteRow(candidate)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 44)
            }
        }
    }

    private var matchSuggestions: [DiscoverSuggestion] {
        visibleMatches.map { DiscoverSuggestion(profile: $0, mutualCount: 0) }
    }

    private func inviteRow(_ candidate: ContactCandidate) -> some View {
        HStack(spacing: 12) {
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
                sendInvite(to: candidate)
            } label: {
                DiscoverPill(title: "Invite", filled: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Invite \(candidate.name)")
        }
        .padding(12)
        .background(Theme.paperCream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

    // MARK: - Invite via Messages

    /// Open Messages pre-filled with the invite text for this contact.
    private func sendInvite(to candidate: ContactCandidate) {
        guard let phone = candidate.primaryPhone else { return }
        let number = phone.filter { $0.isNumber || $0 == "+" }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let body = inviteMessage.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "sms:\(number)&body=\(body)") else { return }
        UIApplication.shared.open(url)
    }
}
